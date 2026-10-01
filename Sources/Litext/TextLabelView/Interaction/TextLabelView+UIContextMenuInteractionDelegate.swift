//
//  TextLabelView+UIContextMenuInteractionDelegate.swift
//  Litext
//
//  Created by 秋星桥 on 7/8/25.
//

#if canImport(UIKit) && !os(tvOS) && !os(watchOS)

    import UIKit

    extension TextLabelView: UIContextMenuInteractionDelegate {
        public func contextMenuInteraction(
            _: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint,
        ) -> UIContextMenuConfiguration? {
            #if targetEnvironment(macCatalyst)
                // From Mac Catalyst 16 the input proxy over the label opens the system
                // text menu instead.
                if #available(macCatalyst 16.0, *) {
                    return nil
                }
                guard hasCommandSelection else { return nil }
                let menuItems: [UIMenuElement] = makeSelectionMenuActions()
                return .init(
                    identifier: nil,
                    previewProvider: nil,
                ) { _ in
                    .init(children: menuItems)
                }
            #else
                DispatchQueue.main.async {
                    guard self.isSelectable else { return }
                    guard self.selectionContains(location) else { return }
                    self.showSelectionMenuController()
                }
                return nil
            #endif
        }
    }

#endif
