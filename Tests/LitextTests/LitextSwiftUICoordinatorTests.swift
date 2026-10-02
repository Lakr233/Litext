//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

@testable import Litext
import Testing

#if !os(watchOS)

    @MainActor
    @Suite("SwiftUI coordinator")
    struct LitextSwiftUICoordinatorTests {
        @MainActor
        final class Recorder {
            var values: [String?] = []
        }

        private func makeLabel() -> TextLabelView {
            let label = TextLabelView(attributedText: NSAttributedString(
                string: "Hello world",
                attributes: [.font: PlatformFont.systemFont(ofSize: 16)],
            ))
            label.isSelectable = true
            return label
        }

        @Test
        func `Selection changes outside an update are reported synchronously`() {
            let recorder = Recorder()
            let coordinator = TextLabel.Coordinator(onTapLink: nil) { recorder.values.append($0) }
            let label = makeLabel()
            label.delegate = coordinator
            label.selectionRange = NSRange(location: 0, length: 5)
            #expect(recorder.values == ["Hello"])
        }

        @Test
        func `Selection changes during an update are deferred and coalesced`() async {
            let recorder = Recorder()
            let coordinator = TextLabel.Coordinator(onTapLink: nil) { recorder.values.append($0) }
            let label = makeLabel()
            label.delegate = coordinator

            coordinator.isApplyingUpdate = true
            label.selectionRange = NSRange(location: 0, length: 5)
            label.selectionRange = nil
            coordinator.isApplyingUpdate = false
            #expect(recorder.values.isEmpty)

            for _ in 0 ..< 10 where recorder.values.isEmpty {
                await Task.yield()
            }
            #expect(recorder.values == [nil])
        }

        @Test
        func `A deferred change never lands after a newer direct one`() async {
            let recorder = Recorder()
            let coordinator = TextLabel.Coordinator(onTapLink: nil) { recorder.values.append($0) }
            let label = makeLabel()
            label.delegate = coordinator

            coordinator.isApplyingUpdate = true
            label.selectionRange = NSRange(location: 0, length: 5)
            coordinator.isApplyingUpdate = false
            label.selectionRange = NSRange(location: 6, length: 5)
            #expect(recorder.values == ["world"])

            for _ in 0 ..< 20 {
                await Task.yield()
            }
            // Labels in parallel tests may clear this selection meanwhile; the deferred
            // "Hello" must still never be reported.
            #expect(recorder.values.first == "world")
            #expect(!recorder.values.contains("Hello"))
        }

        @Test
        func `An attachment tap goes to its handler, else to the link it carries`() throws {
            let url = try #require(URL(string: "https://example.com/attachment"))
            let attachment = TextLabel.Attachment(size: CGSize(width: 10, height: 10))
            let region = TextLabel.HighlightRegion(
                kind: .attachment,
                attributes: [.litextAttachment: attachment, .link: url],
                stringRange: NSRange(location: 0, length: 1),
            )
            var tappedLinks: [URL] = []
            var tappedAttachments: [TextLabel.Attachment] = []
            let coordinator = TextLabel.Coordinator(onTapLink: { tappedLinks.append($0) }, onSelectionChange: nil)
            let label = makeLabel()

            coordinator.onTapAttachment = { tappedAttachments.append($0) }
            coordinator.textLabelView(label, didTapHighlightRegion: region, at: .zero)
            #expect(tappedAttachments.count == 1)
            #expect(tappedAttachments.first === attachment)
            #expect(tappedLinks.isEmpty)

            coordinator.onTapAttachment = nil
            coordinator.textLabelView(label, didTapHighlightRegion: region, at: .zero)
            #expect(tappedAttachments.count == 1)
            #expect(tappedLinks == [url])
        }
    }

#endif
