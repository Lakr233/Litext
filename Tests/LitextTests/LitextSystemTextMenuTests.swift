//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !os(tvOS) && !os(watchOS)

    @testable import Litext
    import Testing
    import UIKit

    /// The input proxy that lends a selectable label the system text menu from iOS 16
    /// and Mac Catalyst 16.
    @MainActor
    @Suite(.serialized)
    struct `System text menu` {
        private let label: TextLabelView

        init() {
            label = TextLabelView(attributedText: NSAttributedString(
                string: "Hello brave new world",
                attributes: [.font: UIFont.systemFont(ofSize: 16)],
            ))
            label.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
            label.isSelectable = true
            label.layoutIfNeeded()
        }

        @available(iOS 16.0, macCatalyst 16.0, *)
        private var proxy: TextLabelInputProxy {
            get throws { try #require(label.inputProxy) }
        }

        @Test func `a selectable label carries the proxy under its other subviews`() throws {
            guard #available(iOS 16.0, macCatalyst 16.0, *) else { return }
            let proxy = try proxy
            #expect(label.subviews.first === proxy)
            #expect(proxy.frame == label.bounds)
            #expect(proxy.isAccessibilityElement == false)
            #if targetEnvironment(macCatalyst)
                #expect(proxy.isUserInteractionEnabled)
            #else
                // Touches keep reaching the label directly.
                #expect(!proxy.isUserInteractionEnabled)
            #endif

            label.isSelectable = false
            #expect(label.inputProxy == nil)
            #expect(proxy.superview == nil)
            label.isSelectable = true
            #expect(label.inputProxy != nil)
        }

        @Test func `editing commands are off and copy follows the selection`() throws {
            guard #available(iOS 16.0, macCatalyst 16.0, *) else { return }
            let proxy = try proxy
            let copy = #selector(UIResponderStandardEditActions.copy(_:))
            let selectAll = #selector(UIResponderStandardEditActions.selectAll(_:))
            #expect(!proxy.canPerformAction(copy, withSender: nil))
            #expect(proxy.canPerformAction(selectAll, withSender: nil))

            label.selectionRange = NSRange(location: 0, length: 5)
            #expect(proxy.canPerformAction(copy, withSender: nil))
            #expect(proxy.canPerformAction(selectAll, withSender: nil))
            for action in [
                #selector(UIResponderStandardEditActions.cut(_:)),
                #selector(UIResponderStandardEditActions.paste(_:)),
                #selector(UIResponderStandardEditActions.delete(_:)),
            ] {
                #expect(!proxy.canPerformAction(action, withSender: nil))
            }

            label.selectAll()
            #expect(!proxy.canPerformAction(selectAll, withSender: nil))
        }

        @Test func `copy keeps the selection`() throws {
            guard #available(iOS 16.0, macCatalyst 16.0, *) else { return }
            let proxy = try proxy
            label.selectionRange = NSRange(location: 6, length: 5)
            // Reading the general pasteboard back would wait on the paste permission
            // prompt, so only the selection is checked here.
            proxy.copy(nil)
            #expect(label.selectionRange == NSRange(location: 6, length: 5))
        }

        @Test func `the menu drops editing commands from the suggested actions`() throws {
            guard #available(iOS 16.0, macCatalyst 16.0, *) else { return }
            label.selectionRange = NSRange(location: 0, length: 5)
            let suggested: [UIMenuElement] = [
                UIMenu(options: .displayInline, children: [
                    UICommand(title: "Cut", action: #selector(UIResponderStandardEditActions.cut(_:))),
                    UICommand(title: "Copy", action: #selector(UIResponderStandardEditActions.copy(_:))),
                    UICommand(title: "Paste", action: #selector(UIResponderStandardEditActions.paste(_:))),
                ]),
                UIMenu(options: .displayInline, children: [
                    UICommand(title: "Delete", action: #selector(UIResponderStandardEditActions.delete(_:))),
                ]),
                UIAction(title: "Other") { _ in },
            ]
            let menu = try #require(label.selectionMenu(suggestedActions: suggested))
            #expect(menu.children.count == 2)
            let edit = try #require(menu.children.first as? UIMenu)
            #expect(edit.children.map(\.title) == ["Copy"])
            #expect(menu.children.last?.title == "Other")
        }

        @Test func `the delegate can replace the menu`() {
            guard #available(iOS 16.0, macCatalyst 16.0, *) else { return }
            final class Delegate: TextLabelViewDelegate {
                var selection: NSRange?
                var suggestedTitles: [String] = []
                func textLabelView(
                    _: TextLabelView,
                    editMenuForSelection selection: NSRange,
                    suggestedActions: [UIMenuElement],
                ) -> UIMenu? {
                    self.selection = selection
                    suggestedTitles = suggestedActions.map(\.title)
                    return UIMenu(title: "Custom", children: suggestedActions)
                }
            }
            let delegate = Delegate()
            label.delegate = delegate
            label.selectionRange = NSRange(location: 6, length: 5)
            let menu = label.selectionMenu(suggestedActions: [
                UICommand(title: "Paste", action: #selector(UIResponderStandardEditActions.paste(_:))),
                UICommand(title: "Copy", action: #selector(UIResponderStandardEditActions.copy(_:))),
            ])
            #expect(menu?.title == "Custom")
            #expect(delegate.selection == NSRange(location: 6, length: 5))
            #expect(delegate.suggestedTitles == ["Copy"])
        }

        @Test func `the text input reports the label's text and geometry`() throws {
            guard #available(iOS 16.0, macCatalyst 16.0, *) else { return }
            let proxy = try proxy
            let range = NSRange(location: 6, length: 5)
            label.selectionRange = range
            let selected = try #require(proxy.selectedTextRange)
            #expect(proxy.text(in: selected) == "brave")
            #expect(proxy.offset(from: proxy.beginningOfDocument, to: proxy.endOfDocument) == 21)

            let expected = label.viewRect(fromLayoutRect: label.textLayout.rects(for: range)[0])
            #expect(proxy.firstRect(for: selected) == expected)
            let rects = proxy.selectionRects(for: selected)
            #expect(rects.count == 1)
            #expect(rects.first?.containsStart == true)
            #expect(rects.first?.containsEnd == true)

            let middle = CGPoint(x: expected.midX, y: expected.midY)
            let position = try #require(proxy.closestPosition(to: middle) as? TextLabelTextPosition)
            #expect((range.location ... NSMaxRange(range)).contains(position.index))
            let character = try #require(proxy.characterRange(at: middle) as? TextLabelTextRange)
            #expect(character.range.length == 1)
            #expect(NSLocationInRange(character.range.location, range))

            #expect(!proxy.caretRect(for: proxy.endOfDocument).isNull)
            #expect(proxy.position(from: proxy.endOfDocument, offset: 1) == nil)
        }

        @Test func `a caret the system parks does not clear the selection`() throws {
            guard #available(iOS 16.0, macCatalyst 16.0, *) else { return }
            let proxy = try proxy
            label.selectionRange = NSRange(location: 6, length: 5)
            proxy.selectedTextRange = TextLabelTextRange(NSRange(location: 0, length: 0))
            #expect(label.selectionRange == NSRange(location: 6, length: 5))
            proxy.selectedTextRange = TextLabelTextRange(NSRange(location: 0, length: 5))
            #expect(label.selectionRange == NSRange(location: 0, length: 5))
        }
    }

#endif
