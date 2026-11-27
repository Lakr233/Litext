# Tiled drawing

Measured on 2026-11-27 on an Apple silicon Mac virtual machine with a 1x display, on macOS 27, in a Mac Catalyst chat app that shows each reply in one label 730 points wide. The code is in `TextLabelView+Tiles.swift`.

## Why it exists

A view that implements `draw(_:)` gets one backing store the size of its bounds. A chat reply of a hundred thousand characters is a label about 46,000 points tall, so its backing store is a bitmap that tall, held while the row is mounted and drawn again whole whenever the text changes. In a profile of a streamed update near the end of such a reply, Core Animation displaying the label was 53% of the main thread's time.

A label whose host sets `tiledDrawing` keeps no contents of its own once it is taller than `TiledDrawing.threshold`. Sublayers 512 points tall draw the lines that cross them through the label's own `draw(_:)`, and only the tiles within `TiledDrawing.reach` of what is on screen exist.

It is off unless a host asks. A label that is not tiled differs from one before this change only in the class of its layer, which passes everything to `CALayer` until the label is tiled.

## Knowing where the label is

A tiled label has to know which part of it is on screen, and nothing tells a view that. Four ways were tried before the one that stayed.

| Way | What happened |
|---|---|
| Look as every turn of the main run loop ends | UIKit commits a turn's changes before the run loop's observers run, so a scroll further than the reach showed one frame without text. |
| Observe `contentOffset` of the scroll view | No change is reported when Swift code sets the offset through a subclass's own override, which is how a list scrolls itself. |
| `UIUpdateLink`, before the commit | Right on iOS 18, and unavailable in Mac Catalyst. |
| Ask Core Animation to display a layer on every turn, and look from there | The look comes at the right moment, in the commit after layout. But a layer asking to be displayed has UIKit schedule an update, which is another turn that asks again: an idle window went from about 90 wake-ups a second to 170. |

What stayed:

- The label observes `bounds` of every scroll view above it. Every scroll changes them whoever asked, and the label looks in that call, so the tiles are made before the frame is committed however far the scroll went.
- A scroll also asks Core Animation to display a one-point layer the label keeps for that. Core Animation draws it in the commit once layout is over, and its drawing is a second look, at where the layout of that frame left the label. Only a scroll asks, so nothing is scheduled while nothing moves.
- The label's own layout pass looks. A host that moves the label without scrolling, as a list does when it measures the rows above a row and shifts every row below, asks for that pass with `setNeedsLayout()` in the layout pass that moved it, and the tiles are in the same frame. The chat app does this from its list's layout: before it did, random sequences of resizes found frames in which a reply had been moved several thousand points and its tiles had not yet followed.
- As every turn of the main run loop ends the label looks once more, for the moves nothing reports: an ancestor's frame, a view hidden or shown. Those tiles can come a commit late, which the reach covers unless the label moved further than that in one step.

With these, an idle window wakes as often with tiled labels as without: 125 times a second either way in the test app, whose other windows account for all of them.

While an ancestor animates, the label keeps tiles both where it will rest and where its presentation layers show it, and up to eight tiles between.

## The same pixels

`LitextTiledDrawingTests` composes the tiles of a label and compares them byte for byte with the same label drawn into one backing store: at scales 1, 2 and 3, in dark mode, at random scroll offsets, and after the text and the width change. They are equal.

In the app, a second list beside the first showed the same conversation with tiling off, and both were captured after the same changes.

| Check | Result |
|---|---|
| 594 pairs of captures: six documents scrolled a screen at a time, both right after each scroll and at rest, rows removed and restored with time frozen at seven moments, a stream, and the lists placed off the pixel grid | 418 identical. 127 differ by one or two levels of a channel in a few pixels, 3,831 pixels in all. 49 differ along single rows, all in the captures with time frozen. |
| 1,115 commits during that run | In every one, each visible part of each tiled label had a drawn tile under it. |
| 235 captures of the app with tiles, against the same captures from the released version | 199 identical, 36 within two levels, none beyond. |
| The same 235 with tiling off | All identical. |

The 49 are not the tiles. The rows that differ lie 256 rows apart in the label, on a grid the 512 point tiles do not account for, and they stayed where they were when the tiles were made 500 points tall. Captures of the two tile heights are identical to each other in all of them. Core Animation shows a bitmap as tall as these in strips of 256 rows, and in some states draws the row where two strips meet a little off: with time frozen, and also at rest in dark mode at some widths, where random sequences of scrolls, resizes, streams and appearance changes turned up six more such rows in 713 comparisons, each at an odd multiple of 256 rows into the label, where no tile ends. Those sequences found no other difference beyond rounding.

The one or two levels are Core Graphics rounding an antialiased edge differently depending on where in its bitmap the edge falls. Tiles 500 and 512 points tall differ from each other the same way, in a few pixels of 26 captures out of 132, by as much as either differs from one backing store.

Two bugs the unit tests found on their first run: a label that got shorter across a tile's edge kept the tile below the edge, a strip one point tall laid over the tile above it, because `CGRect.height` reports a negative height as positive; and asking for the look in the commit drew every tile again, because `CALayer.setNeedsDisplay()` asks for its bounds through `setNeedsDisplay(_:)`, which the label's layer hands to its tiles.

