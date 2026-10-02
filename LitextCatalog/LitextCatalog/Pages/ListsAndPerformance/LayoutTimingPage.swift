//
//  LayoutTimingPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  Times the steps a label goes through, on a document of the chosen size,
//  with ContinuousClock: creating a TextLabel.Layout, measuring it, laying
//  it out and drawing it. Every number is the median of real runs on this
//  device, in this build.
//

import Litext
import SwiftUI

struct LayoutTimingPage: View {
    private static let code = """
    let layout = TextLabel.Layout(attributedString: document)
    let clock = ContinuousClock()

    var size = CGSize.zero
    let measuring = clock.measure {
        size = layout.sizeThatFits(CGSize(width: 360, height: .greatestFiniteMagnitude))
    }
    // Measuring typesets the text; laying out at the measured
    // size reuses those lines instead of typesetting again.
    let layingOut = clock.measure {
        layout.containerSize = CGSize(width: 360, height: size.height)
    }
    // Pass the visible rect, as a view's draw(_:) does, so a long
    // document draws only the lines on screen.
    let window = CGRect(x: 0, y: scrollOffset, width: 360, height: 900)
    let drawing = clock.measure {
        layout.draw(in: context, visibleRect: window)
    }
    """

    @State private var paragraphs = 100
    @State private var content = TimingContent.latin
    @State private var width = 360.0
    @State private var run = TimingRun()
    @State private var runID = 0

    private var configuration: TimingConfiguration {
        TimingConfiguration(paragraphs: paragraphs, content: content, width: CGFloat(width.rounded()), runID: runID)
    }

    var body: some View {
        CatalogPageScaffold(.layoutTiming, code: Self.code) {
            TimingResultsView(run: run, configuration: configuration)
        } controls: {
            CatalogPicker("Paragraphs", selection: $paragraphs, options: [10, 100, 1000, 5000]) {
                $0.formatted()
            }
            .accessibilityIdentifier("demo.timing.paragraphs")
            CatalogPicker("Content", selection: $content, options: TimingContent.allCases) { $0.title }
                .accessibilityIdentifier("demo.timing.content")
            CatalogSlider("Width", value: $width, in: 200 ... 800, step: 20) { "\(Int($0)) pt" }
            HStack {
                Button {
                    runID += 1
                } label: {
                    Label("Run Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(run.isRunning)
                .accessibilityIdentifier("demo.timing.run")
                Spacer()
                if run.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            #if DEBUG
                CatalogNote(
                    "This is a debug build, so Litext runs unoptimized. A release build is several times faster; compare numbers within one build, not across builds.",
                    systemImage: "exclamationmark.triangle",
                )
            #endif
            CatalogNote(
                "Each number is the median of several runs, measured on the main thread with ContinuousClock. The repository keeps a release-build baseline for many more scenarios in Documents/Research/Performance-Baseline.md.",
            )
        }
        .task(id: configuration) {
            await run.measure(configuration)
        }
    }
}

// MARK: - Configuration

enum TimingContent: String, CaseIterable, Hashable {
    case latin
    case cjk
    case bidi

    var title: String {
        switch self {
        case .latin: "Latin"
        case .cjk: "CJK"
        case .bidi: "Bidi"
        }
    }

    /// The body text of one paragraph; the paragraph number varies the line breaks.
    func sentence(for index: Int) -> String {
        switch self {
        case .latin:
            index.isMultiple(of: 2)
                ? "CoreText typesets every line of this paragraph, then Litext keeps the lines, their boxes and their runs so that drawing, hit testing and selection never typeset again."
                : "A longer document costs more to measure, but drawing only the visible window keeps scrolling cheap however long the text grows."
        case .cjk:
            index.isMultiple(of: 2)
                ? "排版引擎逐行计算字形位置，结果被缓存下来，供绘制、命中测试和选择使用。日本語の文章も同じように組版され、行ごとに保存されます。"
                : "文档越长，测量越慢；但只绘制可见区域，滚动时的绘制开销与文档长度无关。"
        case .bidi:
            index.isMultiple(of: 2)
                ? "Mixed direction text needs the bidi algorithm: مرحبا بالعالم and שלום עולם sit inside an English sentence, and every line is reordered visually."
                : "النص العربي يتدفق من اليمين إلى اليسار، with English words and numbers like 2026 kept left to right inside it."
        }
    }
}

struct TimingConfiguration: Hashable {
    var paragraphs: Int
    var content: TimingContent
    var width: CGFloat
    var runID: Int

    /// The document: numbered paragraphs, a bold lead-in, and a link every third paragraph.
    func makeDocument() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 8
        paragraph.lineSpacing = 2
        let body: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 15),
            .foregroundColor: PlatformColor.label,
            .paragraphStyle: paragraph,
        ]
        var lead = body
        lead[.font] = PlatformFont.boldSystemFont(ofSize: 15)
        var link = body
        link[.link] = URL(string: "https://github.com/Lakr233/Litext")
        link[.foregroundColor] = PlatformColor.link

        let document = NSMutableAttributedString()
        for index in 0 ..< paragraphs {
            document.append(NSAttributedString(string: "\(index + 1). ", attributes: lead))
            document.append(NSAttributedString(string: content.sentence(for: index), attributes: body))
            if index % 3 == 2 {
                document.append(NSAttributedString(string: " Read more", attributes: link))
            }
            if index < paragraphs - 1 {
                document.append(NSAttributedString(string: "\n", attributes: body))
            }
        }
        return document
    }
}

