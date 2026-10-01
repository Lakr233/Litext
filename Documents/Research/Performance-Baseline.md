# Performance baseline

Measured on 2026-10-01, before the release that follows 2.2.2. Performance work is paused, so this file records where things stand. Use it as the reference point when that work resumes.

## Setup

- **Machine:** Apple M4 Max with 16 cores and 64 GB, running macOS 27.0.1 and Swift 6.4. Builds were release builds and ran on macOS through AppKit.
- **Revisions compared:**
  - `097475a` is the 2.2.2 tag.
  - `c9b93b8` is the head of the adversarial-review fixes.
  - The current revision is `70a129c`: the audit fixes plus the double-click fix.
- **Method:**
  - Each revision ran in its own process, three times, interleaved with the other revisions.
  - Each scenario takes 50 samples after 5 warm-ups. Each sample repeats the operation until it takes about 10 ms.
  - The table shows the best of the three runs' medians, because interference only ever slows a run down.
  - Scenarios run at a 360 pt width, the width a chat column gives a message bubble.
- **Noise:** The machine was also running simulator test suites, with load averages up to 95. A difference under about 10% is noise unless the scenario's own run-to-run noise is far below that. Differences of 2× or more are real.

### Corpora

| Corpus | Content |
|---|---|
| `short` | A one-line label of about 30 characters. |
| `medium` | A chat message of 5 to 10 lines, with a few links and some emphasis. |
| `centered` | `medium` with centered paragraphs. |
| `long` | 1,200 lines (about 144k characters), a link on every ninth line, 2 pt line spacing. |
| `cjk` | A Chinese and Japanese document. |
| `rtlMedium` | `medium` with right-to-left Arabic and Hebrew content. |
| `rtl` | A longer bidi document that mixes Arabic, Hebrew and English. |
| `emoji` | Emoji-dense text. |
| `attachments` | Text with inline view attachments. |

### Scenario groups

- **layout:**
  - `coldMeasure` and `cachedMeasure` are a size query, without and with the cache.
  - `measure20Widths` measures at 20 widths, more than the size cache keeps.
  - `hostPipeline` measures, then lays out at the measured height.
  - `relayout` changes the width on every assignment.
  - `highlightRegions` and `linkRuns` extract highlights and links.
  - `containerFirst`, `multiProposal` and `heightOnlyRelayout` are call orders that real hosts use.
- **draw:**
  - `full` renders everything into a bitmap context.
  - `visibleWindow900` renders only the 900 pt window a scrolled view paints.
- **query:**
  - `rectsSmallRange` and `rectsLargeRange` get the selection rectangles for a small and a large range.
  - `textIndex1000` and `nearestTextIndex1000` hit-test a 25 × 40 grid of points.
  - `visibleLineCount` counts lines in a 900 pt window and in the whole text.
- **streaming:** a reply arrives in chunks of about 20 characters, and links are restyled as they arrive.
  - `layoutPerChunk` lays out after every chunk.
  - `viewPerChunk` updates a view after every chunk.
  - `viewRenderPerChunk` updates and renders after every chunk.
- **view:**
  - `createSizeLayout` creates a `TextLabelView`, sizes it and lays it out; the `Render` variant also draws it.
  - `cellReuse200` cycles one view through 200 cell contents.
- **interaction:**
  - `selectionDrag100` is a 100-step drag in a window that also holds 200 selectable sibling labels.
  - The double-click scenarios select a word near the end or the start of the long document.
- **memory** and **swiftui:**
  - `renderedLayerBackedView` renders a layer-backed view.
  - `hostingFittingSize` gets a SwiftUI `TextLabel`'s fitting size through `NSHostingView`.

## Highlights

**Faster than 2.2.2**
- `relayout` is about 50% faster in every corpus except `centered`, `rtlMedium` and `rtl`.
- `containerFirst/long` is 31% faster, and `multiProposal/long` 18% faster.
- `selectionDrag100` is 39% faster.
- `rectsSmallRange/long` dropped from 33.7 µs to 0.75 µs.

