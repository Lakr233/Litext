//
//  PlatformColor+Catalog.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  UIKit's semantic color names on AppKit, so pages can build attributed
//  strings with `PlatformColor.label` and friends on every platform.
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    import AppKit

    extension NSColor {
        static var label: NSColor {
            .labelColor
        }

        static var link: NSColor {
            .linkColor
        }

        static var secondaryLabel: NSColor {
            .secondaryLabelColor
        }

        static var tertiaryLabel: NSColor {
            .tertiaryLabelColor
        }

        static var separator: NSColor {
            .separatorColor
        }
    }
#endif
