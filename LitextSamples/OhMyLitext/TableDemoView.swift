//
//  TableDemoView.swift
//  OhMyLitext
//
//  Created by Litext Team.
//
//  A table whose cells are separate labels that share one selection through
//  TextSelectionGroup: a selection can run from one cell into the next, and
//  Copy, Look Up, Translate and Share act on all of it. The menu gains a
//  Copy as Markdown command, and a sheet shows that the menu never opens over
//  a controller that covers the table.
//

import Litext
import SwiftUI

struct TableDemoView: View {
    @State private var selectedText = ""
    @State private var showSheet = false

    private static let rows: [[String]] = [
        ["Feature", "Status", "Comment"],
        ["Bold", "✅", "N/A"],
        ["Italic", "✅", "---"],
        ["Code", "✅", "1145141919810"],
        ["Cross-cell selection", "✅", "Drag from one cell into another, or move a handle across cells."],
        ["Covered menu", "✅", "Open the sheet: the table's menu never shows over it."],
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Every cell is its own TextLabelView. The cells share one TextSelectionGroup, listed row by row, so a selection runs across cells in reading order. Copied text puts a tab between cells and a line break between rows.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                SelectableTable(rows: Self.rows, onSelectionChange: { selectedText = $0 ?? "" })
                    .accessibilityIdentifier("demo.table")

                #if !os(tvOS)
                    Button("Open a Sheet over the Table") {
                        showSheet = true
                    }
                    .buttonStyle(.bordered)
                #endif
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .navigationTitle("Table Selection")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "selection.pin.in.out")
                    .foregroundStyle(.secondary)
                Text(selectedText.isEmpty ? "none" : selectedText.replacingOccurrences(of: "\t", with: " → "))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("state.tableSelection")
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
        #if !os(tvOS)
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                ScrollView {
                    SelectableTable(rows: Self.rows, onSelectionChange: { _ in })
                        .padding(20)
                }
                .navigationTitle("Sheet")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showSheet = false }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 360)
            #endif
        }
        #endif
    }
}

// MARK: - Table

private struct SelectableTable {
    let rows: [[String]]
    let onSelectionChange: (String?) -> Void

    func makeView() -> TableGridView {
        let view = TableGridView(rows: rows)
        view.onSelectionChange = onSelectionChange
        return view
    }

    func update(_ view: TableGridView) {
        view.onSelectionChange = onSelectionChange
    }

    func size(for proposal: ProposedViewSize, view: TableGridView) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: view.height(forWidth: width))
    }
}

#if canImport(UIKit)
    extension SelectableTable: UIViewRepresentable {
        func makeUIView(context _: Context) -> TableGridView {
            makeView()
        }

        func updateUIView(_ uiView: TableGridView, context _: Context) {
            update(uiView)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, uiView: TableGridView, context _: Context) -> CGSize? {
            size(for: proposal, view: uiView)
        }
    }
#else
    extension SelectableTable: NSViewRepresentable {
        func makeNSView(context _: Context) -> TableGridView {
            makeView()
        }

        func updateNSView(_ nsView: TableGridView, context _: Context) {
            update(nsView)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView: TableGridView, context _: Context) -> CGSize? {
            size(for: proposal, view: nsView)
        }
    }
#endif

/// A bordered grid of labels, one per cell, in one selection group.
final class TableGridView: PlatformView, TextSelectionGroupDelegate {
    private let rows: [[String]]
    private let cells: [[TextLabelView]]
    private let group = TextSelectionGroup()
    /// The row and column of each cell.
    private var cellPositions: [ObjectIdentifier: (row: Int, column: Int)] = [:]
    private let gridLayer = CAShapeLayer()
    private let headerLayer = CAShapeLayer()
    private let padding: CGFloat = 12
    private let cornerRadius: CGFloat = 10

    var onSelectionChange: ((String?) -> Void)?

    init(rows: [[String]]) {
        self.rows = rows
        cells = rows.enumerated().map { rowIndex, row in
            row.map { text in
                let label = TextLabelView(attributedText: NSAttributedString(
                    string: text,
                    attributes: [
                        .font: rowIndex == 0
                            ? PlatformFont.boldSystemFont(ofSize: 16)
                            : PlatformFont.systemFont(ofSize: 16),
                        .foregroundColor: PlatformColor.label,
                    ],
                ))
                label.isSelectable = true
                return label
            }
        }
        super.init(frame: .zero)
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
            wantsLayer = true
        #else
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
                self.updateColors()
            }
        #endif
        platformLayer.addSublayer(headerLayer)
        platformLayer.addSublayer(gridLayer)
        for (rowIndex, row) in cells.enumerated() {
            for (columnIndex, label) in row.enumerated() {
                cellPositions[ObjectIdentifier(label)] = (rowIndex, columnIndex)
                addSubview(label)
            }
        }
        // Row by row: the reading order of the table.
        group.labels = cells.flatMap(\.self)
        group.separator = { [weak self] previous, next in
            guard let self,
                  let lhs = cellPositions[ObjectIdentifier(previous)],
                  let rhs = cellPositions[ObjectIdentifier(next)]
            else { return "\n" }
            return lhs.row == rhs.row ? "\t" : "\n"
        }
        group.delegate = self
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private var platformLayer: CALayer {
        #if canImport(UIKit)
            layer
        #else
            layer!
        #endif
    }

    // MARK: Layout

    private var columnCount: Int {
        rows.map(\.count).max() ?? 0
    }

