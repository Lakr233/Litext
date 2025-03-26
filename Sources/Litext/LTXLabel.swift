//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreFoundation
import CoreText
import Foundation
import QuartzCore

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#else
    #error("unsupported platform")
#endif

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

    #if canImport(UIKit)

    #elseif canImport(AppKit)
        public var backgroundColor: PlatformColor = .clear {
            didSet {
                layer?.backgroundColor = backgroundColor.cgColor
            }
        }
    #endif

    public var tapHandler: LTXLabelTapHandler?

    public private(set) var isTouchSequenceActive: Bool = false

    // MARK: - Private Properties

    private var textLayout: LTXTextLayout?
    private var attachmentViews: Set<LTXPlatformView> = []
    private var highlightRegions: [LTXHighlightRegion] = []
    private var activeHighlightRegion: LTXHighlightRegion?
    private var initialTouchLocation: CGPoint = .zero
    private var lastContainerSize: CGSize = .zero

    private struct Flags {
        var layoutIsDirty: Bool = false
        var needsUpdateHighlightRegions: Bool = false
    }

    private var flags = Flags()

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
            // pass
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

    // MARK: - Layout & Auto Layout Support

    override public var intrinsicContentSize: CGSize {
        guard let textLayout else { return .zero }

        var constraintSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if preferredMaxLayoutWidth > 0 {
            constraintSize.width = preferredMaxLayoutWidth
        } else if lastContainerSize.width > 0 {
            constraintSize.width = lastContainerSize.width
        }

        return textLayout.suggestContainerSize(withSize: constraintSize)
    }

    #if canImport(UIKit)
        override public func layoutSubviews() {
            super.layoutSubviews()

            let containerSize = bounds.size
            if flags.layoutIsDirty || lastContainerSize != containerSize {
                if flags.layoutIsDirty || containerSize.width != lastContainerSize.width {
                    invalidateIntrinsicContentSize()
                }

                lastContainerSize = containerSize
                textLayout?.containerSize = containerSize
                flags.needsUpdateHighlightRegions = true
                flags.layoutIsDirty = false

                setNeedsDisplay()
            }
        }

        override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            invalidateTextLayout()
        }

    #elseif canImport(AppKit)
        override public func layout() {
            super.layout()

            let containerSize = bounds.size
            if flags.layoutIsDirty || lastContainerSize != containerSize {
                if flags.layoutIsDirty || containerSize.width != lastContainerSize.width {
                    invalidateIntrinsicContentSize()
                }

                lastContainerSize = containerSize
                textLayout?.containerSize = containerSize
                flags.needsUpdateHighlightRegions = true
                flags.layoutIsDirty = false

                needsDisplay = true
            }
        }
    #else
        #error("unsupported platform")
    #endif

    // MARK: - Rendering

    #if canImport(UIKit)
        override public func draw(_: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else { return }

            if flags.needsUpdateHighlightRegions {
                textLayout?.updateHighlightRegions(with: context)
                highlightRegions = textLayout?.highlightRegions ?? []
                updateAttachmentViews()
                flags.needsUpdateHighlightRegions = false
            }

            textLayout?.draw(in: context)
        }

    #elseif canImport(AppKit)

        override public func draw(_: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }

            if flags.needsUpdateHighlightRegions {
                textLayout?.updateHighlightRegions(with: context)
                highlightRegions = textLayout?.highlightRegions ?? []
                updateAttachmentViews()
                flags.needsUpdateHighlightRegions = false
            }

            textLayout?.draw(in: context)
        }
    #else
        #error("unsupported platform")
    #endif

    // MARK: - Interaction Handling

    #if canImport(UIKit)
        override public func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            if !bounds.contains(point) {
                return false
            }
            if highlightRegionAtPoint(point) == nil {
                return super.point(inside: point, with: event)
            }
            return true
        }

        override public func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let firstTouch = touches.first else { return }
            let touchLocation = firstTouch.location(in: self)

            initialTouchLocation = touchLocation

            if let hitHighlightRegion = highlightRegionAtPoint(touchLocation) {
                addActiveHighlightRegion(hitHighlightRegion)
            }

            isTouchSequenceActive = true
        }

        override public func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard activeHighlightRegion != nil, let firstTouch = touches.first else { return }

            let currentLocation = firstTouch.location(in: self)
            let distance = hypot(currentLocation.x - initialTouchLocation.x, currentLocation.y - initialTouchLocation.y)

            if distance > 2 {
                removeActiveHighlightRegion()
                isTouchSequenceActive = false
            }
        }

        override public func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let activeHighlightRegion else {
                isTouchSequenceActive = false
                return
            }

            // FIXME: currently a single touch is supported
            guard let firstTouch = touches.first else { return }
            let touchLocation = firstTouch.location(in: self)

            if isHighlightRegion(activeHighlightRegion, containsPoint: touchLocation) {
                tapHandler?(activeHighlightRegion, touchLocation)
            }

            removeActiveHighlightRegion()
            isTouchSequenceActive = false
        }

        override public func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
            removeActiveHighlightRegion()
            isTouchSequenceActive = false
        }

    #elseif canImport(AppKit)
        override public func mouseDown(with event: NSEvent) {
            let touchLocation = convert(event.locationInWindow, from: nil)
            initialTouchLocation = touchLocation

            if let hitHighlightRegion = highlightRegionAtPoint(touchLocation) {
                addActiveHighlightRegion(hitHighlightRegion)
            }

            isTouchSequenceActive = true
        }

        override public func mouseDragged(with event: NSEvent) {
            guard activeHighlightRegion != nil else { return }

            let currentLocation = convert(event.locationInWindow, from: nil)
            let distance = hypot(currentLocation.x - initialTouchLocation.x, currentLocation.y - initialTouchLocation.y)

            if distance > 4.0 {
                removeActiveHighlightRegion()
                isTouchSequenceActive = false
            }
        }

        override public func mouseUp(with event: NSEvent) {
            guard let activeHighlightRegion else {
                isTouchSequenceActive = false
                return
            }

            let touchLocation = convert(event.locationInWindow, from: nil)

            if isHighlightRegion(activeHighlightRegion, containsPoint: touchLocation) {
                tapHandler?(activeHighlightRegion, touchLocation)
            }

            removeActiveHighlightRegion()
            isTouchSequenceActive = false
        }

        override public func hitTest(_ point: NSPoint) -> NSView? {
            if !bounds.contains(point) { return nil }
            if highlightRegionAtPoint(point) == nil {
                return super.hitTest(point)
            }
            return self
        }

    #else
        #error("unsupported platform")
    #endif

    // MARK: - Text Layout

    private func invalidateTextLayout() {
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

    // MARK: - Highlight Region

    private func highlightRegionAtPoint(_ point: CGPoint) -> LTXHighlightRegion? {
        for region in highlightRegions {
            if isHighlightRegion(region, containsPoint: point) {
                if region.attributes[.link] == nil {
                    continue
                }
                return region
            }
        }
        return nil
    }

    private func isHighlightRegion(_ highlightRegion: LTXHighlightRegion, containsPoint point: CGPoint) -> Bool {
        for boxedRect in highlightRegion.rects {
            #if canImport(UIKit)
                let rect = boxedRect.cgRectValue
            #elseif canImport(AppKit)
                let rect = boxedRect.rectValue
            #else
                #error("unsupported platform")
            #endif

            let convertedRect = convertRectFromTextLayout(rect, forInteraction: true)
            if convertedRect.contains(point) {
                return true
            }
        }
        return false
    }

    private func convertRectFromTextLayout(_ rect: CGRect, forInteraction interaction: Bool) -> CGRect {
        var result = rect
        result.origin.y = bounds.height - result.origin.y - result.size.height
        if interaction {
            result = result.insetBy(dx: -4, dy: -4)
        }
        return result
    }

    private func addActiveHighlightRegion(_ highlightRegion: LTXHighlightRegion) {
        removeActiveHighlightRegion()

        activeHighlightRegion = highlightRegion

        let highlightPath = LTXPlatformBezierPath()
        for boxedRect in highlightRegion.rects {
            #if canImport(UIKit)
                let rect = boxedRect.cgRectValue
            #elseif canImport(AppKit)
                let rect = boxedRect.rectValue
            #else
                #error("unsupported platform")
            #endif

            let convertedRect = convertRectFromTextLayout(rect, forInteraction: true)

            #if canImport(UIKit)
                let subpath = LTXPlatformBezierPath(roundedRect: convertedRect, cornerRadius: 4)
                highlightPath.append(subpath)
            #elseif canImport(AppKit)
                let subpath = LTXPlatformBezierPath.bezierPath(withRoundedRect: convertedRect, cornerRadius: 4)
                highlightPath.appendPath(subpath)
            #else
                #error("unsupported platform")
            #endif
        }

        let highlightColor: PlatformColor
        if let color = highlightRegion.attributes[.foregroundColor] as? PlatformColor {
            highlightColor = color
        } else {
            #if canImport(UIKit)
                highlightColor = .systemBlue
            #elseif canImport(AppKit)
                highlightColor = .linkColor
            #else
                #error("unsupported platform")
            #endif
        }

        let highlightLayer = CAShapeLayer()

        #if canImport(UIKit)
            highlightLayer.path = highlightPath.cgPath
        #elseif canImport(AppKit)
            highlightLayer.path = highlightPath.quartzPath
        #else
            #error("unsupported platform")
        #endif

        highlightLayer.fillColor = highlightColor.withAlphaComponent(0.1).cgColor

        #if canImport(UIKit)
            layer.addSublayer(highlightLayer)
        #elseif canImport(AppKit)
            layer?.addSublayer(highlightLayer)
        #else
            #error("unsupported platform")
        #endif

        highlightRegion.associatedObject = highlightLayer
    }

    private func removeActiveHighlightRegion() {
        guard let activeHighlightRegion else { return }

        if let highlightLayer = activeHighlightRegion.associatedObject as? CALayer {
            highlightLayer.opacity = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                highlightLayer.removeFromSuperlayer()
            }
        }

        activeHighlightRegion.associatedObject = nil
        self.activeHighlightRegion = nil
    }

    // MARK: - Attachment

    private func updateAttachmentViews() {
        let viewsToRemove = attachmentViews
        var newAttachmentViews: Set<LTXPlatformView> = []

        for highlightRegion in highlightRegions {
            guard let attachment = highlightRegion.attributes[LTXAttachmentAttributeName] as? LTXAttachment,
                  let view = attachment.view else { continue }

            if view.superview == self {
                newAttachmentViews.insert(view)
            } else {
                addSubview(view)
                newAttachmentViews.insert(view)
            }

            #if canImport(UIKit)
                let rect = highlightRegion.rects.first!.cgRectValue
            #elseif canImport(AppKit)
                let rect = highlightRegion.rects.first!.rectValue
            #else
                #error("unsupported platform")
            #endif

            let convertedRect = convertRectFromTextLayout(rect, forInteraction: false)
            view.frame = convertedRect
        }

        for view in viewsToRemove {
            if !newAttachmentViews.contains(view) {
                view.removeFromSuperview()
            }
        }

        attachmentViews = newAttachmentViews
    }
}
