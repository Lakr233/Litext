//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS)

    @testable import Litext
    import Testing
    import UIKit

    /// The recognizer on the label's window that lets a handle be grabbed outside the
    /// label's bounds.
    @MainActor
    struct SelectionHandleGrabTests {
        private func makeWindow() -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
            window.isHidden = false
            return window
        }

        private func makeLabel(y: CGFloat = 100, in superview: UIView? = nil) -> TextLabelView {
            let label = TextLabelView(attributedText: NSAttributedString(
                string: "Hello Litext, a label with two lines of selectable text in it.",
                attributes: [.font: UIFont.systemFont(ofSize: 16)],
            ))
            label.isSelectable = true
            label.preferredMaxLayoutWidth = 300
            label.frame = CGRect(origin: CGPoint(x: 40, y: y), size: label.intrinsicContentSize)
            superview?.addSubview(label)
            label.layoutIfNeeded()
            return label
        }

        private func grabRecognizers(on window: UIWindow) -> [UIGestureRecognizer] {
            (window.gestureRecognizers ?? []).filter { $0.delegate is SelectionHandleGrabGesture }
        }

        /// The centre of a handle's knob, in the window's coordinates.
        private func knobCenter(_ kind: SelectionHandle.Kind, of label: TextLabelView) -> CGPoint {
            let frame = label.selectionHandle(kind).frame
            let y = switch kind {
            case .start: frame.minY + SelectionHandle.knobRadius
            case .end: frame.maxY - SelectionHandle.knobRadius
            }
            return label.convert(CGPoint(x: frame.midX, y: y), to: nil)
        }

        private func select(_ label: TextLabelView) {
            // Without presenting the menu, so selecting one label leaves the others alone.
            label.setSelectionRange(NSRange(location: 0, length: label.attributedText.length), presentsMenu: false)
        }

        @Test func `installs while the handles show and removes when the selection clears`() {
            let window = makeWindow()
            let label = makeLabel(in: window)
            #expect(grabRecognizers(on: window).isEmpty)

            select(label)
            #expect(grabRecognizers(on: window).count == 1)
            // Updating the selection keeps the one recognizer.
            label.setSelectionRange(NSRange(location: 2, length: 5), presentsMenu: false)
            #expect(grabRecognizers(on: window).count == 1)

            label.clearSelection()
            #expect(grabRecognizers(on: window).isEmpty)
        }

        @Test func `follows the label to another window`() {
            let first = makeWindow()
            let second = makeWindow()
            let label = makeLabel(in: first)
            select(label)
            #expect(grabRecognizers(on: first).count == 1)

            second.addSubview(label)
            #expect(grabRecognizers(on: first).isEmpty)

            select(label)
            #expect(grabRecognizers(on: first).isEmpty)
            #expect(grabRecognizers(on: second).count == 1)
            #expect(label.selectionHandleGrabGesture?.window === second)
        }

        @Test func `removing the label from its window removes the recognizer`() {
            let window = makeWindow()
            let container = UIView(frame: window.bounds)
            window.addSubview(container)
            let label = makeLabel(in: container)
            select(label)
            #expect(grabRecognizers(on: window).count == 1)

            // Removing an ancestor takes the label out of the window too.
            container.removeFromSuperview()
            #expect(grabRecognizers(on: window).isEmpty)
        }

        @Test func `hiding the label removes the recognizer`() {
            let window = makeWindow()
            let label = makeLabel(in: window)
            select(label)

            label.isHidden = true
            #expect(grabRecognizers(on: window).isEmpty)
            label.isHidden = false
            #expect(grabRecognizers(on: window).count == 1)
        }

        @Test func `a selected label removed from its window deallocates`() {
            let window = makeWindow()
            weak var weakLabel: TextLabelView?
            autoreleasepool {
                let label = makeLabel(in: window)
                weakLabel = label
                select(label)
                #expect(grabRecognizers(on: window).count == 1)
                label.removeFromSuperview()
            }
            #expect(weakLabel == nil)
            #expect(grabRecognizers(on: window).isEmpty)
        }

        @Test func `a label that deallocates takes its recognizer off the window`() {
            let window = makeWindow()
            weak var weakLabel: TextLabelView?
            weak var weakGesture: SelectionHandleGrabGesture?
            autoreleasepool {
                // A recognizer left on a window the label is not in, so only the label's
                // deinit can remove it. The window must not keep the label alive.
                let label = makeLabel()
                let gesture = SelectionHandleGrabGesture(label: label)
                label.selectionHandleGrabGesture = gesture
                gesture.attach(to: window)
                weakLabel = label
                weakGesture = gesture
                #expect(grabRecognizers(on: window).count == 1)
            }
            #expect(weakLabel == nil)
            #expect(grabRecognizers(on: window).isEmpty)
            #expect(weakGesture == nil)
        }

        @Test func `takes only touches in A visible handles grab area`() throws {
            let window = makeWindow()
            let container = UIView(frame: window.bounds)
            window.addSubview(container)
            let label = makeLabel(in: container)
            select(label)
            let gesture = try #require(label.selectionHandleGrabGesture)

            let start = knobCenter(.start, of: label)
            let end = knobCenter(.end, of: label)
            // Both knobs lie outside the label, above its first line and below its last.
            #expect(!label.frame.contains(start))
            #expect(!label.frame.contains(end))
            #expect(gesture.handleKind(atWindowPoint: start) == .start)
            #expect(gesture.handleKind(atWindowPoint: end) == .end)

            #expect(gesture.handleKind(atWindowPoint: CGPoint(x: 5, y: 5)) == nil)
            #expect(gesture.handleKind(atWindowPoint: CGPoint(x: 200, y: 500)) == nil)
            // Inside the label but away from both handles: the end of the first line, as
            // the short last line ends near the start.
            let middle = label.convert(CGPoint(x: label.bounds.maxX - 5, y: 5), to: nil)
            #expect(gesture.handleKind(atWindowPoint: middle) == nil)

            label.alpha = 0
            #expect(gesture.handleKind(atWindowPoint: start) == nil)
            label.alpha = 1
            label.isUserInteractionEnabled = false
            #expect(gesture.handleKind(atWindowPoint: start) == nil)
            label.isUserInteractionEnabled = true
            container.isHidden = true
            #expect(gesture.handleKind(atWindowPoint: start) == nil)
        }

        @Test func `two labels in one window each take only their own handles`() throws {
            let window = makeWindow()
            let upper = makeLabel(y: 100, in: window)
            let lower = makeLabel(y: 300, in: window)
            select(upper)
            select(lower)
            #expect(grabRecognizers(on: window).count == 2)

            let upperGesture = try #require(upper.selectionHandleGrabGesture)
            let lowerGesture = try #require(lower.selectionHandleGrabGesture)
            for kind in [SelectionHandle.Kind.start, .end] {
                #expect(upperGesture.handleKind(atWindowPoint: knobCenter(kind, of: upper)) == kind)
                #expect(lowerGesture.handleKind(atWindowPoint: knobCenter(kind, of: upper)) == nil)
                #expect(lowerGesture.handleKind(atWindowPoint: knobCenter(kind, of: lower)) == kind)
                #expect(upperGesture.handleKind(atWindowPoint: knobCenter(kind, of: lower)) == nil)
            }

            // Neither recognizer waits on the other.
            #expect(upperGesture.gestureRecognizer(
                upperGesture.recognizer,
                shouldBeRequiredToFailBy: lowerGesture.recognizer,
            ) == false)
            #expect(upperGesture.gestureRecognizer(
                upperGesture.recognizer,
                shouldBeRequiredToFailBy: UIPanGestureRecognizer(),
            ))

            lower.clearSelection()
            #expect(grabRecognizers(on: window).count == 1)
            #expect(upperGesture.window === window)
        }

        @Test func `leaves touches on views outside the labels screen`() throws {
            let window = makeWindow()
            let controller = UIViewController()
            controller.view.frame = window.bounds
            window.rootViewController = controller
            window.addSubview(controller.view)
            let label = makeLabel(in: controller.view)
            select(label)
            let gesture = try #require(label.selectionHandleGrabGesture)
            let start = knobCenter(.start, of: label)
            #expect(gesture.handleKind(atWindowPoint: start) == .start)

            // A view on the label's screen, such as the cell above, does not stop the grab.
            let sibling = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: label.frame.minY))
            controller.view.addSubview(sibling)
            #expect(gesture.handleKind(atWindowPoint: start) == .start)

            // A view over the screen, such as a bar or a presented sheet, does.
            let overlay = UIView(frame: window.bounds)
            window.addSubview(overlay)
            #expect(gesture.handleKind(atWindowPoint: start) == nil)
        }
    }

#endif
