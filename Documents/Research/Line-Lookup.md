# Line lookup by binary search

Measured on 2026-10-02, against the 3.3.0 tag. This resolves candidate 3 in `Performance-Baseline.md`.

## What changed

Every lookup by position used to find its line by scanning from the first line:

- Hit testing: `textIndex(at:)`, `nearestTextIndex(at:)` and `characterIndex(at:)`, which every touch, click, drag step, pointer move and long press reaches.
- Draw culling: `draw(in:visibleRect:)` and `visibleLineCount(in:)`.

A lookup near the end of a long document therefore paid for every line above it. The lookups now binary-search, using three monotone predicates over the line boxes:

- the first box whose bottom reaches `y`, for the line containing a point;
- the first box wholly below a rect, and the first box whose bottom reaches into it, for culling;
- the first box whose middle is at or below `y`, for the nearest line.

## Why the scan stays

Bisection needs the boxes to descend in order, and they do not always:

- A small `lineHeightMultiple` over mixed font sizes squeezes a large line so that its box reaches above the smaller line before it. For example, `[6, 60, 6, 60, 6]` pt at a multiple of 0.1.
- `maximumLineHeight` alone did not produce out-of-order boxes in testing, because CoreText still orders the boxes it squeezes.

Each layout checks the order once, in `adopt(_:)`. It is one pass over the lines, and relayout timings did not change (see below). A layout whose boxes are out of order keeps the original scan. Either path returns exactly what the scan returned before, including:

- **Ties:** of several lines equally near a point, the earlier one. The bisection compares distances rather than middles, because two middles can differ and still round to the same distance at large coordinates.
- **NaN:** a NaN coordinate takes the scan, whose comparisons with NaN behave differently from the bisection's.
- **Infinite and inverted rects:** these agree on both paths without special handling.

## How it is tested

`Tests/LitextTests/LitextLineLookupTests.swift` covers four things.

**Equivalence fuzzing.** Seeded random layouts mix:
- font sizes from 1 to 60 pt;
- line spacing, paragraph spacing, minimum and maximum line heights, and line height multiples down to 0.1;
- attachments with zero, default and oversized descents;
- container widths from unconstrained to 40 pt, and heights from zero to 1e9.

Each layout is probed at every box edge, middle and baseline, one ULP and a quarter point either side of each, and at random, infinite and NaN values. Every pair of the first probes is also tested as a rect. The test requires both paths to run: of 80 layouts, 38 were ordered and 42 out of order. `LITEXT_FUZZ_SEED` and `LITEXT_FUZZ_ITERATIONS` reproduce or widen a run. Under `LITEXT_STRESS` the fuzz runs the stress iteration count.

**Hostile layouts.** Specific layouts go to the extremes:
- uniform lines, 0.5 pt fonts, squeezed lines, tight multiples, and growing and shrinking font sizes;
- each laid out at its own height and at heights of 0, 1e7, 1e8 and 1e9;
- plus blank lines, an empty layout, and the out-of-order layout above.

**Speed.** The timing tests check that the speedup holds and that the harness can see it:
- The harness must see the scan slow down by more than 20× from 100 to 10,000 lines, or it could not tell linear from logarithmic.
- Bisection must slow down by less than 6× over the same range, and beat the scan on 10,000 lines by more than 30×.
- `nearestTextIndex(at:)`, the public entry point, must cost less than 4× more on 10,000 lines than on 100.

**Mutation testing.** Eight bugs were planted in the source, one at a time, to check that the tests catch them:

| Mutant | Caught by |
|---|---|
| The order check always passes. | The fuzz and the out-of-order layout test. |
| `>=` becomes `>` in the containing-line check. | The fuzz and the empty-layout test. |
| Ties in the nearest line go to the later line. | The fuzz. |
| The nearest line skips the earlier lines at an equal distance. | The fuzz (81 issues). |
| `<` becomes `<=` at the cull boundary. | The fuzz. |
| The NaN guard is removed. | The fuzz and the empty-layout test. |
| The order check skips the middles. | Not caught. When bottoms and tops descend, middles do too; the check is kept only as insurance against rounding. |
| The containing-line lookup always scans. | Both speed tests. |

## Measurements

These are release builds on an Apple silicon Mac, running on macOS. Each figure is the best of three runs, and each run takes the median of 15 samples of about 10 ms each.

The documents are lines of about 40 characters at 13 pt in a 360 pt column. Lookups target the bottom of the document, where the scan does the most work. Times are per call, in microseconds.

| Lines | Operation | 3.3.0 | Bisection | Speedup |
|---|---|---|---|---|
| 100 | `nearestTextIndex` | 0.252 | 0.157 | 1.6× |
| 100 | `textIndex` | 0.258 | 0.159 | 1.6× |
| 100 | `characterIndex` | 0.825 | 0.725 | 1.1× |
| 100 | `visibleLineCount` | 0.333 | 0.068 | 4.9× |
| 100 | `drawBottomWindow` | 62.5 | 64.1 | 1.0× |
| 1,200 | `nearestTextIndex` | 1.655 | 0.180 | 9.2× |
| 1,200 | `textIndex` | 1.655 | 0.185 | 8.9× |
| 1,200 | `characterIndex` | 2.247 | 0.758 | 3.0× |
| 1,200 | `visibleLineCount` | 2.561 | 0.111 | 23.1× |
| 1,200 | `drawBottomWindow` | 50.2 | 48.6 | 1.0× |
| 10,000 | `nearestTextIndex` | 12.976 | 0.209 | 62.1× |
| 10,000 | `textIndex` | 12.972 | 0.209 | 62.1× |
| 10,000 | `characterIndex` | 13.629 | 0.784 | 17.4× |
| 10,000 | `visibleLineCount` | 20.531 | 0.151 | 136.0× |
| 10,000 | `drawBottomWindow` | 69.3 | 47.8 | 1.4× |

`characterIndex` gains less than the other lookups, because measuring within the line still walks its characters. Drawing a 900 pt window is dominated by rendering the glyphs, so culling only shows on the longest document.

The order check runs on every layout. Relayout times, alternating the width between 360 and 361 pt, did not move:

| Lines | 3.3.0 (µs) | Bisection (µs) |
|---|---|---|
| 100 | 83.3 | 83.5 |
| 1,200 | 1,010 | 1,034 |
| 10,000 | 9,011 | 8,995 |

The 1,200-line difference is within run-to-run noise.
