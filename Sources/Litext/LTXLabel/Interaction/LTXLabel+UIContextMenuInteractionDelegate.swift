//
//  LTXLabel+UIContextMenuInteractionDelegate.swift
//  MarkdownView
//
//  Created by 秋星桥 on 7/8/25.
//

#if canImport(UIKit) && !os(tvOS) && !os(watchOS)

    import UIKit

    extension LTXLabel: UIContextMenuInteractionDelegate {
        public func contextMenuInteraction(
            _: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            #if targetEnvironment(macCatalyst)
                guard selectionRange != nil else { return nil }
                let menuItems: [UIMenuElement] = LTXLabelMenuItem
                    .textSelectionMenu()
                    .compactMap { item -> UIAction? in
                        guard let selector = item.action else { return nil }
                        guard self.canPerformAction(selector, withSender: nil) else { return nil }
                        return UIAction(title: item.title, image: item.image) { _ in
                            self.perform(selector)
                        }
                    }
                return .init(
                    identifier: nil,
                    previewProvider: nil
                ) { _ in
                    .init(children: menuItems)
                }
            #else
                DispatchQueue.main.async {
                    guard self.isSelectable else { return }
                    guard self.isLocationInSelection(location: location) else { return }
                    self.showSelectionMenuController()
                }
                return nil
            #endif
        }
    }

#endif
