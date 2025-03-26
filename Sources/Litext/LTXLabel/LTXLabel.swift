//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreFoundation
import CoreText
import Foundation
import QuartzCore

public typealias LTXLabelTapHandler = (LTXHighlightRegion?, CGPoint) -> Void

public class LTXLabel: LTXPlatformView {
    // MARK: - Public Properties

    public var attributedText: NSAttributedString? {
        didSet {
            if let attributedText {
                textLayout = LTXTextLayout(attributedString: attributedText)
                invalidateTextLayout()
            }
        }
    }

    public var preferredMaxLayoutWidth: CGFloat = 0 {
        didSet {
            if preferredMaxLayoutWidth != oldValue {
                invalidateTextLayout()
            }
        }
    }

    public var isSelectable: Bool = false {
        didSet {
            if !isSelectable {
                clearSelection()
            }
        }
    }

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

    var textLayout: LTXTextLayout?
    var attachmentViews: Set<LTXPlatformView> = []
    var highlightRegions: [LTXHighlightRegion] = []
    var activeHighlightRegion: LTXHighlightRegion?
    var lastContainerSize: CGSize = .zero

    var selectionRange: NSRange? {
        didSet { updateSelectionLayer() }
    }

    var selectedLinkForMenuAction: URL?
    var selectionLayer: CAShapeLayer?

    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        var selectionHandleStart: LTXSelectionHandle = .init(type: .start)
        var selectionHandleEnd: LTXSelectionHandle = .init(type: .end)
    #endif

    struct InteractionState {
        var initialTouchLocation: CGPoint = .zero
        var clickCount: Int = 1
        var lastClickTime: TimeInterval = 0
        var isFirstMove: Bool = false
    }

    var interactionState = InteractionState()

    struct Flags {
        var layoutIsDirty: Bool = false
        var needsUpdateHighlightRegions: Bool = false
    }

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

    private func commonInit() {
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
        #elseif canImport(AppKit)
            wantsLayer = true
            layer?.backgroundColor = .clear
        #else
            #error("unsupported platform")
        #endif
        attachmentViews = []
    }

    // MARK: - Platform Specific

    #if canImport(UIKit)
    // pass
    #elseif canImport(AppKit)
        override public var isFlipped: Bool {
            true
        }
    #else
        #error("unsupported platform")
    #endif

    // MARK: - Text Layout

    func invalidateTextLayout() {
        flags.layoutIsDirty = true
        #if canImport(UIKit)
            setNeedsLayout()
        #elseif canImport(AppKit)
            needsLayout = true
        #else
            #error("unsupported platform")
        #endif
        invalidateIntrinsicContentSize()
    }
}
