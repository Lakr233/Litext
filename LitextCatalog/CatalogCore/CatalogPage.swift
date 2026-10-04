//
//  CatalogPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  The catalog's table of contents: every page, the group it belongs to, and
//  what it shows. The app maps each page to its view in
//  `CatalogPageID+Content.swift`; this file holds only data, so the unit tests
//  compile it as well.
//

import Foundation

/// A section of the catalog's sidebar.
nonisolated enum CatalogGroup: String, CaseIterable, Identifiable, Sendable {
    case basics
    case typography
    case international
    case interaction
    case attachments
    case layout
    case listsAndPerformance
    case animation

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .basics: "Basics"
        case .typography: "Typography"
        case .international: "International"
        case .interaction: "Interaction"
        case .attachments: "Attachments"
        case .layout: "Layout"
        case .listsAndPerformance: "Lists & Performance"
        case .animation: "Animation"
        }
    }

    /// The pages of this group, in sidebar order.
    var pages: [CatalogPageID] {
        CatalogPageID.allCases.filter { $0.group == self }
    }
}

/// One page of the catalog. The raw value is the identifier `-page <id>` takes on the
/// command line, and the cases are listed in sidebar order.
nonisolated enum CatalogPageID: String, CaseIterable, Identifiable, Hashable, Sendable {
    // Basics
    case plainText = "basics.plainText"
    case swiftUILabel = "basics.swiftUI"
    case labelView = "basics.labelView"
    case markdown = "basics.markdown"

    // Typography
    case fonts = "typography.fonts"
    case colors = "typography.colors"
    case kerning = "typography.kerning"
    case paragraphStyle = "typography.paragraph"
    case decorations = "typography.decorations"
    case shadows = "typography.shadows"
    case baselineOffset = "typography.baseline"
    case lineBreaking = "typography.lineBreaking"

    // International
    case cjk = "international.cjk"
    case bidi = "international.bidi"
    case emoji = "international.emoji"
    case combiningMarks = "international.combiningMarks"
    case verticalMetrics = "international.verticalMetrics"

    // Interaction
    case links = "interaction.links"
    case selection = "interaction.selection"
    case hitTesting = "interaction.hitTesting"
    case contextMenu = "interaction.contextMenu"

    // Attachments
    case viewAttachments = "attachments.views"
    case attachmentDescent = "attachments.descent"
    case inlineControls = "attachments.controls"
    case swiftUIAttachments = "attachments.swiftUI"
    case attachmentLifecycle = "attachments.lifecycle"

    // Layout
    case sizing = "layout.sizing"
    case resizableContainer = "layout.resizable"
    case geometry = "layout.geometry"
    case customLayout = "layout.customLayout"
    case lineDrawingAction = "layout.lineDrawing"
    case offscreenRendering = "layout.offscreen"

    // Lists & Performance
    case selectionTable = "lists.table"
    case showcaseDocument = "lists.document"
    case layoutTiming = "lists.timing"

    // Animation
    case streaming = "animation.streaming"
    case numericTransition = "animation.numeric"
    case cellReuse = "animation.reuse"
    case animationPolicy = "animation.policy"
    case animationControl = "animation.control"
    case customAnimator = "animation.customAnimator"

    var id: Self {
        self
    }

    var group: CatalogGroup {
        switch self {
        case .plainText, .swiftUILabel, .labelView, .markdown:
            .basics
        case .fonts, .colors, .kerning, .paragraphStyle, .decorations, .shadows, .baselineOffset, .lineBreaking:
            .typography
        case .cjk, .bidi, .emoji, .combiningMarks, .verticalMetrics:
            .international
        case .links, .selection, .hitTesting, .contextMenu:
            .interaction
        case .viewAttachments, .attachmentDescent, .inlineControls, .swiftUIAttachments, .attachmentLifecycle:
            .attachments
        case .sizing, .resizableContainer, .geometry, .customLayout, .lineDrawingAction, .offscreenRendering:
            .layout
        case .selectionTable, .showcaseDocument, .layoutTiming:
            .listsAndPerformance
        case .streaming, .numericTransition, .cellReuse, .animationPolicy, .animationControl, .customAnimator:
            .animation
        }
    }

    var title: String {
        switch self {
        case .plainText: "Plain Text"
        case .swiftUILabel: "SwiftUI TextLabel"
        case .labelView: "TextLabelView"
        case .markdown: "Markdown"
        case .fonts: "Fonts & Traits"
        case .colors: "Colors"
        case .kerning: "Kerning & Tracking"
        case .paragraphStyle: "Paragraph Style"
        case .decorations: "Underline & Strikethrough"
        case .shadows: "Shadows"
        case .baselineOffset: "Baseline Offset"
        case .lineBreaking: "Line Breaking"
        case .cjk: "Chinese, Japanese & Korean"
        case .bidi: "Right-to-Left & Bidi"
        case .emoji: "Emoji"
        case .combiningMarks: "Combining Marks"
        case .verticalMetrics: "Vertical Metrics"
        case .links: "Links"
        case .selection: "Selection"
        case .hitTesting: "Hit Testing"
        case .contextMenu: "Context Menu"
        case .viewAttachments: "View Attachments"
        case .attachmentDescent: "Attachment Descent"
        case .inlineControls: "Inline Controls"
        case .swiftUIAttachments: "SwiftUI Attachments"
        case .attachmentLifecycle: "Attachment Lifecycle"
        case .sizing: "Sizing"
        case .resizableContainer: "Resizable Container"
        case .geometry: "Line & Run Geometry"
        case .customLayout: "Custom Layout"
        case .lineDrawingAction: "Line Drawing Action"
        case .offscreenRendering: "Offscreen Rendering"
        case .selectionTable: "Selection Across Cells"
        case .showcaseDocument: "Showcase Document"
        case .layoutTiming: "Layout Timing"
        case .streaming: "Streaming Text"
        case .numericTransition: "Numeric Transition"
        case .cellReuse: "Cell Reuse"
        case .animationPolicy: "Animation Policy"
        case .animationControl: "Animation Control"
        case .customAnimator: "Custom Animator"
        }
    }

    /// One or two sentences on what the page shows, used as its header and in the
    /// sidebar's accessibility hint.
    var summary: String {
        switch self {
        case .plainText:
            "A string with a font and a color, measured and drawn by CoreText alone."
        case .swiftUILabel:
            "TextLabel, the SwiftUI view, with its modifiers for selection, links, attachments and the selection color."
        case .labelView:
            "TextLabelView, the UIKit and AppKit view, set up in code and hosted here through a representable."
        case .markdown:
            "Foundation parses Markdown into an AttributedString; TextLabel shows the result once its runs carry fonts."
        case .fonts:
            "System and custom fonts, weights, italic and bold traits, monospaced digits and text styles."
        case .colors:
            "Foreground colors, dynamic system colors that follow dark mode, and colors per run."
        case .kerning:
            "The kern attribute tightens or loosens the spacing between characters."
        case .paragraphStyle:
            "Alignment, line spacing, line height multiple, minimum and maximum line height, indents and paragraph spacing."
        case .decorations:
            "Underline and strikethrough styles, patterns and colors, drawn by CoreText."
        case .shadows:
            "Text shadows with an offset, a blur radius and a color."
        case .baselineOffset:
            "Raising and lowering runs off the baseline, for superscripts, subscripts and footnote marks."
        case .lineBreaking:
            "How lines break: by word or by character, hyphenation, and long unbreakable words."
        case .cjk:
            "Chinese, Japanese and Korean text, mixed with Latin, with line breaking that follows each script's rules."
        case .bidi:
            "Arabic and Hebrew laid out right to left, and mixed with left-to-right text and numbers in one line."
        case .emoji:
            "ZWJ sequences, flags, skin tones and keycaps, each selected and hit-tested as one character."
        case .combiningMarks:
            "Combining accents, stacked diacritics, Thai and Devanagari marks, kept with their base characters."
        case .verticalMetrics:
            "Scripts and fonts with tall ascenders and deep descenders, and how the label sizes lines around them."
        case .links:
            "Links in an attributed string: tap or click handlers, the highlight color and its corner radius."
        case .selection:
            "Selecting text with touch, mouse and keyboard; selecting a word, a line or everything in code; copying."
        case .hitTesting:
            "Finding the character and the link or attachment under a point, as the pointer moves or a finger taps."
        case .contextMenu:
            "The menu a selection shows, and the delegate hooks that replace or extend it."
        case .viewAttachments:
            "Views of any size placed inline, flowing with the text and wrapping with it."
        case .attachmentDescent:
            "An attachment's descent decides how far it hangs below the baseline."
        case .inlineControls:
            "Buttons, switches and other live controls inside a line of text."
        case .swiftUIAttachments:
            "SwiftUI views hosted inline as attachments."
        case .attachmentLifecycle:
            "When attachment views are added, reused and released as the text changes."
        case .sizing:
            "sizeThatFits, intrinsicContentSize and preferredMaxLayoutWidth, and how they agree."
        case .resizableContainer:
            "Text reflowing as its container narrows and widens."
        case .geometry:
            "Line rects, baselines and run rects from the layout, drawn over the text."
        case .customLayout:
            "A TextLabel.Layout subclass returned from makeTextLayout, overriding draw(line:at:in:)."
        case .lineDrawingAction:
            "A LineDrawingAction attribute draws extra content along every line its range touches."
        case .offscreenRendering:
            "TextLabel.Layout used without a view: measured and drawn into a bitmap context."
        case .selectionTable:
            "Cells that share one TextSelectionGroup, so a selection runs from one cell into the next."
        case .showcaseDocument:
            "One rich document in one label: styles, links, attachments, bidi text and custom drawing together."
        case .layoutTiming:
            "How long measuring, laying out and drawing take as the text grows."
        case .streaming:
            "Simulated model output that fades in as it arrives, with LTXFadeInAnimator or LTXFadeUpAnimator."
        case .numericTransition:
            "A title and a counter that roll from one value to the next, with LTXNumericTransitionAnimator."
        case .cellReuse:
            "Reused cells show their text at once while one row keeps streaming."
        case .animationPolicy:
            "Which changes animate: the default policy, a closure policy, and reduced motion."
        case .animationControl:
            "finishAnimations(), isAnimating, setAttributedText(_:animated:) and the frame rate range."
        case .customAnimator:
            "A minimal LTXTextAnimator written from scratch, to show the protocol's moving parts."
        }
    }

    /// An SF Symbol for the sidebar.
    var systemImage: String {
        switch self {
        case .plainText: "textformat"
        case .swiftUILabel: "swift"
        case .labelView: "rectangle.and.text.magnifyingglass"
        case .markdown: "number"
        case .fonts: "textformat.size"
        case .colors: "paintpalette"
        case .kerning: "arrow.left.and.right.text.vertical"
        case .paragraphStyle: "text.alignleft"
        case .decorations: "underline"
        case .shadows: "shadow"
        case .baselineOffset: "textformat.superscript"
        case .lineBreaking: "text.word.spacing"
        case .cjk: "character.textbox"
        case .bidi: "character.bubble"
        case .emoji: "face.smiling"
        case .combiningMarks: "textformat.characters"
        case .verticalMetrics: "arrow.up.and.down.text.horizontal"
        case .links: "link"
        case .selection: "selection.pin.in.out"
        case .hitTesting: "hand.point.up.left"
        case .contextMenu: "contextualmenu.and.cursorarrow"
        case .viewAttachments: "photo"
        case .attachmentDescent: "arrow.down.to.line"
        case .inlineControls: "switch.2"
        case .swiftUIAttachments: "square.on.square"
        case .attachmentLifecycle: "arrow.triangle.2.circlepath"
        case .sizing: "arrow.up.left.and.arrow.down.right"
        case .resizableContainer: "rectangle.expand.vertical"
        case .geometry: "ruler"
        case .customLayout: "square.3.layers.3d"
        case .lineDrawingAction: "scribble"
        case .offscreenRendering: "photo.on.rectangle"
        case .selectionTable: "tablecells"
        case .showcaseDocument: "doc.richtext"
        case .layoutTiming: "stopwatch"
        case .streaming: "text.bubble"
        case .numericTransition: "textformat.123"
        case .cellReuse: "list.bullet.rectangle"
        case .animationPolicy: "checklist"
        case .animationControl: "slider.horizontal.3"
        case .customAnimator: "wand.and.stars"
        }
    }
}
