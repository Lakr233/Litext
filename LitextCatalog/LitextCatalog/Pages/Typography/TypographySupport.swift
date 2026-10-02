//
//  TypographySupport.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Small pieces the Typography pages share: a palette of colors to pick from,
//  fonts by system design, a measurement through TextLabel.Layout, and a menu
//  picker for long lists of choices.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// The colors the Typography pages offer in their pickers. A fixed palette works on
/// every platform, including tvOS, which has no color picker.
enum TypographySwatch: String, CaseIterable, Identifiable {
    case label
    case blue
    case pink
    case green
    case orange
    case purple

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .label: "Label"
        case .blue: "Blue"
        case .pink: "Pink"
        case .green: "Green"
        case .orange: "Orange"
        case .purple: "Purple"
        }
    }

    /// A dynamic system color, so it follows light and dark mode.
    var color: PlatformColor {
        switch self {
        case .label: .label
        case .blue: .systemBlue
        case .pink: .systemPink
        case .green: .systemGreen
        case .orange: .systemOrange
        case .purple: .systemPurple
        }
    }

    /// The name to show in a code snippet.
    var codeName: String {
        switch self {
        case .label: ".label"
        case .blue: ".systemBlue"
        case .pink: ".systemPink"
        case .green: ".systemGreen"
        case .orange: ".systemOrange"
        case .purple: ".systemPurple"
        }
    }
}

/// The system font designs a font descriptor can ask for.
enum TypographyDesign: String, CaseIterable, Identifiable {
    case standard
    case serif
    case rounded
    case monospaced

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .standard: "Default"
        case .serif: "Serif"
        case .rounded: "Rounded"
        case .monospaced: "Mono"
        }
    }

    #if canImport(UIKit)
        var systemDesign: UIFontDescriptor.SystemDesign {
            switch self {
            case .standard: .default
            case .serif: .serif
            case .rounded: .rounded
            case .monospaced: .monospaced
            }
        }
    #else
        var systemDesign: NSFontDescriptor.SystemDesign {
            switch self {
            case .standard: .default
            case .serif: .serif
            case .rounded: .rounded
            case .monospaced: .monospaced
            }
        }
    #endif
}

extension PlatformFont {
    /// The system font at `size` and `weight` in `design`, with the italic and bold
    /// symbolic traits added on request. A trait or design the font has no face for
    /// falls back to the font without it.
    static func typographyFont(
        ofSize size: CGFloat,
        weight: PlatformFont.Weight = .regular,
        design: TypographyDesign = .standard,
        italic: Bool = false,
        bold: Bool = false,
    ) -> PlatformFont {
        let base = PlatformFont.systemFont(ofSize: size, weight: weight)
        var descriptor = base.fontDescriptor
        if let designed = descriptor.withDesign(design.systemDesign) {
            descriptor = designed
        }
        #if canImport(UIKit)
            var traits = descriptor.symbolicTraits
            if italic {
                traits.insert(.traitItalic)
            }
            if bold {
                traits.insert(.traitBold)
            }
            if let traited = descriptor.withSymbolicTraits(traits) {
                descriptor = traited
            }
            return PlatformFont(descriptor: descriptor, size: size)
        #else
            var traits = descriptor.symbolicTraits
            if italic {
                traits.insert(.italic)
            }
            if bold {
                traits.insert(.bold)
            }
            descriptor = descriptor.withSymbolicTraits(traits)
            return PlatformFont(descriptor: descriptor, size: size) ?? base
        #endif
    }

    /// The height of one line set in this font: ascent, descent and leading.
    var typographyLineHeight: CGFloat {
        let font = self as CTFont
        return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }
}

enum TypographyMeasure {
    /// The size `text` needs at `width`, as TextLabel measures it; an unbounded width
    /// gives the natural single-paragraph width.
    static func size(of text: NSAttributedString, width: CGFloat = .greatestFiniteMagnitude) -> CGSize {
        let layout = TextLabel.Layout(attributedString: text)
        return layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    /// The number of lines `text` takes at `width`.
    static func lineCount(of text: NSAttributedString, width: CGFloat) -> Int {
        let layout = TextLabel.Layout(attributedString: text)
        let size = layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        layout.containerSize = CGSize(width: width, height: size.height)
        return layout.layoutLines.count
    }

    /// `value` as points, for a readout.
    static func points(_ value: CGFloat) -> String {
        points(Double(value))
    }

    /// `value` as points, for a slider.
    static func points(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " pt"
    }
}

/// A menu picker with its title beside it, for choices too many or too long for
/// segments. SwiftUI hides a picker's title outside a Form on iOS, so the title is
/// drawn here and the picker's own is hidden. Short choices use `CatalogPicker`.
struct TypographyMenuPicker<Option: Hashable>: View {
    let title: String
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String

    init(
        _ title: String,
        selection: Binding<Option>,
        options: [Option],
        label: @escaping (Option) -> String,
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}
