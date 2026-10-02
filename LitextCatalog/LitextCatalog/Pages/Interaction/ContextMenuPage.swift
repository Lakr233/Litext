//
//  ContextMenuPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  The menu a selection shows: the system's own on iOS, a read-only text
//  view's on macOS, and the delegate hooks that extend or replace it.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#if os(tvOS)
    struct ContextMenuPage: View {
        var body: some View {
            CatalogUnavailableView(
                page: .contextMenu,
                reason: "tvOS has no edit or context menu, so TextLabelViewDelegate has no menu hook there.",
            )
        }
    }
#else
    struct ContextMenuPage: View {
        #if canImport(UIKit)
            private static let code = """
            // iOS 16+, Mac Catalyst 16+, visionOS: the system edit menu. Return nil
            // to keep it; `suggestedActions` already lacks Cut, Paste and Delete.
            func textLabelView(
                _ label: TextLabelView,
                editMenuForSelection selection: NSRange,
                suggestedActions: [UIMenuElement],
            ) -> UIMenu? {
                let quote = UIAction(title: "Copy as Quote", image: UIImage(systemName: "quote.opening")) { _ in
                    UIPasteboard.general.string = "> " + (label.selectedPlainText() ?? "")
                }
                return UIMenu(children: suggestedActions + [
                    UIMenu(options: .displayInline, children: [quote]),
                ])
            }

            // Mac Catalyst adds a right-click interaction itself; on iOS a secondary
            // click shows the menu without one. Add one when you need it:
            label.installContextMenuInteraction()
            """
        #else
            private static let code = """
            // Right click: Look Up, Translate, Copy, Share, Speech and Services, like
            // a read-only NSTextView. A right click on a link shows Open/Copy Link.
            func textLabelView(
                _ label: TextLabelView,
                menu: NSMenu,
                forSelection selection: NSRange,
                event: NSEvent,
            ) -> NSMenu? {
                menu.addItem(.separator())
                menu.addItem(withTitle: "Copy as Quote", action: #selector(copyAsQuote(_:)), keyEquivalent: "")
                    .target = self
                return menu      // or a new NSMenu to replace it; nil keeps `menu`
            }

            label.startSpeaking(nil)   // the selection, or all the text
            label.stopSpeaking(nil)
            label.copy(nil)            // what Edit ▸ Copy and ⌘C call
            """
        #endif

        @State private var events = ContextMenuEvents()
        @State private var mode = ContextMenuEvents.Mode.extended
        private let text = Self.makeText()

        var body: some View {
            CatalogPageScaffold(.contextMenu, code: Self.code) {
                VStack(alignment: .leading, spacing: 12) {
                    PlatformViewHost.label {
                        TextLabelView()
                    } update: { label in
                        events.label = label
                        events.mode = mode
                        label.delegate = events
                        label.isSelectable = true
                        label.attributedText = text
                    }
                    .accessibilityIdentifier("demo.contextMenu.label")
                    CatalogNote(Self.hint, systemImage: "contextualmenu.and.cursorarrow")
                }
            } controls: {
                CatalogPicker(
                    "Menu",
                    selection: $mode,
                    options: ContextMenuEvents.Mode.allCases,
                ) { $0.title }
                Text(mode.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                #if os(macOS)
                    HStack {
                        Button("startSpeaking(nil)") { events.label?.startSpeaking(nil) }
                        Button("stopSpeaking(nil)") { events.label?.stopSpeaking(nil) }
                        Button("copy(nil)") { events.label?.copy(nil) }
                    }
                    .buttonStyle(.bordered)
                #endif
                Button("Select a word to start") { events.label?.selectWord(at: 4) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("demo.contextMenu.selectWord")
                CatalogReadout("Menu requests", value: "\(events.requestCount)", identifier: "state.contextMenu.requests")
                CatalogReadout("Last selection", value: events.lastSelection, identifier: "state.contextMenu.selection")
                CatalogReadout("Items offered", value: events.offeredItems, identifier: "state.contextMenu.items")
                CatalogReadout("Last custom action", value: events.lastAction, identifier: "state.contextMenu.action")
            }
        }

        private static var hint: String {
            #if os(macOS)
                "Right-click (or Control-click) a word: the label selects it and opens its menu. A right click on "
                    + "the link shows Open Link and Copy Link instead, without asking the delegate."
            #elseif targetEnvironment(macCatalyst)
                "Select some text, then right-click it to open the menu."
            #else
                "Select some text, then tap the selection (or right-click it with a pointer) to show the edit menu."
            #endif
        }

        private static func makeText() -> NSAttributedString {
            let body: [NSAttributedString.Key: Any] = [
                .font: PlatformFont.systemFont(ofSize: 17),
                .foregroundColor: PlatformColor.label,
            ]
            let text = NSMutableAttributedString(
                string: "The menu belongs to the selection. Ask for it over any words here, or over ",
                attributes: body,
            )
            var link = body
            link[.link] = URL(string: "https://github.com/Lakr233/Litext")
            link[.foregroundColor] = PlatformColor.systemBlue
            text.append(NSAttributedString(string: "this link", attributes: link))
            text.append(NSAttributedString(
                string: " to compare. The delegate sees the range and can add, reorder or replace items.",
                attributes: body,
            ))
            return text
        }
    }

    /// Builds the selection menu for the page and keeps what happened for the readouts.
    @Observable
    final class ContextMenuEvents: NSObject, TextLabelViewDelegate {
        enum Mode: String, CaseIterable, Hashable {
            case system
            case extended
            case replaced

            var title: String {
                switch self {
                case .system: "System"
                case .extended: "Extended"
                case .replaced: "Replaced"
                }
            }

            var explanation: String {
                switch self {
                case .system: "The delegate returns nil: the label's own menu shows."
                case .extended: "The delegate appends Copy as Quote and Show Length to the label's menu."
                case .replaced: "The delegate returns a menu of its own with only the custom items."
                }
            }
        }

        @ObservationIgnored weak var label: TextLabelView?
        @ObservationIgnored var mode = Mode.extended
        var requestCount = 0
        var lastSelection = "none"
        var offeredItems = "none"
        var lastAction = "none"

        private func copyAsQuote() {
            let quote = "> " + (label?.selectedPlainText() ?? "")
            #if canImport(UIKit)
                UIPasteboard.general.string = quote
            #else
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(quote, forType: .string)
            #endif
            lastAction = "Copied \(quote.count) characters as a quote"
        }

        private func showLength() {
            let text = label?.selectedPlainText() ?? ""
            lastAction = "\(text.count) characters, \(text.utf16.count) UTF-16 units"
        }

        private func record(_ selection: NSRange, titles: [String]) {
            requestCount += 1
            lastSelection = "{\(selection.location), \(selection.length)}"
            offeredItems = titles.isEmpty ? "none" : titles.joined(separator: ", ")
        }

        #if canImport(UIKit)
            func textLabelView(
                _: TextLabelView,
                editMenuForSelection selection: NSRange,
                suggestedActions: [UIMenuElement],
            ) -> UIMenu? {
                record(selection, titles: suggestedActions.map(Self.title(of:)))
                let custom: [UIMenuElement] = [
                    UIAction(title: "Copy as Quote", image: UIImage(systemName: "quote.opening")) { [weak self] _ in
                        self?.copyAsQuote()
                    },
                    UIAction(title: "Show Length", image: UIImage(systemName: "ruler")) { [weak self] _ in
                        self?.showLength()
                    },
                ]
                switch mode {
                case .system:
                    return nil
                case .extended:
                    return UIMenu(children: suggestedActions + [UIMenu(options: .displayInline, children: custom)])
                case .replaced:
                    return UIMenu(children: custom)
                }
            }

            private static func title(of element: UIMenuElement) -> String {
                if let menu = element as? UIMenu {
                    return menu.title.isEmpty ? "[\(menu.children.map(title(of:)).joined(separator: ", "))]" : menu.title
                }
                if let command = element as? UICommand {
                    return command.title
                }
                if let action = element as? UIAction {
                    return action.title
                }
                return "item"
            }
        #else
            func textLabelView(
                _: TextLabelView,
                menu: NSMenu,
                forSelection selection: NSRange,
                event _: NSEvent,
            ) -> NSMenu? {
                record(selection, titles: menu.items.filter { !$0.isSeparatorItem }.map(\.title))
                let custom = [
                    NSMenuItem(title: "Copy as Quote", action: #selector(copyAsQuoteItem(_:)), keyEquivalent: ""),
                    NSMenuItem(title: "Show Length", action: #selector(showLengthItem(_:)), keyEquivalent: ""),
                ]
                for item in custom {
                    item.target = self
                }
                switch mode {
                case .system:
                    return nil
                case .extended:
                    menu.addItem(.separator())
                    custom.forEach(menu.addItem)
                    return menu
                case .replaced:
                    let replacement = NSMenu()
                    custom.forEach(replacement.addItem)
                    return replacement
                }
            }

            @objc private func copyAsQuoteItem(_: Any?) {
                copyAsQuote()
            }

            @objc private func showLengthItem(_: Any?) {
                showLength()
            }
        #endif
    }
#endif
