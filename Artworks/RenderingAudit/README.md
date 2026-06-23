# Litext Rendering Audit

The `OhMyLitextUITests` target captures the audit fixtures as XCTest attachments and, when
`LITEXT_SCREENSHOT_DIR` is set, writes PNG files into this directory.

Captured artifacts:

- `ios-audit-fixtures.png`
- `ios-multi-style-link.png`
- `ios-linked-attachment.png`
- `ios-selection-state.png`
- `contact-sheet.png`

Local coverage note: this machine currently has only iOS simulator runtimes
installed (`xcrun simctl list runtimes` lists iOS 18.6 and iOS 27.0). The generic
build matrix still covers macOS, Mac Catalyst, tvOS, tvOS Simulator, xrOS, xrOS
Simulator, watchOS, and watchOS Simulator. Additional screenshot captures for
tvOS, visionOS, and watchOS should be rerun on a machine with those simulator
runtimes installed.

Local capture command:

```sh
export DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.app/Contents/Developer
LITEXT_SCREENSHOT_DIR="$PWD/Artworks/RenderingAudit" \
xcodebuild test \
  -scheme OhMyLitext \
  -workspace Litext.xcworkspace \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -only-testing:OhMyLitextUITests
```