// MARK: - Measurement

/// The timings of one configuration, filled in step by step as they are measured.
@MainActor
@Observable
final class TimingRun {
    struct Step: Identifiable {
        let id: String
        let title: String
        let detail: String
        var median: Duration?
        var samples = 0
    }

    private(set) var steps: [Step] = []
    private(set) var isRunning = false
    private(set) var characters = 0
    private(set) var lineCount = 0
    private(set) var height: CGFloat = 0
    private(set) var preview = NSAttributedString()

    /// The height of the window a scrolled view draws.
    static let windowHeight: CGFloat = 900

    func measure(_ configuration: TimingConfiguration) async {
        isRunning = true
        defer { isRunning = false }
        let document = configuration.makeDocument()
        let width = configuration.width
        let unbounded = CGSize(width: width, height: .greatestFiniteMagnitude)
        characters = document.length
        // The first paragraph, to show what the document is made of.
        let firstBreak = (document.string as NSString).range(of: "\n")
        let previewLength = firstBreak.location == NSNotFound ? document.length : firstBreak.location
        preview = document.attributedSubstring(from: NSRange(location: 0, length: previewLength))
        steps = Self.makeSteps(width: width)

        // The document's geometry, from one layout that the drawing steps reuse.
        let laidOut = TextLabel.Layout(attributedString: document)
        let size = laidOut.sizeThatFits(unbounded)
        laidOut.containerSize = CGSize(width: width, height: size.height)
        height = size.height
        lineCount = laidOut.visibleLineCount(in: nil)
        let laidOutSize = CGSize(width: width, height: size.height)
        guard let context = Self.makeContext(width: width) else { return }
        let window = CGRect(
            x: 0,
            y: max(size.height / 2 - Self.windowHeight / 2, 0),
            width: width,
            height: Self.windowHeight,
        )

        await sample("create", setup: {}, body: { _ in
            _ = TextLabel.Layout(attributedString: document)
        })
        await sample("measureCold", setup: { TextLabel.Layout(attributedString: document) }, body: { layout in
            _ = layout.sizeThatFits(unbounded)
        })
        await sample("measureCached", setup: { laidOut }, body: { layout in
            _ = layout.sizeThatFits(unbounded)
        })
        await sample(
            "layoutAfterMeasure",
            setup: { () -> TextLabel.Layout in
                let layout = TextLabel.Layout(attributedString: document)
                _ = layout.sizeThatFits(unbounded)
                return layout
            },
            body: { layout in
                layout.containerSize = laidOutSize
            },
        )
        await sample("layoutCold", setup: { TextLabel.Layout(attributedString: document) }, body: { layout in
            layout.containerSize = laidOutSize
        })
        await sample("drawAll", setup: { laidOut }, body: { layout in
            layout.draw(in: context)
        })
        await sample("drawWindow", setup: { laidOut }, body: { layout in
            // Move the window to the top of the bitmap, as a scrolled view's context is.
            context.saveGState()
            context.translateBy(x: 0, y: -window.minY)
            layout.draw(in: context, visibleRect: window)
            context.restoreGState()
        })
    }

