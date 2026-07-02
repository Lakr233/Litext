//
//  TextLabelMenuItem.swift
//  Litext
//
//  Created by OpenAI Codex.
//

#if canImport(UIKit) && !os(tvOS) && !os(watchOS)

    import UIKit

    enum TextLabelMenuItem: CaseIterable {
        case copy
        case selectAll
        case share

        var action: Selector? {
            switch self {
            case .copy:
                #selector(TextLabelView.copyMenuItemTapped)
            case .selectAll:
                #selector(TextLabelView.selectAllTapped)
            case .share:
                #selector(TextLabelView.shareMenuItemTapped)
            }
        }

        var title: String {
            switch self {
            case .copy:
                LocalizedText.copy
            case .selectAll:
                LocalizedText.selectAll
            case .share:
                LocalizedText.share
            }
        }

        var image: UIImage? {
            switch self {
            case .copy:
                UIImage(systemName: "doc.on.doc")
            case .selectAll:
                UIImage(systemName: "selection.pin.in.out")
            case .share:
                UIImage(systemName: "square.and.arrow.up")
            }
        }

        static func textSelectionMenu() -> [TextLabelMenuItem] {
            allCases
        }
    }

#endif
