//
//  LTXAnimatableLabel.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

import CoreFoundation
import Foundation
import Litext
import QuartzCore

#if !os(watchOS)
    public import DisplayLink
#endif

#if canImport(UIKit) && !os(watchOS)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#if !os(watchOS)

    /// A `TextLabelView` that animates changes to its text with an animator you provide.
    ///
    /// Assign an ``animator`` and keep assigning `attributedText`: each change the
    /// ``animationPolicy`` lets through animates, and the label drives the animator from a
    /// display link that exists only while something is in flight. Without an animator, or
    /// while nothing animates, the label is a plain `TextLabelView`: it draws the same pixels,
    /// has the same subviews and layers, and runs no timer.
    ///
    /// ```swift
    /// label.animator = LTXFadeInAnimator()
    /// label.attributedText = streamedSoFar   // only the new text fades in
    /// ```
    ///
    /// In a reused table or collection view cell, set ``animationIdentity`` before the text,
    /// so the change that shows another item appears at once while further text streamed into
    /// the same item still animates:
    ///
    /// ```swift
    /// cell.label.animationIdentity = message.id
    /// cell.label.attributedText = message.rendered
    /// ```
    ///
    /// The label finishes its animations, jumping to the final text, when it leaves its
    /// window, when its identity or animator changes, when a change is not animated, and when
    /// reduced motion turns on.
    ///
    /// Animation frames never lay the text out. While animating, the label draws the lines
    /// in flight into a sublayer that covers only them, and redraws only that sublayer, and
    /// only where the animator invalidated it, on each frame; its own backing store is
    /// redrawn when the text changes and when lines start or finish animating. See
    /// ``LTXTextAnimator`` for the region the sublayer covers.
    ///
    /// Because the lines in flight live on that sublayer, a snapshot that draws only the
    /// view, such as AppKit's `cacheDisplay(in:to:)`, leaves them out while the label
    /// animates. Call ``finishAnimations()`` before taking one.
    ///
    /// The label lays its text out through `makeTextLayout(_:)`. A subclass that returns a
    /// layout of its own keeps the animator, but no line reaches it: the animation region is
    /// then only the animator's `additionalContentBounds`.
    @MainActor
    open class LTXAnimatableLabel: TextLabelView {
        // MARK: - Public

        /// The effect that animates text changes. `nil`, the default, makes the label behave
        /// exactly like `TextLabelView`.
        ///
        /// Replacing the animator finishes the animations of the previous one.
        open var animator: (any LTXTextAnimator)? {
            didSet {
                guard animator !== oldValue, isAnimating else { return }
                oldValue?.finish()
                stopAnimating()
            }
        }

        /// Decides, for every text change, whether it animates. Defaults to
        /// ``LTXDefaultAnimationPolicy``.
        open var animationPolicy: any LTXAnimationPolicy = LTXDefaultAnimationPolicy()

        /// What the label shows, for telling a reused label's new content from more of the
        /// same content. A reused cell sets it to the identifier of the item it now shows,
        /// before assigning that item's text.
        ///
        /// Changing it finishes any animation in flight, and the next text change sees the
        /// previous and new identities in its ``LTXAnimationContext``; the default policy
        /// does not animate a change of identity.
        open var animationIdentity: AnyHashable? {
            didSet {
                guard animationIdentity != oldValue else { return }
                finishAnimations()
            }
        }

        /// The frame rate the label asks the display for while animating. Defaults to 30
        /// to 120 frames per second, preferring 60, which keeps text effects smooth without
        /// asking a ProMotion display for its top rate.
        open var preferredFrameRateRange = DisplayLinkFrameRateRange(minimum: 30, maximum: 120, preferred: 60) {
            didSet { displayLink?.preferredFrameRateRange = preferredFrameRateRange }
        }

        /// Whether any text is in flight. Key-value observable.
        @objc public private(set) dynamic var isAnimating = false

        /// Sets the text, animating the change only when `animated` is `true` and the
        /// ``animationPolicy`` agrees, like `UILabel`'s animated setters.
        ///
        /// Passing `false` skips the policy, shows the final text at once and finishes any
        /// animation in flight. Passing `true` is the same as assigning `attributedText`.
        open func setAttributedText(_ text: NSAttributedString, animated: Bool) {
            guard !animated else {
                attributedText = text
                return
            }
            isAssigningWithoutAnimation = true
            attributedText = text
            isAssigningWithoutAnimation = false
            finishAnimations()
        }

        /// Ends every animation in flight at once and shows the final text. Calls the
        /// animator's `finish()` and releases the display link.
        open func finishAnimations() {
            guard isAnimating else { return }
            animator?.finish()
            stopAnimating()
        }

        /// Notices real text changes, after `TextLabelView` has built the new layout.
        override open var attributedText: NSAttributedString {
            willSet { layoutBeforeChange = textLayout }
            didSet {
                let previousLayout = layoutBeforeChange ?? textLayout
                layoutBeforeChange = nil
                textDidChange(from: oldValue, previousLayout: previousLayout)
            }
        }

        /// Builds the layout that routes lines in flight to the animator. Overrides that
        /// return a layout of their own turn that routing off.
        override open func makeTextLayout(_ attributedText: NSAttributedString) -> TextLabel.Layout {
            let layout = LTXAnimatableTextLayout(attributedString: attributedText)
            layout.label = self
            return layout
        }

        // MARK: - Internal state

        /// The display link while animating, `nil` otherwise.
        private(set) var displayLink: DisplayLink?
        private var displayLinkTarget: LTXDisplayLinkTarget?

        /// The time of the frame being drawn: the target timestamp of the last frame, or the
        /// time of the change that started the animation.
        var currentTime: CFTimeInterval = 0

        /// Reads the time of a change. Tests replace it with a synthetic clock.
        var clock: () -> CFTimeInterval = { CACurrentMediaTime() }

        /// Replaces the system's reduced-motion setting, for tests.
        var reducedMotionOverride: Bool?

        /// Replaces the scale of the display the label is on, for tests.
        var displayScaleOverride: CGFloat?

        let invalidation = LTXInvalidationContext()

        /// The layer that draws the animation region while animating, `nil` otherwise.
        var animationLayer: LTXAnimationLayer?

        /// The part of the label the animation layer draws, in its coordinates, or `.null`.
        /// The label's own drawing leaves it out.
        var animationRegion: CGRect = .null

        /// Redraw requests for the label's own backing store and for the animation layer
        /// since the label was created, so tests can tell per-frame work from handovers.
        var labelDisplayRequestCount = 0
        var animationLayerDisplayRequestCount = 0

        private var layoutBeforeChange: TextLabel.Layout?
        private var identityOfDisplayedText: AnyHashable?
        private var isAssigningWithoutAnimation = false
        private var isObservingReducedMotion = false
        private var isObservingDisplayScale = false

        /// The animator to draw with, `nil` while nothing is in flight.
        var drawingAnimator: (any LTXTextAnimator)? {
            isAnimating ? animator : nil
        }

        // MARK: - Text changes

        private func textDidChange(from previousText: NSAttributedString, previousLayout: TextLabel.Layout) {
            let previousIdentity = identityOfDisplayedText
            identityOfDisplayedText = animationIdentity
            // An equal string keeps its layout; nothing changed on screen.
            guard textLayout !== previousLayout, let animator else { return }
            guard !isAssigningWithoutAnimation else { return }

            let context = LTXAnimationContext(
                change: LTXTextChange(from: previousText, to: attributedText),
                previousIdentity: previousIdentity,
                identity: animationIdentity,
                previousLayout: previousLayout,
                layout: textLayout,
                isInWindow: window != nil,
                areAnimationsEnabled: Self.platformAllowsAnimations,
                prefersReducedMotion: prefersReducedMotion,
                wasAnimating: isAnimating,
            )
            guard animationPolicy.shouldAnimate(context) else {
                finishAnimations()
                return
            }
            let time = clock()
            currentTime = time
            animator.animateChange(context, at: time)
            startAnimating()
        }

        private static var platformAllowsAnimations: Bool {
            #if canImport(UIKit)
                UIView.areAnimationsEnabled
            #else
                true
            #endif
        }

        var prefersReducedMotion: Bool {
            if let reducedMotionOverride {
                return reducedMotionOverride
            }
            #if canImport(UIKit)
                return UIAccessibility.isReduceMotionEnabled
            #else
                return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            #endif
        }

        // MARK: - Animation lifetime

        private func startAnimating() {
            if !isAnimating {
                isAnimating = true
                observeReducedMotion(true)
            }
            updateAnimationRegion()
            guard displayLink == nil else { return }
            let target = displayLinkTarget ?? LTXDisplayLinkTarget(label: self)
            displayLinkTarget = target
            let link = DisplayLink(context: .view(self), preferredFrameRateRange: preferredFrameRateRange)
            link.delegate = target
            displayLink = link
        }

        /// Releases the display link and the animation layer, and redraws the region the
        /// layer drew in the label, in the same transaction.
        private func stopAnimating() {
            guard isAnimating else { return }
            // Releasing the link removes the hidden subview it added.
            displayLink = nil
            invalidation.clear()
            isAnimating = false
            removeAnimationLayer()
            observeReducedMotion(false)
        }

        /// Advances the animator to `frame` and redraws what it invalidated. The display link
        /// calls it on every frame; tests call it with synthetic frames.
        ///
        /// - Important: Performance-sensitive. Runs on every display frame while animating.
        ///   Never lays the text out; the work is the animator's step plus one binary search
        ///   per invalidated range.
        func displayLinkDidUpdate(_ frame: DisplayLinkFrame) {
            guard isAnimating, let animator else {
                stopAnimating()
                return
            }
            currentTime = frame.targetTimestamp
            let insets = animator.overdrawInsets.sanitized
            let layout = textLayout as? LTXAnimatableTextLayout
            invalidation.reset(
                layout: textLayout,
                lineIndex: layout?.lineIndex,
                canMapCharacters: layout != nil,
                insets: insets,
            )
            let isActive = animator.advance(to: currentTime, invalidation: invalidation)
            guard isActive else {
                // The label takes the region back and draws the final text there.
                stopAnimating()
                return
            }
            // A region that moved is redrawn whole, and so is what the label gave up.
            if !updateAnimationRegion() {
                if invalidation.invalidatesAll {
                    setNeedsAnimationLayerDisplay()
                } else if !invalidation.dirtyRect.isNull {
                    setNeedsAnimationLayerDisplay(in: invalidation.dirtyRect)
                }
            }
        }

        // MARK: - Window and reduced motion

        /// Finishes the animations when the label leaves its window.
        func windowDidChange() {
            if window == nil {
                finishAnimations()
            }
            displayScaleDidChange()
        }

        /// Renders the animation layer at the scale of the display the label is now on, and
        /// realigns the animation region to that display's pixels.
        func displayScaleDidChange() {
            guard let animationLayer, animationLayer.contentsScale != backingScale else { return }
            animationLayer.contentsScale = backingScale
            updateAnimationRegion()
            setNeedsAnimationLayerDisplay()
        }

        private func observeReducedMotion(_ observes: Bool) {
            guard observes != isObservingReducedMotion else { return }
            isObservingReducedMotion = observes
            #if canImport(UIKit)
                let center = NotificationCenter.default
                let name = UIAccessibility.reduceMotionStatusDidChangeNotification
            #else
                let center = NSWorkspace.shared.notificationCenter
                let name = NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
            #endif
            if observes {
                center.addObserver(self, selector: #selector(reducedMotionDidChange), name: name, object: nil)
            } else {
                center.removeObserver(self, name: name, object: nil)
            }
        }

        @objc private func reducedMotionDidChange() {
            reducedMotionStatusDidChange()
        }

        /// Finishes the animations when reduced motion turns on.
        func reducedMotionStatusDidChange() {
            if prefersReducedMotion {
                finishAnimations()
            }
        }

        // MARK: - Platform hooks

        #if canImport(UIKit)
            /// Finishes the animations when the label leaves its window. Overrides must call
            /// `super`.
            override open func didMoveToWindow() {
                super.didMoveToWindow()
                windowDidChange()
            }

            /// Moves the animation region with the laid-out lines. Overrides must call
            /// `super`.
            override open func layoutSubviews() {
                super.layoutSubviews()
                layoutDidChange()
            }

            /// Also redraws the animation layer, since the whole text is being redrawn.
            override open func setNeedsDisplay() {
                super.setNeedsDisplay()
                labelDisplayRequestCount += 1
                setNeedsAnimationLayerDisplay()
            }

            func setNeedsDisplayWithoutAnimationLayer(_ rect: CGRect) {
                setNeedsDisplay(rect)
            }

            #if !os(visionOS)
                /// Follows a change of display scale on systems before iOS 17 and tvOS 17,
                /// which have no trait change registration. Overrides must call `super`.
                override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
                    super.traitCollectionDidChange(previousTraitCollection)
                    if #unavailable(iOS 17.0, tvOS 17.0) {
                        displayScaleDidChange()
                    }
                }
            #endif

            /// Follows changes of display scale while the label has an animation layer, on
            /// systems that register for trait changes. Registers once per label.
            func observeDisplayScale() {
                guard !isObservingDisplayScale else { return }
                if #available(iOS 17.0, tvOS 17.0, visionOS 1.0, *) {
                    isObservingDisplayScale = true
                    registerForTraitChanges([UITraitDisplayScale.self]) { (self: Self, _) in
                        self.displayScaleDidChange()
                    }
                }
            }
        #else
            /// Also redraws the animation layer, since the whole text is being redrawn.
            override open var needsDisplay: Bool {
                get { super.needsDisplay }
                set {
                    super.needsDisplay = newValue
                    if newValue {
                        labelDisplayRequestCount += 1
                        setNeedsAnimationLayerDisplay()
                    }
                }
            }

            func setNeedsDisplayWithoutAnimationLayer(_ rect: CGRect) {
                setNeedsDisplay(rect)
            }
        #endif

        /// Moves the animation region after a layout pass, which can move every line.
        func layoutDidChange() {
            guard isAnimating else { return }
            updateAnimationRegion()
            layoutAnimationLayer()
        }

        /// The scale of the display the label is on.
        var backingScale: CGFloat {
            if let displayScaleOverride {
                return displayScaleOverride
            }
            #if os(visionOS)
                let scale = traitCollection.displayScale
            #elseif canImport(UIKit)
                let scale = window?.screen.scale ?? traitCollection.displayScale
            #else
                let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
            #endif
            return scale > 0 ? scale : 1
        }
    }

    /// Forwards display link frames to a label it does not keep alive.
    @MainActor
    final class LTXDisplayLinkTarget: DisplayLinkDelegate {
        weak var label: LTXAnimatableLabel?

        init(label: LTXAnimatableLabel) {
            self.label = label
        }

        func displayLink(_: DisplayLink, didUpdate frame: DisplayLinkFrame) {
            label?.displayLinkDidUpdate(frame)
        }
    }

#endif
