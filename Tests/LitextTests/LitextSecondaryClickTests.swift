//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
@testable import Litext
import QuartzCore
import Testing

#if !os(watchOS)

    /// A right click with nothing selected passes through the label, to the context
    /// menu of the views behind it, unless it lands on a visible character.
    @MainActor
    struct `Secondary click pass-through` {
        private let label: TextLabelView

        init() {
            label = TextLabelView(attributedText: NSAttributedString(
                string: "Hello world\n\nlast line",
                attributes: [.font: PlatformFont.systemFont(ofSize: 16)],
            ))
            label.isSelectable = true
            label.frame = CGRect(x: 0, y: 0, width: 300, height: 120)
            #if canImport(UIKit)
                label.layoutIfNeeded()
            #elseif canImport(AppKit)
                label.layout()
            #endif
        }

        /// The middle of the character at `index`, in the label's coordinates.
        private func pointOnCharacter(_ index: Int) -> CGPoint {
            let rect = label.viewRect(fromLayoutRect: label.textLayout.rects(
                for: NSRange(location: index, length: 1),
            )[0])
            return CGPoint(x: rect.midX, y: rect.midY)
        }

        @Test func `a click on a letter stays with the label`() {
            #expect(!label.secondaryClickPassesThrough(at: pointOnCharacter(1)))
            #expect(label.visibleCharacterIndexAtPoint(pointOnCharacter(1)) == 1)
        }

        @Test func `a click on a space passes through`() {
            #expect(label.secondaryClickPassesThrough(at: pointOnCharacter(5)))
        }

        @Test func `a click past the end of a line passes through`() {
            let point = CGPoint(x: 290, y: pointOnCharacter(10).y)
            #expect(label.characterIndexAtPoint(point) != nil)
            #expect(label.secondaryClickPassesThrough(at: point))
        }

        @Test func `a click on a blank line passes through`() {
            let top = pointOnCharacter(0)
            let bottom = pointOnCharacter(13)
            #expect(label.secondaryClickPassesThrough(at: CGPoint(x: top.x, y: (top.y + bottom.y) / 2)))
        }

        @Test func `a selection keeps every click with the label`() {
            label.selectionRange = NSRange(location: 0, length: 5)
            #expect(!label.secondaryClickPassesThrough(at: pointOnCharacter(5)))
            #expect(!label.secondaryClickPassesThrough(at: CGPoint(x: 290, y: pointOnCharacter(10).y)))
        }
    }

#endif
