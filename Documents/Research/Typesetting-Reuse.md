# Typesetting reuse

Measured on 2026-10-04 on an Apple silicon Mac, against the 3.5.0 tag.

## Why it exists

A host that streams a document, such as a chat transcript rendering an answer token by token, assigns the whole document to the label on every update. Each assignment built a new layout that typeset the whole string again. In MarkdownView's `stream/tail_16` benchmark, where every update carries a long document, CoreText took about 58% of each update: `CTFramesetterCreateWithAttributedString` about 24% and `CTFramesetterCreateFrame` about 34%. Everything before the last paragraph was typeset to the same lines every time.

`TextLabel.Layout.reuseTypesetting(from:)` hands a new layout the lines the previous one laid out. `TextLabelView` calls it for every new string.

## How it works

The new layout looks for the first character whose text, attributes or attachment metrics differ from the previous string. Lines are reused up to the paragraph before the one holding that character, the anchor. The anchor and everything after it are typeset again. The anchor's first line matches the previous layout's line, and it places the new lines, because CoreText spaces each line from the one before it. The fuzz test in `LitextTypesettingReuseTests` streams rich text through both paths and holds every line's range, origin and box, the measured size and the highlight regions to the whole-string layout.

Paragraphs break independently in CoreText, so a reused line is the line typesetting the whole string would make. A changed attribute is found run by run. A host that builds each string from the pieces of the last one hands over the same attribute dictionaries, which compare by identity. Attachments are compared by the metrics their run delegates reported, since CoreText reads those once per framesetter.

The layout also stopped building its framesetter in `init`. A layout that reuses lines never needs one.

## Keeping offsets

A reused line has to index the layout's own string: `LayoutLine.line`, line drawing actions and animators read string indices straight from the `CTLine`. So the tail is typeset in a string of the full length whose text before the anchor is spaces, ending with the separator before the anchor so the anchor still starts a paragraph.

Typesetting only the substring would be faster and lighter, but every index read from its lines would be off by the anchor's offset.

The measurements below use a 29,344-character document with the change in its last 543 characters:

| Typesetting | Time |
|---|---|
| The whole string | 4.004 ms |
| Spaces before the anchor, frame over the tail | 0.446 ms |
| The tail as its own string | 0.173 ms |
| Comparing the prefix with `isEqual(to:)` | 0.438 ms |
| Comparing the prefix run by run, dictionaries by identity first | 0.012 ms |

## Memory

A `CTLine` keeps the whole string its framesetter typeset alive, along with CoreText's storage for it. With a 30,000-character placeholder, each retained pass held about 700 KB, whatever the placeholder characters were; a line typeset from the substring held about 9 KB. Lines from many passes would keep many such strings alive. Every fill records which pass made each line and how long that pass's string was. When the strings its lines keep alive add up to more than four times the string's length, the layout typesets the whole string again and lets them go. A stream then reuses lines on about three updates out of four.

## Cost

`perf_probe.sh` at 60 iterations, five runs of each revision interleaved, best run of each:

| Scenario | 3.5.0 | With reuse | Ratio |
|---|---|---|---|
| `fullDrawMS` | 10.650 | 10.033 | 0.942 |
| `visibleDrawMS` | 0.114 | 0.110 | 0.965 |
| `layoutMS` | 12.556 | 12.483 | 0.994 |
| `highlightMS` | 13.618 | 13.717 | 1.007 |

These are within noise: the probe assigns each string once, so it never reuses anything.

MarkdownView's benchmark against a local build, with MarkdownView's rebuilt attachments and list markers comparing equal by value so its prefixes match. Best of three interleaved runs, `op_ms`:

| Case | 3.5.0 | With reuse | Ratio |
|---|---|---|---|
| `stream/4` | 0.684 | 0.352 | 0.515 |
| `stream/16` | 3.109 | 1.315 | 0.423 |
| `stream/tail_16` | 6.955 | 3.177 | 0.457 |
| `stream/quote_heavy` | 1.124 | 0.392 | 0.349 |
| `stream/hosted/4` | 1.224 | 0.689 | 0.563 |
| `stream/hosted/quote_heavy` | 2.132 | 1.030 | 0.483 |

Every other case stayed within noise.

Part of the hosted gain is a separate fix. A label measures its text at an unbounded height, and its layout pass measures again at `maxLayoutHeight`. The two proposals clamp to the same path, but the measurement cache matches proposals, so the same string was typeset twice per update. A fill already made for the same path is now reused.
