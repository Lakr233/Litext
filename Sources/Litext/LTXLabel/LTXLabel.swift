//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreFoundation
import CoreText
import Foundation
import QuartzCore

public class LTXLabel: LTXPlatformView {
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

    public var tapHandler: LTXLabelTapHandler?

    // MARK: - Internal Properties

    var textLayout: LTXTextLayout? {
        didSet { invalidateTextLayout() }
    }

    var attachmentViews: Set<LTXPlatformView> = []
    var highlightRegions: [LTXHighlightRegion] = []
    var activeHighlightRegion: LTXHighlightRegion?
    var lastContainerSize: CGSize = .zero

    var selectionRange: NSRange? {
        didSet { updateSelectionLayer() }
    }

    #if canImport(UIKit)
        var firstResponderKeeper: Timer?
    #endif
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
        #if canImport(UIKit)
            firstResponderKeeper?.invalidate()
        #endif
        NotificationCenter.default.removeObserver(self)
    }

    private func commonInit() {
        registerNotificationCenterForSelectionDeduplicate()

        #if canImport(UIKit)
            backgroundColor = .clear

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

            let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self else { return }
                if selectionRange != nil, !isFirstResponder {
                    becomeFirstResponder()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            firstResponderKeeper = timer
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
