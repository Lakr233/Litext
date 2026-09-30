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

    @MainActor
    open class TextLabelView: PlatformView, Identifiable {
        public let id: UUID = .init()

        // MARK: - Public Properties

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
                textLayout = makeTextLayout(attributedText)
            }
        }

        /// Drops interaction state that refers to the previous string.
        ///
        /// The pressed-link overlay and the multi-click sequence always belong to the old
        /// text. The selection survives only when every character up to its end is
        /// unchanged, which keeps a selection alive while a host streams text onto the
        /// end of the label. `isInteractionInProgress` and the gesture phase flags are left
        /// alone: the platform still delivers the rest of the touch or mouse sequence.
        private func resetInteractionForNewText(replacing oldText: NSAttributedString) {
            deactivateHighlightRegion()
            NSObject.cancelPreviousPerformRequests(
                withTarget: self,
                selector: #selector(performContinuousStateReset),
                object: nil
            )
            performContinuousStateReset()

            guard let range = selectionRange else { return }
            let selectionEnd = NSMaxRange(range)
            let isPrefixUnchanged = selectionEnd <= oldText.length
                && selectionEnd <= attributedText.length
                && (oldText.string as NSString).substring(to: selectionEnd)
                == (attributedText.string as NSString).substring(to: selectionEnd)
            if !isPrefixUnchanged {
                clearSelection()
            }
        }

        /// The layout built for every new `attributedText`. Override to hand the
        /// view a `TextLabel.Layout` subclass, for example one that draws lines
        /// differently while keeping Litext's measurement and selection.
        open func makeTextLayout(_ attributedText: NSAttributedString) -> TextLabel.Layout {
            TextLabel.Layout(attributedString: attributedText)
        }

        open var preferredMaxLayoutWidth: CGFloat = 0 {
            didSet {
                if preferredMaxLayoutWidth != oldValue {
                    invalidateTextLayout()
                }
            }
        }

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

        open var isSelectable: Bool = false {
            didSet {
                if !isSelectable {
                    clearSelection()
                }
            }
        }

        open var selectionBackgroundColor: PlatformColor? {
            didSet { updateSelectionLayer() }
        }

        /// Whether a touch or mouse sequence that began on the label is still running.
        public internal(set) var isInteractionInProgress = false

        open weak var delegate: TextLabelViewDelegate?

        // MARK: - Internal Properties

        var textLayout: TextLabel.Layout = .init(attributedString: .init()) {
            didSet { invalidateTextLayout() }
        }

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
        func setSelectionRange(_ newValue: NSRange?, presentsMenu: Bool) {
            let sanitizedRange = NSRange.sanitized(newValue, within: attributedText.length)
            guard sanitizedRange != _selectionRange else { return }
            _selectionRange = sanitizedRange
            updateSelectionLayer(presentsMenu: presentsMenu)
            delegate?.textLabelView(self, didChangeSelection: sanitizedRange)
        }

        var selectedLinkForMenuAction: URL?
        nonisolated(unsafe) var selectionLayer: CAShapeLayer?

        #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
            var selectionHandleStart: SelectionHandle = .init(kind: .start)
            var selectionHandleEnd: SelectionHandle = .init(kind: .end)
            var editMenuInteractionStorage: UIInteraction?
            var isEditMenuVisible = false
            var editMenuTargetRect: CGRect = .zero
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
                    installContextMenuInteraction()
                    installTextPointerInteraction()
                #endif

                #if !os(tvOS)
                    isMultipleTouchEnabled = false
                    isExclusiveTouch = true
                #endif

                #if !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
                    clipsToBounds = false // for selection handle
                    selectionHandleStart.isHidden = true
                    selectionHandleStart.delegate = self
                    addSubview(selectionHandleStart)
                    selectionHandleEnd.isHidden = true
                    selectionHandleEnd.delegate = self
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
        }

        #if canImport(UIKit)
            override open func didMoveToWindow() {
                super.didMoveToWindow()
                clearSelection()
                invalidateTextLayout()
            }

        #elseif canImport(AppKit)
            override open func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                clearSelection()
                // No display request here: the pending layout pass issues one once the text
                // layout matches the new geometry. See `TextLabelView.canDrawTextLayout`.
                invalidateTextLayout()
            }

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
        }

        struct Flags {
            var layoutIsDirty: Bool = false
        }
    }

#endif // !os(watchOS)
