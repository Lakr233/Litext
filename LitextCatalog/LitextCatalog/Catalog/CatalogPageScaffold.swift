//
//  CatalogPageScaffold.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  The chrome every page shares: the explanation at the top, the live demo,
//  the controls for the knobs the page is about, and a collapsible snippet of
//  the code behind it.
//

import SwiftUI

/// Lays out a page that scrolls: explanation, demo, controls, then code.
///
/// ```swift
/// CatalogPageScaffold(.kerning, code: Self.code) {
///     TextLabel(attributedString: sample)
/// } controls: {
///     CatalogSlider("Kern", value: $kern, in: -2 ... 8)
/// }
/// ```
///
/// The demo sits in a card as wide as a readable column; pass `demoInsets: 0` for a
/// demo that draws its own edges.
struct CatalogPageScaffold<Demo: View, Controls: View>: View {
    let page: CatalogPageID
    let code: String
    var demoInsets: CGFloat = 16
    @ViewBuilder let demo: Demo
    @ViewBuilder let controls: Controls

    init(
        _ page: CatalogPageID,
        code: String,
        demoInsets: CGFloat = 16,
        @ViewBuilder demo: () -> Demo,
        @ViewBuilder controls: () -> Controls,
    ) {
        self.page = page
        self.code = code
        self.demoInsets = demoInsets
        self.demo = demo()
        self.controls = controls()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CatalogPageHeader(page: page)

                demo
                    .padding(demoInsets)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CatalogStyle.cardBackground, in: RoundedRectangle(cornerRadius: CatalogStyle.cornerRadius))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("catalog.demo")

                if Controls.self != EmptyView.self {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Controls")
                            .font(.headline)
                        controls
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("catalog.controls")
                }

                CodeSnippetView(code: code)
            }
            .frame(maxWidth: CatalogStyle.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .catalogNavigationTitle(page.title)
    }
}

extension CatalogPageScaffold where Controls == EmptyView {
    init(
        _ page: CatalogPageID,
        code: String,
        demoInsets: CGFloat = 16,
        @ViewBuilder demo: () -> Demo,
    ) {
        self.init(page, code: code, demoInsets: demoInsets, demo: demo) {
            EmptyView()
        }
    }
}

/// Lays out a page whose demo fills the screen and scrolls by itself, such as a table:
/// the explanation and the code sit in a collapsible strip above it.
struct CatalogFillScaffold<Content: View>: View {
    let page: CatalogPageID
    let code: String
    @ViewBuilder let content: Content

    @State private var isHeaderExpanded = true

    init(_ page: CatalogPageID, code: String, @ViewBuilder content: () -> Content) {
        self.page = page
        self.code = code
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if isHeaderExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    CatalogPageHeader(page: page)
                    CodeSnippetView(code: code)
                }
                .frame(maxWidth: CatalogStyle.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .catalogNavigationTitle(page.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation { isHeaderExpanded.toggle() }
                } label: {
                    Label(
                        isHeaderExpanded ? "Hide Explanation" : "Show Explanation",
                        systemImage: isHeaderExpanded ? "info.circle.fill" : "info.circle",
                    )
                }
                .accessibilityIdentifier("catalog.toggleHeader")
            }
        }
    }
}

/// The explanation at the top of a page.
struct CatalogPageHeader: View {
    let page: CatalogPageID

    var body: some View {
        Text(page.summary)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("catalog.summary")
    }
}

/// The minimal code behind a page, collapsed until asked for. The text is plain and kept
/// in step with the page by hand.
struct CodeSnippetView: View {
    let code: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .font(.caption.weight(.semibold))
                    Text("Code")
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("catalog.code.toggle")

            if isExpanded {
                ScrollView(.horizontal) {
                    Text(code)
                        .font(.system(.footnote, design: .monospaced))
                    #if !os(tvOS)
                        .textSelection(.enabled)
                    #endif
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CatalogStyle.cardBackground, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("catalog.code")
            }
        }
    }
}

/// Shared measurements and colors.
enum CatalogStyle {
    static let readableWidth: CGFloat = 760
    static let cornerRadius: CGFloat = 14

    static var cardBackground: Color {
        #if os(tvOS)
            Color.gray.opacity(0.15)
        #else
            Color.secondary.opacity(0.08)
        #endif
    }
}

extension View {
    /// Sets the navigation title, shown inline where a large title would crowd the page.
    func catalogNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
        #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
