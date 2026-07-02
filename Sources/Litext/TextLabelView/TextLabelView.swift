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
            didSet { textLayout = TextLabel.Layout(attributedString: attributedText) }
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
                super.frame = newValue
                invalidateTextLayout()
            }
        }

        open var isSelectable: Bool = false {
            didSet { if !isSelectable { clearSelection() } }
        }

        open var selectionBackgroundColor: PlatformColor? {
            didSet { updateSelectionLayer() }
        }

        open internal(set) var isInteractionInProgress = false

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

        private var _selectionRange: NSRange?

        open var selectionRange: NSRange? {
            get {
                _selectionRange
            }
            set {
                let sanitizedRange = NSRange.sanitized(newValue, within: attributedText.length)
                guard sanitizedRange != _selectionRange else { return }
                _selectionRange = sanitizedRange
                updateSelectionLayer()
                delegate?.textLabelView(self, didChangeSelection: sanitizedRange)
            }
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
                    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
                        self.invalidateTextLayout()
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
            textLayout = TextLabel.Layout(attributedString: attributedText)
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
                invalidateTextLayout()
                setNeedsTextDisplay()
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
            var lastClickTime: TimeInterval = 0
            /// AppKit uses this to clear a pre-existing selection on the first drag event.
            var isFirstMove: Bool = false
        }

        struct Flags {
            var layoutIsDirty: Bool = false
        }
    }

#endif // !os(watchOS)
