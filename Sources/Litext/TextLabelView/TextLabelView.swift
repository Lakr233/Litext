//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreFoundation
import CoreText
import Foundation
import QuartzCore

#if canImport(UIKit) && !os(watchOS)
    import UIKit
#endif

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    import AppKit
#endif

#if !os(watchOS)

    /// A label that draws attributed text with CoreText, with tappable links,
    /// inline attachment views and optional text selection.
    ///
    /// Subclasses that override a layout, drawing or interaction method must call
    /// `super`: the base implementations keep the text layout, the selection and the
    /// menus in step.
    @MainActor
    open class TextLabelView: PlatformView, Identifiable {
        /// A stable identity for the label, unique to each instance.
        public let id: UUID = .init()

        // MARK: - Public Properties

        /// The text the label shows.
        ///
        /// Assigning new text keeps the current selection only when the text up to its end,
        /// including the attachment objects there, is unchanged. A reusing host such as a table
        /// or collection view cell should call `clearSelection()` in `prepareForReuse()`, since
        /// unrelated content can still share a prefix with the previous one.
        ///
        /// - Important: Performance-sensitive. The string is copied on every
        ///   assignment and compared with the previous one; an equal string stops
        ///   there, and a different one builds a new layout through
        ///   `makeTextLayout(_:)` and is typeset on the next layout pass. The new
        ///   layout reuses the previous one's lines before the first changed
        ///   paragraph; see `TextLabel.Layout.reuseTypesetting(from:)`. Overrides
        ///   must call `super`.
        open var attributedText: NSAttributedString = .init() {
            didSet {
                // Keep an immutable snapshot, as UILabel and NSTextField do. Otherwise a
                // caller that edits its mutable string and assigns the same object again
                // would compare the object with itself below and the edit would be lost.
                // Assigning inside `didSet` does not re-trigger the observer.
                attributedText = attributedText.copy() as! NSAttributedString
                // Reusing hosts (cells, SwiftUI updates) routinely reassign an equal
                // string; rebuilding the framesetter for those costs a full measurement
                // pass. Call `reloadTextLayout()` to force a rebuild when the string is
                // unchanged but state a run delegate reads from is not.
                guard !attributedText.isEqual(to: oldValue) else { return }
                resetInteractionForNewText(replacing: oldValue)
                let layout = makeTextLayout(attributedText)
                // Text that only changed near its end, as a streamed document does,
                // typesets only the paragraphs that changed.
                layout.reuseTypesetting(from: textLayout)
                textLayout = layout
            }
        }

        /// Drops interaction state that refers to the previous string.
        ///
        /// The pressed-link overlay and the multi-click sequence always belong to the old
        /// text. The selection survives only when every character up to its end, and every
        /// attachment object there, is unchanged, which keeps a selection alive while a
        /// host streams text onto the end of the label. Other attributes may change: a
        /// streaming markdown renderer restyles text it has already shown.
        /// `isInteractionInProgress` and the gesture phase flags are left alone, since the
        /// platform still delivers the rest of the touch or mouse sequence, but a gesture in
        /// progress no longer taps a link when it ends: the link under it is new.
        private func resetInteractionForNewText(replacing oldText: NSAttributedString) {
            deactivateHighlightRegion()
            NSObject.cancelPreviousPerformRequests(
                withTarget: self,
                selector: #selector(performContinuousStateReset),
                object: nil,
            )
            performContinuousStateReset()
            if isInteractionInProgress {
                interactionState.isTapCancelled = true
            }

            guard let range = selectionRange else { return }
            // A group cannot keep a selection whose part in one member moved.
            if selectionGroup != nil {
                clearSelection()
                return
            }
            let selectionEnd = NSMaxRange(range)
            let isPrefixUnchanged = selectionEnd <= oldText.length
                && selectionEnd <= attributedText.length
                && (oldText.string as NSString).substring(to: selectionEnd)
                == (attributedText.string as NSString).substring(to: selectionEnd)
                && Self.attachments(in: oldText, upTo: selectionEnd)
                .elementsEqual(Self.attachments(in: attributedText, upTo: selectionEnd), by: ===)
            if !isPrefixUnchanged {
                clearSelection()
            }
        }

        /// The attachment objects in the first `length` characters of `text`, in order.
        private static func attachments(
            in text: NSAttributedString,
            upTo length: Int,
        ) -> [TextLabel.Attachment] {
            var result = [TextLabel.Attachment]()
            guard length > 0 else { return result }
            text.enumerateAttribute(
                .litextAttachment,
                in: NSRange(location: 0, length: length),
                options: [],
            ) { value, _, _ in
                if let attachment = value as? TextLabel.Attachment {
                    result.append(attachment)
                }
            }
            return result
        }

        /// The layout built for every new `attributedText`. Override to hand the
        /// view a `TextLabel.Layout` subclass, for example one that draws lines
        /// differently while keeping Litext's measurement and selection.
        ///
        /// Called once for each new string. Return a fresh layout: it should not be
        /// shared with another label.
        open func makeTextLayout(_ attributedText: NSAttributedString) -> TextLabel.Layout {
            TextLabel.Layout(attributedString: attributedText)
        }

        /// The width `intrinsicContentSize` wraps the text at, like
        /// `UILabel.preferredMaxLayoutWidth`. Zero, the default, wraps at the width
        /// the label was last laid out at, or not at all before that.
        open var preferredMaxLayoutWidth: CGFloat = 0 {
            didSet {
                if preferredMaxLayoutWidth != oldValue {
                    invalidateTextLayout()
                }
            }
        }

        /// Moving the label leaves the text layout alone; a size change invalidates it.
        /// Overrides must call `super`.
        override open var frame: CGRect {
            get { super.frame }
            set {
                guard newValue != super.frame else { return }
                let oldSize = super.frame.size
                let sizeChanged = newValue.size != oldSize
                super.frame = newValue
                // Text layout follows `bounds.size`, the intrinsic size follows
                // `preferredMaxLayoutWidth` / `lastContainerSize.width`, and selection
                // validity follows the string length. A pure move changes none of them,
                // so invalidating there would re-extract highlights, re-place attachment
                // views, and repaint the whole backing store on every scroll step.
                guard sizeChanged else { return }
                invalidateTextLayout(invalidatesIntrinsicSize: newValue.width != oldSize.width)
            }
        }

        /// Whether people can select the text. Turning it off clears the selection
        /// the label holds. Links stay tappable either way.
        open var isSelectable: Bool = false {
            didSet {
                if !isSelectable {
                    clearSelectionHeldHere()
                }
                #if canImport(UIKit) && !os(tvOS)
                    updateInputProxy()
                #endif
            }
        }

        /// The color behind selected text; `nil` uses the system's selection color.
        /// On iOS the selection handles use it at full opacity.
        open var selectionBackgroundColor: PlatformColor? {
            didSet { updateSelectionLayer() }
        }

        /// The color of the highlight shown while a link is pressed. `nil`, the
        /// default, uses the link's foreground color at 10% opacity, or the system
        /// blue when it has none. A color you set is used as it is, alpha included.
        open var linkHighlightColor: PlatformColor?

        /// The corner radius of the pressed-link highlight, in points.
        open var linkHighlightCornerRadius: CGFloat = 4

        /// Whether a touch or mouse sequence that began on the label is still running.
        public internal(set) var isInteractionInProgress = false

        /// Receives link and attachment taps, selection changes and menu requests.
        open weak var delegate: TextLabelViewDelegate?

        /// The group whose selection the label shares, set through
        /// `TextSelectionGroup.labels`.
        public internal(set) var selectionGroup: TextSelectionGroup?

        /// The layout showing `attributedText`, built by `makeTextLayout(_:)`.
        ///
        /// Read it to query geometry the view does not forward, such as
        /// `rects(for:)` or `nearestTextIndex(at:)`. The label owns it: setting its
        /// `containerSize` or drawing it elsewhere puts it out of step with the
        /// view until the next layout pass.
        public internal(set) var textLayout: TextLabel.Layout = .init(attributedString: .init()) {
            didSet {
                textLayout.lineRenderer = lineRenderer
                invalidateTextLayout()
            }
        }

        /// Draws each line of the text: what goes behind its glyphs, then the glyphs.
        /// `nil`, the default, draws them with `CTLineDraw` alone.
        ///
        /// The label hands it to every layout it shows, including the ones a subclass
        /// returns from `makeTextLayout(_:)`. Setting it redraws the text without laying
        /// it out again. See `TextLabel.LineRenderer`.
        open var lineRenderer: TextLabel.LineRenderer? {
            didSet {
                guard lineRenderer !== oldValue else { return }
                textLayout.lineRenderer = lineRenderer
                setNeedsTextDisplay()
            }
        }

        // MARK: - Internal Properties

        var attachmentViews: Set<PlatformView> = []
        var highlightRegions: [TextLabel.HighlightRegion] {
            textLayout.highlightRegions
        }

        nonisolated(unsafe) var pendingHighlightRemovalLayers: [CALayer] = []
        var activeHighlightRegion: TextLabel.HighlightRegion?
        var lastContainerSize: CGSize = .zero
        /// The `textLayout.generation` whose highlight regions were last extracted.
        var highlightRegionsGeneration: Int?

        private var _selectionRange: NSRange?

        /// The selected range of `attributedText`, or `nil` when nothing is
        /// selected. Setting it shows the selection and its menu; a range past the
        /// end of the text is clipped to it. In a `TextSelectionGroup` the range
        /// becomes the group's selection, in this label only.
        open var selectionRange: NSRange? {
            get {
                _selectionRange
            }
            set {
                setSelectionRange(newValue, presentsMenu: true)
            }
        }

        /// Sets the selection like the public setter, optionally without presenting the
        /// menu or broadcasting the change to sibling labels, for use while a drag is
        /// still moving the selection.
        ///
        /// In a group, the range becomes the group's selection, in this label only.
        func setSelectionRange(_ newValue: NSRange?, presentsMenu: Bool) {
            if let selectionGroup {
                selectionGroup.select(newValue, in: self, presentsMenu: presentsMenu)
                return
            }
            let sanitizedRange = NSRange.sanitized(newValue, within: attributedText.length)
            guard sanitizedRange != _selectionRange else { return }
            #if canImport(UIKit) && !os(tvOS)
                performSelectionChange { _selectionRange = sanitizedRange }
            #else
                _selectionRange = sanitizedRange
            #endif
            updateSelectionLayer(presentsMenu: presentsMenu)
            delegate?.textLabelView(self, didChangeSelection: sanitizedRange)
        }

        /// Sets this member's part of its group's selection. The group presents the
        /// menu, so this only redraws the selection and its handles, which can move
        /// between members even when the part is unchanged.
        func applyGroupSegment(_ range: NSRange?) {
            let sanitizedRange = NSRange.sanitized(range, within: attributedText.length)
            let didChange = sanitizedRange != _selectionRange
            if didChange {
                #if canImport(UIKit) && !os(tvOS)
                    performSelectionChange { _selectionRange = sanitizedRange }
                #else
                    _selectionRange = sanitizedRange
                #endif
            }
            updateSelectionLayer(presentsMenu: false)
            if didChange {
                delegate?.textLabelView(self, didChangeSelection: sanitizedRange)
            }
        }

        var selectedLinkForMenuAction: URL?
        nonisolated(unsafe) var selectionLayer: CAShapeLayer?

        #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
            var selectionHandleStart: SelectionHandle = .init(kind: .start)
            var selectionHandleEnd: SelectionHandle = .init(kind: .end)
            /// Created the first time the handles show in a window.
            nonisolated(unsafe) var selectionHandleGrabGesture: SelectionHandleGrabGesture?
            var isEditMenuVisible = false
            /// When the edit menu last began to dismiss, in system uptime like
            /// `UITouch.timestamp`.
            var editMenuDismissalTime: TimeInterval = 0
            var editMenuTargetRect: CGRect = .zero
        #endif

        #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
            /// The `TextLabelInputProxy` while the label is selectable, from iOS 16 and
            /// Mac Catalyst 16. Typed loosely because the class needs those systems.
            var inputProxyStorage: UIView?
        #endif

        var interactionState = InteractionState()
        var flags = Flags()

        // MARK: - Initialization

        #if canImport(UIKit)
            override public init(frame: CGRect) {
                super.init(frame: frame)
                registerNotificationCenterForSelectionDeduplicate()

                backgroundColor = .clear
                #if !os(tvOS) && !os(watchOS)
                    // On iOS a right click shows the selection menu from `touchesEnded`.
                    // A context menu interaction would also watch every touch for a long
                    // press, and on iOS 18 it holds back a selection handle drag that
                    // starts over the label until the finger lifts.
                    #if targetEnvironment(macCatalyst)
                        installContextMenuInteraction()
                    #else
                        installLongPressSelection()
                    #endif
                    installTextPointerInteraction()
                #endif

                #if !os(tvOS)
                    isMultipleTouchEnabled = false
                    isExclusiveTouch = true
                #endif

                #if !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                    clipsToBounds = false // for selection handle
                    selectionHandleStart.isHidden = true
                    addSubview(selectionHandleStart)
                    selectionHandleEnd.isHidden = true
                    addSubview(selectionHandleEnd)
                #endif

                if #available(iOS 17.0, tvOS 17.0, visionOS 1.0, *) {
                    // Only colors follow the interface style, so the intrinsic size stays valid.
                    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
                        self.invalidateTextLayout(invalidatesIntrinsicSize: false)
                    }
                }
            }

        #elseif canImport(AppKit)
            override public init(frame: CGRect) {
                super.init(frame: frame)
                registerNotificationCenterForSelectionDeduplicate()
                wantsLayer = true
                layer?.backgroundColor = NSColor.clear.cgColor
            }
        #endif

        public convenience init(frame: CGRect = .zero, attributedText: NSAttributedString) {
            self.init(frame: frame)
            self.attributedText = attributedText
            textLayout = makeTextLayout(attributedText)
            invalidateTextLayout()
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError()
        }

        deinit {
            selectionLayer?.removeFromSuperlayer()
            pendingHighlightRemovalLayers.forEach { $0.removeFromSuperlayer() }
            if let activeHighlightRegion,
               let highlightLayer = activeHighlightRegion.associatedObject as? CALayer
            {
                highlightLayer.removeFromSuperlayer()
            }
            NotificationCenter.default.removeObserver(self)
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                selectionHandleGrabGesture?.detachWhenLabelDeallocates()
            #endif
        }

        #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
            /// Hiding the label also stops its selection handles taking touches.
            override open var isHidden: Bool {
                didSet { updateSelectionHandleGrabGesture() }
            }

            /// Detaches the selection handle gesture from the old window. Overrides must
            /// call `super`.
            override open func willMove(toWindow newWindow: UIWindow?) {
                super.willMove(toWindow: newWindow)
                // Off the old window before the label leaves it; the selection clears once
                // the label is in the new one.
                if newWindow !== window {
                    selectionHandleGrabGesture?.detach()
                }
            }
        #endif

        #if canImport(UIKit)
            /// Clears the selection the label holds and lays the text out again for the
            /// new window. Overrides must call `super`.
            override open func didMoveToWindow() {
                super.didMoveToWindow()
                clearSelectionHeldHere()
                invalidateTextLayout()
            }

        #elseif canImport(AppKit)
            /// Clears the selection the label holds and lays the text out again for the
            /// new window. Overrides must call `super`.
            override open func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                clearSelectionHeldHere()
                // No display request here: the pending layout pass issues one once the text
                // layout matches the new geometry. See `TextLabelView.canDrawTextLayout`.
                invalidateTextLayout()
            }

            /// The layer's background color, mirroring `UIView.backgroundColor`.
            open var backgroundColor: NSColor? {
                get {
                    guard let cgColor = layer?.backgroundColor else { return nil }
                    return NSColor(cgColor: cgColor)
                }
                set {
                    wantsLayer = true
                    layer?.backgroundColor = newValue?.cgColor
                }
            }
        #endif
    }

    extension TextLabelView {
        /// Drops the selection when the label can no longer show it: it moved to
        /// another window or out of one, or stopped being selectable. A group member
        /// clears the group only when part of the selection is in it, so a host that
        /// reuses, scrolls away or disables other members keeps the selection.
        func clearSelectionHeldHere() {
            if selectionGroup != nil, selectionRange == nil {
                updateSelectionLayer(presentsMenu: false)
                return
            }
            clearSelection()
        }

        struct InteractionState {
            var initialTouchLocation: CGPoint = .zero
            var clickCount: Int = 1
            /// The click count as it stood when the current touch began. UIKit reads this
            /// at touchesEnded, because the multi-click timer may reset `clickCount` while
            /// a second or third tap is still held down.
            var clickCountAtBegin: Int = 1
            var lastClickTime: TimeInterval = 0
            /// AppKit uses this to clear a pre-existing selection on the first drag event.
            var isFirstMove: Bool = false
            /// Set when the interaction began over an attachment view and was forwarded to
            /// `super`, so the remaining phases are forwarded too instead of driving selection.
            var isForwardingToSuper: Bool = false
            /// Set when the text changes while the interaction is in progress, so its release
            /// does not tap whatever link now lies under the pointer.
            var isTapCancelled: Bool = false
            /// Set while a selection handle is being dragged. Touches forwarded to the label
            /// during the drag must not end the interaction the handle started.
            var isDraggingSelectionHandle: Bool = false
            /// Set when the interaction began with a secondary (right) click, which shows
            /// the selection menu when it ends.
            var isSecondaryClick: Bool = false
            /// The word a long press selected, which a drag that follows extends.
            var longPressWordRange: NSRange?
            /// Whether the selection menu showed when the touch began. A tap on the
            /// selection hides a menu that showed and shows one that did not.
            var wasSelectionMenuVisible: Bool = false
        }

        struct Flags {
            var layoutIsDirty: Bool = false
        }
    }

#endif // !os(watchOS)
