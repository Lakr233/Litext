# Typesetting in passes

Measured on 2026-11-27 on an Apple silicon Mac virtual machine with a 1x display, on macOS 27, against the commits after the 3.6.7 tag. `Typesetting-Reuse.md` covers the streamed edit this builds on.

## Why it exists

A chat reply of a hundred thousand characters is one label. Typesetting it took far longer than its length explains, and the time grew with the square of the length.

CoreText breaks a line that holds a run delegate by copying the rest of its typesetter's text. A run delegate is how every attachment reserves its space, and a Markdown document has one for each bullet, list number, code block and table. One typesetter over the whole string therefore spends, on each such line, time in proportion to everything after it: about 10.7 ns for every UTF-16 unit after the line.

| Document | Run delegates | With the delegates | Without them |
|---|---|---|---|
| 59,500 units | 640 | 214 ms | 13 ms |
| 180,000 units | not recorded | 1,974 ms | not measured |

## How it works

`TextLabel.Layout.makeFillInPasses(pathSize:)` typesets such a string a stretch of paragraphs at a time. Each stretch has a typesetter of its own whose string ends with the stretch, so a line pays only for the rest of its stretch. The passes are chained the way a streamed edit already was: each begins at a paragraph the pass before it also typeset, checks that it breaks that paragraph's first line the same way, and takes its position from it.

A string is typeset in passes when it is longer than 10,240 units, holds more than one run delegate, and its delegates times its length come to at least twice `PassPolicy.workPerPass`. A pass ends at a paragraph boundary once the delegates in it times its length reach that work.

Three things the passes need to give the lines one frame gives:

- **CoreText breaks a string longer than 10,240 units by another path than a shorter one's**, and not always in the same places. Only strings past that length are typeset in passes, every pass string is padded past it with a trailing paragraph of spaces that no pass lays out, and an edit that takes a string across the length typesets the whole string.
- **A paragraph that ends in a carriage return and a line feed can anchor the next pass.** It could not anchor a streamed edit before, which typeset the whole string instead.
- **The last paragraph of a pass is typeset again by the next one**, so no line but the very last comes from the end of a typesetter's string.

`LitextTypesettingReuseTests` holds every line's range, origin and box, the measured size and the highlight regions to a layout typeset in one frame, over random documents, widths and policies.

## Memory

A pass's lines keep its whole string alive, at about 23 bytes a unit, so more passes cost more memory. A whole typeset takes at most `PassPolicy.maximumPasses`, twelve: past that the passes get longer instead.

| Document | One frame | Twelve passes at most |
|---|---|---|
| 59,500 units, 640 delegates | 10.89 MB | 15.64 MB |
| 180,000 units | 23.87 MB | 31.83 MB |

Without the limit the two layouts held 20.7 MB and 118 MB.

A streamed edit used to add a pass for every update, and the limit on retained text answered by typesetting the whole string again every fourth update. An edit now folds the short passes before it into its own (`anchorFoldingShortPasses`), so passes grow like the digits of a binary counter and a stream never typesets the whole string again.

## Time

Timed before the limit of twelve passes was added, with more and shorter passes, the two documents above took 34 ms and 144 ms. They have not been timed with the limit.

MarkdownView's benchmark, a release build for macOS, on a document of 160 sections, about a hundred thousand characters:

| Case | Before | With passes |
|---|---|---|
| `stream/tail_160`, one update at the end | 57.8 ms | 7.8 ms |
| `scale/cold_build/160`, a new view | 553 ms | 374 ms |
| `scale/build/160` | 92.8 ms | 57 ms |

## A new width

Typesetting the same layout at another width, as every frame of a resize does, built every pass's string and framesetter again, although neither depends on the width. In a profile of a resize in a Mac Catalyst chat app with a 113,000 character reply on screen, that was more of a typeset than breaking the lines was:

| In `typesetTail`, share of the frame | |
|---|---|
| `CTFramesetterCreateFrame`, which breaks the lines | 17.6% |
| `attributedSubstring(from:)` | 9.8% |
| `CTFramesetterCreateWithAttributedString` | 9.5% |
| `String(repeating:count:)`, the placeholder before the pass | 7.1% |

A layout now keeps each pass's framesetter by the range it lays out, until `invalidateLayout()`. The lines of the current fill already keep those framesetters alive, so this holds no more text. A frame of that resize went from a median of 51 ms to 33 ms; the app typesets the reply twice in a frame, once to measure the row and once to lay it out.

What is left of a frame is mostly CoreText breaking lines (35%), then reading runs for highlight regions (14%). Going further means not breaking the lines nobody sees, which a layout that typesets whole strings cannot do.
