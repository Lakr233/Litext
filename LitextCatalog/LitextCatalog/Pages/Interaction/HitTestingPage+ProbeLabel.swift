//
//  HitTestingPage+ProbeLabel.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  A TextLabelView that follows the pointer or a finger and asks the label
//  what lies under it, drawing a marker over the character and the link or
//  attachment it finds. The hit-testing and emoji pages share it.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// What the label reports for one point, every value straight from its public API.
struct HitProbeResult: Equatable {
    /// The probed point in the label's coordinates (top-left origin).
    var viewPoint: CGPoint
    /// The same point in CoreText layout space (lower-left origin).
    var layoutPoint: CGPoint
    /// `TextLabelView.characterIndex(at:)`: the character under the point.
    var characterIndex: Int?
    /// `TextLabel.Layout.textIndex(at:)`: the caret index on the line under the point.
    var textIndex: Int?
    /// `TextLabel.Layout.nearestTextIndex(at:)`: the caret index on the nearest line.
    var nearestTextIndex: Int?
    /// The grapheme cluster around `characterIndex`, in UTF-16 units.
    var clusterRange: NSRange?
    var clusterText: String?
    /// `TextLabelView.highlightRegion(at:)`.
    var regionKind: String?
    var regionRange: NSRange?
    var regionURL: String?
}

/// Receives the probe's results so SwiftUI readouts can show them.
@Observable
final class HitProbeModel {
    var result: HitProbeResult?
}

/// A label that hit-tests the point under the pointer (macOS, iPad pointer),
/// under a finger (iOS, visionOS) or at a point set in code (tvOS), and marks
/// what it finds.
final class HitProbeLabel: TextLabelView {
    /// Called with each new result, outside SwiftUI's update pass.
    var onResult: ((HitProbeResult?) -> Void)?

    /// The character the probe starts on before any pointer or touch arrives, so
    /// the page opens with something to read.
    var initialProbeIndex: Int?

    /// Whether to outline the link or attachment region under the probe.
    var showsRegionRects = true {
        didSet { updateMarkers() }
    }

    /// The point probed, in the label's coordinates.
    private(set) var probePoint: CGPoint?
    /// A point given as fractions of the bounds, for platforms without a pointer.
    var probeFraction: CGPoint? {
        didSet { applyProbeFraction() }
    }

    private let regionLayer = CAShapeLayer()
    private let characterLayer = CAShapeLayer()
    private let pointLayer = CAShapeLayer()

    #if canImport(UIKit)
        override init(frame: CGRect) {
            super.init(frame: frame)
            installMarkerLayers()
            #if os(iOS) || os(visionOS)
                addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
            #endif
        }
    #else
        override init(frame: CGRect) {
            super.init(frame: frame)
            installMarkerLayers()
        }
    #endif

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Following the pointer

