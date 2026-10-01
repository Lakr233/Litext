# Known layout issues

The clean-layout suite (`Tests/LitextTests/CleanLayout`) records 24 known issues on a 2x display, and one more on a 1x display such as a CI runner. They don't fail the run: `swift test` exits 0 and `xcodebuild test` reports success. They are recorded with `withKnownIssue(isIntermittent: true)`, and each one is limited to the inputs that trigger it. A known issue anywhere else, or a new kind of failure, still fails the run.

They fall into three groups. All three are deferred.

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

## 3. Pixel rounding past the proposal re-wraps lines on 1x displays

**Where:** `label view is clean`, corpus `indents` at width 57.3, on a 1x display only.
- It is the one extra known issue on CI.
- On a 2x display, 57.06 rounds to 57.5 and the lines stay the same.

**Cause:**
- `TextLabelView` sizes itself to the measured width rounded up to the pixel grid. At 1x, the measured 57.06 pt becomes a 58 pt frame, which is wider than the 57.3 pt proposal.
- In that frame the text wraps into 80 lines instead of the measured 82, leaving about 37 pt empty below the last line.
- The same can happen to an app on a non-Retina display whenever a label's width proposal is off the pixel grid.

The condition is `roundsPastProposal` in `label view is clean`. Only proposals off the pixel grid are affected.

**Fixing it later:**
- Have the view lay out with the measured width rather than the pixel-ceiled frame width when the two differ by less than a pixel.
- Alternatively, round the intrinsic width down to the proposal when rounding up would pass it.

## Reproducing

```sh
swift test --filter CleanLayout 2>&1 | grep "known issue"
```
