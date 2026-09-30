//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
@testable import Litext
import QuartzCore
import Testing

#if !os(watchOS)

    @MainActor
    private func makeLaidOutLabel(_ text: NSAttributedString) -> TextLabelView {
        let label = TextLabelView(attributedText: text)
        label.isSelectable = true
        label.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
        #if canImport(UIKit)
            label.layoutIfNeeded()
        #elseif canImport(AppKit)
            label.layout()
        #endif
        return label
    }

    @MainActor
    private func plain(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: PlatformFont.systemFont(ofSize: 16)])
    }

    // MARK: - Content changes reset interaction state

    @MainActor
    @Test func newTextOfTheSameLengthClearsTheSelection() {
        let label = makeLaidOutLabel(plain("Hello Litext"))
        label.selectionRange = NSRange(location: 0, length: 5)
        #expect(label.selectionRange != nil)

        label.attributedText = plain("Howdy people")
        #expect(label.selectionRange == nil)
    }

    @MainActor
    @Test func longerUnrelatedTextClearsTheSelection() {
        let label = makeLaidOutLabel(plain("Hello Litext"))
        label.selectionRange = NSRange(location: 0, length: 5)

        label.attributedText = plain("Something else entirely, and longer")
        #expect(label.selectionRange == nil)
    }

    @MainActor
    @Test func appendedTextKeepsTheSelection() {
        let label = makeLaidOutLabel(plain("Hello Litext"))
        label.selectionRange = NSRange(location: 0, length: 5)

        label.attributedText = plain("Hello Litext, streaming more text")
        #expect(label.selectionRange == NSRange(location: 0, length: 5))
    }

    @MainActor
    @Test func swappedAttachmentInTheKeptPrefixClearsTheSelection() {
        let font = PlatformFont.systemFont(ofSize: 16)
        func text(_ attachment: TextLabel.Attachment, tail: String) -> NSAttributedString {
            let result = NSMutableAttributedString(string: "A", attributes: [.font: font])
            result.append(attachment.attributedString(attributes: [.font: font]))
            result.append(NSAttributedString(string: tail, attributes: [.font: font]))
            return result
        }
        let first = TextLabel.Attachment(size: CGSize(width: 20, height: 20))
        let label = makeLaidOutLabel(text(first, tail: " tail"))
        label.selectionRange = NSRange(location: 0, length: 3)

        // The same attachment with more text streamed on keeps the selection.
        label.attributedText = text(first, tail: " tail and more")
        #expect(label.selectionRange == NSRange(location: 0, length: 3))

        // Another attachment behind the same U+FFFC is different content.
        let second = TextLabel.Attachment(size: CGSize(width: 20, height: 20))
        label.attributedText = text(second, tail: " tail and more")
        #expect(label.selectionRange == nil)
    }

    @MainActor
    @Test func newTextClearsTheActiveHighlight() throws {
        let url = try #require(URL(string: "https://example.com"))
        let text = NSMutableAttributedString(attributedString: plain("Open "))
        text.append(NSAttributedString(
            string: "link",
            attributes: [.font: PlatformFont.systemFont(ofSize: 16), .link: url]
        ))
        let label = makeLaidOutLabel(text)
        let region = try #require(label.highlightRegions.first { $0.kind == .link })
        label.addActiveHighlightRegion(region)
        #expect(label.activeHighlightRegion != nil)

        label.attributedText = plain("Some new text of greater length")
        #expect(label.activeHighlightRegion == nil)
        #expect(region.associatedObject == nil)
    }

    @MainActor
    @Test func newTextResetsTheMultiClickSequence() {
        let label = makeLaidOutLabel(plain("Hello Litext"))
        label.interactionState.clickCount = 2
        label.interactionState.lastClickTime = 42

        label.attributedText = plain("Howdy people")
        #expect(label.interactionState.clickCount == 1)
        #expect(label.interactionState.lastClickTime == 0)
    }

    // MARK: - Hit testing

    @MainActor
    @Test func hitTargetDistinguishesTextFromPassThrough() {
        let label = makeLaidOutLabel(plain("Hello Litext"))
        let inside = CGPoint(x: 10, y: 10)
        #expect(label.hitTarget(at: inside) == .interactiveText)
        #expect(label.hitTarget(at: CGPoint(x: -5, y: 10)) == .outside)

        label.isSelectable = false
        #expect(label.hitTarget(at: inside) == .passThrough)
    }

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        @MainActor
        @Test func nonSelectableLabelLetsClicksThroughOnAppKit() {
            let container = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
            let label = makeLaidOutLabel(plain("Hello Litext"))
            label.frame.origin = CGPoint(x: 20, y: 20)
            container.addSubview(label)
            let point = CGPoint(x: 30, y: 30)

            #expect(label.hitTest(point) === label)
            label.isSelectable = false
            #expect(label.hitTest(point) == nil)
        }

        @MainActor
        private final class TapRecorder: TextLabelViewDelegate {
            var tappedLinks: [URL] = []

            func textLabelView(
                _: TextLabelView,
                didTapHighlightRegion region: TextLabel.HighlightRegion,
                at _: CGPoint
            ) {
                if let url = region.linkURL {
                    tappedLinks.append(url)
                }
            }
        }

        @MainActor
        @Test func releasingAfterTheTextChangedDoesNotTapTheNewLink() throws {
            func linked(_ link: String, _ url: String) throws -> NSAttributedString {
                let font = PlatformFont.systemFont(ofSize: 16)
                let text = NSMutableAttributedString(string: "Lead ", attributes: [.font: font])
                try text.append(NSAttributedString(
                    string: link,
                    attributes: [.font: font, .link: #require(URL(string: url))]
                ))
                text.append(NSAttributedString(string: " tail", attributes: [.font: font]))
                return text
            }
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            let label = try TextLabelView(attributedText: linked("first", "https://pressed.example"))
            label.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
            window.contentView?.addSubview(label)
            label.layoutSubtreeIfNeeded()
            let recorder = TapRecorder()
            label.delegate = recorder

            let run = try #require(label.layoutRuns(matching: .link).first)
            let runRect = label.textLayout.viewRect(fromLayoutRect: run.rect)
            let point = label.convert(CGPoint(x: runRect.midX, y: runRect.midY), to: nil)
            func click(_ type: NSEvent.EventType) throws -> NSEvent {
                try #require(NSEvent.mouseEvent(
                    with: type,
                    location: point,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1
                ))
            }

            try label.mouseDown(with: click(.leftMouseDown))
            label.attributedText = try linked("other", "https://never-pressed.example")
            label.layoutSubtreeIfNeeded()
            try label.mouseUp(with: click(.leftMouseUp))
            #expect(recorder.tappedLinks.isEmpty)
            #expect(!label.isInteractionInProgress)

            // The next click on the new link taps it.
            try label.mouseDown(with: click(.leftMouseDown))
            try label.mouseUp(with: click(.leftMouseUp))
            #expect(recorder.tappedLinks == [URL(string: "https://never-pressed.example")])
        }
    #endif

    #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS)
        @MainActor
        @Test func forwardedTouchEndDoesNotEndAHandleDrag() {
            let label = makeLaidOutLabel(plain("Hello Litext"))
            label.selectionRange = NSRange(location: 0, length: 5)
            label.selectionHandleDidBeginDrag(.end)
            #expect(label.isInteractionInProgress)

            label.touchesCancelled([], with: nil)
            #expect(label.isInteractionInProgress)
            label.touchesEnded([], with: nil)
            #expect(label.isInteractionInProgress)

            label.selectionHandleDidEndDrag(.end)
            #expect(!label.isInteractionInProgress)
        }
    #endif

#endif // !os(watchOS)