    #if canImport(UIKit)
        /// The label claims touches only over links or selectable text; the probe
        /// wants them anywhere inside it.
        override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
            bounds.contains(point)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            if let touch = touches.first {
                probe(at: touch.location(in: self))
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event)
            if let touch = touches.first {
                probe(at: touch.location(in: self))
            }
        }

        #if os(iOS) || os(visionOS)
            @objc private func hover(_ recognizer: UIHoverGestureRecognizer) {
                switch recognizer.state {
                case .began, .changed:
                    probe(at: recognizer.location(in: self))
                default:
                    break
                }
            }
        #endif

        override func layoutSubviews() {
            super.layoutSubviews()
            layoutDidChange()
        }
    #else
        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            probe(at: convert(event.locationInWindow, from: nil))
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            probe(at: convert(event.locationInWindow, from: nil))
        }

        override func mouseDragged(with event: NSEvent) {
            super.mouseDragged(with: event)
            probe(at: convert(event.locationInWindow, from: nil))
        }

        override func layout() {
            super.layout()
            layoutDidChange()
        }
    #endif

    /// Probes `point`, in the label's coordinates, and reports what lies there.
    func probe(at point: CGPoint) {
        probePoint = point
        updateMarkers()
        onResult?(currentResult())
    }

    // MARK: Asking the label

    private func currentResult() -> HitProbeResult? {
        guard let point = probePoint else { return nil }
        let layoutPoint = layoutPoint(fromViewPoint: point)
        let characterIndex = characterIndex(at: point)
        let string = attributedText.string as NSString
        var result = HitProbeResult(
            viewPoint: point,
            layoutPoint: layoutPoint,
            characterIndex: characterIndex,
            textIndex: textLayout.textIndex(at: layoutPoint),
            nearestTextIndex: textLayout.nearestTextIndex(at: layoutPoint),
        )
        if let characterIndex, characterIndex < string.length {
            let cluster = string.rangeOfComposedCharacterSequence(at: characterIndex)
            result.clusterRange = cluster
            result.clusterText = string.substring(with: cluster)
        }
        if let region = highlightRegion(at: point) {
            result.regionKind = region.kind == .link ? "link" : "attachment"
            result.regionRange = region.stringRange
            result.regionURL = region.linkURL?.absoluteString
        }
        return result
    }

    // MARK: Markers

    private func installMarkerLayers() {
        #if canImport(UIKit)
            let host = layer
        #else
            wantsLayer = true
            guard let host = layer else { return }
        #endif
        regionLayer.fillColor = PlatformColor.systemOrange.withAlphaComponent(0.12).cgColor
        regionLayer.strokeColor = PlatformColor.systemOrange.cgColor
        regionLayer.lineWidth = 1
        characterLayer.fillColor = PlatformColor.systemPink.withAlphaComponent(0.22).cgColor
        characterLayer.strokeColor = PlatformColor.systemPink.cgColor
        characterLayer.lineWidth = 1
        pointLayer.fillColor = PlatformColor.systemPink.cgColor
        pointLayer.strokeColor = PlatformColor.white.cgColor
        pointLayer.lineWidth = 1.5
        for marker in [regionLayer, characterLayer, pointLayer] {
            marker.zPosition = 10
            host.addSublayer(marker)
        }
    }

    private func layoutDidChange() {
        if probePoint == nil, let index = initialProbeIndex {
            startProbe(atCharacter: index)
        } else if probeFraction != nil {
            applyProbeFraction()
        } else {
            updateMarkers()
            let result = currentResult()
            let onResult = onResult
            // Layout can run inside a SwiftUI update; report one hop later.
            DispatchQueue.main.async { onResult?(result) }
        }
    }

    private func startProbe(atCharacter index: Int) {
        let string = attributedText.string as NSString
        guard index < string.length else { return }
        let cluster = string.rangeOfComposedCharacterSequence(at: index)
        guard let rect = textLayout.rects(for: cluster).first else { return }
        let viewRect = viewRect(fromLayoutRect: rect)
        probePoint = CGPoint(x: viewRect.midX, y: viewRect.midY)
        updateMarkers()
        let result = currentResult()
        let onResult = onResult
        DispatchQueue.main.async { onResult?(result) }
    }

    private func applyProbeFraction() {
        guard let probeFraction, bounds.width > 0, bounds.height > 0 else { return }
        let point = CGPoint(x: bounds.width * probeFraction.x, y: bounds.height * probeFraction.y)
        guard point != probePoint else { return }
        probePoint = point
        updateMarkers()
        let result = currentResult()
        let onResult = onResult
        DispatchQueue.main.async { onResult?(result) }
    }

    private func updateMarkers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let point = probePoint else {
            for marker in [regionLayer, characterLayer, pointLayer] {
                marker.path = nil
            }
            return
        }
        pointLayer.path = CGPath(
            ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8),
            transform: nil,
        )

        let characterPath = CGMutablePath()
        let string = attributedText.string as NSString
        if let index = characterIndex(at: point), index < string.length {
            let cluster = string.rangeOfComposedCharacterSequence(at: index)
            for rect in textLayout.rects(for: cluster) {
                characterPath.addRect(viewRect(fromLayoutRect: rect))
            }
        }
        characterLayer.path = characterPath

        let regionPath = CGMutablePath()
        if showsRegionRects, let region = highlightRegion(at: point) {
            for rect in region.rects {
                let viewRect = viewRect(fromLayoutRect: rect).insetBy(dx: -2, dy: -2)
                regionPath.addRoundedRect(in: viewRect, cornerWidth: 3, cornerHeight: 3)
            }
        }
        regionLayer.path = regionPath
    }
}

extension HitProbeResult {
    static func describe(_ range: NSRange?) -> String {
        guard let range else { return "nil" }
        return "{\(range.location), \(range.length)}"
    }

    static func describe(_ index: Int?) -> String {
        index.map(String.init) ?? "nil"
    }

    static func describe(_ point: CGPoint) -> String {
        "(\(Int(point.x.rounded())), \(Int(point.y.rounded())))"
    }

    /// The cluster's Unicode scalars as `U+` code points.
    static func scalars(of text: String?) -> String {
        guard let text else { return "nil" }
        return text.unicodeScalars
            .map { "U+" + String($0.value, radix: 16, uppercase: true) }
            .joined(separator: " ")
    }
}
