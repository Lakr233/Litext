//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  The animatable label drives a recording animator with synthetic frames: when it
//  animates, what it hands the animator, what it redraws, and that it holds nothing while
//  idle and leaks nothing afterwards.
//

#if !os(watchOS)

    import DisplayLink
    import Foundation
    import Litext
    @testable import LitextAnimation
    import Testing

    #if canImport(UIKit)
        import UIKit
    #elseif canImport(AppKit)
        import AppKit
    #endif

    @MainActor
    @Suite("Animatable label")
    struct LTXAnimatableLabelTests {
        // MARK: - Idle

        @Test
        func `without an animator the label draws exactly like TextLabelView`() {
            let label = makeLabel(paragraphs)
            let plain = TextLabelView(attributedText: text(paragraphs))
            plain.frame = label.frame
            performLayoutPass(plain)

            let expected = renderedBytes(plain)
            #expect(inkedByteCount(expected) > 0)
            #expect(renderedBytes(label) == expected)
        }

        @Test
        func `an idle label with an animator draws exactly like TextLabelView`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel("Paragraph", animator: animator)
            addToWindow(label, window)
            label.attributedText = text(paragraphs)
            performLayoutPass(label)
            label.displayLinkDidUpdate(frame(at: 200))
            #expect(!label.isAnimating)

            let plain = TextLabelView(attributedText: text(paragraphs))
            plain.frame = label.frame
            performLayoutPass(plain)
            #expect(renderedBytes(label) == renderedBytes(plain))
        }

        @Test
        func `an idle label has no display link and the subviews of a plain label`() {
            let window = makeWindow()
            let label = makeLabel(animator: RecordingAnimator())
            let plain = TextLabelView(attributedText: text("Hello"))
            addToWindow(label, window)
            addToWindow(plain, window)

            #expect(label.displayLink == nil)
            #expect(!label.isAnimating)
            #expect(label.subviews.count == plain.subviews.count)
            #expect(hostLayer(label).sublayers?.count == hostLayer(plain).sublayers?.count)
            #expect(label.animationLayer == nil)
        }

        @Test
        func `a minimal animator needs only the required members`() {
            let label = makeLabel(animator: MinimalAnimator())
            #expect(label.animator?.overdrawInsets == .zero)
        }

        // MARK: - Display link lifetime

        @Test
        func `an animated change binds a display link that the end of the animation releases`() throws {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel(animator: animator)
            addToWindow(label, window)
            let idleSubviews = label.subviews.count

            label.attributedText = text("Hello, world")
            #expect(label.isAnimating)
            weak let link = label.displayLink
            #expect(try #require(link).preferredFrameRateRange == label.preferredFrameRateRange)
            #expect(label.subviews.count == idleSubviews + 1)
            #expect(animator.contexts.count == 1)
            #expect(animator.changeTimes == [100])

            label.displayLinkDidUpdate(frame(at: 100.5))
            #expect(label.isAnimating)
            label.displayLinkDidUpdate(frame(at: 101.5))
            #expect(animator.advanceTimes == [100.5, 101.5])
            #expect(!label.isAnimating)
            #expect(label.displayLink == nil)
            #expect(link == nil)
            #expect(label.subviews.count == idleSubviews)
            #expect(animator.finishCount == 0)
        }

        @Test
        func `a streamed change keeps the one display link`() throws {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel(animator: animator)
            addToWindow(label, window)
            let idleSubviews = label.subviews.count

            label.attributedText = text("Hello, wor")
            let link = try #require(label.displayLink)
            label.attributedText = text("Hello, world")
            #expect(label.displayLink === link)
            #expect(label.subviews.count == idleSubviews + 1)
            #expect(animator.contexts.last?.wasAnimating == true)
        }

        @Test
        func `the frame rate range reaches a running display link`() throws {
            let window = makeWindow()
            let label = makeLabel(animator: RecordingAnimator())
            addToWindow(label, window)
            label.attributedText = text("Hello, world")
            let range = DisplayLinkFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            label.preferredFrameRateRange = range
            #expect(try #require(label.displayLink).preferredFrameRateRange == range)
        }

        // MARK: - Finishing

        @Test
        func `finishing the animations finishes the animator and releases the link`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel(animator: animator)
            addToWindow(label, window)
            let idleSubviews = label.subviews.count
            label.attributedText = text("Hello, world")

            label.finishAnimations()
            #expect(animator.finishCount == 1)
            #expect(!label.isAnimating)
            #expect(label.displayLink == nil)
            #expect(label.subviews.count == idleSubviews)

            label.finishAnimations()
            #expect(animator.finishCount == 1)
        }

        @Test
        func `leaving the window finishes the animations`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel(animator: animator)
            addToWindow(label, window)
            label.attributedText = text("Hello, world")

            label.removeFromSuperview()
            #expect(animator.finishCount == 1)
            #expect(!label.isAnimating)
            #expect(label.displayLink == nil)
        }

        @Test
        func `a new identity finishes the animations and shows the next text at once`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel(animator: animator)
            label.animationIdentity = "first"
            addToWindow(label, window)
            label.attributedText = text("Hi")
            #expect(!label.isAnimating)
            label.attributedText = text("Hi, world")
            #expect(label.isAnimating)

            label.animationIdentity = "second"
            #expect(animator.finishCount == 1)
            #expect(!label.isAnimating)

            label.attributedText = text("Another message")
            #expect(animator.contexts.count == 1)
            #expect(!label.isAnimating)

            label.attributedText = text("Another message, streamed")
            #expect(animator.contexts.count == 2)
            #expect(animator.contexts.last?.previousIdentity == AnyHashable("second"))
            #expect(animator.contexts.last?.isIdentityChange == false)
        }

        @Test
        func `a declined change finishes the animation in flight`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel(animator: animator)
            addToWindow(label, window)
            label.attributedText = text("Hello, world")
            #expect(label.isAnimating)

            label.attributedText = text("Goodbye")
            #expect(animator.finishCount == 1)
            #expect(animator.contexts.count == 1)
            #expect(!label.isAnimating)
        }

        @Test
        func `replacing the animator finishes the previous one`() {
            let first = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel(animator: first)
            addToWindow(label, window)
            label.attributedText = text("Hello, world")

            label.animator = RecordingAnimator()
            #expect(first.finishCount == 1)
            #expect(!label.isAnimating)
            #expect(label.displayLink == nil)
        }

        @Test
        func `turning reduced motion on finishes the animations`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel(animator: animator)
            addToWindow(label, window)
            label.attributedText = text("Hello, world")
            #expect(animator.contexts.last?.prefersReducedMotion == false)

            label.reducedMotionStatusDidChange()
            #expect(label.isAnimating)

            label.reducedMotionOverride = true
            label.reducedMotionStatusDidChange()
            #expect(animator.finishCount == 1)
            #expect(!label.isAnimating)
        }

        @Test
        func `reduced motion reaches the animator in the context`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel(animator: animator)
            label.reducedMotionOverride = true
            addToWindow(label, window)
            label.attributedText = text("Hello, world")
            #expect(label.isAnimating)
            #expect(animator.contexts.last?.prefersReducedMotion == true)
        }

        // MARK: - Policy

        @Test
        func `setting text without animation skips the policy`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel(animator: animator)
            var asked = 0
            label.animationPolicy = LTXClosureAnimationPolicy { _ in
                asked += 1
                return true
            }
            addToWindow(label, window)

            label.setAttributedText(text("Hello, world"), animated: false)
            #expect(asked == 0)
            #expect(animator.contexts.isEmpty)
            #expect(!label.isAnimating)
            #expect(label.attributedText.string == "Hello, world")

            label.setAttributedText(text("Hello, world!"), animated: true)
            #expect(asked == 1)
            #expect(label.isAnimating)

            label.setAttributedText(text("Hello, world!?"), animated: false)
            #expect(asked == 1)
            #expect(animator.finishCount == 1)
            #expect(!label.isAnimating)
        }

        @Test
        func `a custom policy animates a replacement of the whole text`() {
            let animator = RecordingAnimator()
            let label = makeLabel("12", animator: animator)
            label.animationPolicy = LTXClosureAnimationPolicy { _ in true }

            label.attributedText = text("37")
            #expect(label.isAnimating)
            let context = animator.contexts.last
            #expect(context?.change.isReplacement == true)
            #expect(context?.isInWindow == false)
        }

        @Test
        func `assigning equal text asks nothing`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel(animator: animator)
            addToWindow(label, window)
            var asked = 0
            label.animationPolicy = LTXClosureAnimationPolicy { _ in
                asked += 1
                return true
            }
            label.attributedText = text("Hello")
            #expect(asked == 0)
            #expect(!label.isAnimating)
        }

        @Test
        func `the context carries both layouts`() throws {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel(animator: animator)
            addToWindow(label, window)
            let previousLayout = label.textLayout

            label.attributedText = text("Hello, world")
            let context = try #require(animator.contexts.last)
            #expect(context.previousLayout === previousLayout)
            #expect(context.layout === label.textLayout)
            #expect(context.previousLayout.layoutLines.count == 1)
            #expect(context.change.insertedRange == NSRange(location: 5, length: 7))
            #expect(!context.wasAnimating)
        }

        // MARK: - Drawing

        @Test
        func `only lines in flight reach the animator`() throws {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel("", animator: animator, size: CGSize(width: 400, height: 300))
            addToWindow(label, window)
            label.attributedText = text(paragraphs)
            performLayoutPass(label)
            let lines = label.layoutLines
            try #require(lines.count == 8)

            // Characters from the middle of the third line to the start of the fourth.
            let third = lines[2].stringRange
            animator.animatingRangeOverride = NSRange(location: third.location + 4, length: third.length)
            label.displayLinkDidUpdate(frame(at: 100.25))
            drawAnimationLayer(of: label)

            #expect(animator.drawnLines.map(\.index) == [2, 3])
            #expect(animator.drawnLines.map(\.stringRange) == [lines[2].stringRange, lines[3].stringRange])
            #expect(animator.drawnLines.allSatisfy { $0.time == 100.25 })
            #expect(animator.additionalContentTimes == [100.25])
        }

        @Test
        func `the label's own drawing never reaches the animator`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel("", animator: animator)
            addToWindow(label, window)
            label.attributedText = text(paragraphs)
            performLayoutPass(label)
            #expect(label.isAnimating)

            _ = renderedBytes(label)
            #expect(animator.drawnLines.isEmpty)
            #expect(animator.additionalContentTimes.isEmpty)
        }

        @Test
        func `the label and its animation layer together draw the text once`() {
            let animator = RecordingAnimator()
            animator.drawsLines = false
            let window = makeWindow()
            let label = makeLabel("", animator: animator, size: CGSize(width: 400, height: 300))
            addToWindow(label, window)
            label.attributedText = text(paragraphs)
            performLayoutPass(label)
            let lines = label.layoutLines
            animator.animatingRangeOverride = lines[3].stringRange
            label.displayLinkDidUpdate(frame(at: 100.1))
            #expect(label.animationLayer != nil)

            let plain = TextLabelView(attributedText: text(paragraphs))
            plain.frame = label.frame
            addToWindow(plain, window)
            performLayoutPass(plain)

            // The label leaves the region out, and the layer fills exactly that.
            #expect(renderedBytes(label) != renderedBytes(plain))
            #expect(compositeBytes(label) == renderedBytes(plain))
        }

        @Test
        func `a line the animator draws is not drawn again`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel("", animator: animator)
            addToWindow(label, window)
            label.attributedText = text("Hello")
            performLayoutPass(label)
            // The animator claims the only line and draws nothing, and the label leaves the
            // line's strip to the animation layer.
            #expect(inkedByteCount(drawAnimationLayer(of: label)) == 0)
            #expect(inkedByteCount(renderedBytes(label)) == 0)
            #expect(animator.drawnLines.count == 1)
        }

        @Test
        func `a line the animator declines is drawn by the label`() {
            let animator = RecordingAnimator()
            animator.drawsLines = false
            let window = makeWindow()
            let label = makeLabel("", animator: animator)
            addToWindow(label, window)
            label.attributedText = text("Hello")
            performLayoutPass(label)
            #expect(inkedByteCount(drawAnimationLayer(of: label)) > 0)
            #expect(animator.drawnLines.count == 1)
        }

        @Test
        func `additional content is drawn even without text`() {
            let animator = RecordingAnimator()
            animator.additionalBounds = CGRect(x: 0, y: 0, width: 40, height: 20)
            let window = makeWindow()
            let label = makeLabel("12", animator: animator)
            label.animationPolicy = LTXClosureAnimationPolicy { _ in true }
            addToWindow(label, window)
            label.attributedText = text("")
            performLayoutPass(label)
            #expect(label.isAnimating)
            #expect(label.animationRegion == CGRect(x: 0, y: 0, width: 40, height: 20))
            drawAnimationLayer(of: label)
            #expect(animator.additionalContentTimes == [100])
            #expect(animator.drawnLines.isEmpty)
        }

        @Test
        func `drawing stops consulting the animator once it is idle`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel("", animator: animator)
            addToWindow(label, window)
            label.attributedText = text("Hello")
            performLayoutPass(label)
            label.displayLinkDidUpdate(frame(at: 102))
            #expect(!label.isAnimating)
            #expect(label.animationLayer == nil)

            _ = renderedBytes(label)
            #expect(animator.drawnLines.isEmpty)
            #expect(animator.additionalContentTimes.isEmpty)
        }

        // MARK: - Animation layer

        @Test
        func `the animation layer covers the strips of the lines in flight`() throws {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel("", animator: animator, size: CGSize(width: 400, height: 300))
            addToWindow(label, window)
            label.attributedText = text(paragraphs)
            performLayoutPass(label)
            let lines = label.layoutLines
            animator.animatingRangeOverride = NSRange(location: lines[2].stringRange.location, length: lines[2].stringRange.length + 2)
            label.displayLinkDidUpdate(frame(at: 100.1))

            let layer = try #require(label.animationLayer)
            let expected = pixelAligned(strip(of: 2 ..< 4, in: label), scale: label.backingScale)
            #expect(label.animationRegion == expected)
            #expect(layer.region == expected)
            #expect(isNearlyEqual(layer.frame, expected))
            #expect(layer.superlayer === hostLayer(label))
            #expect(!layer.isHidden)
        }

        @Test
        func `the animation layer reaches past the bounds by the overdraw insets`() throws {
            let animator = RecordingAnimator()
            animator.insets = LTXInsets(top: 10, left: 4, bottom: 12, right: 6)
            let window = makeWindow()
            let label = makeLabel(animator: animator)
            addToWindow(label, window)
            label.attributedText = text("Hello, world")
            performLayoutPass(label)

            let layer = try #require(label.animationLayer)
            let box = strip(of: 0 ..< 1, in: label)
            let expected = pixelAligned(animator.insets.outset(box), scale: label.backingScale)
            #expect(isNearlyEqual(layer.frame, expected))
            #expect(layer.frame.minX < 0)
            #expect(layer.frame.minY < 0)
            #expect(layer.frame.maxX > label.bounds.width)
        }

        @Test
        func `the animation layer follows the display to another scale`() throws {
            let animator = RecordingAnimator()
            animator.insets = LTXInsets(all: 0.3)
            let window = makeWindow()
            let label = makeLabel(animator: animator)
            addToWindow(label, window)
            label.attributedText = text("Hello, world")
            performLayoutPass(label)
            let layer = try #require(label.animationLayer)

            label.displayScaleOverride = 3
            #if canImport(UIKit)
                label.displayScaleDidChange()
            #else
                label.viewDidChangeBackingProperties()
            #endif
            #expect(layer.contentsScale == 3)
            let expected = pixelAligned(animator.insets.outset(strip(of: 0 ..< 1, in: label)), scale: 3)
            #expect(isNearlyEqual(label.animationRegion, expected))
            #expect(isNearlyEqual(layer.frame, expected))
        }

        @Test
        func `the animation layer sits behind the selection and is gone when idle`() throws {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel(animator: animator)
            addToWindow(label, window)
            let idleSublayers = hostLayer(label).sublayers?.count ?? 0
            label.attributedText = text("Hello, world")
            performLayoutPass(label)
            let layer = try #require(label.animationLayer)
            #expect(layer.zPosition < 0)
            for sibling in hostLayer(label).sublayers ?? [] where sibling !== layer {
                #expect(sibling.zPosition > layer.zPosition)
            }

            label.finishAnimations()
            #expect(label.animationLayer == nil)
            #expect(layer.superlayer == nil)
            #expect((hostLayer(label).sublayers?.count ?? 0) == idleSublayers)
        }

        @Test
        func `animation frames redraw the animation layer and not the label`() {
            let animator = RecordingAnimator()
            animator.duration = 10
            let window = makeWindow()
            let label = makeLabel("", animator: animator, size: CGSize(width: 400, height: 300))
            addToWindow(label, window)
            label.attributedText = text(paragraphs)
            performLayoutPass(label)
            let lines = label.layoutLines
            let inFlight = lines[6].stringRange
            animator.animatingRangeOverride = inFlight
            animator.invalidate = { $0.invalidateCharacters(in: inFlight) }
            label.displayLinkDidUpdate(frame(at: 100.01))

            let labelRequests = label.labelDisplayRequestCount
            let layerRequests = label.animationLayerDisplayRequestCount
            for step in 1 ... 30 {
                label.displayLinkDidUpdate(frame(at: 100.01 + Double(step) / 60))
            }
            #expect(label.labelDisplayRequestCount == labelRequests)
            #expect(label.animationLayerDisplayRequestCount == layerRequests + 30)

            // A frame that invalidates nothing redraws nothing.
            animator.invalidate = { _ in }
            label.displayLinkDidUpdate(frame(at: 101))
            #expect(label.animationLayerDisplayRequestCount == layerRequests + 30)

            // The line finishing hands its strip back to the label, once.
            animator.animatingRangeOverride = lines[7].stringRange
            label.displayLinkDidUpdate(frame(at: 101.1))
            #expect(label.labelDisplayRequestCount == labelRequests + 1)
            animator.duration = 0
            label.displayLinkDidUpdate(frame(at: 200))
            #expect(!label.isAnimating)
            #expect(label.labelDisplayRequestCount == labelRequests + 2)
        }

        @Test
        func `attachment views stay where a plain label puts them`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel("", animator: animator)
            addToWindow(label, window)
            let attachmentView = PlatformView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
            let attachment = TextLabel.Attachment(size: CGSize(width: 20, height: 20), view: attachmentView)
            let content = NSMutableAttributedString(attributedString: text("Before "))
            content.append(attachment.attributedString(attributes: [.font: PlatformFont.systemFont(ofSize: 16)]))
            content.append(text(" after"))
            label.attributedText = content
            performLayoutPass(label)
            #expect(label.isAnimating)
            #expect(attachmentView.superview === label)
            let animatingFrame = attachmentView.frame

            label.finishAnimations()
            performLayoutPass(label)
            #expect(attachmentView.superview === label)
            #expect(attachmentView.frame == animatingFrame)
        }

        // MARK: - Invalidation

        @Test
        func `invalidated characters redraw the strips of their lines`() throws {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel("", animator: animator, size: CGSize(width: 400, height: 300))
            addToWindow(label, window)
            label.attributedText = text(paragraphs)
            performLayoutPass(label)
            let lines = label.layoutLines
            try #require(lines.count == 8)

            let range = NSRange(location: lines[1].stringRange.location + 2, length: 3)
            animator.invalidate = { $0.invalidateCharacters(in: range) }
            label.displayLinkDidUpdate(frame(at: 100.1))
            #expect(label.invalidation.dirtyRect == strip(of: 1 ..< 2, in: label))
            #expect(!label.invalidation.invalidatesAll)

            let span = NSRange(location: lines[3].stringRange.location, length: lines[3].stringRange.length + 1)
            animator.invalidate = { $0.invalidateCharacters(in: span) }
            label.displayLinkDidUpdate(frame(at: 100.2))
            #expect(label.invalidation.dirtyRect == strip(of: 3 ..< 5, in: label))

            // Strips of neighbouring lines leave no gap, and the first and last reach past
            // their boxes.
            #expect(strip(of: 3 ..< 4, in: label).maxY >= strip(of: 4 ..< 5, in: label).minY)
            #expect(strip(of: 0 ..< 1, in: label).minY < label.viewRect(fromLayoutRect: lines[0].rect).minY)
            #expect(strip(of: 0 ..< 1, in: label).width == 400)
        }

        @Test
        func `an empty range redraws the line its location is on`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel("", animator: animator, size: CGSize(width: 400, height: 300))
            addToWindow(label, window)
            label.attributedText = text(paragraphs)
            performLayoutPass(label)
            let lines = label.layoutLines

            animator.invalidate = { $0.invalidateCharacters(in: NSRange(location: lines[5].stringRange.location, length: 0)) }
            label.displayLinkDidUpdate(frame(at: 100.1))
            #expect(label.invalidation.dirtyRect == strip(of: 5 ..< 6, in: label))

            animator.invalidate = { $0.invalidateCharacters(in: NSRange(location: 10000, length: 4)) }
            label.displayLinkDidUpdate(frame(at: 100.2))
            #expect(label.invalidation.dirtyRect.isNull)
        }

        @Test
        func `overdraw insets widen invalidated characters`() {
            let animator = RecordingAnimator()
            animator.insets = LTXInsets(top: 4, left: 2, bottom: 6, right: 8)
            let window = makeWindow()
            let label = makeLabel("", animator: animator)
            addToWindow(label, window)
            label.attributedText = text("Hello")
            performLayoutPass(label)

            animator.invalidate = { $0.invalidateCharacters(in: NSRange(location: 0, length: 1)) }
            label.displayLinkDidUpdate(frame(at: 100.1))
            let box = strip(of: 0 ..< 1, in: label)
            #expect(label.invalidation.dirtyRect == CGRect(
                x: box.minX - 2,
                y: box.minY - 4,
                width: box.width + 10,
                height: box.height + 10,
            ))
        }

        @Test
        func `invalidated rects add up with characters, and invalid rects are ignored`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel("", animator: animator)
            addToWindow(label, window)
            label.attributedText = text("Hello")
            performLayoutPass(label)

            let rect = CGRect(x: 200, y: 100, width: 10, height: 10)
            animator.invalidate = {
                $0.invalidate(rect)
                $0.invalidate(CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1))
                $0.invalidate(.null)
                $0.invalidateCharacters(in: NSRange(location: 0, length: 1))
            }
            label.displayLinkDidUpdate(frame(at: 100.1))
            #expect(label.invalidation.dirtyRect == strip(of: 0 ..< 1, in: label).union(rect))

            animator.invalidate = { $0.invalidateAll() }
            label.displayLinkDidUpdate(frame(at: 100.2))
            #expect(label.invalidation.invalidatesAll)
        }

        @Test
        func `the invalidation context starts empty on every frame`() {
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = makeLabel("", animator: animator)
            addToWindow(label, window)
            label.attributedText = text("Hello")
            performLayoutPass(label)

            animator.invalidate = { $0.invalidateAll() }
            label.displayLinkDidUpdate(frame(at: 100.1))
            animator.invalidate = { _ in }
            label.displayLinkDidUpdate(frame(at: 100.2))
            #expect(!label.invalidation.invalidatesAll)
            #expect(label.invalidation.dirtyRect.isNull)
        }

        @Test
        func `a layout of the label's own makes every invalidation redraw everything`() {
            final class CustomLayoutLabel: LTXAnimatableLabel {
                override func makeTextLayout(_ attributedText: NSAttributedString) -> TextLabel.Layout {
                    TextLabel.Layout(attributedString: attributedText)
                }
            }
            let animator = RecordingAnimator()
            let window = makeWindow()
            let label = CustomLayoutLabel(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
            label.clock = { 100 }
            label.animator = animator
            addToWindow(label, window)
            label.attributedText = text("Hello")
            performLayoutPass(label)

            animator.invalidate = { $0.invalidateCharacters(in: NSRange(location: 0, length: 1)) }
            label.displayLinkDidUpdate(frame(at: 100.1))
            #expect(label.invalidation.invalidatesAll)
            #expect(label.animationRegion.isNull)
        }

        // MARK: - Memory

        @Test
        func `releasing the label releases its animator and display link`() {
            weak var weakLabel: LTXAnimatableLabel?
            weak var weakAnimator: RecordingAnimator?
            weak var weakLink: DisplayLink?
            let window = makeWindow()
            autoreleasepool {
                let animator = RecordingAnimator()
                let label = makeLabel(animator: animator)
                addToWindow(label, window)
                label.attributedText = text("Hello, world")
                weakLabel = label
                weakAnimator = animator
                weakLink = label.displayLink
                #expect(weakLink != nil)
                label.removeFromSuperview()
                label.attributedText = text("Hello, world!")
            }
            evictCoreTextLastTypesetAttributes()
            #expect(weakLabel == nil)
            #expect(weakAnimator == nil)
            #expect(weakLink == nil)
        }

        @Test
        func `releasing an animating label out of a window releases everything`() {
            weak var weakLabel: LTXAnimatableLabel?
            weak var weakAnimator: RecordingAnimator?
            weak var weakLink: DisplayLink?
            autoreleasepool {
                let animator = RecordingAnimator()
                let label = makeLabel(animator: animator)
                label.animationPolicy = LTXClosureAnimationPolicy { _ in true }
                label.attributedText = text("Hello, world")
                weakLabel = label
                weakAnimator = animator
                weakLink = label.displayLink
            }
            #expect(weakLink == nil)
            #expect(weakLabel == nil)
            #expect(weakAnimator == nil)
        }
    }

#endif
