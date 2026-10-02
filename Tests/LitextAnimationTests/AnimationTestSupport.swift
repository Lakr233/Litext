//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  A recording animator, synthetic frames and the view helpers the label tests share.
//  Test targets cannot share sources, so the few helpers this needs from
//  `LitextTests/MemoryTestSupport.swift` are repeated here.
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

    // MARK: - Recording animator

    /// An animator that records every call the label makes and animates for a fixed time.
    @MainActor
    final class RecordingAnimator: LTXTextAnimator {
        struct DrawnLine: Equatable {
            let index: Int
            let stringRange: NSRange
            let time: CFTimeInterval
        }

        // What the label asked.
        private(set) var contexts: [LTXAnimationContext] = []
        private(set) var changeTimes: [CFTimeInterval] = []
        private(set) var advanceTimes: [CFTimeInterval] = []
        private(set) var drawnLines: [DrawnLine] = []
        private(set) var additionalContentTimes: [CFTimeInterval] = []
        private(set) var finishCount = 0

        /// How the animator behaves.
        /// The time the animation ends at, counted from the last change.
        var duration: CFTimeInterval = 1
        /// What `animatingRange` reports; `nil` reports the last inserted range.
        var animatingRangeOverride: NSRange?
        var drawsLines = true
        var insets: LTXInsets = .zero
        var additionalBounds: CGRect = .null
        /// Called on every step to invalidate.
        var invalidate: (LTXInvalidationContext) -> Void = { _ in }

        private var endTime: CFTimeInterval = 0
        private var insertedRange: NSRange?

        func animateChange(_ context: LTXAnimationContext, at time: CFTimeInterval) {
            contexts.append(context)
            changeTimes.append(time)
            insertedRange = context.change.insertedRange
            endTime = time + duration
        }

        func advance(to time: CFTimeInterval, invalidation: LTXInvalidationContext) -> Bool {
            advanceTimes.append(time)
            invalidate(invalidation)
            let isActive = time < endTime
            if !isActive {
                insertedRange = nil
            }
            return isActive
        }

        var animatingRange: NSRange? {
            animatingRangeOverride ?? insertedRange
        }

        func draw(_ line: LTXAnimatedLine, in _: CGContext, at time: CFTimeInterval) -> Bool {
            drawnLines.append(DrawnLine(index: line.index, stringRange: line.stringRange, time: time))
            return drawsLines
        }

        func drawAdditionalContent(in _: CGContext, at time: CFTimeInterval) {
            additionalContentTimes.append(time)
        }

        var overdrawInsets: LTXInsets {
            insets
        }

        var additionalContentBounds: CGRect {
            additionalBounds
        }

        func finish() {
            finishCount += 1
            insertedRange = nil
            endTime = 0
        }

        func resetRecords() {
            contexts.removeAll()
            changeTimes.removeAll()
            advanceTimes.removeAll()
            drawnLines.removeAll()
            additionalContentTimes.removeAll()
            finishCount = 0
        }
    }

    /// An animator with only the required members, which proves a minimal one compiles
    /// against the protocol defaults.
    @MainActor
    final class MinimalAnimator: LTXTextAnimator {
        func animateChange(_: LTXAnimationContext, at _: CFTimeInterval) {}
        func advance(to _: CFTimeInterval, invalidation _: LTXInvalidationContext) -> Bool {
            false
        }

        var animatingRange: NSRange? {
            nil
        }

        func draw(_: LTXAnimatedLine, in _: CGContext, at _: CFTimeInterval) -> Bool {
            false
        }

        func finish() {}
    }

    // MARK: - Frames and text

    /// A display frame whose target timestamp is `time`.
    func frame(at time: CFTimeInterval) -> DisplayLinkFrame {
        DisplayLinkFrame(timestamp: time - 1.0 / 60, targetTimestamp: time)
    }

    @MainActor
    func text(_ string: String, size: CGFloat = 16) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: PlatformFont.systemFont(ofSize: size)])
    }

    /// Several lines at a label width of 200 points, one paragraph each.
    let paragraphs = (1 ... 8).map { "Paragraph \($0) of the streamed reply." }.joined(separator: "\n")

    // MARK: - Labels and windows

    /// A label with a synthetic clock at time 100, laid out at `size`.
    @MainActor
    func makeLabel(
        _ string: String = "Hello",
        animator: (any LTXTextAnimator)? = nil,
        size: CGSize = CGSize(width: 320, height: 240),
    ) -> LTXAnimatableLabel {
        let label = LTXAnimatableLabel(frame: CGRect(origin: .zero, size: size))
        label.clock = { 100 }
        label.reducedMotionOverride = false
        label.animator = animator
        label.attributedText = text(string)
        performLayoutPass(label)
        return label
    }

    @MainActor
    func performLayoutPass(_ label: TextLabelView) {
        #if canImport(UIKit)
            label.setNeedsLayout()
            label.layoutIfNeeded()
        #elseif canImport(AppKit)
            label.needsLayout = true
            label.layout()
        #endif
    }

    #if canImport(UIKit)
        typealias TestWindow = UIWindow

        @MainActor
        func makeWindow() -> UIWindow {
            UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        }

        @MainActor
        func addToWindow(_ view: PlatformView, _ window: UIWindow) {
            window.addSubview(view)
        }
    #elseif canImport(AppKit)
        typealias TestWindow = NSWindow

        @MainActor
        func makeWindow() -> NSWindow {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 400, height: 400),
                styleMask: [.titled],
                backing: .buffered,
                defer: false,
            )
            window.isReleasedWhenClosed = false
            return window
        }

        @MainActor
        func addToWindow(_ view: PlatformView, _ window: NSWindow) {
            window.contentView?.addSubview(view)
        }
    #endif

    // MARK: - Rendering

    /// Paints `label` through its own `draw(_:)` into an RGBA bitmap and returns the bytes.
    @MainActor
    func renderedBytes(_ label: TextLabelView, scale: CGFloat = 2) -> [UInt8] {
        let width = Int(label.bounds.width * scale)
        let height = Int(label.bounds.height * scale)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return }
            // A top-left space, as a view's drawing context has.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: scale, y: -scale)
            #if canImport(UIKit)
                UIGraphicsPushContext(context)
                label.draw(label.bounds)
                UIGraphicsPopContext()
            #elseif canImport(AppKit)
                let previous = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                label.draw(label.bounds)
                NSGraphicsContext.current = previous
            #endif
        }
        return bytes
    }

    /// Draws the label's animation layer the way Core Animation does, into an RGBA bitmap of
    /// the layer's size, and returns the bytes. Draws nothing without a layer.
    @MainActor
    @discardableResult
    func drawAnimationLayer(of label: LTXAnimatableLabel, scale: CGFloat = 2) -> [UInt8] {
        guard let layer = label.animationLayer else { return [] }
        let width = Int((layer.bounds.width * scale).rounded(.up))
        let height = Int((layer.bounds.height * scale).rounded(.up))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return }
            if layer.contentsAreFlipped() {
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: scale, y: -scale)
            } else {
                context.scaleBy(x: scale, y: scale)
            }
            layer.draw(in: context)
        }
        return bytes
    }

    /// Paints the label through its own `draw(_:)`, then its animation layer over the
    /// animation region, the way the two appear on screen, and returns the bytes.
    @MainActor
    func compositeBytes(_ label: LTXAnimatableLabel, scale: CGFloat = 2) -> [UInt8] {
        let width = Int(label.bounds.width * scale)
        let height = Int(label.bounds.height * scale)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: scale, y: -scale)
            #if canImport(UIKit)
                UIGraphicsPushContext(context)
                label.draw(label.bounds)
                UIGraphicsPopContext()
            #elseif canImport(AppKit)
                let previous = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                label.draw(label.bounds)
                NSGraphicsContext.current = previous
            #endif
            guard let layer = label.animationLayer, !layer.isHidden else { return }
            context.saveGState()
            context.translateBy(x: layer.region.minX, y: layer.region.minY)
            context.clip(to: CGRect(origin: .zero, size: layer.region.size))
            if !layer.contentsAreFlipped() {
                context.translateBy(x: 0, y: layer.region.height)
                context.scaleBy(x: 1, y: -1)
            }
            layer.draw(in: context)
            context.restoreGState()
        }
        return bytes
    }

    @MainActor
    func hostLayer(_ view: PlatformView) -> CALayer {
        #if canImport(UIKit)
            view.layer
        #else
            view.wantsLayer = true
            return view.layer!
        #endif
    }

    // MARK: - Geometry

    /// The strip of the label that `lines` own: its width, and halfway into the gaps to the
    /// neighbouring lines, or half a line height past the first and last lines.
    @MainActor
    func strip(of lines: Range<Int>, in label: TextLabelView) -> CGRect {
        let all = label.layoutLines
        let boxes = all.map { label.viewRect(fromLayoutRect: $0.rect) }
        let first = boxes[lines.lowerBound]
        let last = boxes[lines.upperBound - 1]
        // Boxes of neighbouring lines can overlap; a strip always covers its own boxes.
        let top = lines.lowerBound > 0
            ? min(first.minY, (boxes[lines.lowerBound - 1].maxY + first.minY) / 2)
            : first.minY - first.height / 2
        let bottom = lines.upperBound < boxes.count
            ? max(last.maxY, (last.maxY + boxes[lines.upperBound].minY) / 2)
            : last.maxY + last.height / 2
        let maxX = max(label.textLayout.containerSize.width, first.maxX, last.maxX)
        let minX = min(0, first.minX, last.minX)
        return CGRect(x: minX, y: top, width: maxX - minX, height: bottom - top)
    }

    /// Whether two rects agree to well under a pixel. A layer's `frame` is derived from its
    /// position and bounds, so it does not always read back exactly as assigned.
    func isNearlyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 1e-6 && abs(lhs.minY - rhs.minY) < 1e-6
            && abs(lhs.width - rhs.width) < 1e-6 && abs(lhs.height - rhs.height) < 1e-6
    }

    /// `rect` grown outward to whole pixels at `scale`.
    func pixelAligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let minX = (rect.minX * scale).rounded(.down) / scale
        let minY = (rect.minY * scale).rounded(.down) / scale
        let maxX = (rect.maxX * scale).rounded(.up) / scale
        let maxY = (rect.maxY * scale).rounded(.up) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The number of bytes that are not zero, so a test can tell an empty bitmap from text.
    func inkedByteCount(_ bytes: [UInt8]) -> Int {
        bytes.reduce(0) { $0 + ($1 == 0 ? 0 : 1) }
    }

    // MARK: - Memory

    /// A weak reference that can live in an array.
    @MainActor
    final class WeakBox<Value: AnyObject> {
        weak var value: Value?

        init(_ value: Value) {
            self.value = value
        }
    }

    /// Typesets one unrelated line, which makes CoreText let go of the attributes of the
    /// string it typeset before. See `LitextTests/MemoryTestSupport.swift`.
    @MainActor
    func evictCoreTextLastTypesetAttributes() {
        _ = CTLineCreateWithAttributedString(NSAttributedString(string: "evict"))
    }

#endif