    private func columnWidth(forWidth width: CGFloat) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        return (width / CGFloat(columnCount)).rounded(.down)
    }

    /// The height of each row at `width`.
    private func rowHeights(forWidth width: CGFloat) -> [CGFloat] {
        let textWidth = max(columnWidth(forWidth: width) - padding * 2, 1)
        return cells.map { row in
            let tallest = row.map { label in
                label.preferredMaxLayoutWidth = textWidth
                return label.intrinsicContentSize.height
            }.max() ?? 0
            return (tallest + padding * 2).rounded(.up)
        }
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        rowHeights(forWidth: width).reduce(0, +)
    }

    #if canImport(UIKit)
        override func layoutSubviews() {
            super.layoutSubviews()
            layoutGrid()
        }
    #else
        override var isFlipped: Bool {
            true
        }

        override func layout() {
            super.layout()
            layoutGrid()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateColors()
        }
    #endif

    private func layoutGrid() {
        let width = bounds.width
        let column = columnWidth(forWidth: width)
        let heights = rowHeights(forWidth: width)
        let textWidth = max(column - padding * 2, 1)
        var y: CGFloat = 0
        let lines = CGMutablePath()
        for (rowIndex, row) in cells.enumerated() {
            for (columnIndex, label) in row.enumerated() {
                let x = CGFloat(columnIndex) * column
                label.frame = CGRect(
                    x: x + padding,
                    y: y + padding,
                    width: textWidth,
                    height: heights[rowIndex] - padding * 2,
                )
            }
            y += heights[rowIndex]
            if rowIndex < cells.count - 1 {
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: width, y: y))
            }
        }
        for columnIndex in 1 ..< max(columnCount, 1) {
            let x = CGFloat(columnIndex) * column
            lines.move(to: CGPoint(x: x, y: 0))
            lines.addLine(to: CGPoint(x: x, y: y))
        }
        let outline = CGPath(
            roundedRect: CGRect(x: 0.5, y: 0.5, width: max(width - 1, 0), height: max(y - 1, 0)),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil,
        )
        lines.addPath(outline)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gridLayer.frame = bounds
        gridLayer.path = lines
        gridLayer.fillColor = nil
        gridLayer.lineWidth = 1
        headerLayer.frame = bounds
        let header = CGMutablePath()
        header.addRect(CGRect(x: 0, y: 0, width: width, height: heights.first ?? 0))
        let mask = CAShapeLayer()
        mask.path = outline
        headerLayer.path = header
        headerLayer.mask = mask
        CATransaction.commit()
    }

    private func updateColors() {
        #if canImport(UIKit)
            let separator = PlatformColor.separator.resolvedColor(with: traitCollection)
            #if os(tvOS)
                let header = PlatformColor.systemGray.withAlphaComponent(0.2)
            #else
                let header = PlatformColor.secondarySystemFill.resolvedColor(with: traitCollection)
            #endif
        #else
            var separator = NSColor.separatorColor
            var header = NSColor.quaternaryLabelColor
            effectiveAppearance.performAsCurrentDrawingAppearance {
                separator = NSColor(cgColor: NSColor.separatorColor.cgColor) ?? separator
                header = NSColor(cgColor: NSColor.quaternaryLabelColor.cgColor) ?? header
            }
        #endif
        gridLayer.strokeColor = separator.cgColor
        headerLayer.fillColor = header.cgColor
    }

    // MARK: Selection group

    func textSelectionGroupDidChangeSelection(_ group: TextSelectionGroup) {
        onSelectionChange?(group.selectedPlainText())
    }

    /// The selection as a Markdown table: one row per selected table row, padded
    /// to the selected columns, with a delimiter row after the first.
    private func selectionAsMarkdown() -> String {
        var cellsByRow: [Int: [Int: String]] = [:]
        for segment in group.selectedSegments {
            guard let position = cellPositions[ObjectIdentifier(segment.label)] else { continue }
            let text = (segment.label.attributedText.string as NSString).substring(with: segment.range)
            cellsByRow[position.row, default: [:]][position.column] = text
                .replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\n", with: " ")
        }
        let columns = cellsByRow.values.flatMap(\.keys)
        guard let first = columns.min(), let last = columns.max() else { return "" }
        var lines = cellsByRow.keys.sorted().map { row in
            "| " + (first ... last).map { cellsByRow[row]?[$0] ?? "" }.joined(separator: " | ") + " |"
        }
        lines.insert("|" + String(repeating: " --- |", count: last - first + 1), at: min(1, lines.count))
        return lines.joined(separator: "\n")
    }

    #if os(iOS) || os(visionOS)
        func textSelectionGroup(
            _: TextSelectionGroup,
            editMenuForSuggestedActions suggestedActions: [UIMenuElement],
        ) -> UIMenu? {
            let copyMarkdown = UIAction(
                title: "Copy as Markdown",
                image: UIImage(systemName: "tablecells"),
            ) { [weak self] _ in
                guard let self else { return }
                UIPasteboard.general.string = selectionAsMarkdown()
            }
            return UIMenu(children: suggestedActions + [copyMarkdown])
        }

    #elseif os(macOS)
        func textSelectionGroup(_: TextSelectionGroup, menu: NSMenu, event _: NSEvent) -> NSMenu? {
            let item = NSMenuItem(title: "Copy as Markdown", action: #selector(copyMarkdown(_:)), keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
            return menu
        }

        @objc private func copyMarkdown(_: Any?) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selectionAsMarkdown(), forType: .string)
        }
    #endif
}
