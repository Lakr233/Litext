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
    public class LTXLabel: LTXPlatformView, Identifiable {
        public let id: UUID = .init()

        // MARK: - Public Properties

        public var attributedText: NSAttributedString = .init() {
            didSet { textLayout = LTXTextLayout(attributedString: attributedText) }
        }

        public var preferredMaxLayoutWidth: CGFloat = 0 {
            didSet {
                if preferredMaxLayoutWidth != oldValue {
                    invalidateTextLayout()
                }
            }
        }

        override public var frame: CGRect {
            get { super.frame }
            set {
                guard newValue != super.frame else { return }
                super.frame = newValue
                invalidateTextLayout()
            }
        }

        public var isSelectable: Bool = false {
            didSet { if !isSelectable { clearSelection() } }
        }

        public var selectionBackgroundColor: PlatformColor? {
            didSet { updateSelectionLayer() }
        }

        /// When enabled, drawing is clipped to the portion of the label currently visible
        /// through its window and nearest scrolling ancestors. Layout, hit-testing, selection,
        /// and highlight regions still use the full text container.
        public var drawsOnlyVisibleText: Bool = true {
            didSet {
                guard drawsOnlyVisibleText != oldValue else { return }
                #if (canImport(UIKit) && !os(watchOS)) || (canImport(AppKit) && !targetEnvironment(macCatalyst))
                    updateVisibleRenderingObservation()
                #endif
                setNeedsTextDisplay()
            }
        }

        public internal(set) var isInteractionInProgress = false

        public weak var delegate: LTXLabelDelegate?

        // MARK: - Internal Properties

        var textLayout: LTXTextLayout = .init(attributedString: .init()) {
            didSet { invalidateTextLayout() }
        }

        var attachmentViews: Set<LTXPlatformView> = []
        var highlightRegions: [LTXHighlightRegion] {
            textLayout.highlightRegions
        }

        nonisolated(unsafe) var pendingHighlightRemovalLayers: [CALayer] = []
        var activeHighlightRegion: LTXHighlightRegion?
        var lastContainerSize: CGSize = .zero

        private var _selectionRange: NSRange?

        public var selectionRange: NSRange? {
            get {
                _selectionRange
            }
            set {
                let sanitizedRange = NSRange.sanitized(newValue, within: attributedText.length)
                guard sanitizedRange != _selectionRange else { return }
                _selectionRange = sanitizedRange
                updateSelectionLayer()
                delegate?.ltxLabelSelectionDidChange(self, selection: sanitizedRange)
            }
        }

        var selectedLinkForMenuAction: URL?
        nonisolated(unsafe) var selectionLayer: CAShapeLayer?

        #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)
            var selectionHandleStart: LTXSelectionHandle = .init(type: .start)
            var selectionHandleEnd: LTXSelectionHandle = .init(type: .end)
            var editMenuInteractionStorage: UIInteraction?
            var isEditMenuVisible = false
            var editMenuTargetRect: CGRect = .zero
        #endif

        #if canImport(UIKit) && !os(watchOS)
            weak var visibleRenderingScrollView: UIScrollView?
            var visibleRenderingBoundsObservation: NSKeyValueObservation?
            var visibleRenderingContentOffsetObservation: NSKeyValueObservation?
        #endif

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
            weak var visibleRenderingClipView: NSClipView?
            nonisolated(unsafe) var visibleRenderingBoundsObserver: NSObjectProtocol?
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
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError()
        }

        deinit {
            #if canImport(UIKit) && !os(watchOS)
                visibleRenderingBoundsObservation?.invalidate()
                visibleRenderingContentOffsetObservation?.invalidate()
            #endif
            #if canImport(AppKit) && !targetEnvironment(macCatalyst)
                if let visibleRenderingBoundsObserver {
                    NotificationCenter.default.removeObserver(visibleRenderingBoundsObserver)
                }
            #endif
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
            override public func didMoveToSuperview() {
                super.didMoveToSuperview()
                updateVisibleRenderingObservation()
                setNeedsTextDisplay()
            }

            override public func didMoveToWindow() {
                super.didMoveToWindow()
                clearSelection()
                updateVisibleRenderingObservation()
                invalidateTextLayout()
            }

        #elseif canImport(AppKit)
            override public func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                clearSelection()
                updateVisibleRenderingObservation()
                invalidateTextLayout()
                setNeedsTextDisplay()
            }

            public var backgroundColor: NSColor? {
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

    extension LTXLabel {
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
