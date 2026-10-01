//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)

    import AppKit
    import AVFoundation
    import SwiftUI
    import Translation

    /// The context menu, built from public AppKit API to match a read-only
    /// `NSTextView`: Look Up, Translate, Copy, Share and Speech, with the Services
    /// submenu that AppKit appends to any menu of a view that can send text.
    extension TextLabelView {
        override open func menu(for event: NSEvent) -> NSMenu? {
            let point = convert(event.locationInWindow, from: nil)
            if !selectionContains(point), let linkURL = linkRegion(at: point)?.linkURL {
                selectedLinkForMenuAction = linkURL
                return linkMenu()
            }
            guard isSelectable else { return super.menu(for: event) }

            // Like NSTextView, a right click away from the selection selects the word under it.
            if !selectionContains(point), let index = characterIndexAtPoint(point) {
                selectWordAtIndex(index)
            }
            guard let range = selectionRange, range.length > 0,
                  let text = selectedPlainText(), !text.isEmpty
            else { return super.menu(for: event) }

            window?.makeFirstResponder(self)
            Self.registerServicesSendTypes()
            let menu = selectionMenu(for: text)
            return delegate?.textLabelView(self, menu: menu, forSelection: range, event: event) ?? menu
        }

        private func selectionMenu(for text: String) -> NSMenu {
            let menu = NSMenu()
            let title = Self.menuTitleQuote(for: text)
            menu.addItem(NSMenuItem(
                title: String(format: LocalizedText.lookUp, title),
                action: #selector(lookUpSelection(_:)),
                keyEquivalent: "",
            ))
            if #available(macOS 14.4, *) {
                menu.addItem(NSMenuItem(
                    title: String(format: LocalizedText.translate, title),
                    action: #selector(translateSelection(_:)),
                    keyEquivalent: "",
                ))
            }
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: LocalizedText.copy, action: #selector(copy(_:)), keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(shareMenuItem(for: text))
            menu.addItem(.separator())
            menu.addItem(speechMenuItem())
            return menu
        }

        private func linkMenu() -> NSMenu {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: LocalizedText.openLink, action: #selector(openLink(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: LocalizedText.copyLink, action: #selector(copyLink(_:)), keyEquivalent: ""))
            return menu
        }

        /// The selection as the system quotes it in a menu title: whitespace runs
        /// collapsed to one space and anything past 30 characters cut to an ellipsis.
        static func menuTitleQuote(for text: String) -> String {
            let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let limit = 30
            guard words.count > limit else { return words }
            return words.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
        }

        // MARK: - Look Up and Translate

        @objc private func lookUpSelection(_: Any?) {
            guard let range = selectionRange, let text = selectedAttributedText(),
                  let origin = textLayout.baselineOrigin(at: range.location)
            else { return }
            let point = viewRect(fromLayoutRect: CGRect(origin: origin, size: .zero)).origin
            showDefinition(for: text, at: point)
        }

        /// Looks up the word under a force click or a three-finger tap, as NSTextView does.
        override open func quickLook(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let string = textLayout.attributedString
            guard let index = characterIndexAtPoint(point) else {
                super.quickLook(with: event)
                return
            }
            let wordRange = (string.string as NSString).rangeOfWord(at: index)
            guard wordRange.location != NSNotFound, wordRange.length > 0,
                  let origin = textLayout.baselineOrigin(at: wordRange.location)
            else {
                super.quickLook(with: event)
                return
            }
            let baseline = viewRect(fromLayoutRect: CGRect(origin: origin, size: .zero)).origin
            showDefinition(for: string.attributedSubstring(from: wordRange), at: baseline)
        }

        @available(macOS 14.4, *)
        @objc private func translateSelection(_: Any?) {
            guard let range = selectionRange, let text = selectedPlainText(), !text.isEmpty,
                  let anchor = textLayout.rects(for: range).first
            else { return }
            // The system translation popover is SwiftUI-only; a hosting view over the
            // first selected line anchors it and goes away when it closes.
            let host = NSHostingView(rootView: TranslationPopoverAnchor(text: text))
            host.rootView.onDismiss = { [weak host] in host?.removeFromSuperview() }
            host.frame = viewRect(fromLayoutRect: anchor)
            addSubview(host)
        }

        // MARK: - Share and Speech

        private func shareMenuItem(for text: String) -> NSMenuItem {
            if #available(macOS 13.0, *) {
                return NSSharingServicePicker(items: [text]).standardShareMenuItem
            }
            let item = NSMenuItem(title: LocalizedText.shareEllipsis, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for service in NSSharingService.sharingServices(forItems: [text]) {
                let serviceItem = NSMenuItem(
                    title: service.menuItemTitle,
                    action: #selector(performShareService(_:)),
                    keyEquivalent: "",
                )
                serviceItem.image = service.image
                serviceItem.representedObject = service
                submenu.addItem(serviceItem)
            }
            item.submenu = submenu
            item.isEnabled = !submenu.items.isEmpty
            return item
        }

        @objc private func performShareService(_ sender: NSMenuItem) {
            guard let service = sender.representedObject as? NSSharingService,
                  let text = selectedPlainText()
            else { return }
            service.perform(withItems: [text])
        }

        private func speechMenuItem() -> NSMenuItem {
            let item = NSMenuItem(title: LocalizedText.speech, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.addItem(NSMenuItem(
                title: LocalizedText.startSpeaking,
                action: #selector(startSpeaking(_:)),
                keyEquivalent: "",
            ))
            submenu.addItem(NSMenuItem(
                title: LocalizedText.stopSpeaking,
                action: #selector(stopSpeaking(_:)),
                keyEquivalent: "",
            ))
            item.submenu = submenu
            return item
        }

        /// Speaks the selection, or the whole text when nothing is selected.
        @objc open func startSpeaking(_: Any?) {
            let text = selectedPlainText() ?? attributedText.string
            guard !text.isEmpty else { return }
            TextLabelSpeech.shared.speak(text)
        }

        @objc open func stopSpeaking(_: Any?) {
            TextLabelSpeech.shared.stop()
        }

        // MARK: - Links

        @objc func copyLink(_: Any?) {
            guard let linkURL = selectedLinkForMenuAction else { return }
            writeToPasteboard(linkURL.absoluteString)
        }

        @objc func openLink(_: Any?) {
            guard let url = selectedLinkForMenuAction else { return }
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Edit menu and Services

    extension TextLabelView: NSMenuItemValidation {
        /// Copies the selection. The Edit menu's Copy and ⌘C reach it through the responder chain.
        @objc open func copy(_: Any?) {
            copySelectionOrNestedSelection()
        }

        override open func selectAll(_: Any?) {
            selectAll()
        }

        open func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
            switch menuItem.action {
            case #selector(copy(_:)):
                (selectionRange?.length ?? 0) > 0
            case #selector(selectAll(_:)):
                selectAllRange() != nil
            case #selector(stopSpeaking(_:)):
                TextLabelSpeech.shared.isSpeaking
            default:
                true
            }
        }

        override open func validRequestor(
            forSendType sendType: NSPasteboard.PasteboardType?,
            returnType: NSPasteboard.PasteboardType?,
        ) -> Any? {
            // Read-only: the label can send its selection to a service but takes nothing back.
            if returnType == nil, sendType == nil || sendType == .string || sendType == .rtf,
               let range = selectionRange, range.length > 0
            {
                return self
            }
            return super.validRequestor(forSendType: sendType, returnType: returnType)
        }

        /// AppKit lists only the services whose send types an app has registered.
        /// NSTextView registers plain and rich text; a label that sends text does the same.
        fileprivate static func registerServicesSendTypes() {
            guard !didRegisterServicesSendTypes else { return }
            didRegisterServicesSendTypes = true
            NSApp.registerServicesMenuSendTypes([.string, .rtf], returnTypes: [])
        }

        private static var didRegisterServicesSendTypes = false
    }

    extension TextLabelView: @preconcurrency NSServicesMenuRequestor {
        public func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
            guard let text = selectedAttributedText(), text.length > 0 else { return false }
            pboard.clearContents()
            var didWrite = false
            if types.contains(.string) {
                didWrite = pboard.setString(text.string, forType: .string) || didWrite
            }
            if types.contains(.rtf),
               let data = try? text.data(
                   from: NSRange(location: 0, length: text.length),
                   documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
               )
            {
                didWrite = pboard.setData(data, forType: .rtf) || didWrite
            }
            return didWrite
        }
    }

    // MARK: - Helpers

    /// One speech synthesizer for every label, so starting one stops the other, as
    /// the system's Start Speaking does.
    @MainActor
    final class TextLabelSpeech {
        static let shared = TextLabelSpeech()
        private let synthesizer = AVSpeechSynthesizer()

        var isSpeaking: Bool {
            synthesizer.isSpeaking
        }

        func speak(_ text: String) {
            synthesizer.stopSpeaking(at: .immediate)
            synthesizer.speak(AVSpeechUtterance(string: text))
        }

        func stop() {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// Presents the system translation popover as soon as it appears and reports when
    /// the popover closes.
    @available(macOS 14.4, *)
    private struct TranslationPopoverAnchor: View {
        let text: String
        var onDismiss: () -> Void = {}
        @State private var isPresented = false

        var body: some View {
            Color.clear
                .translationPresentation(isPresented: $isPresented, text: text)
                .onAppear { isPresented = true }
                .onChange(of: isPresented) { _, isPresented in
                    if !isPresented {
                        onDismiss()
                    }
                }
        }
    }

#endif
