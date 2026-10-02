//
//  CatalogControls.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Controls the pages share, so every page offers its knobs the same way on
//  every platform. tvOS has no Slider, so CatalogSlider steps there instead.
//

import SwiftUI

/// A labeled slider that shows its value, or a pair of step buttons on tvOS.
struct CatalogSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var format: (Double) -> String

    init(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double? = nil,
        format: @escaping (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0 ... 2))) },
    ) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            #if os(tvOS)
                HStack {
                    Button("−") { nudge(by: -1) }
                    Button("+") { nudge(by: 1) }
                }
            #else
                if let step {
                    Slider(value: $value, in: range, step: step)
                        .accessibilityLabel(title)
                } else {
                    Slider(value: $value, in: range)
                        .accessibilityLabel(title)
                }
            #endif
        }
    }

    #if os(tvOS)
        private func nudge(by direction: Double) {
            let increment = step ?? (range.upperBound - range.lowerBound) / 20
            value = min(max(value + direction * increment, range.lowerBound), range.upperBound)
        }
    #endif
}

/// A picker over a fixed set of choices, segmented where the platform has segments.
struct CatalogPicker<Option: Hashable>: View {
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
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(label(option)).tag(option)
            }
        }
        #if os(tvOS) || os(watchOS)
        .pickerStyle(.automatic)
        #else
        .pickerStyle(.segmented)
        #endif
    }
}

/// A label and a value that changes as the demo runs, such as a selection range or a
/// measured size. The value is monospaced so it does not jitter as it updates.
struct CatalogReadout: View {
    let title: String
    let value: String
    var identifier: String?

    init(_ title: String, value: String, identifier: String? = nil) {
        self.title = title
        self.value = value
        self.identifier = identifier
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.callout.monospaced())
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .truncationMode(.middle)
                .accessibilityIdentifier(identifier ?? "readout.\(title)")
        }
        .font(.callout)
    }
}

/// A short note under a demo, for a caveat or a hint on what to try.
struct CatalogNote: View {
    let text: String
    var systemImage = "lightbulb"

    init(_ text: String, systemImage: String = "lightbulb") {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// Stands in for a page that this platform cannot show.
struct CatalogUnavailableView: View {
    let page: CatalogPageID
    let reason: String

    var body: some View {
        ContentUnavailableView {
            Label(page.title, systemImage: page.systemImage)
        } description: {
            Text(reason)
        }
        .catalogNavigationTitle(page.title)
    }
}

/// Stands in for a page that is still being written.
struct CatalogPlaceholderView: View {
    let page: CatalogPageID

    var body: some View {
        CatalogPageScaffold(page, code: "// Coming soon.") {
            Label("This page is not written yet.", systemImage: "hammer")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }
}
