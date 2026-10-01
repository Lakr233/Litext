# Litext

Litext is a CoreText-only rich-text label for UIKit, AppKit and SwiftUI, including watchOS. The package is in `Sources/Litext`, the tests are in `Tests/LitextTests`, and the sample apps (`OhMyLitext` and its watch app) are in `LitextSamples`, opened through `Litext.xcworkspace`.

## Ground rules

- **Language and platform floors:** Swift 6 in strict concurrency mode. iOS 13, Mac Catalyst 13, macOS 12, tvOS 13, visionOS 1 and watchOS 8 are the floors. Gate newer APIs with `#available`, and keep every floor building; don't raise one to reach an API.
- **Signing:** Build and test with `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`. Never change signing settings in the projects: no adding `DEVELOPMENT_TEAM`, no switching `CODE_SIGN_STYLE`, no `-allowProvisioningUpdates`.
- **Formatting and lint:** CI runs `swiftformat --lint .` and `swiftlint --strict`. Both must report nothing before you push.
- **Commits and pull requests:**
  - Commits use an imperative subject that says what the change does for the user of the label, followed by a body explaining why.
  - Keep `Sources` changes and test changes in separate commits, so a fix can land without its tests when needed.
- **Platform split:** Code shared between UIKit and AppKit lives in files without a suffix. Platform-only files use an `@AppKit` suffix or `#if canImport(UIKit)` guards. watchOS has no `TextLabelView`, only the SwiftUI `TextLabel`.

## Layout rules the code relies on

- **Zero width:** a container width of zero or less means unconstrained, for both measurement and layout.
- **Invalid sizes:** a size with a NaN, negative or infinite dimension is invalid. Layout, drawing and measurement skip it rather than producing garbage geometry. See `CGSize.isValidLayoutSize` in `Supplement/Extension/Ext+CGSize.swift`.
- **Unbounded heights:**
  - Measurement clamps unbounded heights to `maxLayoutDimension` (1e6).
  - Text taller than that is laid out again at `maxLayoutHeight` (1e8) so it is never cut off.
  - Keep geometry finite.
- **Typographic bounds:** sizes come from typographic bounds, the way `UILabel` computes them. Glyph ink that reaches outside them (deep descenders, Arabic marks, emoji bitmaps) can be clipped. This is a known, accepted limitation.

## Building and testing

```sh
swift build
swift test                                        # macOS, about 12 s; skips the stress suites
LITEXT_STRESS=1 swift test --filter Stress        # stress suites at quick sizes, about 25 s
LITEXT_STRESS=full swift test --filter Stress     # stress suites at full sizes, about 6 min
Script/test.sh                                    # every platform build plus sample-app tests
```

Run the package tests on an iOS simulator through Xcode:

```sh
xcodebuild test -scheme Litext -destination 'platform=iOS Simulator,id=<UDID>' \
  -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

- **Test framework:** The tests use Swift Testing.
- **Stress suites:** They are tagged `.stress` and skipped unless `LITEXT_STRESS` is set. CI runs them at quick sizes in a separate step. On a simulator, pass the variable as `TEST_RUNNER_LITEXT_STRESS=1`. Run them at full size before changing layout, selection or streaming paths.
- **`CleanLayout`:** These tests record 24 known issues for glyph ink outside the typographic bounds. Those issues are expected, but new ones are not.
- **Fuzzing:** `LITEXT_FUZZ_SEED` and `LITEXT_FUZZ_ITERATIONS` reproduce or widen the fuzz tests.
- **Simulator tests:** Disable parallel testing. The view tests share one window and time-based budgets.
- **Memory tests:** On iOS, CoreText keeps the attributes of the last string it typeset on each thread. A test that expects an attachment to deallocate must first call `evictCoreTextLastTypesetAttributes()` from `MemoryTestSupport.swift`.
- **Code coverage:** Run `xcodebuild test -scheme Litext -enableCodeCoverage YES` from a path outside `/tmp`. Under the `/private/tmp` symlink, the Litext target reports no coverable files.

## Research notes

`Documents/Research` holds measurements and investigations worth keeping, such as the performance baseline in `Performance-Baseline.md`. Add a new note there rather than putting the findings in commit messages or pull request descriptions only.
