//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if !os(watchOS) && !os(tvOS)

    @testable import Litext
    import Testing

    #if canImport(UIKit)
        import UIKit
    #else
        import AppKit
    #endif

    /// Labels that share one selection through `TextSelectionGroup`, laid out as a
    /// two-by-two table read row by row.
    @MainActor
    @Suite(.serialized)
    struct `Selection group` {
        #if canImport(UIKit)
            private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        #else
            private let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 400, height: 400),
                styleMask: [.titled],
                backing: .buffered,
                defer: false,
            )
        #endif
        private let cells: [TextLabelView]
        private let group = TextSelectionGroup()

        init() {
            let texts = ["Feature", "Status", "Bold", "Done"]
            cells = texts.map { text in
                let label = TextLabelView(attributedText: NSAttributedString(
                    string: text,
                    attributes: [.font: PlatformFont.systemFont(ofSize: 16)],
                ))
                label.isSelectable = true
                return label
            }
            #if canImport(UIKit)
                window.isHidden = false
                let container: PlatformView = window
            #else
                window.isReleasedWhenClosed = false
                let container: PlatformView = window.contentView!
            #endif
            for (index, label) in cells.enumerated() {
                label.frame = CGRect(x: CGFloat(index % 2) * 200, y: CGFloat(index / 2) * 100, width: 180, height: 40)
                container.addSubview(label)
                #if canImport(UIKit)
                    label.layoutIfNeeded()
                #else
                    label.layout()
                #endif
            }
            group.labels = cells
            let cells = cells
            group.separator = { previous, next in
                let lhs = cells.firstIndex { $0 === previous } ?? 0
                let rhs = cells.firstIndex { $0 === next } ?? 0
                return lhs / 2 == rhs / 2 ? "\t" : "\n"
            }
        }

        /// The middle of the character at `index` in `label`, in window coordinates.
        private func windowPoint(in label: TextLabelView, atCharacter index: Int) -> CGPoint {
            let rect = label.viewRect(fromLayoutRect: label.textLayout.rects(
                for: NSRange(location: index, length: 1),
            )[0])
            return label.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil)
        }

        private var ranges: [NSRange?] {
            cells.map(\.selectionRange)
        }

        @Test func `the labels join the group in order`() {
            #expect(group.labels.count == 4)
            #expect(group.labels.elementsEqual(cells, by: ===))
            #expect(cells.allSatisfy { $0.selectionGroup === group })
            #expect(!group.hasSelection)
        }

        @Test func `select all spans every member and joins with the separators`() {
            group.selectAll()
            #expect(ranges == [
                NSRange(location: 0, length: 7),
                NSRange(location: 0, length: 6),
                NSRange(location: 0, length: 4),
                NSRange(location: 0, length: 4),
            ])
            #expect(group.selectedPlainText() == "Feature\tStatus\nBold\tDone")
            #expect(group.isEntireTextSelected)
            #expect(group.selectedSegments.map(\.label).elementsEqual(cells, by: ===))
            // A member's own commands act on the whole group.
            #expect(cells[1].commandSelectedText()?.string == "Feature\tStatus\nBold\tDone")
            #expect(cells[1].hasCommandSelection)
            #expect(cells[1].isEntireTextSelected)
        }

        @Test func `a selection in one member selects only there`() {
            cells[2].selectionRange = NSRange(location: 1, length: 2)
            #expect(ranges == [nil, nil, NSRange(location: 1, length: 2), nil])
            #expect(group.selectedPlainText() == "ol")
            #expect(!group.isEntireTextSelected)
            #expect(cells[0].commandSelectedText()?.string == "ol")
        }

        @Test func `a drag runs from its anchor through the members between`() throws {
            // From "S|tatus" in the first row to "Bo|ld" in the second.
            let anchor = cells[1].convert(windowPoint(in: cells[1], atCharacter: 0), from: nil)
            cells[1].interactionState.initialTouchLocation = CGPoint(x: anchor.x + 4, y: anchor.y)
            let anchorIndex = try #require(cells[1].nearestTextIndexAtPoint(cells[1].interactionState.initialTouchLocation))
            group.extendDrag(
                from: cells[1].interactionState.initialTouchLocation,
                in: cells[1],
                toWindowPoint: windowPoint(in: cells[2], atCharacter: 1),
            )
            let focus = try #require(cells[2].nearestTextIndexAtPoint(cells[2].convert(windowPoint(in: cells[2], atCharacter: 1), from: nil)))
            #expect(cells[0].selectionRange == nil)
            #expect(cells[1].selectionRange == NSRange(location: anchorIndex, length: 6 - anchorIndex))
            #expect(cells[2].selectionRange == NSRange(location: 0, length: focus))
            #expect(cells[3].selectionRange == nil)
            #expect(group.selectedPlainText()?.hasSuffix("\n" + String("Bold".prefix(focus))) == true)

            // Dragging back before the anchor flips the ends.
            group.extendDrag(
                from: cells[1].interactionState.initialTouchLocation,
                in: cells[1],
                toWindowPoint: windowPoint(in: cells[0], atCharacter: 0),
            )
            #expect(cells[0].selectionRange != nil)
            #expect(cells[1].selectionRange == NSRange(location: 0, length: anchorIndex))
            #expect(cells[2].selectionRange == nil)
        }

        @Test func `a point between members goes to the nearest one`() throws {
            // Between the two columns of the second row, nearer the left cell.
            let left = cells[2].convert(CGPoint(x: cells[2].bounds.maxX + 4, y: 20), to: nil)
            let position = try #require(group.position(atWindowPoint: left))
            #expect(position.member == 2)
            #expect(position.offset == 4)
        }

        @Test func `ends at a member edge move into the next member`() {
            let selection = group.normalizedSelection(
                from: .init(member: 0, offset: 7),
                to: .init(member: 2, offset: 0),
            )
            #expect(selection == .init(start: .init(member: 1, offset: 0), end: .init(member: 1, offset: 6)))
            #expect(group.normalizedSelection(from: .init(member: 0, offset: 7), to: .init(member: 1, offset: 0)) == nil)
        }

        @Test func `moving an end keeps at least one character`() {
            group.selectAll()
            let start = windowPoint(in: cells[0], atCharacter: 0)
            group.moveEnd(isStart: false, toWindowPoint: start)
            #expect(group.selectedPlainText() == "F")
            group.moveEnd(isStart: false, toWindowPoint: windowPoint(in: cells[3], atCharacter: 3))
            #expect(cells[3].selectionRange != nil)
            group.moveEnd(isStart: true, toWindowPoint: windowPoint(in: cells[3], atCharacter: 3))
            #expect(cells[0].selectionRange == nil)
            #expect(group.selectedSegments.count == 1)
        }

        @Test func `clearing any member clears the group`() {
            group.selectAll()
            cells[3].clearSelection()
            #expect(ranges == [nil, nil, nil, nil])
            #expect(!group.hasSelection)
        }

        @Test func `a selection outside the group clears it and the group clears others`() {
            let outsider = TextLabelView(attributedText: NSAttributedString(string: "Outside"))
            outsider.isSelectable = true
            outsider.frame = CGRect(x: 0, y: 300, width: 200, height: 40)
            cells[0].superview?.addSubview(outsider)
            #if canImport(UIKit)
                outsider.layoutIfNeeded()
            #else
                outsider.layout()
            #endif

            group.selectAll()
            outsider.selectionRange = NSRange(location: 0, length: 3)
            #expect(!group.hasSelection)
            #expect(ranges == [nil, nil, nil, nil])

            group.selectAll()
            #expect(outsider.selectionRange == nil)
            #expect(group.hasSelection)
        }

        @Test func `new text in a selected member clears the group, elsewhere it does not`() {
            cells[0].selectionRange = NSRange(location: 0, length: 3)
            cells[3].attributedText = NSAttributedString(string: "Done!")
            #expect(group.hasSelection)
            cells[0].attributedText = NSAttributedString(string: "Feature!")
            #expect(!group.hasSelection)
        }

        @Test func `a member leaving the window clears the group only when it holds part of the selection`() {
            let superview = cells[0].superview
            cells[0].selectionRange = NSRange(location: 0, length: 3)
            // Like a reused or scrolled-away cell that holds no part of the selection.
            cells[3].removeFromSuperview()
            #expect(group.hasSelection)
            superview?.addSubview(cells[3])
            #expect(group.hasSelection)

            cells[0].removeFromSuperview()
            #expect(!group.hasSelection)
        }

        @Test func `select all passes over empty and unselectable members`() {
            cells[3].attributedText = NSAttributedString(string: "")
            cells[0].isSelectable = false
            group.selectAll()
            #expect(ranges == [nil, NSRange(location: 0, length: 6), NSRange(location: 0, length: 4), nil])
            #expect(group.isEntireTextSelected)
            #expect(group.selectedPlainText() == "Status\nBold")

            // An unselectable member that holds no part of the selection leaves it alone.
            group.selectAll()
            cells[3].isSelectable = false
            #expect(group.hasSelection)
            cells[2].isSelectable = false
            #expect(!group.hasSelection)
        }

        @Test func `a group with no text selects nothing`() {
            for label in cells {
                label.attributedText = NSAttributedString(string: "")
            }
            group.selectAll()
            #expect(!group.hasSelection)
            #expect(!cells[0].hasCommandSelection)
        }

        @Test func `a drag skips unselectable members`() throws {
            cells[2].isSelectable = false
            let position = try #require(group.position(atWindowPoint: windowPoint(in: cells[2], atCharacter: 1)))
            #expect(position.member != 2)
        }

        @Test func `the delegate hears each change once`() {
            final class Delegate: TextSelectionGroupDelegate {
                var changes = 0
                func textSelectionGroupDidChangeSelection(_: TextSelectionGroup) {
                    changes += 1
                }
            }
            let delegate = Delegate()
            group.delegate = delegate
            group.selectAll()
            #expect(delegate.changes == 1)
            group.selectAll()
            #expect(delegate.changes == 1)
            group.clearSelection()
            #expect(delegate.changes == 2)
        }

        @Test func `replacing the labels moves them between groups`() {
            group.selectAll()
            let other = TextSelectionGroup(labels: [cells[0], cells[1]])
            #expect(!group.hasSelection)
            #expect(group.labels.elementsEqual([cells[2], cells[3]], by: ===))
            #expect(cells[0].selectionGroup === other)

            group.labels = []
            #expect(cells[2].selectionGroup == nil)
            cells[2].selectionRange = NSRange(location: 0, length: 2)
            #expect(cells[2].selectionRange == NSRange(location: 0, length: 2))
        }

        @Test func `the group does not keep its labels alive`() {
            weak var released: TextLabelView?
            autoreleasepool {
                let label = TextLabelView(attributedText: NSAttributedString(string: "Gone"))
                group.labels = cells + [label]
                released = label
            }
            #if canImport(UIKit)
                evictCoreTextLastTypesetAttributes()
            #endif
            #expect(released == nil)
            #expect(group.labels.count == 4)
            group.selectAll()
            #expect(group.selectedPlainText() == "Feature\tStatus\nBold\tDone")
        }
    }

    #if canImport(UIKit)

        @MainActor
        @Suite(.serialized)
        struct `Selection group on UIKit` {
            private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
            private let cells: [TextLabelView]
            private let group = TextSelectionGroup()

            init() {
                window.isHidden = false
                cells = ["Alpha", "Beta", "Gamma"].enumerated().map { index, text in
                    let label = TextLabelView(attributedText: NSAttributedString(
                        string: text,
                        attributes: [.font: UIFont.systemFont(ofSize: 16)],
                    ))
                    label.isSelectable = true
                    label.frame = CGRect(x: 20, y: 40 + CGFloat(index) * 60, width: 200, height: 40)
                    return label
                }
                for label in cells {
                    window.addSubview(label)
                    label.layoutIfNeeded()
                }
                group.labels = cells
            }

            #if !targetEnvironment(macCatalyst)
                @Test func `the first member shows the start handle and the last the end handle`() {
                    group.selectAll()
                    #expect(!cells[0].selectionHandleStart.isHidden)
                    #expect(cells[0].selectionHandleEnd.isHidden)
                    #expect(cells[1].selectionHandleStart.isHidden)
                    #expect(cells[1].selectionHandleEnd.isHidden)
                    #expect(cells[2].selectionHandleStart.isHidden)
                    #expect(!cells[2].selectionHandleEnd.isHidden)
                }

                @Test func `an end handle dragged into another member keeps its recognizer until it ends`() {
                    group.selectAll()
                    let label = cells[2]
                    label.selectionHandleDidBeginDrag(.end)
                    let target = cells[0].convert(CGPoint(x: cells[0].bounds.maxX - 2, y: 20), to: label)
                    label.selectionHandleDidMove(.end, toLocationInSuperView: target)
                    #expect(cells[2].selectionRange == nil)
                    #expect(!cells[0].selectionHandleEnd.isHidden)
                    #expect(label.selectionHandleGrabGesture?.window === window)

                    label.selectionHandleDidEndDrag(.end)
                    #expect(label.selectionHandleGrabGesture?.window == nil)
                    #expect(group.selectedPlainText() == "Alpha")
                }
            #endif

            @Test func `the system text input reads the whole selection`() throws {
                guard #available(iOS 16.0, macCatalyst 16.0, *) else { return }
                group.selectAll()
                let proxy = try #require(cells[2].inputProxy)
                let selected = try #require(proxy.selectedTextRange)
                #expect(proxy.text(in: selected) == "Alpha\nBeta\nGamma")
                let selectAll = #selector(UIResponderStandardEditActions.selectAll(_:))
                #expect(!proxy.canPerformAction(selectAll, withSender: nil))
                #expect(proxy.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))
            }

            @Test func `the group delegate builds the menu`() {
                guard #available(iOS 16.0, macCatalyst 16.0, *) else { return }
                final class Delegate: TextSelectionGroupDelegate {
                    var text: String?
                    func textSelectionGroup(
                        _ group: TextSelectionGroup,
                        editMenuForSuggestedActions suggestedActions: [UIMenuElement],
                    ) -> UIMenu? {
                        text = group.selectedPlainText()
                        return UIMenu(title: "Custom", children: suggestedActions)
                    }
                }
                let delegate = Delegate()
                group.delegate = delegate
                group.selectAll()
                let menu = cells[1].selectionMenu(suggestedActions: [])
                #expect(menu?.title == "Custom")
                #expect(delegate.text == "Alpha\nBeta\nGamma")
            }

            @Test func `the menu covers the selection in every member`() {
                group.selectAll()
                let rects = group.selectionRects(in: cells[2])
                #expect(rects.count == 3)
                let union = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
                #expect(union.minY < -100)
                #expect(union.maxY > 0)
            }
        }

    #else

        @MainActor
        @Suite(.serialized)
        struct `Selection group on AppKit` {
            private let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled],
                backing: .buffered,
                defer: false,
            )
            private let cells: [TextLabelView]
            private let group = TextSelectionGroup()

            init() {
                window.isReleasedWhenClosed = false
                cells = ["Alpha", "Beta"].enumerated().map { index, text in
                    let label = TextLabelView(attributedText: NSAttributedString(
                        string: text,
                        attributes: [.font: NSFont.systemFont(ofSize: 16)],
                    ))
                    label.isSelectable = true
                    label.frame = CGRect(x: 20, y: 200 - CGFloat(index) * 60, width: 200, height: 40)
                    return label
                }
                for label in cells {
                    window.contentView?.addSubview(label)
                    label.layout()
                }
                group.labels = cells
            }

            private func rightClick(in label: TextLabelView) -> NSEvent {
                let rect = label.viewRect(fromLayoutRect: label.textLayout.rects(
                    for: NSRange(location: 1, length: 1),
                )[0])
                return NSEvent.mouseEvent(
                    with: .rightMouseDown,
                    location: label.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil),
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1,
                )!
            }

            @Test func `the menu acts on the whole selection and the group can change it`() throws {
                final class Delegate: TextSelectionGroupDelegate {
                    func textSelectionGroup(_: TextSelectionGroup, menu: NSMenu, event _: NSEvent) -> NSMenu? {
                        menu.insertItem(NSMenuItem(title: "Extra", action: nil, keyEquivalent: ""), at: 0)
                        return menu
                    }
                }
                let delegate = Delegate()
                group.delegate = delegate
                group.selectAll()
                let menu = try #require(cells[1].menu(for: rightClick(in: cells[1])))
                #expect(menu.items.first?.title == "Extra")
                #expect(menu.items.contains { $0.title.contains("Alpha Beta") })
                // A right click inside the selection keeps all of it.
                #expect(group.selectedPlainText() == "Alpha\nBeta")
            }

            @Test func `services and copy read the whole selection`() {
                group.selectAll()
                #expect(cells[0].validRequestor(forSendType: .string, returnType: nil) as AnyObject? === cells[0])
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("LitextSelectionGroupTests"))
                #expect(cells[0].writeSelection(to: pasteboard, types: [.string]))
                #expect(pasteboard.string(forType: .string) == "Alpha\nBeta")
            }

            @Test func `a mouse drag continues into the next member`() {
                let start = cells[0].viewRect(fromLayoutRect: cells[0].textLayout.rects(
                    for: NSRange(location: 2, length: 1),
                )[0])
                cells[0].interactionState.initialTouchLocation = CGPoint(x: start.minX, y: start.midY)
                let end = cells[1].viewRect(fromLayoutRect: cells[1].textLayout.rects(
                    for: NSRange(location: 1, length: 1),
                )[0])
                let endInFirst = cells[0].convert(CGPoint(x: end.maxX, y: end.midY), from: cells[1])
                cells[0].updateSelectionRange(withLocation: endInFirst)
                #expect(cells[0].selectionRange == NSRange(location: 2, length: 3))
                #expect(cells[1].selectionRange == NSRange(location: 0, length: 2))
                #expect(group.selectedPlainText() == "pha\nBe")
            }
        }

    #endif

#endif
