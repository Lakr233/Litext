//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

@testable import Litext
import QuartzCore
import Testing

#if canImport(UIKit) && !os(watchOS)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#if !os(watchOS)

    /// Reassigning the text many times must leave exactly the state the last string needs.
    @MainActor
    @Suite("Repeated updates", .tags(.memory))
    struct LitextAccumulationTests {
        enum Content: String, CaseIterable, CustomTestStringConvertible {
            case plain
            case links
            /// A fresh attachment and view for every string.
            case newAttachments
            /// The same attachments in every string.
            case sharedAttachments
            case linksAndNewAttachments

            var testDescription: String {
                rawValue
            }
        }

        private static let iterations = 500

        /// Layers Litext adds itself: the selection layer and link highlights.
        private func shapeSublayerCount(_ label: TextLabelView) -> Int {
            label.backingLayer?.sublayers?.count { $0 is CAShapeLayer } ?? 0
        }

        /// Builds string `index`. Its link and attachment counts vary with `index`, so the
        /// label sees counts go up and down rather than settle.
        private func makeText(
            _ content: Content,
            index: Int,
            sharedAttachments: [TextLabel.Attachment],
            createdViews: inout [PlatformView]
        ) -> NSAttributedString {
            let text = uniqueText("Update \(index)", length: 60)
            let count = index % 4
            switch content {
            case .plain:
                break
            case .links:
                for _ in 0 ... count {
                    appendLink(to: text)
                }
            case .newAttachments, .linksAndNewAttachments:
                for _ in 0 ... count {
                    let view = PlatformView()
                    createdViews.append(view)
                    appendAttachment(to: text, TextLabel.Attachment(size: CGSize(width: 14, height: 14), view: view))
                    if content == .linksAndNewAttachments {
                        appendLink(to: text)
                    }
                }
            case .sharedAttachments:
                for attachment in sharedAttachments.prefix(count + 1) {
                    appendAttachment(to: text, attachment)
                }
            }
            return text
        }

        @Test("500 reassignments leave the state the last string needs", arguments: Content.allCases)
        func repeatedAssignmentsStayBounded(content: Content) async throws {
            let sharedViews = (0 ..< 4).map { _ in PlatformView() }
            let sharedAttachments = sharedViews.map {
                TextLabel.Attachment(size: CGSize(width: 14, height: 14), view: $0)
            }
            var createdViews: [PlatformView] = []

            let label = makeLaidOutTestLabel(uniqueText(), size: CGSize(width: 360, height: 200))
            label.isSelectable = true
            let baselineSubviews = label.subviews.count
            let baselineSublayers = sublayerCount(label)

            var lastText = NSAttributedString()
            for index in 0 ..< Self.iterations {
                autoreleasepool {
                    lastText = makeText(
                        content,
                        index: index,
                        sharedAttachments: sharedAttachments,
                        createdViews: &createdViews
                    )
                    label.attributedText = lastText
                    performLayoutPass(label)
                    _ = label.intrinsicContentSize
                    // Leave interaction state behind for the next assignment to clean up.
                    if let link = label.highlightRegions.first(where: { $0.kind == .link }) {
                        label.addActiveHighlightRegion(link)
                    }
                    if index.isMultiple(of: 3) {
                        label.selectAll()
                    }
                    if index.isMultiple(of: 50) {
                        render(label)
                    }
                }
            }
            // The loop never yields, so no fade-out has run: everything still attached is
            // what the label accumulated. At most a selection layer, the pressed link's
            // highlight and the one fading out from the previous string may remain.
            #expect(label.pendingHighlightRemovalLayers.count <= 1)
            #expect(shapeSublayerCount(label) <= 3)

            label.clearSelection()
            label.deactivateHighlightRegion()
            // Let the scheduled highlight fade-outs finish and the layer transaction commit.
            await spinMainRunLoop(for: .milliseconds(600))
            performLayoutPass(label)

            var expectedLinks = 0
            var expectedAttachmentViews: [PlatformView] = []
            lastText.enumerateAttributes(in: NSRange(location: 0, length: lastText.length)) { attributes, _, _ in
                if attributes[.link] != nil {
                    expectedLinks += 1
                }
                if let view = (attributes[.litextAttachment] as? TextLabel.Attachment)?.view {
                    expectedAttachmentViews.append(view)
                }
            }

            #expect(label.highlightRegions.count == expectedLinks + expectedAttachmentViews.count)
            #expect(label.attachmentViews == Set(expectedAttachmentViews))
            #expect(label.subviews.count == baselineSubviews + expectedAttachmentViews.count)
            #expect(shapeSublayerCount(label) == 0)
            // AppKit adds its own content layer, and attaches subview layers lazily.
            #expect(sublayerCount(label) <= baselineSublayers + expectedAttachmentViews.count + 1)
            #expect(label.pendingHighlightRemovalLayers.isEmpty)
            #expect(label.selectionLayer == nil)
            #expect(try measurementHistoryCount(label.textLayout) <= 4)

            // Views from earlier strings are out of the label.
            let shownViews = Set(expectedAttachmentViews.map(ObjectIdentifier.init))
            let strayViews = (createdViews + sharedViews).filter {
                $0.superview != nil && !shownViews.contains(ObjectIdentifier($0))
            }
            #expect(strayViews.isEmpty)
        }

        @Test("Views of dropped attachments deallocate after repeated updates")
        func droppedAttachmentViewsDeallocate() async {
            let label = makeLaidOutTestLabel(uniqueText())
            var weakViews: [WeakBox<PlatformView>] = []
            for _ in 0 ..< 100 {
                autoreleasepool {
                    let view = PlatformView()
                    weakViews.append(WeakBox(view))
                    let text = uniqueText()
                    appendAttachment(to: text, TextLabel.Attachment(size: CGSize(width: 10, height: 10), view: view))
                    label.attributedText = text
                    performLayoutPass(label)
                }
            }
            label.attributedText = uniqueText()
            performLayoutPass(label)
            #expect(label.subviews.allSatisfy { view in !weakViews.contains { $0.value === view } })
            // CoreText may keep typeset run attributes, which name the attachments, briefly.
            #expect(await waitUntil { weakViews.allSatisfy { $0.value == nil } })
        }
    }

#endif // !os(watchOS)
