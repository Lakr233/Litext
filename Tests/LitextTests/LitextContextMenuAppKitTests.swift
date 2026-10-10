//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)

    import AppKit
    @testable import Litext
    import Testing

    @MainActor
    @Suite(.serialized)
    struct `AppKit context menu` {
        private let window: NSWindow
        private let label: TextLabelView

        init() {
            window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.titled],
                backing: .buffered,
                defer: false,
            )
            window.isReleasedWhenClosed = false
            label = TextLabelView(attributedText: NSAttributedString(
                string: "Hello brave new world",
                attributes: [.font: NSFont.systemFont(ofSize: 16)],
            ))
            label.isSelectable = true
            label.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
            window.contentView?.addSubview(label)
            label.layout()
        }

        /// A right click at the middle of the character at `index`, in window coordinates.
        private func rightClick(atCharacter index: Int, modifierFlags: NSEvent.ModifierFlags = []) -> NSEvent {
            mouseEvent(.rightMouseDown, atCharacter: index, modifierFlags: modifierFlags)
        }

        /// A mouse event at the middle of the character at `index`, in window coordinates.
        private func mouseEvent(
            _ type: NSEvent.EventType,
            atCharacter index: Int,
            modifierFlags: NSEvent.ModifierFlags = [],
        ) -> NSEvent {
            let rect = label.viewRect(fromLayoutRect: label.textLayout.rects(
                for: NSRange(location: index, length: 1),
            )[0])
            let point = label.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil)
            return NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: modifierFlags,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1,
            )!
        }

        private func actions(of menu: NSMenu) -> [String] {
            menu.items.map { item in
                if item.isSeparatorItem {
                    return "---"
                }
                if item.hasSubmenu {
                    return "submenu"
                }
                return item.action.map(NSStringFromSelector) ?? "none"
            }
        }

        @Test func `the selection menu matches a read-only text view`() throws {
            label.selectionRange = NSRange(location: 0, length: 5)
            let menu = try #require(label.menu(for: rightClick(atCharacter: 1)))

            var expected = ["lookUpSelection:"]
            if #available(macOS 14.4, *) {
                expected.append("translateSelection:")
            }
            expected += ["---", "copy:", "---"]
            if #available(macOS 13.0, *) {
                expected.append("_performStandardShareMenuItem:")
            } else {
                expected.append("submenu")
            }
            expected += ["---", "submenu"]
            #expect(actions(of: menu) == expected)
            #expect(menu.items[0].title.contains("Hello"))
            let speech = try #require(menu.items.last?.submenu)
            #expect(actions(of: speech) == ["startSpeaking:", "stopSpeaking:"])
        }

        @Test func `a right click away from the selection selects the word under it`() throws {
            label.selectionRange = NSRange(location: 0, length: 5)
            _ = try #require(label.menu(for: rightClick(atCharacter: 7)))
            #expect(label.selectionRange == NSRange(location: 6, length: 5))
        }

        @Test func `a right click inside the selection keeps it`() throws {
            label.selectionRange = NSRange(location: 0, length: 11)
            _ = try #require(label.menu(for: rightClick(atCharacter: 7)))
            #expect(label.selectionRange == NSRange(location: 0, length: 11))
        }

        @Test func `a click inside the selection clears it`() {
            label.selectionRange = NSRange(location: 0, length: 11)
            label.mouseDown(with: mouseEvent(.leftMouseDown, atCharacter: 7))
            label.mouseUp(with: mouseEvent(.leftMouseUp, atCharacter: 7))
            #expect(label.selectionRange == nil)
        }

        /// A right click at `point`, in the label's coordinates.
        private func rightClick(at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: label.convert(point, to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1,
            )!
        }

        /// The middle of the character at `index`, in the label's coordinates.
        private func pointOnCharacter(_ index: Int) -> CGPoint {
            let rect = label.viewRect(fromLayoutRect: label.textLayout.rects(
                for: NSRange(location: index, length: 1),
            )[0])
            return CGPoint(x: rect.midX, y: rect.midY)
        }

        @Test func `a right click without a selection selects the word under it`() throws {
            _ = try #require(label.menu(for: rightClick(atCharacter: 7)))
            #expect(label.selectionRange == NSRange(location: 6, length: 5))
        }

        @Test func `a right click past the end of a line without a selection shows no menu`() {
            let lastCharacter = pointOnCharacter(20)
            #expect(label.menu(for: rightClick(at: CGPoint(x: 380, y: lastCharacter.y))) == nil)
            #expect(label.selectionRange == nil)
        }

        @Test func `a right click on a space without a selection shows no menu`() {
            #expect(label.menu(for: rightClick(atCharacter: 5)) == nil)
            #expect(label.selectionRange == nil)
        }

        @Test func `a right click on a blank line without a selection shows no menu`() {
            label.attributedText = NSAttributedString(
                string: "Hello\n\nworld",
                attributes: [.font: NSFont.systemFont(ofSize: 16)],
            )
            label.layout()
            let top = pointOnCharacter(0)
            let bottom = pointOnCharacter(7)
            #expect(label.menu(for: rightClick(at: CGPoint(x: top.x, y: (top.y + bottom.y) / 2))) == nil)
            #expect(label.selectionRange == nil)
        }

        @Test func `a right click past the end of a line keeps working with a selection`() throws {
            label.selectionRange = NSRange(location: 0, length: 5)
            let lastCharacter = pointOnCharacter(20)
            _ = try #require(label.menu(for: rightClick(at: CGPoint(x: 380, y: lastCharacter.y))))
        }

        @Test func `a right click on blank space reaches the view behind the label`() {
            final class Container: NSView {
                var rightClicks = 0
                override func rightMouseDown(with _: NSEvent) {
                    rightClicks += 1
                }
            }
            let container = Container(frame: label.frame)
            window.contentView?.addSubview(container)
            label.removeFromSuperview()
            container.addSubview(label)
            let lastCharacter = pointOnCharacter(20)

            label.rightMouseDown(with: rightClick(at: CGPoint(x: 380, y: lastCharacter.y)))
            #expect(container.rightClicks == 1)
            #expect(label.selectionRange == nil)
        }

        @Test func `a label that is not selectable shows no selection menu`() {
            label.isSelectable = false
            #expect(label.menu(for: rightClick(atCharacter: 1)) == nil)
            #expect(label.selectionRange == nil)
        }

        @Test func `the delegate can replace the menu`() throws {
            final class Delegate: TextLabelViewDelegate {
                var selection: NSRange?
                func textLabelView(
                    _: TextLabelView,
                    menu _: NSMenu,
                    forSelection selection: NSRange,
                    event _: NSEvent,
                ) -> NSMenu? {
                    self.selection = selection
                    return NSMenu(title: "Custom")
                }
            }
            let delegate = Delegate()
            label.delegate = delegate
            label.selectionRange = NSRange(location: 0, length: 5)
            let menu = try #require(label.menu(for: rightClick(atCharacter: 1)))
            #expect(menu.title == "Custom")
            #expect(delegate.selection == NSRange(location: 0, length: 5))
        }

        @Test func `a long selection is quoted the way the system quotes it`() {
            #expect(TextLabelView.menuTitleQuote(for: "  two\nlines  ") == "two lines")
            #expect(TextLabelView.menuTitleQuote(for: "The quick brown fox jumps over the lazy dog")
                == "The quick brown fox jumps over…")
        }

        @Test func `copy keeps the selection and validates against it`() {
            let copyItem = NSMenuItem(title: "Copy", action: #selector(TextLabelView.copy(_:)), keyEquivalent: "")
            #expect(!label.validateMenuItem(copyItem))

            label.selectionRange = NSRange(location: 6, length: 5)
            #expect(label.validateMenuItem(copyItem))
            label.copy(nil)
            #expect(NSPasteboard.general.string(forType: .string) == "brave")
            #expect(label.selectionRange == NSRange(location: 6, length: 5))
        }

        @Test func `select all from the Edit menu selects the whole text`() {
            label.selectAll(nil as Any?)
            #expect(label.selectionRange == NSRange(location: 0, length: 21))
        }

        @Test func `services can read the selection but not write back`() {
            #expect(label.validRequestor(forSendType: .string, returnType: nil) == nil)

            label.selectionRange = NSRange(location: 0, length: 5)
            #expect(label.validRequestor(forSendType: .string, returnType: nil) as? TextLabelView === label)
            #expect(label.validRequestor(forSendType: .string, returnType: .string) == nil)

            let pasteboard = NSPasteboard(name: NSPasteboard.Name("litext-services-test"))
            defer { pasteboard.releaseGlobally() }
            #expect(label.writeSelection(to: pasteboard, types: [.string, .rtf]))
            #expect(pasteboard.string(forType: .string) == "Hello")
            #expect(pasteboard.data(forType: .rtf) != nil)
        }

        @Test func `translate leaves nothing behind in a hidden window`() {
            label.selectionRange = NSRange(location: 6, length: 5)
            let subviews = label.subviews
            label.perform(NSSelectorFromString("translateSelection:"), with: nil)
            #expect(label.subviews == subviews)
        }
    }

#endif
