//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

@testable import Litext
import QuartzCore
import Testing

#if !os(watchOS)

    /// A coarse leak check at the process level. It only catches a leak of whole labels or
    /// their layouts, which costs tens of megabytes over the loop, and stays well clear of
    /// allocator noise. The loop never suspends, so other main-actor tests cannot run, and
    /// allocate, while it is measured.
    @MainActor
    @Suite("Footprint smoke test", .tags(.memory, .smoke))
    struct LitextFootprintSmokeTests {
        /// Long enough that a leaked label (string, framesetter, lines, regions) costs tens
        /// of kilobytes, so leaking all 1,000 crosses the threshold.
        private static let textLength = 4000
        private static let thresholdBytes: UInt64 = 20 * 1024 * 1024

        private func createUseAndDrop(count: Int, sampleAt sampleIndex: Int? = nil) -> WeakBox<TextLabelView>? {
            var sample: WeakBox<TextLabelView>?
            for index in 0 ..< count {
                autoreleasepool {
                    let owner = OwningDelegate()
                    let text = uniqueText("Smoke", length: Self.textLength)
                    appendLink(to: text)
                    let label = makeLaidOutTestLabel(text, size: CGSize(width: 300, height: 400))
                    label.delegate = owner
                    owner.label = label
                    label.isSelectable = true
                    label.selectionRange = NSRange(location: 0, length: 40)
                    _ = label.intrinsicContentSize
                    render(label)
                    if index == sampleIndex {
                        sample = WeakBox(label)
                    }
                }
                // Commit the implicit layer transaction the loop would otherwise grow.
                CATransaction.flush()
            }
            return sample
        }

        @Test("Creating, using and dropping 1,000 labels does not grow the footprint")
        func thousandLabels() throws {
            _ = createUseAndDrop(count: 100)
            let before = try #require(physicalFootprint())
            let sample = createUseAndDrop(count: 1000, sampleAt: 500)
            let after = try #require(physicalFootprint())

            #expect(sample?.value == nil)
            let growth = after > before ? after - before : 0
            #expect(
                growth < Self.thresholdBytes,
                "Footprint grew by \(growth / 1024) KB over 1,000 labels"
            )
        }
    }

#endif // !os(watchOS)
