//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)

    @testable import Litext
    import Testing
    import UIKit

    /// The recognizer on the label's window that clears the selection when a tap
    /// lands elsewhere on the label's screen.
    @MainActor
    @Suite(.serialized)
    struct SelectionDismissTests {
        /// A key window with a root view controller, as an app's would be.
        private func makeScreen() -> (UIWindow, UIView) {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
            let controller = UIViewController()
            controller.view.frame = window.bounds
            window.rootViewController = controller
            window.makeKeyAndVisible()
            return (window, controller.view)
        }

        private func makeLabel(y: CGFloat = 100, in superview: UIView) -> TextLabelView {
            let label = TextLabelView(attributedText: NSAttributedString(
                string: "Hello Litext, a label with two lines of selectable text in it.",
                attributes: [.font: UIFont.systemFont(ofSize: 16)],
            ))
            label.isSelectable = true
            label.preferredMaxLayoutWidth = 300
            label.frame = CGRect(origin: CGPoint(x: 40, y: y), size: label.intrinsicContentSize)
            superview.addSubview(label)
            label.layoutIfNeeded()
            return label
        }

        private func dismissRecognizers(on window: UIWindow) -> [UIGestureRecognizer] {
            (window.gestureRecognizers ?? []).filter { $0.delegate is SelectionDismissGesture }
        }

        private func select(_ label: TextLabelView) {
            label.setSelectionRange(NSRange(location: 0, length: label.attributedText.length), presentsMenu: false)
        }

        /// Whether a tap at `point`, in window coordinates, clears the label's selection.
        private func tapDismisses(at point: CGPoint, in window: UIWindow, for label: TextLabelView) throws -> Bool {
            let gesture = try #require(label.selectionDismissGesture)
            return gesture.dismissesSelection(
                atWindowPoint: point,
                on: window.hitTest(point, with: nil),
                at: ProcessInfo.processInfo.systemUptime,
            )
        }

        @Test func `installs while the label holds a selection and removes when it clears`() {
            let (window, screen) = makeScreen()
            defer { window.isHidden = true }
            let label = makeLabel(in: screen)
            #expect(dismissRecognizers(on: window).isEmpty)

            select(label)
            #expect(dismissRecognizers(on: window).count == 1)
            label.setSelectionRange(NSRange(location: 2, length: 5), presentsMenu: false)
            #expect(dismissRecognizers(on: window).count == 1)
            // A caret is not a selection to dismiss.
            label.setSelectionRange(NSRange(location: 2, length: 0), presentsMenu: false)
            #expect(dismissRecognizers(on: window).isEmpty)

            select(label)
            label.clearSelection()
            #expect(dismissRecognizers(on: window).isEmpty)
        }

        @Test func `leaves the window with the label and stays off while it is hidden`() {
            let (window, screen) = makeScreen()
            defer { window.isHidden = true }
            let label = makeLabel(in: screen)
            select(label)

            label.isHidden = true
            #expect(dismissRecognizers(on: window).isEmpty)
            label.isHidden = false
            #expect(dismissRecognizers(on: window).count == 1)

            label.removeFromSuperview()
            #expect(dismissRecognizers(on: window).isEmpty)
        }

        @Test func `never takes a touch from the views under it`() throws {
            let (window, screen) = makeScreen()
            defer { window.isHidden = true }
            let label = makeLabel(in: screen)
            select(label)
            let recognizer = try #require(label.selectionDismissGesture?.recognizer)
            #expect(!recognizer.cancelsTouchesInView)
            #expect(!recognizer.delaysTouchesBegan)
            #expect(!recognizer.delaysTouchesEnded)
            let other = UIPanGestureRecognizer()
            #expect(recognizer.delegate?.gestureRecognizer?(recognizer, shouldRecognizeSimultaneouslyWith: other) == true)
        }

        @Test func `a tap elsewhere on the screen dismisses, on the label or a handle it does not`() throws {
            let (window, screen) = makeScreen()
            defer { window.isHidden = true }
            let label = makeLabel(in: screen)
            let button = UIButton(frame: CGRect(x: 0, y: 500, width: 400, height: 60))
            screen.addSubview(button)
            select(label)

            #expect(try tapDismisses(at: CGPoint(x: 200, y: 400), in: window, for: label))
            #expect(try tapDismisses(at: CGPoint(x: 200, y: 530), in: window, for: label))

            #expect(try !tapDismisses(at: label.convert(CGPoint(x: 10, y: 5), to: nil), in: window, for: label))
            for kind in [SelectionHandle.Kind.start, .end] {
                let rect: CGRect
                #if !os(visionOS)
                    let handle = try #require(label.displayedSelectionHandle(kind))
                    rect = handle.convert(handle.bounds, to: nil)
                #else
                    let handle = label.selectionHandle(kind)
                    rect = handle.convert(handle.bounds, to: nil)
                #endif
                let knob = CGPoint(x: rect.midX, y: kind == .start ? rect.minY - 10 : rect.maxY + 10)
                #expect(!label.frame.contains(knob))
                #expect(try !tapDismisses(at: knob, in: window, for: label))
            }
        }

        @Test func `a tap off the labels screen does not dismiss`() throws {
            let (window, screen) = makeScreen()
            defer { window.isHidden = true }
            let label = makeLabel(in: screen)
            select(label)
            let point = CGPoint(x: 200, y: 400)
            #expect(try tapDismisses(at: point, in: window, for: label))

            // A view over the screen, such as a bar, a presented sheet or the menu.
            let overlay = UIView(frame: window.bounds)
            window.addSubview(overlay)
            #expect(try !tapDismisses(at: point, in: window, for: label))
        }

        @Test func `a tap on another label or a sibling controller dismisses`() throws {
            let (window, screen) = makeScreen()
            defer { window.isHidden = true }
            let root = try #require(window.rootViewController)
            // The label in one child controller, like a transcript, and an input bar in
            // another.
            let transcript = UIViewController()
            let inputBar = UIViewController()
            for (child, frame) in [
                (transcript, CGRect(x: 0, y: 0, width: 400, height: 500)),
                (inputBar, CGRect(x: 0, y: 500, width: 400, height: 100)),
            ] {
                root.addChild(child)
                child.view.frame = frame
                screen.addSubview(child.view)
                child.didMove(toParent: root)
            }
            let label = makeLabel(y: 100, in: transcript.view)
            let other = makeLabel(y: 300, in: transcript.view)
            other.isSelectable = false
            select(label)

            #expect(try tapDismisses(at: other.convert(CGPoint(x: 10, y: 5), to: nil), in: window, for: label))
            #expect(try tapDismisses(at: CGPoint(x: 200, y: 450), in: window, for: label))
            #expect(try tapDismisses(at: CGPoint(x: 200, y: 550), in: window, for: label))
        }

        @Test func `dismissing tells the group delegate`() throws {
            let (window, screen) = makeScreen()
            defer { window.isHidden = true }
            let label = makeLabel(in: screen)
            let group = TextSelectionGroup(labels: [label])
            let delegate = GroupDelegate()
            group.delegate = delegate
            group.selectAll()
            let changes = delegate.changes

            try #require(label.selectionDismissGesture).dismiss()
            #expect(!group.hasSelection)
            #expect(delegate.changes == changes + 1)
        }

        @Test func `a tap while the menu shows only dismisses the menu`() throws {
            guard #available(iOS 16.0, visionOS 1.0, *) else { return }
            let (window, screen) = makeScreen()
            defer { window.isHidden = true }
            let label = makeLabel(in: screen)
            select(label)
            let point = CGPoint(x: 200, y: 400)
            #expect(try tapDismisses(at: point, in: window, for: label))

            label.showSelectionMenuController()
            #expect(label.isEditMenuVisible)
            #expect(try !tapDismisses(at: point, in: window, for: label))
            label.hideSelectionMenuController()
        }

        @Test func `a tap on another member of the group does not dismiss`() throws {
            let (window, screen) = makeScreen()
            defer { window.isHidden = true }
            let upper = makeLabel(y: 100, in: screen)
            let middle = makeLabel(y: 250, in: screen)
            let lower = makeLabel(y: 400, in: screen)
            let group = TextSelectionGroup(labels: [upper, middle, lower])
            // A selection held in the first member only.
            upper.setSelectionRange(NSRange(location: 0, length: 5), presentsMenu: false)
            #expect(group.hasSelection)
            #expect(dismissRecognizers(on: window).count == 1)

            let onLower = lower.convert(CGPoint(x: 10, y: 5), to: nil)
            #expect(try !tapDismisses(at: onLower, in: window, for: upper))
            #expect(try tapDismisses(at: CGPoint(x: 200, y: 580), in: window, for: upper))

            group.selectAll()
            #expect(dismissRecognizers(on: window).count == 3)
            group.clearSelection()
            #expect(dismissRecognizers(on: window).isEmpty)
        }

        @Test func `a tap that dismisses clears the selection and its group`() throws {
            let (window, screen) = makeScreen()
            defer { window.isHidden = true }
            let upper = makeLabel(y: 100, in: screen)
            let lower = makeLabel(y: 300, in: screen)
            let group = TextSelectionGroup(labels: [upper, lower])
            group.selectAll()
            let gesture = try #require(lower.selectionDismissGesture)

            gesture.dismiss()
            #expect(!group.hasSelection)
            #expect(upper.selectionRange == nil)
            #expect(lower.selectionRange == nil)
            #expect(dismissRecognizers(on: window).isEmpty)
        }

        @Test func `a label that deallocates takes its recognizer off the window`() {
            let (window, screen) = makeScreen()
            defer { window.isHidden = true }
            weak var weakLabel: TextLabelView?
            weak var weakGesture: SelectionDismissGesture?
            autoreleasepool {
                // A recognizer left on a window the label is not in, so only the label's
                // deinit can remove it. The window must not keep the label alive.
                let label = makeLabel(in: screen)
                label.removeFromSuperview()
                let gesture = SelectionDismissGesture(label: label)
                label.selectionDismissGesture = gesture
                gesture.attach(to: window)
                weakLabel = label
                weakGesture = gesture
                #expect(dismissRecognizers(on: window).count == 1)
            }
            #expect(weakLabel == nil)
            #expect(dismissRecognizers(on: window).isEmpty)
            #expect(weakGesture == nil)
        }
    }

    @MainActor
    private final class GroupDelegate: TextSelectionGroupDelegate {
        var changes = 0

        func textSelectionGroupDidChangeSelection(_: TextSelectionGroup) {
            changes += 1
        }
    }

#endif