## Seams

Tiles abut. A layer shown off the pixel grid is sampled between its pixels, and at its last row that could read a row it does not have. Each tile holding two rows of its neighbours behind a clip was built to prevent that and removed again: with both lists placed at 0.5, 0.25 and 0.7 of a point, 48 pairs of captures were identical with plain tiles.

## What it costs and saves

A conversation of three replies of 22,000, 56,000 and 113,000 characters, scrolled to the end at 1x:

| | One backing store | Tiles |
|---|---|---|
| Bitmaps of mounted labels | 187 MB | 62 MB |
| Process footprint | 231 MB | about 195 MB |

The 62 MB are the tiles around the screen and every label this host does not tile: code blocks, table cells, and text shorter than the threshold.

Scrolling now draws a tile for every 512 points scrolled, where before the whole reply was already a bitmap. Streaming draws the tiles around the screen instead of the whole reply.

## A capture that was not a frame

One run of the frozen-time captures, on a machine loaded to several times its cores by other work, showed the tiled label without text at the moment a row above it was removed while the middle of the label was on screen: 14 captures of 56. The probe then gave up waiting for a commit after a quarter of a second and captured anyway. Made to wait for the commit, and to count the frames it could not wait for, it has not shown the label without text again: four more runs of the 594 comparisons, at load averages from 3 to 40, each with every frame committed before its capture. One of them, run beside a simulator test, had the two lists a few points apart during one animation, with all the text in both. A capture taken between a change and its commit is not a frame the screen shows, so this is taken to have been the probe; it was never reproduced to prove it.

## The released configuration

With the host's call after its list lays out, on a quiet machine, in two builds of the chat app: one against local checkouts of the libraries, one against Litext 3.7.0 as tagged.

| Check | Result |
|---|---|
| 594 pairs of captures, as above, in each build | First build: no pair differs beyond two levels of a channel; 76 differ within them. Second build: 56 pairs differ, each in the two edges of one inline code pill and nowhere else; 100 more within two levels. No seams of the one bitmap in either. |
| 1,115 commits during each of those runs | Tiles drawn under every visible part of every tiled label. |
| 1,658 checks over five runs of random sequences of jumps, scrolls, resizes, appearance changes, streams and row changes | The only pixels that differ are that pill. Tiles under everything visible in every commit, except the first two commits of one row animation, where the tiles were where the label was still shown and not yet where it would rest. |
| 235 captures against the released version, below the list's top edge effect | With tiles: 198 identical, 34 within two levels, 3 with that pill. Without, in the second build: all identical. |

The pill is not the tiles. MarkdownView draws the first inline code a process builds four points wider than every other, the host's list now builds rows ahead of a scroll in an order that depends on timing, and so the wider pill lands in one list in one run and in the other, or in neither capture, in the next. The capture comparisons without tiles show it too: three captures in the first build, none in the second.

In the second build, with tiles and without, the machine otherwise idle:

| | One backing store | Tiles |
|---|---|---|
| Bitmaps of mounted labels after opening the conversation | 281 MB | 92 MB |
| Process footprint after opening / after a stream | 303 / 434 MB | 210 / 306 MB |
| A scroll frame, median | 0.15 ms | 0.18 ms |
| Slowest frame in three scrolls through the conversation | 6 ms | 9 ms |
| A streamed update at 111,000 characters, layout and commit | 25 ms | 9 ms |
| A frame of a resize that rewraps the text, median / mean | 26 / 25 ms | 3 / 8 ms |

The host mounts rows ahead of a scroll, which is why one bitmap costs it more than the table further down says. Tiles save memory, and the drawing of a whole reply on every streamed update and every step of a resize; a scroll frame costs about 0.03 ms more with them. An earlier run of this comparison, made while another build was using the machine, showed 19 frames over 16.7 ms in a first scroll with one backing store and none with tiles. Idle, the slowest frame of a first scroll is 6 ms with one backing store and 9 ms with tiles, or 12 ms and 17 ms when a frame is timed through the run loop's own commit and not a flushed transaction.

Not run: the app on a 2x display. The unit tests compare tiles with one bitmap at 2x and 3x; how Core Animation shows abutting tiles at 2x was only seen at 1x, with the lists placed at fractions of a point.

## Limits

- A move by anything other than a scroll, further than the reach, in one step, by code that commits it before the run loop comes around, shows a frame without text there. No case of it was found in the app.
- `CALayer.render(in:)` on a tiled label draws the whole text into one backing store for as long as the rendering takes.
- A label an animation carries further than eight tiles shows no text between where it started and where it rests.
- A snapshot taken through the render server, such as `snapshotView(afterScreenUpdates:)`, holds the tiles that exist: what is near the screen, and nothing of the rest of a tall label.
- A subclass that returns its own `layerClass` is never tiled.
- Observing `bounds` makes the scroll views above a tiled label instances of a key-value observing subclass for as long as the label is in a window.
