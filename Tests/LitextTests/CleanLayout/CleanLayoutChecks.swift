//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreText
import Foundation
@testable import Litext
import Testing

// MARK: - Tolerances and widths

enum CleanLayout {
    /// Marks every character, so `layoutRuns(matching:)` returns every run of every line.
    static let probeKey = NSAttributedString.Key("LitextCleanLayoutProbe")

    /// One device pixel at @2x, the coarsest scale the containment checks allow.
    static let pixel: CGFloat = 0.5
    /// Floating point noise between two computations of the same edge.
    static let epsilon: CGFloat = 0.01
    /// CoreText advances from one baseline to the next by rounded metrics, so two
    /// adjacent lines set in different fonts (a heading run, a fallback font for
    /// Hebrew or Arabic, a tall attachment) may overlap by a fraction of a point.
    static let lineOverlapTolerance: CGFloat = pixel
    /// CoreText places the first baseline by the ascent of the requested font. A
    /// first line drawn entirely in a fallback font with a smaller ascent (a lone
    /// Hebrew letter in a system-font string) starts that much below the top.
    static let fallbackFontTolerance: CGFloat = 1
    /// Alignment is checked within one point.
    static let alignmentTolerance: CGFloat = 1
    /// The scale used to pixel-ceil a measured size into a container.
    static let containerScale: CGFloat = 2

    static let widths: [CGFloat] = [1, 20, 57.3, 120, 320, 1000, .greatestFiniteMagnitude]

    static func isUnconstrained(_ width: CGFloat) -> Bool {
        width >= 1e12
    }

    static func proposal(_ width: CGFloat) -> CGSize {
        CGSize(width: width, height: .greatestFiniteMagnitude)
    }

    static func pixelCeil(_ value: CGFloat, scale: CGFloat = containerScale) -> CGFloat {
        ceil(value * scale) / scale
    }

    static func probed(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        result.addAttribute(probeKey, value: true, range: NSRange(location: 0, length: result.length))
        return result
    }
}

// MARK: - Prepared layouts

/// A layout measured at a proposed width and laid out in the size it reported.
@MainActor
struct PreparedLayout {
    let layout: TextLabel.Layout
    let width: CGFloat
    let measured: CGSize
    /// The measured width exceeds the proposal. That is only clean when a single
    /// unbreakable cluster cannot fit (see `assertCleanLayout`); the container then
    /// keeps the proposed width so the layout reproduces the measured line breaks.
    let overflows: Bool

    init(_ text: NSAttributedString, width: CGFloat) {
        layout = TextLabel.Layout(attributedString: CleanLayout.probed(text))
        self.width = width
        measured = layout.sizeThatFits(CleanLayout.proposal(width))
        overflows = !CleanLayout.isUnconstrained(width) && measured.width > width + CleanLayout.epsilon
        layout.containerSize = CGSize(
            width: overflows ? width : CleanLayout.pixelCeil(measured.width),
            height: CleanLayout.pixelCeil(measured.height),
        )
        layout.updateHighlightRegions()
    }
}

// MARK: - Line model

/// One laid-out line, rebuilt from the public `layoutRuns(matching:)` output.
struct CleanLayoutLine: Equatable {
    var index: Int
    var range: NSRange
    /// `LayoutRun.lineRect`: the typographic box, without the leading below it.
    var lineRect: CGRect
}

@MainActor
func cleanLayoutLines(_ layout: TextLabel.Layout, log: CleanLayoutLog) -> [CleanLayoutLine] {
    let runs = layout.layoutRuns(matching: CleanLayout.probeKey)
    var lines = [CleanLayoutLine]()
    for run in runs {
        if let last = lines.last, last.index == run.lineIndex {
            log.check(last.lineRect == run.lineRect, "line \(run.lineIndex): runs disagree on the line rect")
            let start = min(last.range.location, run.stringRange.location)
            let end = max(NSMaxRange(last.range), NSMaxRange(run.stringRange))
            lines[lines.count - 1].range = NSRange(location: start, length: end - start)
        } else {
            lines.append(CleanLayoutLine(index: run.lineIndex, range: run.stringRange, lineRect: run.lineRect))
        }
    }
    let runLengths = Dictionary(grouping: runs, by: \.lineIndex).mapValues { $0.reduce(0) { $0 + $1.stringRange.length } }
    for line in lines {
        log.check(
            runLengths[line.index] == line.range.length,
            "line \(line.index): its runs overlap or leave a gap inside \(line.range)",
        )
    }
    return lines
}

