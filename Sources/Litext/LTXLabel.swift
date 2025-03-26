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

    public internal(set) var isTouchSequenceActive: Bool = false

    // MARK: - Internal Properties

    var textLayout: LTXTextLayout?
    var attachmentViews: Set<LTXPlatformView> = []
    var highlightRegions: [LTXHighlightRegion] = []
    var activeHighlightRegion: LTXHighlightRegion?
    var initialTouchLocation: CGPoint = .zero
    var lastContainerSize: CGSize = .zero

    // Selection properties
    var selectionStartPoint: CGPoint?
    var selectionEndPoint: CGPoint?
    var selectionRange: NSRange?
    var selectionLayer: CAShapeLayer?

    // 右键菜单相关
    var currentLinkURL: String?
    
    // 交互状态结构体
    struct InteractionState {
        var clickCount: Int = 0
        var lastClickTime: TimeInterval = 0
        let multiClickTimeThreshold: TimeInterval = 0.3
    }
    
    var interactionState = InteractionState()

    struct Flags {
        var layoutIsDirty: Bool = false
        var needsUpdateHighlightRegions: Bool = false
        var isSelectingText: Bool = false
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
        clearSelection()
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
