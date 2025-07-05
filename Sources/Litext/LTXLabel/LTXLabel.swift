//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreFoundation
import CoreText
import Foundation
import QuartzCore

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

    public internal(set) var isInteractionInProgress = false

    #if canImport(UIKit)

    #elseif canImport(AppKit)
        public var backgroundColor: PlatformColor = .clear {
            didSet {
                layer?.backgroundColor = backgroundColor.cgColor
            }
        }
    #endif

    public weak var delegate: LTXLabelDelegate?

    // MARK: - Internal Properties

    var textLayout: LTXTextLayout? {
        didSet { invalidateTextLayout() }
    }

    var attachmentViews: Set<LTXPlatformView> = []
    var highlightRegions: [LTXHighlightRegion] = []
    var activeHighlightRegion: LTXHighlightRegion?
    var lastContainerSize: CGSize = .zero

    public internal(set) var selectionRange: NSRange? {
        didSet {
            updateSelectionLayer()
            if selectionRange != oldValue {
                delegate?.ltxLabelSelectionDidChange(self, selection: selectionRange)
            }
        }
    }

    var selectedLinkForMenuAction: URL?
    var selectionLayer: CAShapeLayer?

    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        var selectionHandleStart: LTXSelectionHandle = .init(type: .start)
        var selectionHandleEnd: LTXSelectionHandle = .init(type: .end)
    #endif

    var interactionState = InteractionState()
    var flags = Flags()

    // MARK: - Initialization

    override public init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        attributedText = .init()
        attachmentViews = []
        clearSelection()
        deactivateHighlightRegion()
        NotificationCenter.default.removeObserver(self)
    }

    private func commonInit() {
        registerNotificationCenterForSelectionDeduplicate()

        #if canImport(UIKit)
            backgroundColor = .clear
            installContextMenuInteraction()
            installTextPointerInteraction()

            #if targetEnvironment(macCatalyst)
            #else
                clipsToBounds = false // for selection handle
                selectionHandleStart.isHidden = true
                selectionHandleStart.delegate = self
                addSubview(selectionHandleStart)
                selectionHandleEnd.isHidden = true
                selectionHandleEnd.delegate = self
                addSubview(selectionHandleEnd)
            #endif
        #elseif canImport(AppKit)
            wantsLayer = true
            layer?.backgroundColor = .clear
        #endif
    }

    // MARK: - Platform Specific

    #if !canImport(UIKit) && canImport(AppKit)
        override public var isFlipped: Bool {
            true
        }
    #endif

    #if canImport(UIKit)
        override public func didMoveToWindow() {
            super.didMoveToWindow()
            clearSelection()
            invalidateTextLayout()
        }

    #elseif canImport(AppKit)
        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            clearSelection()
            invalidateTextLayout()
        }
    #endif
}

extension LTXLabel {
    struct InteractionState {
        var initialTouchLocation: CGPoint = .zero
        var clickCount: Int = 1
        var lastClickTime: TimeInterval = 0
        var isFirstMove: Bool = false
    }

    struct Flags {
        var layoutIsDirty: Bool = false
        var needsUpdateHighlightRegions: Bool = false
    }
}
