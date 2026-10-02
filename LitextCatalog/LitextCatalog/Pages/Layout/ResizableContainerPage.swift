//
//  ResizableContainerPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  A SwiftUI TextLabel in a container you can narrow and widen: the text
//  reflows on every change, and the readouts show the measured height and the
//  number of lines at each width.
//

import Litext
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct ResizableContainerPage: View {
    private static let code = """
    // TextLabel takes the width it is offered and asks for the height
    // the text needs there, so a frame is all it takes.
    TextLabel(attributedString: text)
        .frame(width: width)

    // The same measurement without a view, with the line count.
    let layout = TextLabel.Layout(attributedString: text)
    layout.containerSize = CGSize(width: width, height: 0) // 0: unconstrained
    let lines = layout.layoutLines.count
    let height = layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
    """

    private static let minimumWidth = 40.0
    private static let handleWidth = 16.0

    @State private var fraction = 0.6
    @State private var availableWidth = 0.0
    @State private var measuredHeight = 0.0
    @State private var dragStartFraction: Double?
    @State private var layout = TextLabel.Layout(attributedString: ResizableContainerPage.text)

    private var span: Double {
        max(availableWidth - Self.handleWidth - Self.minimumWidth, 1)
    }

    private var width: Double {
        (Self.minimumWidth + span * fraction).rounded()
    }

    var body: some View {
        CatalogPageScaffold(.resizableContainer, code: Self.code) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: 0)
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: Double.self) { $0.size.width } action: { availableWidth = $0 }
                HStack(alignment: .top, spacing: 0) {
                    TextLabel(attributedString: Self.text)
                        .frame(width: width, alignment: .leading)
                        .onGeometryChange(for: Double.self) { $0.size.height } action: { measuredHeight = $0 }
                        .background(Color.accentColor.opacity(0.08))
                        .accessibilityIdentifier("demo.resizable.label")
                    handle
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } controls: {
            CatalogSlider("Width", value: $fraction, in: 0 ... 1) { _ in "\(Int(width)) pt" }
            CatalogReadout("Container width", value: "\(Int(width)) pt", identifier: "state.resizable.width")
            CatalogReadout(
                "Measured height",
                value: measuredHeight.formatted(.number.precision(.fractionLength(0 ... 1))) + " pt",
                identifier: "state.resizable.height",
            )
            CatalogReadout("Lines", value: "\(lineCount)", identifier: "state.resizable.lines")
            #if !os(tvOS)
                CatalogNote("Drag the handle at the right edge of the text, or use the slider.")
            #endif
        }
    }

    private var lineCount: Int {
        layout.containerSize = CGSize(width: width, height: 0)
        return layout.layoutLines.count
    }

    @ViewBuilder private var handle: some View {
        let grip = RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor)
            .frame(width: 6, height: 44)
            .frame(width: Self.handleWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .accessibilityLabel("Container width")
            .accessibilityValue("\(Int(width)) points")
        #if os(tvOS)
            grip
        #else
            grip
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let start = dragStartFraction ?? fraction
                            dragStartFraction = start
                            fraction = min(max(start + value.translation.width / span, 0), 1)
                        }
                        .onEnded { _ in dragStartFraction = nil },
                )
            #if os(macOS)
                .onHover { inside in
                    if inside {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            #endif
        #endif
    }

    static let text: NSAttributedString = {
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 17),
            .foregroundColor: PlatformColor.label,
        ]
        let text = NSMutableAttributedString(
            string: "Text reflows as its container changes width. Words wrap at spaces, ",
            attributes: body,
        )
        text.append(NSAttributedString(
            string: "汉字和日本語のテキストは文字ごとに折り返し、",
            attributes: body,
        ))
        text.append(NSAttributedString(
            string: " and a very long word such as Donaudampfschifffahrtsgesellschaft breaks inside itself only when a line has no other place to break.",
            attributes: body,
        ))
        return text
    }()
}
