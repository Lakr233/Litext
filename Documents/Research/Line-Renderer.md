# Line renderer

Measured on 2026-10-04, against the 3.4.2 tag.

## Why it exists

`TextLabel.Layout` was the only place to change how a line is drawn, and a label has exactly one layout class. A host that draws behind its lines, such as MarkdownView with the pill behind inline code, and `LTXAnimatableLabel`, whose layout routes lines in flight to the animator, each needed their own subclass, and Swift cannot combine the two. Opening `LTXAnimatableTextLayout` would not have been enough either: an animator that draws a line in flight with `CTLineDraw` leaves out whatever the host's layout draws behind it, so the pill would vanish, or sit at full strength under text that is fading in.

`TextLabel.LineRenderer` moves the drawing of one line out of the layout class. The label hands its renderer to every layout it builds, its subclasses' layouts included, and `LTXAnimatedLine.draw(in:)` draws a line in flight through the same renderer, so an effect fades or moves the background along with the glyphs.

## Cost

A layout without a renderer draws as before, after one `nil` check per line.

`perf_probe.sh` at 60 iterations, four runs of each revision interleaved, best run of each:

| Scenario | 3.4.2 | With the renderer | Ratio |
|---|---|---|---|
| `fullDrawMS` | 11.015 | 10.954 | 0.994 |
| `visibleDrawMS` | 0.113 | 0.113 | 1.000 |
| `layoutMS` | 12.273 | 12.323 | 1.004 |

The first version declared `lineRenderer` on the layout as a plain `public var`. Full draws then came out about 1.5% slower, and every run of the new revision was slower than every run of the old. Declaring it `final` removed the difference: in an open class a property that is not `final` can be overridden, so reading it may go through dynamic dispatch, once per line.
