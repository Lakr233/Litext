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
    struct `AppKit pointer tracking` {
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
            label.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
            window.contentView?.addSubview(label)
        }

        @Test
        func `one area follows the visible rect across resizes`() throws {
            label.updateTrackingAreas()
            let area = try #require(label.trackingAreas.first)
            #expect(label.trackingAreas.count == 1)
            #expect(area.options.contains(.inVisibleRect))
            #expect(area.options.contains(.cursorUpdate))

            for width in stride(from: 100, through: 380, by: 40) {
                label.frame.size.width = CGFloat(width)
                label.updateTrackingAreas()
            }
            #expect(label.trackingAreas.count == 1)
            #expect(label.trackingAreas.first === area)
        }

        @Test
        func `an area a subclass adds survives the update`() {
            let extra = NSTrackingArea(
                rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: label,
                userInfo: nil,
            )
            label.addTrackingArea(extra)
            label.updateTrackingAreas()
            label.updateTrackingAreas()
            #expect(label.trackingAreas.count == 2)
            #expect(label.trackingAreas.contains { $0 === extra })
        }
    }

#endif