**Double-click: a regression, now fixed**
- `c9b93b8` turned a double-click on a space or punctuation mark near the start of the text into a tokenization of the whole rest of the string: 36 µs became 1.5 ms.
- The current revision stops the word walk once it passes the clicked index, which brings it back to 41 µs.

**Slower than 2.2.2: optimization candidates, ranked by impact**
1. **`rectsLargeRange` and `rectsSmallRange` on bidi text:**
   - `rectsLargeRange/rtl` went from 0.63 µs to 757 µs, and `rectsSmallRange/rtl` from 0.6 µs to 18 µs.
   - Per-line bidi extents now give correct visual rectangles, but every line pays for a full walk of its runs.
   - Fix: cache the extents per line, or compute them only for lines whose runs mix directions.
2. **`rectsLargeRange` on `long` and `cjk`:**
   - Both are 7× to 9× slower: 38 to 293 µs on `long`, and 0.8 to 7 µs on `cjk`.
   - The cause is the same per-line extent work.
3. **`visibleLineCount900/long` is 3.9× slower:** 0.9 µs became 3.5 µs. A binary search over the line origins would bring it back.
4. **`highlightRegions` and `linkRuns` on `cjk`, `rtl`, `emoji` and `attachments`:**
   - They are 30% to 90% slower, because highlight paths are now clipped to line boxes.
   - These are microsecond costs per layout.
5. **`swiftui/hostingFittingSize/medium`:**
   - It is 19% slower, and its peak footprint is 6 MB higher.
   - The measurement is noisy (13% range), so it needs a quiet machine before anyone acts on it.

**Unchanged**
- Streaming is still O(n²) in the reply length on both revisions. A 16 KB reply costs about 1.1 s of layout and 1.8 s with rendering.
- `cellReuse200/rtl` costs 5.6× `ltr`, and centered layout costs about 1.6× left-aligned. Both ratios are the same as in 2.2.2.

## Results

The Δ columns compare the current revision against the older one; a positive value means the current revision is slower.

