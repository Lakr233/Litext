//
//  ContentView.swift
//  OhMyLitext
//
//  Created by Litext Team.
//
//  The demo renders one rich-text document inside a single LTXLabel —
//  the way Litext is meant to be used — instead of scattering features
//  across many small labels.
//

import Litext
import SwiftUI

struct ContentView: View {
    @State private var theme = DocumentTheme()
    @State private var document = ShowcaseDocument.make(theme: DocumentTheme())

    @State private var lastTappedURL = ""
    @State private var lastSelectedText = ""
    @State private var showLinkAlert = false
    @State private var showSettings = false

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                LitextLabel(attributedString: document)
                    .selectable(theme.isSelectable)
                    .selectionBackgroundColor(theme.selectionColor)
                    .onTapLink(recordLinkTap)
                    .onSelectionChange(recordSelection)
                    .accessibilityIdentifier("demo.document")
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
            }
            .navigationTitle("Litext")
            #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    settingsButton
                }
            }
            #endif
            .safeAreaInset(edge: .bottom, spacing: 0) {
                statusBar
            }
        }
        .onChange(of: theme) { newTheme in
            document = ShowcaseDocument.make(theme: newTheme)
        }
        .alert("Link Tapped", isPresented: $showLinkAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lastTappedURL)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 400)
        #endif
    }

    // MARK: - Settings

    #if !os(tvOS)
        @ViewBuilder
        private var settingsButton: some View {
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "textformat.size")
            }
            .accessibilityIdentifier("demo.settings")
            #if os(iOS)
                .popover(isPresented: Binding(
                    get: { showSettings && horizontalSizeClass != .compact },
                    set: { showSettings = $0 }
                )) {
                    settingsPanel
                }
                .sheet(isPresented: Binding(
                    get: { showSettings && horizontalSizeClass == .compact },
                    set: { showSettings = $0 }
                )) {
                    settingsPanel
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                }
            #else
                .popover(isPresented: $showSettings) {
                        settingsPanel
                    }
            #endif
        }

        private var settingsPanel: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Appearance")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Font Size — \(Int(theme.fontSize)) pt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Slider(value: $theme.fontSize, in: 12 ... 28, step: 1)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Line Spacing — \(Int(theme.lineSpacing)) pt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Slider(value: $theme.lineSpacing, in: 0 ... 16, step: 1)
                }

                Picker("Text Color", selection: $theme.textColorIndex) {
                    ForEach(0 ..< DocumentTheme.textColors.count, id: \.self) { index in
                        Text(DocumentTheme.textColors[index].name).tag(index)
                    }
                }

                Picker("Selection Color", selection: $theme.selectionColorIndex) {
                    ForEach(0 ..< DocumentTheme.selectionColors.count, id: \.self) { index in
                        Text(DocumentTheme.selectionColors[index].name).tag(index)
                    }
                }

                Toggle("Selectable", isOn: $theme.isSelectable)

                Button("Reset to Defaults") {
                    theme.reset()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            .frame(minWidth: 300, idealWidth: 320)
        }
    #endif

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            Text(lastTappedURL.isEmpty ? "none" : lastTappedURL)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("state.lastTappedURL")

            Divider()
                .frame(height: 12)

            Image(systemName: "selection.pin.in.out")
                .foregroundStyle(.secondary)
            Text(lastSelectedText.isEmpty ? "none" : lastSelectedText)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityIdentifier("state.selectedText")

            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        #if os(tvOS)
            .background(.regularMaterial)
        #else
            .background(.bar)
        #endif
    }

    // MARK: - Events

    private func recordLinkTap(_ url: URL) {
        lastTappedURL = url.absoluteString
        showLinkAlert = true
    }

    private func recordSelection(_ text: String?) {
        lastSelectedText = text ?? ""
    }
}

#Preview {
    ContentView()
}
