//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !os(tvOS) && !os(watchOS)

    @testable import Litext
    import Testing
    import UIKit

    /// Selection UI must never show over a controller or a view that covers the label.
    @MainActor
    @Suite(.serialized)
    struct `Presentation gate` {
        private let window: UIWindow
        private let controller: UIViewController
        private let label: TextLabelView

        init() {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
            controller = UIViewController()
            window.rootViewController = controller
            window.makeKeyAndVisible()
            label = TextLabelView(attributedText: NSAttributedString(
                string: "Hello brave new world",
                attributes: [.font: UIFont.systemFont(ofSize: 16)],
            ))
            label.isSelectable = true
            label.frame = CGRect(x: 20, y: 100, width: 300, height: 60)
            controller.view.addSubview(label)
            label.layoutIfNeeded()
        }

        /// Takes the window down before the test ends, so UIKit lays out nothing that
        /// refers to a controller the test released.
        private func tearDown() {
            controller.presentedViewController?.dismiss(animated: false)
            window.rootViewController = nil
            window.isHidden = true
        }

        private var selectionRect: CGRect {
            label.viewRect(fromLayoutRect: label.textLayout.rects(for: NSRange(location: 0, length: 5))[0])
        }

        @Test func `an uncovered label may present`() {
            defer { tearDown() }
            #expect(label.canPresentSelectionUI(from: selectionRect))
            // A view on the label's own screen, such as the next cell, does not count.
            let sibling = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 90))
            controller.view.addSubview(sibling)
            #expect(label.canPresentSelectionUI(from: selectionRect))
        }

        @Test func `a label outside a window or in a hidden window may not`() {
            defer { tearDown() }
            let detached = TextLabelView(attributedText: NSAttributedString(string: "Hello"))
            #expect(!detached.canPresentSelectionUI(from: .zero))
            window.isHidden = true
            #expect(!label.canPresentSelectionUI(from: selectionRect))
        }

        @Test func `a presented controller covers the label`() {
            defer { tearDown() }
            let sheet = UIViewController()
            sheet.modalPresentationStyle = .formSheet
            controller.present(sheet, animated: false)
            #expect(!label.canPresentSelectionUI(from: selectionRect))
            // The hit test is skipped while a menu is moving, the presentation is not.
            #expect(!label.canPresentSelectionUI(from: selectionRect, hitTests: false))
        }

        @Test func `a presentation from an ancestor covers a label in a child controller`() {
            defer { tearDown() }
            let child = UIViewController()
            controller.addChild(child)
            child.view.frame = controller.view.bounds
            controller.view.addSubview(child.view)
            child.didMove(toParent: controller)
            child.view.addSubview(label)
            #expect(label.canPresentSelectionUI(from: selectionRect))

            controller.present(UIViewController(), animated: false)
            #expect(!label.canPresentSelectionUI(from: selectionRect))
        }

        @Test func `a view laid over the window covers the label`() {
            defer { tearDown() }
            let overlay = UIView(frame: window.bounds)
            window.addSubview(overlay)
            #expect(!label.canPresentSelectionUI(from: selectionRect))
            // Only where it takes touches.
            overlay.isUserInteractionEnabled = false
            #expect(label.canPresentSelectionUI(from: selectionRect))
        }

        @Test func `a selection taller than the window passes where it shows`() {
            defer { tearDown() }
            label.frame = CGRect(x: 20, y: -500, width: 300, height: 2000)
            // Its middle lies under a bar laid over the lower part of the window.
            let bar = UIView(frame: CGRect(x: 0, y: 500, width: 400, height: 100))
            window.addSubview(bar)
            #expect(label.canPresentSelectionUI(from: label.bounds))
            // Nothing of a rect outside the window shows.
            #expect(!label.canPresentSelectionUI(from: CGRect(x: 0, y: 1700, width: 10, height: 10)))
        }

        @Test func `a covered label shows no menu`() {
            defer { tearDown() }
            guard #available(iOS 16.0, *) else { return }
            #if !targetEnvironment(macCatalyst)
                controller.present(UIViewController(), animated: false)
                label.selectionRange = NSRange(location: 0, length: 5)
                #expect(!label.isEditMenuVisible)
            #endif
        }
    }

#elseif canImport(AppKit) && !targetEnvironment(macCatalyst)

    import AppKit
    @testable import Litext
    import Testing

    @MainActor
    @Suite(.serialized)
    struct `Presentation gate` {
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

        private var selectionRect: CGRect {
            label.viewRect(fromLayoutRect: label.textLayout.rects(for: NSRange(location: 0, length: 5))[0])
        }

        @Test func `only a label in a visible window may present`() {
            #expect(!label.canPresentSelectionUI(from: selectionRect))
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            #expect(label.canPresentSelectionUI(from: selectionRect))
        }

        @Test func `a selection scrolled out of view checks the visible part`() {
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 100))
            let document = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
            scrollView.documentView = document
            window.contentView?.addSubview(scrollView)
            label.frame = document.bounds
            document.addSubview(label)
            label.layout()
            #expect(label.canPresentSelectionUI(from: CGRect(x: 0, y: 390, width: 10, height: 10)))
        }

        @Test func `a view laid over the label covers it`() {
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            let overlay = NSView(frame: label.frame)
            window.contentView?.addSubview(overlay)
            #expect(!label.canPresentSelectionUI(from: selectionRect))
        }

        @Test func `an attached sheet covers the label`() {
            window.orderFrontRegardless()
            let sheet = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
                styleMask: [.titled],
                backing: .buffered,
                defer: false,
            )
            sheet.isReleasedWhenClosed = false
            window.beginSheet(sheet, completionHandler: nil)
            #expect(window.attachedSheet === sheet)
            #expect(!label.canPresentSelectionUI(from: selectionRect))
            window.endSheet(sheet)
            window.orderOut(nil)
        }
    }

#endif
