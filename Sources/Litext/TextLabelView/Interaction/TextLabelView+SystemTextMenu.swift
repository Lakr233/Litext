//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !os(tvOS) && !os(watchOS)

    import UIKit

    /// The system text menu, through `TextLabelInputProxy`.
    ///
    /// From iOS 16 and Mac Catalyst 16 the selection menu is the system's own, with
    /// Look Up, Translate, Share and whatever the system adds later. Earlier systems
    /// keep the label's Copy, Select All and Share menu.
    extension TextLabelView {
        @available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *)
        var inputProxy: TextLabelInputProxy? {
            inputProxyStorage as? TextLabelInputProxy
        }

        /// Adds the proxy while the label is selectable and removes it otherwise.
        func updateInputProxy() {
            guard #available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *) else { return }
            if isSelectable {
                guard inputProxyStorage == nil else { return }
                let proxy = TextLabelInputProxy(label: self)
                proxy.frame = bounds
                // Under the attachment views and the selection handles.
                insertSubview(proxy, at: 0)
                inputProxyStorage = proxy
            } else if let proxy = inputProxyStorage {
                hideSelectionMenuController()
                proxy.resignFirstResponder()
                proxy.removeFromSuperview()
                inputProxyStorage = nil
            }
        }

        /// Makes the responder that runs Copy and Select All the first responder: the
        /// proxy where the system menu is in use, the label itself otherwise.
        @discardableResult
        func becomeSelectionFirstResponder() -> Bool {
            if #available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *), let proxy = inputProxy {
                return proxy.isFirstResponder || proxy.becomeFirstResponder()
            }
            return isFirstResponder || becomeFirstResponder()
        }

        /// Runs `change` between the input delegate's selection notifications, so
        /// the system menu reads the new range.
        func performSelectionChange(_ change: () -> Void) {
            if #available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *), let proxy = inputProxy {
                proxy.performSelectionChange(change)
            } else {
                change()
            }
        }

        /// The selection menu built from the system's suggested actions, without the
        /// editing commands a read-only label cannot run, then handed to the delegate.
        @available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *)
        func selectionMenu(suggestedActions: [UIMenuElement]) -> UIMenu? {
            let actions = Self.removingEditingCommands(from: suggestedActions)
            if let selectionGroup {
                return selectionGroup.delegate?.textSelectionGroup(
                    selectionGroup,
                    editMenuForSuggestedActions: actions,
                ) ?? UIMenu(children: actions)
            }
            if let range = selectionRange,
               let menu = delegate?.textLabelView(self, editMenuForSelection: range, suggestedActions: actions)
            {
                return menu
            }
            return UIMenu(children: actions)
        }

        /// UIKit hides these on iOS when `canPerformAction` declines them, but Mac
        /// Catalyst only dims them, so they are taken out of the menu itself.
        @available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *)
        private static func removingEditingCommands(from elements: [UIMenuElement]) -> [UIMenuElement] {
            let editingActions: Set<Selector> = [
                #selector(UIResponderStandardEditActions.cut(_:)),
                #selector(UIResponderStandardEditActions.paste(_:)),
                #selector(UIResponderStandardEditActions.delete(_:)),
                #selector(UIResponderStandardEditActions.pasteAndMatchStyle(_:)),
            ]
            return elements.compactMap { element in
                if let command = element as? UICommand, editingActions.contains(command.action) {
                    return nil
                }
                if let menu = element as? UIMenu {
                    let children = removingEditingCommands(from: menu.children)
                    return children.isEmpty ? nil : menu.replacingChildren(children)
                }
                return element
            }
        }
    }

#endif
