# Animatable label: partial redraws

Measured on 2026-10-02 with Xcode 27.0, on macOS 27 and an iOS 27 simulator, on an Apple silicon Mac. It decides how `LTXAnimatableLabel` redraws on each animation frame.

## The question

An animation frame changes a few lines. The label can only stay cheap per frame if drawing that frame costs those lines and not the whole text. The original plan was to redraw with `setNeedsDisplay(_:)` on the lines' rect, and to cull drawing to `context.boundingBoxOfClipPath` in case the platform hands `draw(_:)` more than the dirty rect.

The measurements below put a `TextLabelView` subclass that records what `draw(_:)` receives into a window, let one full display pass run, invalidate a 50 × 20 pt rect, and record the next pass.

## What the platforms do

| Request | `draw(_:)` rect | Clip box |
|---|---|---|
| macOS, layer-backed view, one rect | the rect | the rect |
| macOS, two rects in one pass | their bounding box | their bounding box |
| iOS, view, any rect | the whole bounds | the whole bounds |
| iOS, standalone sublayer, one rect | — | the rect |

- **macOS** honours partial invalidation for a layer-backed `NSView`. Several rects in one pass are merged into their bounding box, so drawing several far-apart rects costs the band between them.
- **iOS** repaints a view's whole backing store for any `setNeedsDisplay(_:)`, and the clip box is the whole bounds too. Culling to the clip box cannot help there. A plain `CALayer` that is not a view's layer does receive only the invalidated rect.
- On both platforms the layer contents of a view's sublayer are already flipped to a top-left origin when Core Animation calls `draw(in:)`. `contentsAreFlipped()` reports this, and the label checks it rather than assuming it.

## The design that follows

Redrawing the label's own backing store on every frame would cost the whole text on iOS. So while it animates, the label splits itself into two areas:

- **The animation region** is the strips of the lines touching the animator's `animatingRange`, plus its `additionalContentBounds`, widened by its `overdrawInsets` and rounded out to whole pixels. A strip spans the label's width and reaches halfway into the gap to the neighbouring lines. A sublayer covers exactly this region, draws everything in it, and is the only thing redrawn per frame. Because it is a plain layer, iOS redraws only the invalidated part of it.
- **Everything else** is drawn by the label's own backing store, as `TextLabelView` draws it, with the region clipped out, so nothing is drawn twice. The label redraws it only when the text changes or the region moves, as when a line starts or finishes animating. The layer's move and the label's redraw happen in the same transaction, with implicit actions off, so no frame shows the text twice or not at all.

Further details:

- The sublayer sits at `zPosition` −1. A layer's own contents stay behind all of its sublayers, so the text stays above the label's backing store, and the selection, link highlights and attachment views stay above the text.
- The region may extend outside the label's bounds, which is how an effect draws past them. A view cannot do that from its own `draw(_:)`.
- When the animation ends, the layer is removed and the label redraws the region it gave back. An idle label has exactly the layers and subviews of a `TextLabelView`.

## Cost per frame

Measured on macOS with a release build. The label holds a 16,000-character text at 400 pt wide: 308 lines and 5,545 pt tall. The last line is in flight.

| Work | Time |
|---|---|
| One frame of bookkeeping: animator step, region, invalidation | 0.35 µs |
| Drawing the animation layer: one line strip | 6 µs |
| Drawing the whole label, for comparison | 1,840 µs |

The frame bookkeeping is two binary searches and a few rect operations. It allocates nothing: the invalidation context is reused, and line geometry comes from an index built once per layout pass.

## How it is tested

- `LTXAnimatableLabelTests` counts redraw requests. Thirty frames that invalidate the line in flight redraw only the animation layer. A frame that invalidates nothing redraws nothing. The label redraws once when the line finishes and once when the animation ends.
- A composite test draws the label's own drawing and then the animation layer over its region, and compares the result byte for byte with a plain `TextLabelView`.
