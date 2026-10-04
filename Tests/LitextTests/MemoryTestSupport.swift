//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation
@testable import Litext
import Testing

#if canImport(UIKit) && !os(watchOS)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

extension Tag {
    /// Deallocation and leak checks.
    @Tag static var memory: Self
    /// Coarse process-level checks that only catch large regressions.
    @Tag static var smoke: Self
}

// MARK: - Waiting

/// Lets the main actor, the main dispatch queue and the main run loop make progress until
/// `condition` holds or `timeout` passes. Returns whether the condition held.
///
/// Swift Testing drives the main actor from the main run loop, so sleeping here lets
/// `DispatchQueue.main.asyncAfter`, `perform(_:with:afterDelay:)` and main-actor tasks run.
/// The timeout is generous because other main-actor tests can hold the run loop for a while;
/// a passing wait returns as soon as the condition holds.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(5),
    _ condition: () -> Bool,
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// Typesets one unrelated line, which makes CoreText let go of the attributes of the
/// string it typeset before.
///
/// CoreText on iOS keeps the attributes of the last string it typeset on a thread until that
/// thread typesets another one, however long it waits, so an attribute value such as a
/// `TextLabel.Attachment` outlives every string, framesetter and line that named it. The
/// cache holds that one entry per thread: it is bounded, independent of Litext, and released
/// by typesetting anything else on the same thread. A test that checks an attribute value
/// deallocates calls this first, on the thread that typeset it.
@MainActor
func evictCoreTextLastTypesetAttributes() {
    _ = CTLineCreateWithAttributedString(NSAttributedString(string: "evict"))
}

/// Gives already-queued main-actor work a few turns without sleeping.
@MainActor
func yieldToMainActor(times: Int = 10) async {
    for _ in 0 ..< times {
        await Task.yield()
    }
}

/// Lets queued and delayed main-thread work run for `duration`.
@MainActor
func spinMainRunLoop(for duration: Duration) async {
    try? await Task.sleep(for: duration)
}

/// A weak reference that can live in an array.
@MainActor
final class WeakBox<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value) {
        self.value = value
    }
}

// MARK: - Content

/// Text that no other test lays out, so CoreText's own caches never hand this test a line
/// another test built, and a line this test built is never kept alive by another test.
@MainActor
func uniqueText(_ prefix: String = "Memory", length: Int = 0) -> NSMutableAttributedString {
    var string = "\(prefix) \(UUID().uuidString)"
    while string.count < length {
        string += " lorem ipsum dolor sit amet"
    }
    return NSMutableAttributedString(
        string: string,
        attributes: [.font: PlatformFont.systemFont(ofSize: 16)],
    )
}

@MainActor
func appendLink(to text: NSMutableAttributedString, _ title: String = "link") {
    text.append(NSAttributedString(
        string: " \(title)",
        attributes: [
            .font: PlatformFont.systemFont(ofSize: 16),
            .link: URL(string: "https://example.com/\(UUID().uuidString)")!,
        ],
    ))
}

@MainActor
func appendAttachment(to text: NSMutableAttributedString, _ attachment: TextLabel.Attachment) {
    text.append(NSAttributedString(string: " ", attributes: [.font: PlatformFont.systemFont(ofSize: 16)]))
    text.append(attachment.attributedString(attributes: [.font: PlatformFont.systemFont(ofSize: 16)]))
}

// MARK: - Layout internals

/// Reads a stored property of `TextLabel.Layout` that is `private` in the module, so the
/// tests can observe caches without widening their access level.
@MainActor
func layoutStoredValue(_ layout: TextLabel.Layout, _ name: String) -> Any? {
    var mirror: Mirror? = Mirror(reflecting: layout)
    while let current = mirror {
        if let child = current.children.first(where: { $0.label == name }) {
            return child.value
        }
        mirror = current.superclassMirror
    }
    return nil
}

/// The number of entries in the layout's measurement history (`suggestedSizeHistory`),
/// the only cache that grows with the number of distinct sizes measured.
@MainActor
func measurementHistoryCount(_ layout: TextLabel.Layout) throws -> Int {
    let value = try #require(layoutStoredValue(layout, "suggestedSizeHistory"))
    return Mirror(reflecting: value).children.count
}

@MainActor
func layoutFramesetter(_ layout: TextLabel.Layout) throws -> CTFramesetter {
    // Built the first time the layout typesets the whole string.
    let optional = try #require(layoutStoredValue(layout, "cachedFramesetter"))
    let value = try #require(Mirror(reflecting: optional).children.first?.value)
    return value as! CTFramesetter
}

@MainActor
func layoutLines(_ layout: TextLabel.Layout) -> [CTLine] {
    (layoutStoredValue(layout, "lines") as? [CTLine]?)?.flatMap(\.self) ?? []
}

/// The retain count of the private metrics box an attachment's run delegate reads. The
/// attachment holds one reference and its cached run delegate holds another, so a balanced
/// box reads one more after `runDelegate` was first created than before.
@MainActor
func runMetricsRetainCount(_ attachment: TextLabel.Attachment) throws -> CFIndex {
    var mirror: Mirror? = Mirror(reflecting: attachment)
    while let current = mirror {
        if let child = current.children.first(where: { $0.label == "runMetrics" }) {
            return CFGetRetainCount(child.value as AnyObject)
        }
        mirror = current.superclassMirror
    }
    Issue.record("TextLabel.Attachment has no runMetrics box")
    return 0
}

// MARK: - Views

#if !os(watchOS)

    @MainActor
    func makeLaidOutTestLabel(
        _ text: NSAttributedString,
        size: CGSize = CGSize(width: 320, height: 120),
    ) -> TextLabelView {
        let label = TextLabelView(attributedText: text)
        label.frame = CGRect(origin: .zero, size: size)
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

    /// Paints the label into an offscreen bitmap through its own `draw(_:)`.
    @MainActor
    func render(_ label: TextLabelView) {
        #if canImport(UIKit)
            let renderer = UIGraphicsImageRenderer(bounds: label.bounds)
            _ = renderer.image { _ in label.draw(label.bounds) }
        #elseif canImport(AppKit)
            guard let rep = label.bitmapImageRepForCachingDisplay(in: label.bounds) else { return }
            label.cacheDisplay(in: label.bounds, to: rep)
        #endif
    }

    @MainActor
    func sublayerCount(_ label: TextLabelView) -> Int {
        label.backingLayer?.sublayers?.count ?? 0
    }

    /// A delegate that owns its label, as a view controller does.
    @MainActor
    final class OwningDelegate: TextLabelViewDelegate {
        var label: TextLabelView?
        var selectionChanges = 0

        func textLabelView(_: TextLabelView, didChangeSelection _: NSRange?) {
            selectionChanges += 1
        }
    }

    /// The first `TextLabelView` in `view`'s subtree, depth first.
    @MainActor
    func findTextLabelView(in view: PlatformView) -> TextLabelView? {
        if let label = view as? TextLabelView {
            return label
        }
        for subview in view.subviews {
            if let label = findTextLabelView(in: subview) {
                return label
            }
        }
        return nil
    }

#endif

// MARK: - Process memory

/// The process's physical footprint, the figure Xcode's memory gauge and jetsam use.
func physicalFootprint() -> UInt64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size,
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }
    return info.phys_footprint
}
