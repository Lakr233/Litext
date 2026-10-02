//
//  CatalogPageID+Content.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Maps every catalog page to its view. Each page is one self-contained view
//  in Pages/<Group>/, named after its CatalogPageID case.
//

import SwiftUI

extension CatalogPageID {
    /// The page's view. Every page exists on every platform the app runs on; a page
    /// that a platform cannot show says so with `CatalogUnavailableView`.
    var content: AnyView {
        switch self {
        case .plainText: AnyView(PlainTextPage())
        case .swiftUILabel: AnyView(SwiftUILabelPage())
        case .labelView: AnyView(LabelViewPage())
        case .markdown: AnyView(MarkdownPage())
        case .fonts: AnyView(FontsPage())
        case .colors: AnyView(ColorsPage())
        case .kerning: AnyView(KerningPage())
        case .paragraphStyle: AnyView(ParagraphStylePage())
        case .decorations: AnyView(DecorationsPage())
        case .shadows: AnyView(ShadowsPage())
        case .baselineOffset: AnyView(BaselineOffsetPage())
        case .lineBreaking: AnyView(LineBreakingPage())
        case .cjk: AnyView(CJKPage())
        case .bidi: AnyView(BidiPage())
        case .emoji: AnyView(EmojiPage())
        case .combiningMarks: AnyView(CombiningMarksPage())
        case .verticalMetrics: AnyView(VerticalMetricsPage())
        case .links: AnyView(LinksPage())
        case .selection: AnyView(SelectionPage())
        case .hitTesting: AnyView(HitTestingPage())
        case .contextMenu: AnyView(ContextMenuPage())
        case .viewAttachments: AnyView(ViewAttachmentsPage())
        case .attachmentDescent: AnyView(AttachmentDescentPage())
        case .inlineControls: AnyView(InlineControlsPage())
        case .swiftUIAttachments: AnyView(SwiftUIAttachmentsPage())
        case .attachmentLifecycle: AnyView(AttachmentLifecyclePage())
        case .sizing: AnyView(SizingPage())
        case .resizableContainer: AnyView(ResizableContainerPage())
        case .geometry: AnyView(GeometryPage())
        case .customLayout: AnyView(CustomLayoutPage())
        case .lineDrawingAction: AnyView(LineDrawingActionPage())
        case .offscreenRendering: AnyView(OffscreenRenderingPage())
        case .selectionTable: AnyView(SelectionTablePage())
        case .showcaseDocument: AnyView(ShowcaseDocumentPage())
        case .layoutTiming: AnyView(LayoutTimingPage())
        case .streaming: AnyView(StreamingPage())
        case .numericTransition: AnyView(NumericTransitionPage())
        case .cellReuse: AnyView(CellReusePage())
        case .animationPolicy: AnyView(AnimationPolicyPage())
        case .animationControl: AnyView(AnimationControlPage())
        case .customAnimator: AnyView(CustomAnimatorPage())
        }
    }
}
