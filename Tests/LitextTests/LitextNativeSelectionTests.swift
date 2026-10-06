#if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS) && !os(visionOS)
    @testable import Litext
    import Testing
    import UIKit

    @MainActor
    @Suite(.serialized)
    struct NativeSelectionTests {
        private func host(_ texts: [String]) -> (UIWindow, [TextLabelView], TextSelectionGroup) {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
            let controller = UIViewController()
            window.rootViewController = controller
            window.makeKeyAndVisible()
            let labels = texts.enumerated().map { index, text in
                let label = TextLabelView(attributedText: NSAttributedString(
                    string: text,
                    attributes: [.font: UIFont.systemFont(ofSize: 16)],
                ))
                label.frame = CGRect(x: 20, y: 100 + index * 60, width: 300, height: 45)
                label.isSelectable = true
                controller.view.addSubview(label)
                label.layoutIfNeeded()
                return label
            }
            return (window, labels, TextSelectionGroup(labels: labels))
        }

        @Test func `group positions and geometry use one UTF16 document`() throws {
            guard #available(iOS 17.0, *) else { return }
            let (window, labels, group) = host(["A😀", "Beta"])
            defer { window.isHidden = true }
            group.separator = { _, _ in "\t" }
            let proxy = try #require(labels[0].inputProxy)
            let all = try #require(proxy.textRange(from: proxy.beginningOfDocument, to: proxy.endOfDocument))
            #expect(proxy.offset(from: proxy.beginningOfDocument, to: proxy.endOfDocument) == 8)
            #expect(proxy.text(in: all) == "A😀\tBeta")
            let start = try #require(proxy.position(from: proxy.beginningOfDocument, offset: 1))
            let end = try #require(proxy.position(from: proxy.beginningOfDocument, offset: 6))
            proxy.selectedTextRange = proxy.textRange(from: start, to: end)
            #expect(group.selectedPlainText() == "😀\tBe")
            let selected = try #require(proxy.selectedTextRange)
            #expect(proxy.text(in: selected) == "😀\tBe")
            #expect(proxy.selectionRects(for: selected).count == 2)
            let caret = proxy.caretRect(for: end)
            #expect(caret.width >= 1)
            #expect(labels[1].convert(labels[1].bounds, to: proxy.textInputView).contains(CGPoint(x: caret.midX, y: caret.midY)))
        }

        @Test func `a continuous selection has one pair of native handles and removal clears it`() throws {
            guard #available(iOS 17.0, *) else { return }
            let (window, labels, group) = host(["First", "Second"])
            defer { window.isHidden = true }
            group.selectAll()
            let display = try #require(labels[0].systemSelectionDisplay)
            #expect(labels[1].systemSelectionDisplay === display)
            #expect(labels[0].displayedSelectionHandle(.start) != nil)
            #expect(labels[0].displayedSelectionHandle(.end) == nil)
            #expect(labels[1].displayedSelectionHandle(.start) == nil)
            #expect(labels[1].displayedSelectionHandle(.end) != nil)
            #expect(labels.allSatisfy { $0.selectionHandleStart.isHidden && $0.selectionHandleEnd.isHidden && $0.selectionLayer == nil })
            labels[0].removeFromSuperview()
            #expect(!group.hasSelection)
            #expect(labels[1].displayedSelectionHandle(.end) == nil)
        }

        @Test func `a group whose first member is not selectable shows native UI over the rest`() throws {
            guard #available(iOS 17.0, *) else { return }
            let (window, labels, group) = host(["Header", "First", "Second"])
            defer { window.isHidden = true }
            labels[0].isSelectable = false
            group.selectAll()
            #expect(labels[1].displayedSelectionHandle(.start) != nil)
            #expect(labels[2].displayedSelectionHandle(.end) != nil)
            let proxy = try #require(labels[1].inputProxy)
            let all = try #require(proxy.textRange(from: proxy.beginningOfDocument, to: proxy.endOfDocument))
            #expect(proxy.text(in: all) == "First\nSecond")
            let selected = try #require(proxy.selectedTextRange)
            #expect(proxy.text(in: selected) == group.selectedPlainText())
            #expect(proxy.selectionRects(for: selected).count == 2)
        }

        @Test func `the selection keeps native UI when a member outside it leaves the window`() {
            guard #available(iOS 17.0, *) else { return }
            let (window, labels, group) = host(["Zero", "First", "Second"])
            defer { window.isHidden = true }
            group.setSelection(group.normalizedSelection(
                from: .init(member: 1, offset: 0),
                to: .init(member: 2, offset: 6),
            ), presentsMenu: false)
            labels[0].removeFromSuperview()
            #expect(group.selectedPlainText() == "First\nSecond")
            #expect(labels[1].displayedSelectionHandle(.start) != nil)
            #expect(labels[2].displayedSelectionHandle(.end) != nil)
        }

        @Test func `custom colors retain exact legacy fills and switching back restores native UI`() {
            guard #available(iOS 17.0, *) else { return }
            let (window, labels, group) = host(["First", "Second"])
            defer { window.isHidden = true }
            group.selectAll()
            let color = UIColor.systemRed.withAlphaComponent(0.4)
            labels[0].selectionBackgroundColor = color
            #expect(labels.allSatisfy { !$0.usesSystemSelectionDisplay && $0.selectionLayer != nil })
            #expect(labels[0].selectionLayer?.fillColor == color.cgColor)
            #expect(!labels[0].selectionHandleStart.isHidden)
            #expect(!labels[1].selectionHandleEnd.isHidden)
            #expect(group.selectedPlainText() == "First\nSecond")
            labels[0].selectionBackgroundColor = nil
            #expect(labels.allSatisfy { $0.usesSystemSelectionDisplay && $0.selectionLayer == nil })
            #expect(labels[0].systemSelectionDisplay === labels[1].systemSelectionDisplay)
        }

        @Test func `selection geometry follows reflow and hiding preserves the selection`() throws {
            guard #available(iOS 17.0, *) else { return }
            let (window, labels, group) = host([String(repeating: "wrap me across several lines. ", count: 4)])
            defer { window.isHidden = true }
            let label = labels[0]
            group.selectAll()
            let proxy = try #require(label.inputProxy)
            let range = try #require(proxy.selectedTextRange)
            let before = proxy.selectionRects(for: range).map(\.rect)
            #expect(!before.isEmpty)
            label.frame.size.width = 180
            label.setNeedsLayout()
            label.layoutIfNeeded()
            let after = proxy.selectionRects(for: range).map(\.rect)
            #expect(!after.isEmpty)
            #expect(after != before)
            let selected = group.selectedPlainText()
            label.isHidden = true
            #expect(group.selectedPlainText() == selected)
            #expect(label.displayedSelectionHandle(.start) == nil)
            label.isHidden = false
            #expect(group.selectedPlainText() == selected)
            #expect(label.displayedSelectionHandle(.start) != nil)
        }

        @Test func `a held long press clears a different group before release`() throws {
            guard #available(iOS 17.0, *) else { return }
            let (window, labels, oldGroup) = host(["First", "Second"])
            defer { window.isHidden = true }
            oldGroup.selectAll()
            let other = TextLabelView(attributedText: NSAttributedString(
                string: "Other word", attributes: [.font: UIFont.systemFont(ofSize: 16)],
            ))
            other.frame = CGRect(x: 20, y: 300, width: 300, height: 45)
            other.isSelectable = true
            window.rootViewController?.view.addSubview(other)
            other.layoutIfNeeded()
            let rect = try #require(other.textLayout.rects(for: NSRange(location: 1, length: 1)).first)
            let point = other.convertRectFromTextLayout(rect, insetForInteraction: false)
            other.longPressSelection(.began, at: CGPoint(x: point.midX, y: point.midY))
            defer { other.longPressSelection(.cancelled, at: .zero) }
            #expect(other.selectedPlainText() == "Other")
            #expect(!oldGroup.hasSelection)
            #expect(labels.allSatisfy { $0.displayedSelectionHandle(.start) == nil && $0.displayedSelectionHandle(.end) == nil })
        }
    }
#endif