// MARK: - Issue log

/// Collects invariant violations for one case, capped so a broken case stays readable.
@MainActor
final class CleanLayoutLog {
    let context: String
    let sourceLocation: SourceLocation
    private(set) var count = 0
    private static let limit = 12

    init(_ context: String, sourceLocation: SourceLocation) {
        self.context = context
        self.sourceLocation = sourceLocation
    }

    func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        guard !condition else { return }
        count += 1
        if count <= Self.limit {
            Issue.record("[\(context)] \(message())", sourceLocation: sourceLocation)
        } else if count == Self.limit + 1 {
            Issue.record("[\(context)] further violations suppressed", sourceLocation: sourceLocation)
        }
    }
}

// MARK: - Geometry helpers

extension CGRect {
    var isCleanFinite: Bool {
        origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
            && size.width >= 0 && size.height >= 0
    }

    func horizontalOverlap(with other: CGRect) -> CGFloat {
        min(maxX, other.maxX) - max(minX, other.minX)
    }

    func isInside(_ container: CGRect, tolerance: CGFloat) -> Bool {
        minX >= container.minX - tolerance && maxX <= container.maxX + tolerance
            && minY >= container.minY - tolerance && maxY <= container.maxY + tolerance
    }

    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = CleanLayout.epsilon) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(maxX - other.maxX) <= tolerance
            && abs(minY - other.minY) <= tolerance && abs(maxY - other.maxY) <= tolerance
    }
}

extension CGSize {
    var isCleanFinite: Bool {
        width.isFinite && height.isFinite && width >= 0 && height >= 0
    }
}

func cleanLayoutUnion(_ rects: [CGRect]) -> CGRect {
    rects.reduce(CGRect.null) { $0.union($1) }
}

/// A composed character sequence and how the invariants treat it.
struct CleanLayoutCluster {
    var range: NSRange
    var isNewline: Bool
    var isWhitespace: Bool
    /// CJK punctuation that UAX #14 forbids at the start or end of a line, so it
    /// travels with its neighbour and does not count as a separate break unit.
    var isNoBreakPunctuation: Bool
}

func cleanLayoutClusters(_ string: NSString) -> [CleanLayoutCluster] {
    let noBreakPunctuation = CharacterSet(charactersIn: "。、，．！？：；」』）】〉》「『（【〈《・ー")
    var clusters = [CleanLayoutCluster]()
    var index = 0
    while index < string.length {
        let range = string.rangeOfComposedCharacterSequence(at: index)
        let scalars = string.substring(with: range).unicodeScalars
        clusters.append(CleanLayoutCluster(
            range: range,
            isNewline: scalars.allSatisfy { CharacterSet.newlines.contains($0) },
            isWhitespace: scalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) },
            isNoBreakPunctuation: scalars.allSatisfy { noBreakPunctuation.contains($0) },
        ))
        index = NSMaxRange(range)
    }
    return clusters
}

// MARK: - The clean-layout invariants

