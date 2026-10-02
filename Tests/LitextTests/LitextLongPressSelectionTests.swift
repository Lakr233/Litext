//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)

    @testable import Litext
    import Testing
    import UIKit

    /// A long press selects a word and a drag that follows extends it, without the
    /// context menu interaction that held back handle drags on iOS 18.
    @MainActor
    struct LongPressSelectionTests {
        private func makeLabel(_ string: String = "Hello Litext label", in window: UIWindow) -> TextLabelView {
            let label = TextLabelView(attributedText: NSAttributedString(
                string: string,
                attributes: [.font: UIFont.systemFont(ofSize: 16)],
            ))
            label.isSelectable = true
            label.frame = CGRect(origin: CGPoint(x: 20, y: 100), size: label.intrinsicContentSize)
            window.addSubview(label)
            label.layoutIfNeeded()
            return label
        }

        private func makeWindow() -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
            window.isHidden = false
            return window
        }

        /// The middle of the character at `index`, in the label's coordinates.
        private func point(at index: Int, in label: TextLabelView) throws -> CGPoint {
            let rect = try #require(label.textLayout.rects(for: NSRange(location: index, length: 1)).first)
            let converted = label.convertRectFromTextLayout(rect, insetForInteraction: false)
            return CGPoint(x: converted.midX, y: converted.midY)
        }

        @Test func `installs a long press for touches and no context menu interaction`() throws {
            let window = makeWindow()
            let label = makeLabel(in: window)
            #expect(!label.interactions.contains { $0 is UIContextMenuInteraction })
            let recognizer = try #require(label.gestureRecognizers?.first {
                $0 is TextLabelView.LongPressSelectionRecognizer
            })
            #expect(recognizer.allowedTouchTypes == [NSNumber(value: UITouch.TouchType.direct.rawValue)])
        }

        @Test func `begins only over a word in a selectable label`() throws {
            let window = makeWindow()
            let label = makeLabel(in: window)
            let word = try point(at: 8, in: label)
            #expect(label.longPressWord(at: word) == NSRange(location: 6, length: 6))

            // A label that is not selectable keeps the press for its links.
            label.isSelectable = false
            #expect(label.longPressWord(at: word) == nil)
        }

        @Test func `selects the word, extends it with a drag and keeps it`() throws {
            let window = makeWindow()
            let label = makeLabel(in: window)

            try label.longPressSelection(.began, at: point(at: 8, in: label))
            #expect(label.selectionRange == NSRange(location: 6, length: 6))
            #expect(label.isInteractionInProgress)

            // Past the end of the word, the selection grows from its start.
            try label.longPressSelection(.changed, at: point(at: 15, in: label))
            let extended = try #require(label.selectionRange)
            #expect(extended.location == 6)
            #expect(NSMaxRange(extended) >= 15)

            // Before the word, it grows from the word's end.
            try label.longPressSelection(.changed, at: point(at: 0, in: label))
            let backward = try #require(label.selectionRange)
            #expect(backward.location <= 1)
            #expect(NSMaxRange(backward) == 12)

            try label.longPressSelection(.ended, at: point(at: 0, in: label))
            #expect(label.selectionRange == backward)
            #expect(!label.isInteractionInProgress)
        }

        @Test func `cancelled touches do not end the press`() throws {
            let window = makeWindow()
            let label = makeLabel(in: window)
            try label.longPressSelection(.began, at: point(at: 8, in: label))
            // The recognizer cancels the label's own touches as it begins.
            label.touchesCancelled([], with: nil)
            #expect(label.isInteractionInProgress)
            try label.longPressSelection(.ended, at: point(at: 8, in: label))
            #expect(!label.isInteractionInProgress)
        }

        @Test func `selects within the member of a group`() throws {
            let window = makeWindow()
            let first = makeLabel("First cell", in: window)
            let second = makeLabel("Second cell", in: window)
            second.frame.origin.y = 200
            let group = TextSelectionGroup(labels: [first, second])

            try second.longPressSelection(.began, at: point(at: 8, in: second))
            try second.longPressSelection(.ended, at: point(at: 8, in: second))
            #expect(group.selectedSegments.count == 1)
            #expect(group.selectedSegments.first?.label === second)
            #expect(group.selectedSegments.first?.range == NSRange(location: 7, length: 4))
        }
    }

#endif
