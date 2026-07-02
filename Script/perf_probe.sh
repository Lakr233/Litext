#!/bin/bash

set -euo pipefail

REPO_PATH="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTPUT_PATH="${2:-}"
ITERATIONS="${LITEXT_PERF_ITERATIONS:-12}"
WARMUPS="${LITEXT_PERF_WARMUPS:-3}"

REPO_PATH="$(cd "$REPO_PATH" && pwd)"
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/litext-perf-probe.XXXXXX")"
trap 'rm -rf "$PROBE_DIR"' EXIT

HAS_VISIBLE_RECT_API=0
if grep -q "visibleRect:" "$REPO_PATH/Sources/Litext/TextLabelView/Layout/TextLabel+Layout.swift"; then
	HAS_VISIBLE_RECT_API=1
fi

cat > "$PROBE_DIR/Package.swift" <<EOF
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LitextPerfProbe",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(name: "Litext", path: "$REPO_PATH"),
    ],
    targets: [
        .executableTarget(
            name: "LitextPerfProbe",
            dependencies: [.product(name: "Litext", package: "Litext")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
EOF

mkdir -p "$PROBE_DIR/Sources/LitextPerfProbe"

cat > "$PROBE_DIR/Sources/LitextPerfProbe/main.swift" <<'EOF'
import CoreGraphics
import Foundation
import Litext

private func environmentInt(_ key: String, defaultValue: Int) -> Int {
    Int(ProcessInfo.processInfo.environment[key] ?? "") ?? defaultValue
}

@MainActor
private func makeAttributedText(lineCount: Int) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 2

    let text = NSMutableAttributedString()
    for index in 0 ..< lineCount {
        let line = "Line \(index): Litext performance probe validates layout, links, highlights, and CoreText drawing without state regressions.\n"
        let start = text.length
        text.append(NSAttributedString(
            string: line,
            attributes: [
                .font: PlatformFont.systemFont(ofSize: 16),
                .foregroundColor: PlatformColor.textColor,
                .paragraphStyle: paragraph,
            ]
        ))

        if index.isMultiple(of: 9), let url = URL(string: "https://example.com/probe/\(index)") {
            let range = NSRange(location: start + 8, length: min(34, max(0, line.count - 8)))
            text.addAttributes(
                [
                    .link: url,
                    .foregroundColor: PlatformColor.systemBlue,
                ],
                range: range
            )
        }
    }
    return text
}

@MainActor
private func makeLayout(text: NSAttributedString, width: CGFloat) -> TextLabel.Layout {
    let layout = TextLabel.Layout(attributedString: text)
    let suggested = layout.sizeThatFits(
        CGSize(width: width, height: .greatestFiniteMagnitude)
    )
    layout.containerSize = CGSize(width: width, height: max(1, suggested.height.rounded(.up)))
    return layout
}

private func makeBitmapContext(size: CGSize) -> CGContext {
    let width = max(1, Int(size.width.rounded(.up)))
    let height = max(1, Int(size.height.rounded(.up)))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("failed to create bitmap context")
    }
    return context
}

@MainActor
private func measure(iterations: Int, warmups: Int, _ block: () -> Void) -> Double {
    for _ in 0 ..< warmups {
        block()
    }

    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0 ..< iterations {
        block()
    }
    let end = DispatchTime.now().uptimeNanoseconds
    return Double(end - start) / 1_000_000.0 / Double(iterations)
}

@MainActor
private func jsonNumber(_ value: Double?) -> Any {
    guard let value else { return NSNull() }
    return (value * 1000).rounded() / 1000
}

@MainActor
private func runProbe() throws {
    let iterations = environmentInt("LITEXT_PERF_ITERATIONS", defaultValue: 12)
    let warmups = environmentInt("LITEXT_PERF_WARMUPS", defaultValue: 3)
    let hasVisibleRectAPI = ProcessInfo.processInfo.environment["LITEXT_HAS_VISIBLE_RECT_API"] == "1"
    let width: CGFloat = 360
    let lineCount = 1_200
    let text = makeAttributedText(lineCount: lineCount)
    let layout = makeLayout(text: text, width: width)
    let fullContext = makeBitmapContext(size: layout.containerSize)

    let layoutMS = measure(iterations: iterations, warmups: warmups) {
        _ = makeLayout(text: text, width: width)
    }

    let highlightMS = measure(iterations: iterations, warmups: warmups) {
        let freshLayout = makeLayout(text: text, width: width)
        freshLayout.updateHighlightRegions()
    }

    let fullDrawMS = measure(iterations: iterations, warmups: warmups) {
        layout.draw(in: fullContext)
    }
EOF

if [ "$HAS_VISIBLE_RECT_API" -eq 1 ]; then
	cat >> "$PROBE_DIR/Sources/LitextPerfProbe/main.swift" <<'EOF'
    let visibleContext = makeBitmapContext(size: layout.containerSize)
    let visibleRect = CGRect(
        x: 0,
        y: max(0, layout.containerSize.height * 0.45),
        width: width,
        height: 900
    )
    let visibleLineCount: Int? = layout.visibleLineCount(in: visibleRect)
    let totalLineCount: Int? = layout.visibleLineCount(in: nil)
    let visibleDrawMS: Double? = measure(iterations: iterations, warmups: warmups) {
        layout.draw(in: visibleContext, visibleRect: visibleRect)
    }
EOF
else
	cat >> "$PROBE_DIR/Sources/LitextPerfProbe/main.swift" <<'EOF'
    let visibleDrawMS: Double? = nil
    let visibleLineCount: Int? = nil
    let totalLineCount: Int? = nil
EOF
fi

cat >> "$PROBE_DIR/Sources/LitextPerfProbe/main.swift" <<'EOF'

    let result: [String: Any] = [
        "repo": ProcessInfo.processInfo.environment["LITEXT_REPO_PATH"] ?? "",
        "hasVisibleRectAPI": hasVisibleRectAPI,
        "iterations": iterations,
        "warmups": warmups,
        "lineCount": lineCount,
        "containerWidth": width,
        "containerHeight": Double(layout.containerSize.height),
        "totalLineCount": totalLineCount as Any,
        "visibleLineCount": visibleLineCount as Any,
        "layoutMS": jsonNumber(layoutMS),
        "highlightMS": jsonNumber(highlightMS),
        "fullDrawMS": jsonNumber(fullDrawMS),
        "visibleDrawMS": jsonNumber(visibleDrawMS),
    ]

    let data = try JSONSerialization.data(
        withJSONObject: result,
        options: [.prettyPrinted, .sortedKeys]
    )
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

@main
private struct Runner {
    @MainActor
    static func main() throws {
        try runProbe()
    }
}
EOF

export LITEXT_PERF_ITERATIONS="$ITERATIONS"
export LITEXT_PERF_WARMUPS="$WARMUPS"
export LITEXT_HAS_VISIBLE_RECT_API="$HAS_VISIBLE_RECT_API"
export LITEXT_REPO_PATH="$REPO_PATH"

RESULT="$(swift run --package-path "$PROBE_DIR" -c release LitextPerfProbe)"
if [ -n "$OUTPUT_PATH" ]; then
	mkdir -p "$(dirname "$OUTPUT_PATH")"
	printf '%s\n' "$RESULT" > "$OUTPUT_PATH"
fi
printf '%s\n' "$RESULT"