/// Asserts that a laid-out `layout` is clean. See `LitextCleanLayoutTests` for the list.
///
/// `width` is the width the layout was measured at. Single-cluster overflow: when one
/// unbreakable unit is wider than `width` (a glyph cluster, a ligature, or a cluster
/// glued to CJK punctuation that may not start or end a line, plus any head indent),
/// CoreText puts it on a line of its own and that line, and the measured width, may
/// exceed `width`. Every other line must fit.
@MainActor
func assertCleanLayout(
    _ layout: TextLabel.Layout,
    width: CGFloat,
    corpus: CleanLayoutCorpus,
    context: String = "",
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    let log = CleanLayoutLog("\(corpus) @ \(width)\(context)", sourceLocation: sourceLocation)
    let string = layout.attributedString.string as NSString
    let container = CGRect(origin: .zero, size: layout.containerSize)
    let px = CleanLayout.pixel
    let eps = CleanLayout.epsilon

    // 1. Finite geometry.
    log.check(layout.containerSize.isCleanFinite, "container size \(layout.containerSize) is not finite")
    let measured = layout.sizeThatFits(CleanLayout.proposal(width))
    log.check(measured.isCleanFinite, "measured size \(measured) is not finite")
    let overflows = !CleanLayout.isUnconstrained(width) && measured.width > width + eps

    let lines = cleanLayoutLines(layout, log: log)
    if string.length == 0 {
        log.check(lines.isEmpty, "empty text produced \(lines.count) lines")
        log.check(layout.visibleLineCount(in: nil) == 0, "empty text reports visible lines")
        log.check(measured == .zero, "empty text measures \(measured)")
        log.check(layout.rects(for: NSRange(location: 0, length: 0)).isEmpty, "empty text has rects")
        return
    }

    // 3. Completeness: every character in exactly one line, nothing dropped.
    log.check(!lines.isEmpty, "non-empty text produced no lines")
    log.check(
        layout.visibleLineCount(in: nil) == lines.count,
        "visibleLineCount(in: nil) = \(layout.visibleLineCount(in: nil)) but \(lines.count) lines carry runs",
    )
    log.check(
        layout.visibleLineCount(in: container) == lines.count,
        "only \(layout.visibleLineCount(in: container)) of \(lines.count) lines intersect the container",
    )
    var expectedLocation = 0
    for (position, line) in lines.enumerated() {
        log.check(line.index == position, "line indices skip: found \(line.index) at position \(position)")
        log.check(
            line.range.location == expectedLocation && line.range.length > 0,
            "line \(line.index) covers \(line.range), expected it to start at \(expectedLocation)",
        )
        expectedLocation = NSMaxRange(line.range)
    }
    log.check(expectedLocation == string.length, "lines end at \(expectedLocation), text length is \(string.length)")

    // 4. Line boxes.
    let clusters = cleanLayoutClusters(string)
    func line(containing index: Int) -> CleanLayoutLine? {
        lines.first { NSLocationInRange(index, $0.range) }
    }

    func visibleRects(_ cluster: CleanLayoutCluster) -> [CGRect] {
        layout.rects(for: cluster.range)
    }

    var clustersByLine = [Int: [(cluster: CleanLayoutCluster, rects: [CGRect])]]()
    for cluster in clusters {
        guard let owner = line(containing: cluster.range.location) else { continue }
        log.check(
            NSMaxRange(cluster.range) <= NSMaxRange(owner.range),
            "cluster \(cluster.range) is split across lines",
        )
        clustersByLine[owner.index, default: []].append((cluster, visibleRects(cluster)))
    }

    // Lines whose visible ink extent leaves the container: allowed only for a single
    // unbreakable unit that cannot fit the proposed width.
    var overflowingLines = Set<Int>()
    for line in lines {
        let entries = clustersByLine[line.index] ?? []
        let visible = entries.filter { !$0.cluster.isWhitespace }
        let extent = cleanLayoutUnion(visible.flatMap(\.rects))
        guard !extent.isNull, extent.minX < -px || extent.maxX > container.maxX + px else { continue }
        overflowingLines.insert(line.index)
        var units = [CGRect]()
        for entry in visible where !entry.cluster.isNoBreakPunctuation {
            let rect = cleanLayoutUnion(entry.rects)
            if !units.contains(where: { $0.isApproximatelyEqual(to: rect) }) {
                units.append(rect)
            }
        }
        log.check(
            overflows && units.count <= 1,
            "line \(line.index) \(line.range) "
                + "'\(string.substring(with: line.range).debugDescription)' overflows the container "
                + "(ink \(extent.minX)...\(extent.maxX), width \(container.width)) with \(units.count) break units",
        )
    }
    if overflows {
        log.check(!overflowingLines.isEmpty, "measured width \(measured.width) exceeds \(width) but no line overflows")
    } else {
        log.check(measured.width <= width + eps, "measured width \(measured.width) exceeds the proposal \(width)")
    }

    for (position, line) in lines.enumerated() {
        log.check(line.lineRect.isCleanFinite, "line \(line.index) rect \(line.lineRect) is not finite")
        log.check(line.lineRect.height > 0, "line \(line.index) has an empty box")
        let horizontallyExempt = overflowingLines.contains(line.index)
        log.check(
            line.lineRect.minY >= -px && line.lineRect.maxY <= container.maxY + px,
            "line \(line.index) box \(line.lineRect) leaves the container vertically (height \(container.height))",
        )
        log.check(
            horizontallyExempt || (line.lineRect.minX >= -px && line.lineRect.maxX <= container.maxX + px),
            "line \(line.index) box \(line.lineRect) leaves the container horizontally (width \(container.width))",
        )
        if position > 0 {
            let previous = lines[position - 1]
            log.check(
                line.lineRect.midY < previous.lineRect.midY,
                "line \(line.index) is not below line \(previous.index)",
            )
            log.check(
                line.lineRect.maxY <= previous.lineRect.minY + CleanLayout.lineOverlapTolerance,
                "line \(line.index) box \(line.lineRect) overlaps line \(previous.index) box \(previous.lineRect)",
            )
        }
    }

    if let first = lines.first {
        let topGap = container.maxY - first.lineRect.maxY
        log.check(
            topGap >= -px && topGap <= corpus.topSpacingAllowance + CleanLayout.fallbackFontTolerance,
            "first line starts \(topGap)pt below the top of the container",
        )
    }
    if let last = lines.last {
        // The measured height is the last line's descent, rounded up to a whole point.
        let bottomGap = last.lineRect.minY - container.minY
        log.check(bottomGap >= -px, "last line descends \(-bottomGap)pt below the container")
        log.check(bottomGap <= 1 + px, "last line ends \(bottomGap)pt above the bottom of the container")
    }

    // 5. Selection geometry.
    let fullRange = NSRange(location: 0, length: string.length)
    for rect in layout.rects(for: fullRange) {
        log.check(rect.isCleanFinite, "selection rect \(rect) is not finite")
        let exempt = overflowingLines.contains { index in
            let box = lines[index].lineRect
            return rect.maxY > box.minY && rect.minY < box.maxY
        }
        log.check(
            rect.minY >= -px && rect.maxY <= container.maxY + px
                && (exempt || (rect.minX >= -px && rect.maxX <= container.maxX + px)),
            "selection rect \(rect) leaves the container \(container.size)",
        )
    }

    for line in lines {
        let entries = clustersByLine[line.index] ?? []
        let band = cleanLayoutUnion(layout.rects(for: line.range))
        log.check(!band.isNull, "line \(line.index) has no selection rects")
        log.check(
            band.isNull || abs(band.maxY - line.lineRect.maxY) <= eps && band.minY <= line.lineRect.minY + eps,
            "line \(line.index) selection band \(band) does not match its box \(line.lineRect)",
        )

        // Whitespace after the line's last visible character hangs past the line end.
        // It is clipped to the container, and justified lines collapse it, so it may
        // be zero wide, like the caret rect of a newline.
        let lastVisible = entries.lastIndex { !$0.cluster.isWhitespace } ?? -1
        for (position, entry) in entries.enumerated() {
            let isHanging = position > lastVisible && entry.cluster.isWhitespace
            let description = "'\(string.substring(with: entry.cluster.range).debugDescription)' \(entry.cluster.range)"
            if entry.cluster.isNewline || isHanging {
                log.check(
                    !isHanging || entry.cluster.isNewline || !entry.rects.isEmpty,
                    "hanging whitespace \(description) on line \(line.index) has no rect",
                )
                log.check(
                    entry.rects.allSatisfy {
                        $0.minX >= line.lineRect.minX - eps && $0.maxX <= line.lineRect.maxX + eps
                    },
                    "hanging \(description) rects \(entry.rects) leave line \(line.index) box \(line.lineRect)",
                )
                guard entry.cluster.isNewline else { continue }
                log.check(
                    entry.rects.allSatisfy { $0.width <= eps },
                    "newline \(description) on line \(line.index) has a wide rect \(entry.rects)",
                )
                continue
            }
            log.check(!entry.rects.isEmpty, "\(description) on line \(line.index) has no rects")
            for rect in entry.rects {
                log.check(rect.isCleanFinite && rect.width > 0, "\(description) has an empty rect \(rect)")
                log.check(
                    rect.minX >= line.lineRect.minX - eps && rect.maxX <= line.lineRect.maxX + eps
                        && rect.minY >= band.minY - eps && rect.maxY <= band.maxY + eps,
                    "\(description) rect \(rect) leaves line \(line.index) box \(line.lineRect)",
                )
            }
        }

        // Disjoint ranges on one line never share horizontal space, except clusters
        // drawn by one shared glyph (a ligature), whose rects are identical.
        let drawn = entries.filter { !$0.cluster.isNewline && !$0.rects.isEmpty }
        for lhsIndex in drawn.indices {
            for rhsIndex in drawn.indices where rhsIndex > lhsIndex {
                for lhs in drawn[lhsIndex].rects {
                    for rhs in drawn[rhsIndex].rects where !lhs.isApproximatelyEqual(to: rhs) {
                        log.check(
                            lhs.horizontalOverlap(with: rhs) <= px,
                            "rects of \(drawn[lhsIndex].cluster.range) \(lhs) and "
                                + "\(drawn[rhsIndex].cluster.range) \(rhs) overlap on line \(line.index)",
                        )
                    }
                }
            }
        }

        // 6. Hit testing round-trips through the centre of each character.
        for entry in drawn {
            guard let rect = entry.rects.max(by: { $0.width < $1.width }), rect.width > px else { continue }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let range = entry.cluster.range
            func sharesGlyph(_ index: Int) -> Bool {
                guard index >= 0, index < string.length else { return false }
                let other = string.rangeOfComposedCharacterSequence(at: index)
                return layout.rects(for: other).contains { $0.contains(center) }
            }
            let character = layout.characterIndex(at: center)
            log.check(
                character.map { NSLocationInRange($0, range) || sharesGlyph($0) } ?? false,
                "characterIndex at the centre of \(range) returned \(String(describing: character))",
            )
            let caret = layout.textIndex(at: center)
            log.check(
                caret.map { ($0 >= range.location && $0 <= NSMaxRange(range)) || sharesGlyph($0) || sharesGlyph($0 - 1) }
                    ?? false,
                "textIndex at the centre of \(range) returned \(String(describing: caret))",
            )
        }

        // 7. Alignment.
        let visible = entries.filter { !$0.cluster.isWhitespace }
        let extent = cleanLayoutUnion(visible.flatMap(\.rects))
        guard !extent.isNull, !overflowingLines.contains(line.index) else { continue }
        switch corpus.checkedAlignment {
        case .center:
            log.check(
                abs(extent.midX - container.midX) <= CleanLayout.alignmentTolerance,
                "centered line \(line.index) spans \(extent.minX)...\(extent.maxX) in width \(container.width)",
            )
        case .right:
            log.check(
                abs(extent.maxX - container.maxX) <= CleanLayout.alignmentTolerance,
                "right-aligned line \(line.index) ends at \(extent.maxX) in width \(container.width)",
            )
        case .justified:
            let isParagraphEnd = line.index == lines.count - 1
                || (entries.last?.cluster.isNewline ?? false)
            let interior = visible.first.map { first in
                entries.contains { entry in
                    entry.cluster.isWhitespace && entry.cluster.range.location > first.cluster.range.location
                        && entry.cluster.range.location < (visible.last?.cluster.range.location ?? 0)
                }
            } ?? false
            guard !isParagraphEnd, interior else { break }
            log.check(
                extent.minX <= container.minX + CleanLayout.alignmentTolerance
                    && extent.maxX >= container.maxX - CleanLayout.alignmentTolerance,
                "justified line \(line.index) spans \(extent.minX)...\(extent.maxX) in width \(container.width)",
            )
        default:
            break
        }
    }

    // 8. Links.
    let attributed = layout.attributedString
    for region in layout.highlightRegions {
        for rect in region.rects {
            log.check(rect.isCleanFinite, "\(region.kind) region rect \(rect) is not finite")
            let exempt = overflowingLines.contains { lines[$0].lineRect.intersects(rect) }
            log.check(
                rect.minY >= -px && rect.maxY <= container.maxY + px
                    && (exempt || (rect.minX >= -px && rect.maxX <= container.maxX + px)),
                "\(region.kind) region rect \(rect) leaves the container \(container.size)",
            )
            log.check(
                lines.contains { line in
                    rect.minY >= line.lineRect.minY - eps && rect.maxY <= line.lineRect.maxY + eps
                        && rect.minX >= line.lineRect.minX - eps && rect.maxX <= line.lineRect.maxX + eps
                },
                "\(region.kind) region rect \(rect) is not inside any line box",
            )
        }
        guard region.kind == .link else { continue }
        var effective = NSRange()
        let value = attributed.attribute(
            .link,
            at: region.stringRange.location,
            longestEffectiveRange: &effective,
            in: NSRange(location: 0, length: attributed.length),
        )
        log.check(value != nil, "link region \(region.stringRange) has no link attribute")
        log.check(
            effective == region.stringRange,
            "link region \(region.stringRange) differs from the attribute's range \(effective)",
        )
        let regionUnion = region.rects
        for index in region.stringRange.location ..< NSMaxRange(region.stringRange) {
            for rect in layout.rects(for: NSRange(location: index, length: 1)) where rect.width > eps {
                log.check(
                    regionUnion.contains { $0.horizontalOverlap(with: rect) >= rect.width - eps && $0.midY > rect.minY && $0.midY < rect.maxY },
                    "link character \(index) rect \(rect) is not covered by the link region",
                )
            }
        }
    }
    var linkLocations = Set<Int>()
    attributed.enumerateAttribute(.link, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
        if value != nil {
            linkLocations.insert(range.location)
        }
    }
    log.check(
        Set(layout.highlightRegions.filter { $0.kind == .link }.map(\.stringRange.location)) == linkLocations,
        "link regions do not match the link attributes",
    )

    // 9. Attachments.
    for run in layout.layoutRuns(matching: .litextAttachment) {
        guard let attachment = run.attributes[.litextAttachment] as? TextLabel.Attachment else {
            log.check(false, "attachment run \(run.stringRange) carries no attachment")
            continue
        }
        log.check(
            abs(run.rect.width - attachment.size.width) <= 0.5 && abs(run.rect.height - attachment.size.height) <= 0.5,
            "attachment \(run.stringRange) rect \(run.rect) does not have its size \(attachment.size)",
        )
        let exempt = overflowingLines.contains(run.lineIndex)
        log.check(
            run.rect.minY >= -px && run.rect.maxY <= container.maxY + px
                && (exempt || (run.rect.minX >= -px && run.rect.maxX <= container.maxX + px)),
            "attachment \(run.stringRange) rect \(run.rect) leaves the container \(container.size)",
        )
        log.check(
            run.rect.minY >= run.lineRect.minY - eps && run.rect.maxY <= run.lineRect.maxY + eps,
            "attachment \(run.stringRange) rect \(run.rect) leaves its line box \(run.lineRect)",
        )
        for neighbour in [run.stringRange.location - 1, NSMaxRange(run.stringRange)] {
            guard neighbour >= 0, neighbour < string.length,
                  line(containing: neighbour)?.index == run.lineIndex
            else { continue }
            for rect in layout.rects(for: NSRange(location: neighbour, length: 1)) {
                log.check(
                    rect.horizontalOverlap(with: run.rect) <= px,
                    "attachment \(run.stringRange) rect \(run.rect) overlaps neighbour \(neighbour) rect \(rect)",
                )
            }
        }
    }
}

// MARK: - Snapshots for stability checks

/// Everything a host can observe about a layout's geometry.
@MainActor
struct CleanLayoutSnapshot: Equatable {
    struct Region: Equatable {
        var isLink: Bool
        var range: NSRange
        var rects: [CGRect]
    }

    var containerSize: CGSize
    var lines: [CleanLayoutLine]
    var runRects: [CGRect]
    var selection: [CGRect]
    var regions: [Region]

    init(_ layout: TextLabel.Layout) {
        let log = CleanLayoutLog("snapshot", sourceLocation: #_sourceLocation)
        containerSize = layout.containerSize
        lines = cleanLayoutLines(layout, log: log)
        runRects = layout.layoutRuns(matching: CleanLayout.probeKey).map(\.rect)
        selection = layout.rects(for: NSRange(location: 0, length: layout.attributedString.length))
        regions = layout.highlightRegions
            .map { Region(isLink: $0.kind == .link, range: $0.stringRange, rects: $0.rects) }
            .sorted { ($0.range.location, $0.isLink ? 0 : 1) < ($1.range.location, $1.isLink ? 0 : 1) }
    }
}
