//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

@testable import Litext
import SwiftUI
import Testing

#if canImport(UIKit) && !os(watchOS)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#if !os(watchOS)

    @MainActor
    @Suite("SwiftUI lifetime", .tags(.memory))
    struct LitextSwiftUILifetimeTests {
        private struct Host: View {
            let text: NSAttributedString

            var body: some View {
                VStack {
                    TextLabel(attributedString: text)
                        .selectable()
                        .onTapLink { _ in }
                        .onSelectionChange { _ in }
                }
                .frame(width: 320)
            }
        }

        #if canImport(UIKit)
            /// Hosts `Host` in a window, runs `body` with the hosted label, and tears it all down.
            private func hostAndTearDown(
                _ body: (TextLabelView) -> Void,
            ) throws -> (label: WeakBox<TextLabelView>, coordinator: WeakBox<TextLabel.Coordinator>) {
                var result: (WeakBox<TextLabelView>, WeakBox<TextLabel.Coordinator>)!
                try autoreleasepool {
                    let text = uniqueText("Hosted", length: 60)
                    appendLink(to: text)
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
                    let controller = UIHostingController(rootView: Host(text: text))
                    window.rootViewController = controller
                    window.isHidden = false
                    controller.view.frame = window.bounds
                    controller.view.layoutIfNeeded()
                    let label = try #require(findTextLabelView(in: controller.view))
                    let coordinator = try #require(label.delegate as? TextLabel.Coordinator)
                    body(label)
                    result = (WeakBox(label), WeakBox(coordinator))
                    window.rootViewController = nil
                    window.isHidden = true
                }
                return result
            }
        #elseif canImport(AppKit)
            /// Hosts `Host` in a window, runs `body` with the hosted label, and tears it all down.
            private func hostAndTearDown(
                _ body: (TextLabelView) -> Void,
            ) throws -> (label: WeakBox<TextLabelView>, coordinator: WeakBox<TextLabel.Coordinator>) {
                var result: (WeakBox<TextLabelView>, WeakBox<TextLabel.Coordinator>)!
                try autoreleasepool {
                    let text = uniqueText("Hosted", length: 60)
                    appendLink(to: text)
                    let window = makeWindow()
                    let hostingView = NSHostingView(rootView: Host(text: text))
                    hostingView.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
                    window.contentView = hostingView
                    hostingView.layoutSubtreeIfNeeded()
                    let label = try #require(findTextLabelView(in: hostingView))
                    let coordinator = try #require(label.delegate as? TextLabel.Coordinator)
                    body(label)
                    result = (WeakBox(label), WeakBox(coordinator))
                    window.contentView = nil
                }
                return result
            }
        #endif

        @Test
        func `A hosted TextLabel's view and coordinator deallocate after the host is torn down`() async throws {
            let refs = try hostAndTearDown { label in
                #expect(label.attributedText.length > 0)
                #expect(label.isSelectable)
            }
            // SwiftUI may finish dismantling the graph on a later turn.
            #expect(await waitUntil { refs.label.value == nil })
            #expect(await waitUntil { refs.coordinator.value == nil })
        }

        @Test
        func `A hosted label with a selection and a pending deferred report deallocates`() async throws {
            let refs = try hostAndTearDown { label in
                label.selectionRange = NSRange(location: 0, length: 6)
                if let coordinator = label.delegate as? TextLabel.Coordinator {
                    // Queue the deferred report as an update in flight would.
                    coordinator.isApplyingUpdate = true
                    label.selectionRange = NSRange(location: 0, length: 3)
                    coordinator.isApplyingUpdate = false
                }
            }
            #expect(await waitUntil { refs.label.value == nil })
            #expect(await waitUntil { refs.coordinator.value == nil })
        }

        @Test
        func `The deferred selection flush holds the coordinator weakly`() async {
            weak var weakCoordinator: TextLabel.Coordinator?
            var reports = 0
            let label = makeLaidOutTestLabel(uniqueText())
            label.isSelectable = true
            autoreleasepool {
                let coordinator = TextLabel.Coordinator(onTapLink: nil) { _ in reports += 1 }
                label.delegate = coordinator
                coordinator.isApplyingUpdate = true
                label.selectionRange = NSRange(location: 0, length: 4)
                coordinator.isApplyingUpdate = false
                weakCoordinator = coordinator
            }
            // The flush task has not run yet, and it must not be what keeps the coordinator.
            #expect(weakCoordinator == nil)
            await yieldToMainActor(times: 20)
            #expect(reports == 0)
        }

        @Test
        func `A coordinator does not keep the label it serves alive`() {
            weak var weakLabel: TextLabelView?
            let coordinator = TextLabel.Coordinator(onTapLink: nil, onSelectionChange: nil)
            autoreleasepool {
                let label = makeLaidOutTestLabel(uniqueText())
                label.isSelectable = true
                label.delegate = coordinator
                label.selectionRange = NSRange(location: 0, length: 4)
                weakLabel = label
            }
            #expect(weakLabel == nil)
        }
    }

#endif // !os(watchOS)
