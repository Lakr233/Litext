//
//  PlatformFont+Catalog.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  One way to ask for a system font with a weight, italic and monospacing on
//  UIKit and AppKit, for pages that build attributed strings by hand.
//

import Litext

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

extension PlatformFont {
    /// The system font at `size`, with `weight`, optionally italic and monospaced.
    static func catalogFont(
        ofSize size: CGFloat,
        weight: PlatformFont.Weight = .regular,
        italic: Bool = false,
        monospaced: Bool = false,
    ) -> PlatformFont {
        let base: PlatformFont = monospaced
            ? .monospacedSystemFont(ofSize: size, weight: weight)
            : .systemFont(ofSize: size, weight: weight)
        guard italic else { return base }
        #if canImport(UIKit)
            guard let descriptor = base.fontDescriptor.withSymbolicTraits(.traitItalic) else { return base }
            return PlatformFont(descriptor: descriptor, size: size)
        #else
            let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
            return PlatformFont(descriptor: descriptor, size: size) ?? base
        #endif
    }
}