| Scenario | 2.2.2 (`097475a`) | `c9b93b8` | Current | Δ vs 2.2.2 | Δ vs `c9b93b8` |
|---|---:|---:|---:|---:|---:|
| `layout/coldMeasure/short` | 6.91 us | 7.45 us | 7.38 us | +6.9% | -0.9% |
| `layout/cachedMeasure/short` | 3.0 ns | 3.0 ns | 3.0 ns | +0.0% | +0.0% |
| `layout/measure20Widths/short` | 42.80 us | 43.92 us | 42.40 us | -1.0% | -3.5% |
| `layout/hostPipeline/short` | 6.97 us | 7.57 us | 7.38 us | +5.8% | -2.5% |
| `layout/relayout/short` | 3.95 us | 2.34 us | 2.31 us | -41.6% | -1.3% |
| `layout/highlightRegions/short` | 13.0 ns | 13.0 ns | 13.0 ns | +0.0% | +0.0% |
| `layout/linkRuns/short` | 92.0 ns | 166.0 ns | 162.0 ns | +76.1% | -2.4% |
| `layout/coldMeasure/medium` | 144.48 us | 148.49 us | 144.84 us | +0.3% | -2.5% |
| `layout/cachedMeasure/medium` | 3.0 ns | 3.0 ns | 3.0 ns | +0.0% | +0.0% |
| `layout/measure20Widths/medium` | 1.02 ms | 1.01 ms | 991.55 us | -2.3% | -1.5% |
| `layout/hostPipeline/medium` | 144.60 us | 148.83 us | 145.36 us | +0.5% | -2.3% |
| `layout/relayout/medium` | 98.06 us | 48.80 us | 47.72 us | -51.3% | -2.2% |
| `layout/highlightRegions/medium` | 9.36 us | 7.96 us | 8.27 us | -11.7% | +3.8% |
| `layout/linkRuns/medium` | 7.71 us | 5.50 us | 5.53 us | -28.2% | +0.6% |
| `layout/coldMeasure/centered` | 143.22 us | 142.99 us | 139.83 us | -2.4% | -2.2% |
| `layout/cachedMeasure/centered` | 3.0 ns | 3.0 ns | 3.0 ns | +0.0% | +0.0% |
| `layout/measure20Widths/centered` | 1.00 ms | 1.02 ms | 1.00 ms | -0.1% | -1.2% |
| `layout/hostPipeline/centered` | 240.25 us | 241.03 us | 240.04 us | -0.1% | -0.4% |
| `layout/relayout/centered` | 97.78 us | 97.83 us | 97.89 us | +0.1% | +0.1% |
| `layout/highlightRegions/centered` | 9.22 us | 8.08 us | 8.34 us | -9.6% | +3.2% |
| `layout/linkRuns/centered` | 7.71 us | 5.58 us | 5.55 us | -28.1% | -0.6% |
| `layout/coldMeasure/long` | 11.36 ms | 12.54 ms | 12.13 ms | +6.8% | -3.3% |
| `layout/cachedMeasure/long` | 3.0 ns | 3.0 ns | 3.0 ns | +0.0% | +0.0% |
| `layout/measure20Widths/long` | 212.56 ms | 215.71 ms | 215.20 ms | +1.2% | -0.2% |
| `layout/hostPipeline/long` | 11.55 ms | 12.75 ms | 12.80 ms | +10.7% | +0.3% |
| `layout/relayout/long` | 20.94 ms | 10.77 ms | 10.45 ms | -50.1% | -3.0% |
| `layout/highlightRegions/long` | 886.86 us | 1.04 ms | 1.05 ms | +18.0% | +0.7% |
| `layout/linkRuns/long` | 740.33 us | 657.49 us | 641.00 us | -13.4% | -2.5% |
| `layout/coldMeasure/cjk` | 796.62 us | 800.10 us | 790.20 us | -0.8% | -1.2% |
| `layout/cachedMeasure/cjk` | 3.0 ns | 3.0 ns | 3.0 ns | +0.0% | +0.0% |
| `layout/measure20Widths/cjk` | 4.50 ms | 4.49 ms | 4.35 ms | -3.4% | -3.2% |
| `layout/hostPipeline/cjk` | 805.45 us | 809.90 us | 788.78 us | -2.1% | -2.6% |
| `layout/relayout/cjk` | 399.71 us | 198.51 us | 199.11 us | -50.2% | +0.3% |
| `layout/highlightRegions/cjk` | 31.55 us | 54.97 us | 54.41 us | +72.4% | -1.0% |
| `layout/linkRuns/cjk` | 22.33 us | 32.45 us | 31.60 us | +41.5% | -2.6% |
| `layout/coldMeasure/rtlMedium` | 761.13 us | 730.45 us | 735.12 us | -3.4% | +0.6% |
| `layout/cachedMeasure/rtlMedium` | 3.0 ns | 3.0 ns | 4.0 ns | +33.3% | +33.3% |
| `layout/measure20Widths/rtlMedium` | 2.28 ms | 2.19 ms | 2.19 ms | -3.8% | +0.1% |
| `layout/hostPipeline/rtlMedium` | 1.01 ms | 949.31 us | 963.88 us | -5.0% | +1.5% |
| `layout/relayout/rtlMedium` | 217.95 us | 217.44 us | 222.39 us | +2.0% | +2.3% |
| `layout/highlightRegions/rtlMedium` | 32.79 us | 42.09 us | 42.74 us | +30.4% | +1.6% |
| `layout/linkRuns/rtlMedium` | 24.93 us | 27.24 us | 27.94 us | +12.1% | +2.6% |
| `layout/coldMeasure/rtl` | 2.14 ms | 2.04 ms | 2.06 ms | -3.8% | +0.6% |
| `layout/cachedMeasure/rtl` | 3.0 ns | 3.0 ns | 4.0 ns | +33.3% | +33.3% |
| `layout/measure20Widths/rtl` | 7.57 ms | 7.52 ms | 7.54 ms | -0.5% | +0.3% |
| `layout/hostPipeline/rtl` | 2.84 ms | 2.83 ms | 2.88 ms | +1.4% | +1.9% |
| `layout/relayout/rtl` | 750.74 us | 761.57 us | 753.92 us | +0.4% | -1.0% |
| `layout/highlightRegions/rtl` | 49.87 us | 96.42 us | 97.58 us | +95.7% | +1.2% |
| `layout/linkRuns/rtl` | 34.88 us | 55.19 us | 55.21 us | +58.3% | +0.0% |
| `layout/coldMeasure/emoji` | 1.44 ms | 1.41 ms | 1.44 ms | +0.3% | +2.0% |
| `layout/cachedMeasure/emoji` | 3.0 ns | 3.0 ns | 3.0 ns | +0.0% | +0.0% |
| `layout/measure20Widths/emoji` | 6.56 ms | 6.35 ms | 6.36 ms | -2.9% | +0.3% |
| `layout/hostPipeline/emoji` | 1.42 ms | 1.39 ms | 1.44 ms | +1.1% | +3.2% |
| `layout/relayout/emoji` | 712.32 us | 350.44 us | 360.18 us | -49.4% | +2.8% |
| `layout/highlightRegions/emoji` | 13.0 ns | 13.0 ns | 13.0 ns | +0.0% | +0.0% |
| `layout/linkRuns/emoji` | 31.20 us | 54.51 us | 56.09 us | +79.8% | +2.9% |
| `layout/coldMeasure/attachments` | 442.09 us | 438.99 us | 455.92 us | +3.1% | +3.9% |
| `layout/cachedMeasure/attachments` | 3.0 ns | 3.0 ns | 3.0 ns | +0.0% | +0.0% |
| `layout/measure20Widths/attachments` | 5.82 ms | 5.73 ms | 5.81 ms | -0.3% | +1.3% |
| `layout/hostPipeline/attachments` | 449.06 us | 441.29 us | 455.53 us | +1.4% | +3.2% |
| `layout/relayout/attachments` | 580.69 us | 289.42 us | 286.78 us | -50.6% | -0.9% |
| `layout/highlightRegions/attachments` | 62.30 us | 64.60 us | 67.92 us | +9.0% | +5.1% |
| `layout/linkRuns/attachments` | 4.60 us | 8.59 us | 8.64 us | +87.7% | +0.6% |
| `layout/containerFirst/medium` | 242.93 us | 196.58 us | 199.09 us | -18.0% | +1.3% |
| `layout/multiProposal/medium` | 324.00 us | 271.90 us | 279.76 us | -13.7% | +2.9% |
| `layout/heightOnlyRelayout/medium` | 489.0 ns | 480.0 ns | 494.0 ns | +1.0% | +2.9% |
| `layout/containerFirst/rtlMedium` | 966.47 us | 935.45 us | 953.56 us | -1.3% | +1.9% |
| `layout/multiProposal/rtlMedium` | 1.12 ms | 1.07 ms | 1.10 ms | -1.3% | +2.7% |
| `layout/heightOnlyRelayout/rtlMedium` | 109.01 us | 106.88 us | 109.76 us | +0.7% | +2.7% |
| `layout/containerFirst/rtl` | 2.86 ms | 2.78 ms | 2.81 ms | -1.7% | +1.2% |
| `layout/multiProposal/rtl` | 3.37 ms | 3.29 ms | 3.32 ms | -1.3% | +0.9% |
| `layout/heightOnlyRelayout/rtl` | 397.76 us | 386.10 us | 394.52 us | -0.8% | +2.2% |
| `layout/containerFirst/long` | 33.08 ms | 22.68 ms | 22.91 ms | -30.8% | +1.0% |
| `layout/multiProposal/long` | 54.80 ms | 43.45 ms | 44.91 ms | -18.0% | +3.4% |
| `layout/heightOnlyRelayout/long` | 142.09 us | 136.17 us | 135.19 us | -4.9% | -0.7% |
| `draw/full/short` | 1.70 us | 1.66 us | 1.66 us | -2.4% | -0.2% |
| `draw/full/medium` | 32.20 us | 30.71 us | 30.94 us | -3.9% | +0.7% |
| `draw/full/centered` | 32.73 us | 30.92 us | 30.90 us | -5.6% | -0.1% |
| `draw/full/long` | 12.47 ms | 11.33 ms | 11.99 ms | -3.9% | +5.8% |
| `draw/full/cjk` | 168.58 us | 163.03 us | 164.32 us | -2.5% | +0.8% |
| `draw/full/rtlMedium` | 93.36 us | 89.44 us | 90.52 us | -3.0% | +1.2% |
| `draw/full/rtl` | 291.07 us | 284.32 us | 287.20 us | -1.3% | +1.0% |
| `draw/full/emoji` | 575.55 us | 563.19 us | 575.53 us | -0.0% | +2.2% |
| `draw/full/attachments` | 62.39 us | 60.49 us | 62.54 us | +0.2% | +3.4% |
| `draw/visibleWindow900/long` | 125.59 us | 119.35 us | 120.99 us | -3.7% | +1.4% |
| `query/rectsSmallRange/medium` | 360.0 ns | 353.0 ns | 424.0 ns | +17.8% | +20.1% |
| `query/rectsLargeRange/medium` | 554.0 ns | 1.11 us | 1.55 us | +180.5% | +40.5% |
| `query/textIndex1000/medium` | 267.12 us | 263.33 us | 270.01 us | +1.1% | +2.5% |
| `query/nearestTextIndex1000/medium` | 267.89 us | 255.16 us | 260.65 us | -2.7% | +2.2% |
| `query/rectsSmallRange/long` | 33.68 us | 598.0 ns | 749.0 ns | -97.8% | +25.3% |
| `query/rectsLargeRange/long` | 38.05 us | 155.13 us | 292.67 us | +669.3% | +88.7% |
| `query/textIndex1000/long` | 3.42 ms | 3.36 ms | 3.41 ms | -0.2% | +1.3% |
| `query/nearestTextIndex1000/long` | 5.52 ms | 5.39 ms | 5.41 ms | -1.8% | +0.5% |
| `query/rectsSmallRange/cjk` | 645.0 ns | 291.0 ns | 351.0 ns | -45.6% | +20.6% |
| `query/rectsLargeRange/cjk` | 775.0 ns | 5.48 us | 7.08 us | +814.2% | +29.3% |
| `query/textIndex1000/cjk` | 210.49 us | 208.67 us | 216.73 us | +3.0% | +3.9% |
| `query/nearestTextIndex1000/cjk` | 215.44 us | 200.68 us | 211.41 us | -1.9% | +5.3% |
| `query/rectsSmallRange/rtl` | 598.0 ns | 5.19 us | 18.05 us | +2918.6% | +247.7% |
| `query/rectsLargeRange/rtl` | 628.0 ns | 123.39 us | 757.46 us | +120514.6% | +513.9% |
| `query/textIndex1000/rtl` | 263.04 us | 257.35 us | 253.72 us | -3.5% | -1.4% |
| `query/nearestTextIndex1000/rtl` | 323.70 us | 305.79 us | 308.54 us | -4.7% | +0.9% |
| `query/visibleLineCount900/long` | 899.0 ns | 3.43 us | 3.47 us | +285.8% | +1.1% |
| `query/visibleLineCountAll/long` | 7.0 ns | 7.0 ns | 7.0 ns | +0.0% | +0.0% |
| `streaming/layoutPerChunk/reply4KB` | 119.72 ms | 120.54 ms | 124.14 ms | +3.7% | +3.0% |
| `streaming/layoutPerChunk/reply16KB` | 1110.28 ms | 1140.35 ms | 1166.94 ms | +5.1% | +2.3% |
| `streaming/viewPerChunk/reply4KB` | 129.72 ms | 126.90 ms | 129.23 ms | -0.4% | +1.8% |
| `streaming/viewRenderPerChunk/reply4KB` | 219.46 ms | 222.38 ms | 217.55 ms | -0.9% | -2.2% |
| `streaming/viewRenderPerChunk/reply16KB` | 1849.88 ms | 1855.99 ms | 1823.39 ms | -1.4% | -1.8% |
| `view/createSizeLayout/short` | 17.17 us | 18.08 us | 18.11 us | +5.4% | +0.1% |
| `view/createSizeLayoutRender/short` | 53.70 us | 54.51 us | 54.28 us | +1.1% | -0.4% |
| `view/createSizeLayout/medium` | 167.34 us | 168.86 us | 169.69 us | +1.4% | +0.5% |
| `view/createSizeLayoutRender/medium` | 323.57 us | 327.12 us | 325.12 us | +0.5% | -0.6% |
| `view/createSizeLayout/centered` | 264.73 us | 265.67 us | 262.62 us | -0.8% | -1.1% |
| `view/createSizeLayoutRender/centered` | 419.98 us | 419.60 us | 421.79 us | +0.4% | +0.5% |
| `view/createSizeLayout/long` | 12.38 ms | 13.33 ms | 13.11 ms | +5.9% | -1.7% |
| `view/createSizeLayout/cjk` | 855.56 us | 877.81 us | 874.47 us | +2.2% | -0.4% |
| `view/createSizeLayoutRender/cjk` | 1.57 ms | 1.59 ms | 1.59 ms | +1.7% | +0.2% |
| `view/createSizeLayout/rtlMedium` | 997.86 us | 1.00 ms | 1.00 ms | +0.6% | -0.1% |
| `view/createSizeLayoutRender/rtlMedium` | 1.75 ms | 1.74 ms | 1.69 ms | -3.7% | -2.9% |
| `view/createSizeLayout/rtl` | 2.88 ms | 2.95 ms | 2.95 ms | +2.4% | +0.0% |
| `view/createSizeLayoutRender/rtl` | 5.15 ms | 5.01 ms | 5.25 ms | +2.1% | +4.9% |
| `view/createSizeLayout/emoji` | 1.40 ms | 1.43 ms | 1.40 ms | -0.1% | -2.2% |
| `view/createSizeLayoutRender/emoji` | 2.73 ms | 2.72 ms | 2.72 ms | -0.4% | -0.0% |
| `view/createSizeLayout/attachments` | 580.47 us | 592.46 us | 599.80 us | +3.3% | +1.2% |
| `view/createSizeLayoutRender/attachments` | 894.35 us | 913.03 us | 919.73 us | +2.8% | +0.7% |
| `view/cellReuse200/ltr` | 18.23 ms | 18.63 ms | 18.63 ms | +2.2% | +0.0% |
| `view/cellReuse200/rtl` | 105.01 ms | 105.09 ms | 105.05 ms | +0.0% | -0.0% |
| `view/cellReuse200/centered` | 28.70 ms | 28.66 ms | 28.99 ms | +1.0% | +1.1% |
| `interaction/selectionDrag100/long+200siblings` | 7.96 ms | 4.93 ms | 4.87 ms | -38.7% | -1.1% |
| `interaction/doubleClickWordNearEnd/long` | 1.47 ms | 1.47 ms | 1.57 ms | +6.2% | +6.7% |
| `interaction/doubleClickWordNearStart/long` | 36.62 us | 1.48 ms | 40.90 us | +11.7% | -97.2% |
| `memory/renderedLayerBackedView/medium` | 197.76 us | 104.69 us | 106.92 us | -45.9% | +2.1% |
| `memory/renderedLayerBackedView/long` | 429.63 us | 249.13 us | 248.94 us | -42.1% | -0.1% |
| `swiftui/hostingFittingSize/medium` | 212.24 us | 253.48 us | 252.79 us | +19.1% | -0.3% |

## Peak memory footprint

| Group | 2.2.2 | Current | Δ |
|---|---:|---:|---:|
| layout | 36.8 MB | 38.5 MB | +1.7 MB |
| draw | 126.0 MB | 125.3 MB | −0.7 MB |
| query | 26.1 MB | 24.9 MB | −1.2 MB |
| streaming | 47.3 MB | 43.2 MB | −4.1 MB |
| view | 41.0 MB | 40.1 MB | −0.9 MB |
| interaction | 33.8 MB | 31.8 MB | −2.0 MB |
| memory | 44.1 MB | 43.8 MB | −0.3 MB |
| swiftui | 14.0 MB | 20.3 MB | +6.3 MB |
