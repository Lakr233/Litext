//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
@testable import Litext
import QuartzCore
import Testing

#if canImport(UIKit) && !os(watchOS)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#if !os(watchOS)

    /// Every test drops its last strong reference inside an `autoreleasepool` and then checks
    /// a `weak` reference. Labels hold no CoreText-cached objects, so a label must be gone as
    /// soon as the pool drains; only work the label deliberately defers gets a grace period.
    @MainActor
    @Suite("TextLabelView lifetime", .tags(.memory))
    struct LitextViewLifetimeTests {
        // MARK: - Plain use

        @Test("A label that was laid out and drawn deallocates")
        func plainUse() {
            weak var weakLabel: TextLabelView?
            weak var weakLayout: TextLabel.Layout?
            autoreleasepool {
                let label = TextLabelView()
                label.attributedText = uniqueText()
                label.frame = CGRect(x: 0, y: 0, width: 240, height: 80)
                performLayoutPass(label)
                render(label)
                _ = label.intrinsicContentSize
                weakLabel = label
                weakLayout = label.textLayout
            }
            #expect(weakLabel == nil)
            #expect(weakLayout == nil)
        }

        @Test("A label with links and every interaction-free API exercised deallocates")
        func linkedTextUse() {
            weak var weakLabel: TextLabelView?
            var regions: [TextLabel.HighlightRegion] = []
            autoreleasepool {
                let text = uniqueText()
                appendLink(to: text)
                let label = makeLaidOutTestLabel(text)
                render(label)
                _ = label.layoutRuns(matching: .link)
                regions = label.highlightRegions
                weakLabel = label
            }
            // Regions outlive the label: they must not have kept it alive.
            #expect(!regions.isEmpty)
            #expect(weakLabel == nil)
        }

        // MARK: - Delegate

        @Test("The delegate is weak, so a delegate that owns its label releases both")
        func delegateIsWeak() {
            weak var weakLabel: TextLabelView?
            weak var weakDelegate: OwningDelegate?
            autoreleasepool {
                let delegate = OwningDelegate()
                let label = makeLaidOutTestLabel(uniqueText())
                label.isSelectable = true
                label.delegate = delegate
                delegate.label = label
                label.selectionRange = NSRange(location: 0, length: 4)
                weakLabel = label
                weakDelegate = delegate
                #expect(delegate.selectionChanges > 0)
            }
            #expect(weakDelegate == nil)
            #expect(weakLabel == nil)
        }

        @Test("A label does not keep its delegate alive")
        func labelDoesNotRetainDelegate() {
            let label = makeLaidOutTestLabel(uniqueText())
            weak var weakDelegate: OwningDelegate?
            autoreleasepool {
                let delegate = OwningDelegate()
                label.delegate = delegate
                weakDelegate = delegate
            }
            #expect(weakDelegate == nil)
            #expect(label.delegate == nil)
        }

        // MARK: - Selection

        @Test("A label with a live selection and selection layer deallocates, taking the layer with it")
        func activeSelection() async {
            weak var weakLabel: TextLabelView?
            weak var weakSelectionLayer: CAShapeLayer?
            autoreleasepool {
                let label = makeLaidOutTestLabel(uniqueText())
                label.isSelectable = true
                label.selectionBackgroundColor = .systemBlue
                label.selectionRange = NSRange(location: 0, length: 6)
                performLayoutPass(label)
                render(label)
                weakSelectionLayer = label.selectionLayer
                weakLabel = label
            }
            #expect(weakLabel == nil)
            // The implicit Core Animation transaction keeps the layers it touched until it
            // commits at the end of this run-loop turn.
            #expect(await waitUntil { weakSelectionLayer == nil })
        }

        // MARK: - Attachments

        @Test("A label with attachment views deallocates and leaves the views without a superview")
        func attachmentViewsAreReleasedWithTheLabel() {
            weak var weakLabel: TextLabelView?
            let views = (0 ..< 3).map { _ in PlatformView() }
            autoreleasepool {
                let text = uniqueText()
                for view in views {
                    appendAttachment(to: text, TextLabel.Attachment(size: CGSize(width: 12, height: 12), view: view))
                }
                let label = makeLaidOutTestLabel(text)
                render(label)
                #expect(views.allSatisfy { $0.superview === label })
                weakLabel = label
            }
            #expect(weakLabel == nil)
            #expect(views.allSatisfy { $0.superview == nil })
        }

        @Test("Attachments and their views deallocate once the label and the string are gone")
        func attachmentsDeallocateWithTheLabel() async {
            weak var weakLabel: TextLabelView?
            weak var weakAttachment: TextLabel.Attachment?
            weak var weakView: PlatformView?
            autoreleasepool {
                let view = PlatformView()
                let attachment = TextLabel.Attachment(size: CGSize(width: 18, height: 14), view: view)
                let text = uniqueText()
                appendAttachment(to: text, attachment)
                let label = makeLaidOutTestLabel(text)
                render(label)
                weakLabel = label
                weakAttachment = attachment
                weakView = view
            }
            #expect(weakLabel == nil)
            // The string was typeset, and CoreText may hold the run attributes, which name
            // the attachment, in a cache for a moment. Allow it to let go.
            #expect(await waitUntil { weakAttachment == nil && weakView == nil })
        }

        // MARK: - Window

        @Test("A label that was shown in a window and removed again deallocates")
        func addedToAndRemovedFromAWindow() {
            weak var weakLabel: TextLabelView?
            autoreleasepool {
                let window = makeWindow()
                let text = uniqueText()
                appendLink(to: text)
                let label = TextLabelView(attributedText: text)
                label.isSelectable = true
                label.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
                addToWindow(label, window)
                // No menu: the iOS test runner has no window scene, so UIKit can never show
                // an edit menu here, and its pending presentation would hold the view.
                label.setSelectionRange(NSRange(location: 0, length: 4), presentsMenu: false)
                label.removeFromSuperview()
                weakLabel = label
            }
            #expect(weakLabel == nil)
        }

        @Test("A label still inside a window deallocates with the window")
        func releasedWithItsWindow() {
            weak var weakLabel: TextLabelView?
            weak var weakWindow: PlatformWindowForTests?
            autoreleasepool {
                let window = makeWindow()
                let label = TextLabelView(attributedText: uniqueText())
                label.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
                addToWindow(label, window)
                weakLabel = label
                weakWindow = window
            }
            #expect(weakWindow == nil)
            #expect(weakLabel == nil)
        }

        // MARK: - Selection deduplication

        @Test("Deduplication notifications from other labels neither keep a label alive nor reach it afterwards")
        func selectionDeduplicationObserver() {
            weak var weakLabel: TextLabelView?
            let other = makeLaidOutTestLabel(uniqueText())
            other.isSelectable = true
            autoreleasepool {
                let label = makeLaidOutTestLabel(uniqueText())
                label.isSelectable = true
                label.selectionRange = NSRange(location: 0, length: 4)
                // The other label's selection posts the notification this label observes.
                other.selectionRange = NSRange(location: 0, length: 3)
                #expect(label.selectionRange == nil)
                label.selectionRange = NSRange(location: 0, length: 4)
                #expect(other.selectionRange == nil)
                weakLabel = label
            }
            #expect(weakLabel == nil)
            // Posting after the observer is gone must be harmless.
            other.selectionRange = NSRange(location: 0, length: 3)
            other.selectionRange = nil
            other.selectAll()
            #expect(other.selectionRange != nil)
        }

        @Test("Many labels that cleared each other's selections all deallocate")
        func manyDeduplicatingLabels() {
            var weakLabels: [WeakBox<TextLabelView>] = []
            autoreleasepool {
                let labels = (0 ..< 20).map { _ in makeLaidOutTestLabel(uniqueText()) }
                for label in labels {
                    label.isSelectable = true
                    label.selectionRange = NSRange(location: 0, length: 4)
                }
                #expect(labels.dropLast().allSatisfy { $0.selectionRange == nil })
                weakLabels = labels.map(WeakBox.init)
            }
            #expect(weakLabels.allSatisfy { $0.value == nil })
        }

        // MARK: - Highlight regions

        @Test("A pressed link's highlight region and layer do not keep the label alive")
        func activeHighlightRegionDoesNotRetainTheLabel() {
            weak var weakLabel: TextLabelView?
            var activeRegion: TextLabel.HighlightRegion?
            autoreleasepool {
                let text = uniqueText()
                appendLink(to: text)
                let label = makeLaidOutTestLabel(text)
                let region = label.highlightRegions.first { $0.kind == .link }
                if let region {
                    label.addActiveHighlightRegion(region)
                }
                #expect(region?.associatedObject is CALayer)
                activeRegion = region
                weakLabel = label
            }
            #expect(activeRegion != nil)
            #expect(weakLabel == nil)
        }

        @Test("The deferred highlight fade-out does not keep the label alive", .timeLimit(.minutes(1)))
        func highlightFadeOutHoldsTheLabelWeakly() async {
            weak var weakLabel: TextLabelView?
            weak var weakHighlightLayer: CALayer?
            autoreleasepool {
                let text = uniqueText()
                appendLink(to: text)
                let label = makeLaidOutTestLabel(text)
                if let region = label.highlightRegions.first(where: { $0.kind == .link }) {
                    label.addActiveHighlightRegion(region)
                    weakHighlightLayer = region.associatedObject as? CALayer
                }
                // Schedules a removal 0.4 s from now.
                label.deactivateHighlightRegion()
                #expect(label.pendingHighlightRemovalLayers.count == 1)
                weakLabel = label
            }
            // The label goes now, not when the fade-out fires.
            #expect(weakLabel == nil)
            await spinMainRunLoop(for: .milliseconds(600))
            #expect(weakHighlightLayer == nil)
        }
    }

    // MARK: - AppKit interaction

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)

        typealias PlatformWindowForTests = NSWindow

        @MainActor
        func makeWindow() -> NSWindow {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            return window
        }

        @MainActor
        func addToWindow(_ label: TextLabelView, _ window: NSWindow) {
            window.contentView?.addSubview(label)
            label.layoutSubtreeIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }

        @MainActor
        @Suite("TextLabelView lifetime after AppKit interaction", .tags(.memory))
        struct LitextAppKitInteractionLifetimeTests {
            private func mouseEvent(
                _ type: NSEvent.EventType,
                at point: CGPoint,
                in window: NSWindow,
                clickCount: Int = 1
            ) throws -> NSEvent {
                try #require(NSEvent.mouseEvent(
                    with: type,
                    location: point,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: clickCount,
                    pressure: 1
                ))
            }

            /// Builds a selectable, linked label in a window and runs `interact` on it.
            /// Returns weak references once every strong one is gone.
            private func runInteraction(
                _ interact: (TextLabelView, NSWindow) throws -> Void
            ) rethrows -> (label: WeakBox<TextLabelView>, window: WeakBox<NSWindow>) {
                var result: (WeakBox<TextLabelView>, WeakBox<NSWindow>)!
                try autoreleasepool {
                    let window = makeWindow()
                    let text = uniqueText("Interaction", length: 80)
                    appendLink(to: text, "pressable")
                    let label = TextLabelView(attributedText: text)
                    label.isSelectable = true
                    label.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
                    addToWindow(label, window)
                    let recorder = OwningDelegate()
                    label.delegate = recorder
                    try interact(label, window)
                    label.removeFromSuperview()
                    result = (WeakBox(label), WeakBox(window))
                }
                return result
            }

            private func textPoint(_ label: TextLabelView, x: CGFloat) -> CGPoint {
                let firstLine = label.textLayout.rects(for: NSRange(location: 0, length: 1)).first ?? .zero
                let rect = label.textLayout.viewRect(fromLayoutRect: firstLine)
                return label.convert(CGPoint(x: x, y: rect.midY), to: nil)
            }

            @Test("Mouse down, drag and up that select text leave nothing holding the label")
            func dragSelection() async throws {
                let refs = try runInteraction { label, window in
                    let start = textPoint(label, x: 2)
                    let end = textPoint(label, x: 120)
                    try label.mouseDown(with: mouseEvent(.leftMouseDown, at: start, in: window))
                    try label.mouseDragged(with: mouseEvent(.leftMouseDragged, at: end, in: window))
                    try label.mouseUp(with: mouseEvent(.leftMouseUp, at: end, in: window))
                    #expect(label.selectionRange != nil)
                }
                #expect(refs.label.value == nil)
                await spinMainRunLoop(for: .milliseconds(500))
                #expect(refs.label.value == nil)
            }

            @Test("Double and triple clicks leave nothing holding the label")
            func multiClickSelection() async throws {
                let refs = try runInteraction { label, window in
                    let point = textPoint(label, x: 20)
                    for clickCount in 1 ... 3 {
                        try label.mouseDown(with: mouseEvent(.leftMouseDown, at: point, in: window, clickCount: clickCount))
                        try label.mouseUp(with: mouseEvent(.leftMouseUp, at: point, in: window, clickCount: clickCount))
                    }
                    #expect(label.selectionRange != nil)
                }
                #expect(refs.label.value == nil)
                await spinMainRunLoop(for: .milliseconds(500))
                #expect(refs.label.value == nil)
            }

            @Test("Clicking a link schedules a fade-out that holds the label weakly")
            func linkClick() async throws {
                let refs = try runInteraction { label, window in
                    let run = try #require(label.layoutRuns(matching: .link).first)
                    let rect = label.textLayout.viewRect(fromLayoutRect: run.rect)
                    let point = label.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil)
                    try label.mouseDown(with: mouseEvent(.leftMouseDown, at: point, in: window))
                    #expect(label.activeHighlightRegion != nil)
                    try label.mouseUp(with: mouseEvent(.leftMouseUp, at: point, in: window))
                    #expect(label.pendingHighlightRemovalLayers.count == 1)
                }
                // Immediately, without waiting the 0.4 s the fade-out is scheduled for.
                #expect(refs.label.value == nil)
                await spinMainRunLoop(for: .milliseconds(600))
                #expect(refs.label.value == nil)
            }

            @Test("A label dropped mid-press, between mouse down and mouse up, deallocates")
            func droppedMidPress() throws {
                let refs = try runInteraction { label, window in
                    let point = textPoint(label, x: 10)
                    try label.mouseDown(with: mouseEvent(.leftMouseDown, at: point, in: window))
                    #expect(label.isInteractionInProgress)
                }
                #expect(refs.label.value == nil)
            }

            @Test("A label that was first responder and copied its selection deallocates")
            func firstResponderAndCopy() {
                let refs = runInteraction { label, window in
                    #expect(window.makeFirstResponder(label))
                    label.selectAll()
                    label.copyAction(nil)
                    #expect(window.firstResponder === label)
                }
                #expect(refs.label.value == nil)
            }

            @Test("Deferred work that runs after the label is gone is harmless")
            func deferredWorkAfterDeallocation() async throws {
                let refs = try runInteraction { label, window in
                    let run = try #require(label.layoutRuns(matching: .link).first)
                    let rect = label.textLayout.viewRect(fromLayoutRect: run.rect)
                    let point = label.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil)
                    // Press, release, press again and swap the text while pressed: every path
                    // that schedules a fade-out or a reset.
                    try label.mouseDown(with: mouseEvent(.leftMouseDown, at: point, in: window))
                    try label.mouseUp(with: mouseEvent(.leftMouseUp, at: point, in: window))
                    try label.mouseDown(with: mouseEvent(.leftMouseDown, at: point, in: window, clickCount: 2))
                    label.attributedText = uniqueText()
                }
                #expect(refs.label.value == nil)
                await spinMainRunLoop(for: .milliseconds(600))
                #expect(refs.label.value == nil)
                #expect(refs.window.value == nil)
            }
        }
    #endif

    // MARK: - UIKit interaction

    #if canImport(UIKit)

        typealias PlatformWindowForTests = UIWindow

        @MainActor
        func makeWindow() -> UIWindow {
            UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        }

        @MainActor
        func addToWindow(_ label: TextLabelView, _ window: UIWindow) {
            window.addSubview(label)
            window.layoutIfNeeded()
            label.layoutIfNeeded()
            render(label)
        }

        @MainActor
        @Suite("TextLabelView lifetime after UIKit interaction", .tags(.memory))
        struct LitextUIKitInteractionLifetimeTests {
            /// Builds a selectable, linked label and runs `interact` on it.
            ///
            /// The label stays out of a window. The iOS test runner has no window scene, so
            /// UIKit could never show the edit menu a selection asks for, and its pending
            /// presentation would hold the view; outside a window the label asks for none.
            private func runInteraction(
                _ interact: (TextLabelView) throws -> Void
            ) rethrows -> WeakBox<TextLabelView> {
                var result: WeakBox<TextLabelView>!
                try autoreleasepool {
                    let text = uniqueText("Interaction", length: 80)
                    appendLink(to: text, "pressable")
                    let label = makeLaidOutTestLabel(text, size: CGSize(width: 400, height: 200))
                    label.isSelectable = true
                    render(label)
                    let recorder = OwningDelegate()
                    label.delegate = recorder
                    try interact(label)
                    result = WeakBox(label)
                }
                return result
            }

            @Test("A selection set outside a window presents no menu and does not keep the label alive")
            func offscreenSelection() {
                let ref = runInteraction { label in
                    label.selectionRange = NSRange(location: 0, length: 5)
                    label.selectAll()
                    #expect(label.selectionRange != nil)
                }
                #expect(ref.value == nil)
            }

            @Test("A double tap's multi-click bookkeeping releases the label once its reset fires")
            func doubleTap() async {
                let ref = runInteraction { label in
                    label.setInteractionStateToBegin(initialLocation: CGPoint(x: 10, y: 10))
                    // Each tap schedules `performContinuousStateReset` 0.25 s out, which
                    // retains the label until it fires.
                    label.bumpClickCountIfWithinTimeGap()
                    label.bumpClickCountIfWithinTimeGap()
                    #expect(label.interactionState.clickCount == 2)
                    label.selectWordAtIndex(2)
                    #expect(label.selectionRange != nil)
                }
                #expect(await waitUntil { ref.value == nil })
            }

            @Test("Pressing and releasing a link holds the label weakly")
            func linkPress() async {
                let ref = runInteraction { label in
                    let region = label.highlightRegions.first { $0.kind == .link }
                    if let region {
                        label.addActiveHighlightRegion(region)
                    }
                    label.deactivateHighlightRegion()
                }
                #expect(ref.value == nil)
                await spinMainRunLoop(for: .milliseconds(600))
                #expect(ref.value == nil)
            }

            #if !targetEnvironment(macCatalyst) && !os(tvOS)
                @Test("Dragging a selection handle does not keep the label or its handles alive")
                func selectionHandlesAndMenu() async {
                    weak var weakHandle: SelectionHandle?
                    let ref = runInteraction { label in
                        label.selectionRange = NSRange(location: 0, length: 5)
                        label.selectionHandleDidBeginDrag(.end)
                        label.selectionHandleDidEndDrag(.end)
                        weakHandle = label.selectionHandleStart
                        #expect(weakHandle?.isHidden == false)
                    }
                    #expect(await waitUntil { ref.value == nil })
                    #expect(weakHandle == nil)
                }
            #endif
        }
    #endif

#endif // !os(watchOS)
