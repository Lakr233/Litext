//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//
//  Stress: strings holding attachments, typeset and released off the main
//  thread, the way a cache of rendered strings is cleared under memory
//  pressure. See StressSupport.swift for the quick and full modes.
//
//  CoreText keeps the attributes of the last string it typeset on each thread,
//  so every background block typesets an unrelated line before it returns;
//  otherwise a worker thread would keep one string's attachments alive.
//

import CoreGraphics
import CoreText
import Foundation
@testable import Litext
import Testing

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#if !os(watchOS)

    /// A value shared between the main actor and background threads.
    private final class Locked<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value

        init(_ value: Value) {
            self.value = value
        }

        func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
            lock.lock()
            defer { lock.unlock() }
            return body(&value)
        }

        /// Returns the value and leaves `nil` in its place.
        func take<Wrapped>() -> Wrapped? where Value == Wrapped? {
            withLock { value in
                defer { value = nil }
                return value
            }
        }
    }

    /// An attachment whose size is computed and never stored.
    private final class SquareAttachment: TextLabel.Attachment {
        let side: CGFloat

        init(side: CGFloat) {
            self.side = side
            super.init()
        }

        override var size: CGSize {
            get { CGSize(width: side, height: side) }
            set {}
        }
    }

    /// Makes CoreText on the current thread let go of the last string it typeset.
    private func evictCoreTextCacheOnCurrentThread() {
        _ = CTLineCreateWithAttributedString(NSAttributedString(string: "evict"))
    }

    @MainActor private let font = PlatformFont.systemFont(ofSize: 14)

    /// Text followed by three attachments: a stored size, a computed size and an
    /// explicit descent. Returns the string, weak references to the attachments
    /// and their total width.
    @MainActor
    private func attachmentString(
        _ index: Int,
        withViews: Bool,
    ) -> (string: NSAttributedString, attachments: [WeakBox<TextLabel.Attachment>], width: Double) {
        let result = NSMutableAttributedString(string: "item \(index) ", attributes: [.font: font])
        let attachments: [TextLabel.Attachment] = [
            TextLabel.Attachment(size: CGSize(width: 20, height: 12)),
            SquareAttachment(side: CGFloat(10 + index % 7)),
            TextLabel.Attachment(size: CGSize(width: 22, height: 12)),
        ]
        attachments[2].descent = 3
        for attachment in attachments {
            if withViews {
                attachment.view = PlatformView(frame: .zero)
            }
            result.append(attachment.attributedString(attributes: [.font: font]))
        }
        let width = attachments.reduce(0) { $0 + Double($1.size.width) }
        return (result, attachments.map(WeakBox.init), width)
    }

    @Suite(.tags(.stress), StressMode.enabled, .serialized)
    @MainActor
    struct StressOffMainReleaseTests {
        @Test
        func `thousands of strings are released concurrently on background threads`() async {
            let count = StressMode.pick(4000, full: 40000)
            var strings: [NSAttributedString?] = []
            var attachments: [WeakBox<TextLabel.Attachment>] = []
            for index in 0 ..< count {
                let made = attachmentString(index, withViews: index.isMultiple(of: 4))
                // Measure on the main actor first, so the cached run delegates are the ones released.
                _ = TextLabel.Layout(attributedString: made.string).sizeThatFits(CGSize(width: 300, height: 0))
                strings.append(made.string)
                attachments.append(contentsOf: made.attachments)
            }
            let shared = Locked(strings)
            strings.removeAll()

            await Task.detached {
                DispatchQueue.concurrentPerform(iterations: count) { index in
                    autoreleasepool {
                        let string = shared.withLock { strings in
                            defer { strings[index] = nil }
                            return strings[index]
                        }
                        if let string {
                            _ = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(string), nil, nil, nil)
                        }
                        evictCoreTextCacheOnCurrentThread()
                    }
                }
            }.value

            evictCoreTextLastTypesetAttributes()
            let released = await waitUntil(timeout: .seconds(10)) { attachments.allSatisfy { $0.value == nil } }
            let alive = attachments.count { $0.value != nil }
            #expect(released, "\(alive) of \(attachments.count) attachments are still alive")
        }

        @Test
        func `a string typeset on many threads at once measures the same everywhere and is released`() async {
            // Only `shared` holds the string, so the background thread that clears it releases it.
            let (shared, attachments, attachmentWidth) = {
                let made = attachmentString(7, withViews: true)
                return (Locked<NSAttributedString?>(made.string), made.attachments, made.width)
            }()
            let textWidth = CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(NSAttributedString(string: "item 7 ", attributes: [.font: font])),
                nil, nil, nil,
            )
            let expected = textWidth + attachmentWidth
            let rounds = StressMode.pick(2000, full: 20000)
            let mismatches = Locked(0)

            await Task.detached {
                DispatchQueue.concurrentPerform(iterations: rounds) { _ in
                    autoreleasepool {
                        guard let string = shared.withLock({ $0 }) else { return }
                        let framesetter = CTFramesetterCreateWithAttributedString(string)
                        let path = CGPath(rect: CGRect(x: 0, y: 0, width: 1000, height: 100), transform: nil)
                        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
                        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
                        let width = lines.first.map { CTLineGetTypographicBounds($0, nil, nil, nil) } ?? 0
                        if abs(width - expected) > 0.5 {
                            mismatches.withLock { $0 += 1 }
                        }
                        evictCoreTextCacheOnCurrentThread()
                    }
                }
                _ = shared.take()
            }.value

            #expect(mismatches.withLock { $0 } == 0)
            evictCoreTextLastTypesetAttributes()
            #expect(await waitUntil { attachments.allSatisfy { $0.value == nil } })
        }

        @Test
        func `a cache cleared on a background queue while a label keeps showing its strings`() async {
            let cache = Locked<[Int: NSAttributedString]>([:])
            let stop = Locked(false)
            let clears = Locked(0)
            // Clears the cache over and over, the way a memory-pressure handler would.
            let clearer = Task.detached {
                while !stop.withLock({ $0 }) {
                    autoreleasepool {
                        let removed = cache.withLock { cache in
                            defer { cache.removeAll() }
                            return cache
                        }
                        _ = removed.count
                        evictCoreTextCacheOnCurrentThread()
                    }
                    clears.withLock { $0 += 1 }
                    try? await Task.sleep(for: .microseconds(200))
                }
            }

            let label = TextLabelView()
            label.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
            label.preferredMaxLayoutWidth = 320
            var attachments: [WeakBox<TextLabel.Attachment>] = []
            for round in 0 ..< StressMode.pick(300, full: 3000) {
                let made = attachmentString(round, withViews: round.isMultiple(of: 3))
                attachments.append(contentsOf: made.attachments)
                cache.withLock { $0[round] = made.string }
                label.attributedText = made.string
                layOut(label)
                if round.isMultiple(of: 20) {
                    await Task.yield()
                }
            }
            label.attributedText = NSAttributedString()
            layOut(label)
            stop.withLock { $0 = true }
            await clearer.value
            cache.withLock { $0.removeAll() }

            #expect(clears.withLock { $0 } > 0)
            evictCoreTextLastTypesetAttributes()
            let released = await waitUntil(timeout: .seconds(10)) { attachments.allSatisfy { $0.value == nil } }
            #expect(released, "\(attachments.count { $0.value != nil }) attachments are still alive")
        }

        @Test
        func `a resized attachment measures its new size when typeset and released off the main thread`() async {
            for round in 0 ..< StressMode.pick(1000, full: 10000) {
                let attachment = TextLabel.Attachment(size: CGSize(width: 10, height: 10))
                let shared = Locked<NSAttributedString?>(attachment.attributedString())
                attachment.size = CGSize(width: CGFloat(round % 50 + 1), height: 10)
                let expected = Double(attachment.size.width)
                let width = await Task.detached {
                    autoreleasepool {
                        let width = shared.take().map {
                            CTLineGetTypographicBounds(CTLineCreateWithAttributedString($0), nil, nil, nil)
                        }
                        evictCoreTextCacheOnCurrentThread()
                        return width
                    }
                }.value
                #expect(width == expected, "round \(round)")
            }
        }

        private func layOut(_ label: TextLabelView) {
            _ = label.intrinsicContentSize
            #if canImport(UIKit)
                label.layoutIfNeeded()
            #else
                label.layoutSubtreeIfNeeded()
            #endif
        }
    }

#endif
