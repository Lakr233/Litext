# Known layout issues

The clean-layout suite (`Tests/LitextTests/CleanLayout`) records 24 known issues. They don't fail the run: `swift test` exits 0 and `xcodebuild test` reports success. They are recorded with `withKnownIssue(isIntermittent: true)`, and each one is limited to the inputs that trigger it. A known issue anywhere else, or a new kind of failure, still fails the run.

They fall into two groups. Both are deferred.

## 1. Glyph ink outside the typographic bounds: 21 cases

**Where:** the `label view is clean` test, which checks that `ink.outside == 0`.

| Corpus | Widths |
|---|---|
| `fontWithLeading` | 1, 20, 57.3, 120, 320, 1000, unconstrained |
| `maximumLineHeight` | 57.3, 120, 320, 1000, unconstrained |
| `emoji` | 120, 320, 1000, unconstrained |
| `arabic` | 1, 20 |
| `mixedBidi` | 1, 20 |
| `rightAligned` | 1 |

**Cause:**
- Litext sizes text by its typographic bounds (`CTLineGetTypographicBounds`), as `UILabel` does, not by its ink (`CTLineGetImageBounds`).
- Some glyphs draw outside that box: Hiragino descenders and `J`, Arabic marks, emoji bitmaps, and lines squeezed by `maximumLineHeight`.
- A view whose backing store is exactly its bounds clips that ink.

**What still holds:**
- Ink never strays more than 2.5 pt (`glyphOverhangLimit`) from the frame. That limit is still asserted, so misplaced lines would fail.

**Fixing it later:**
- Keep the layout as it is and let drawing overflow: draw into a layer or backing store inset outward by the ink overhang.
- Don't grow the measured size; that would change every host's layout.

## 2. Whitespace CoreText wraps but does not measure: 3 cases

**Where:** corpus `whitespaceOnly` at width 1, in three places:
- `layout in the measured size is clean`, the measured layout;
- the same test's check that shrink-wrapping keeps the lines;
- `label view is clean`.

**Cause:**
- A tab narrower than the proposal is wrapped by CoreText but measures zero wide.
- A zero width means unconstrained, so laying out in the measured size puts the text on fewer lines than were measured.

The condition is `wrapsUnmeasuredWhitespace(_:width:)` in `LitextCleanLayoutTests.swift`.

**Fixing it later:**
- Give whitespace-only text that wraps a minimum measured width of one pixel, so the measured container stays constrained.
- Alternatively, treat whitespace-only text as a single line in measurement too.

## Reproducing

```sh
swift test --filter CleanLayout 2>&1 | grep "known issue"
```