    /// Runs `body` until about 150 ms of samples or 25 samples have been taken, at least
    /// three times, and records the median. `setup` runs before every sample and is not
    /// timed. Yields between samples so the page stays responsive and a new configuration
    /// cancels the run.
    private func sample<Value>(
        _ id: String,
        setup: () -> Value,
        body: (Value) -> Void,
    ) async {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        let clock = ContinuousClock()
        var durations: [Duration] = []
        var total = Duration.zero
        while durations.count < 3 || (total < .milliseconds(150) && durations.count < 25) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            let value = setup()
            let duration = clock.measure { body(value) }
            durations.append(duration)
            total += duration
        }
        durations.sort()
        steps[index].median = durations[durations.count / 2]
        steps[index].samples = durations.count
    }

    private static func makeSteps(width: CGFloat) -> [Step] {
        let width = Int(width)
        return [
            Step(id: "create", title: "Create layout", detail: "Layout(attributedString:)"),
            Step(id: "measureCold", title: "Measure", detail: "sizeThatFits at \(width) pt, first call"),
            Step(id: "measureCached", title: "Measure again", detail: "the same proposal, from the cache"),
            Step(id: "layoutAfterMeasure", title: "Lay out after measuring", detail: "containerSize at the measured size"),
            Step(id: "layoutCold", title: "Lay out, not measured", detail: "containerSize on a new layout"),
            Step(id: "drawAll", title: "Draw every line", detail: "draw(in:)"),
            Step(id: "drawWindow", title: "Draw a 900 pt window", detail: "draw(in:visibleRect:), mid-document"),
        ]
    }

    /// A bitmap one window tall, at scale 1, flipped to a top-left origin like a view's
    /// context.
    private static func makeContext(width: CGFloat) -> CGContext? {
        let context = CGContext(
            data: nil,
            width: Int(width.rounded(.up)),
            height: Int(windowHeight),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )
        context?.translateBy(x: 0, y: windowHeight)
        context?.scaleBy(x: 1, y: -1)
        return context
    }
}

// MARK: - Results

private struct TimingResultsView: View {
    let run: TimingRun
    let configuration: TimingConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextLabel(attributedString: run.preview)
                .accessibilityIdentifier("demo.timing.preview")

            HStack(spacing: 16) {
                stat("Characters", run.characters.formatted())
                stat("Lines", run.lineCount.formatted())
                stat("Height", "\(Int(run.height).formatted()) pt")
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                ForEach(run.steps) { step in
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                            Text(step.detail)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(step.median.map(Self.format) ?? "…")
                            .font(.body.monospacedDigit())
                            .gridColumnAlignment(.trailing)
                            .accessibilityIdentifier("state.timing.\(step.id)")
                    }
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
        }
    }

    /// Microseconds below a millisecond, milliseconds above.
    static func format(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
        let microseconds = seconds * 1e6
        if microseconds < 1000 {
            return microseconds.formatted(.number.precision(.fractionLength(microseconds < 10 ? 2 : 0))) + " µs"
        }
        return (microseconds / 1000).formatted(.number.precision(.fractionLength(microseconds < 100_000 ? 2 : 0))) + " ms"
    }
}
