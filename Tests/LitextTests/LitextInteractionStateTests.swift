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
    #endif

#endif // !os(watchOS)
