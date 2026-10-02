# Pointer tracking during a resize

Measured on 2026-10-02, against the 3.3.1 tag, on an Apple silicon Mac.

## What changed

AppKit calls `updateTrackingAreas()` on every view whose frame, or whose ancestor's frame, changes. While a window resizes that is every label on screen, once per step of the drag.

The label used to remove every tracking area it owned and add a new one sized to its bounds each time. It now adds one area, with `.inVisibleRect`, the first time, and leaves it in place afterwards. AppKit keeps an `.inVisibleRect` area matched to the visible rect itself, so the area needs no rebuilding when the frame changes.

The area is marked in its `userInfo`, so the check finds it among areas a subclass adds. The old code removed those areas too; they now survive the update.

## Measurement

A markdown document with many labels was swept between 900 and 1700 pt wide for ten seconds, under the Time Profiler, alternating the old and new builds:

| Samples in | 3.3.1 | Now |
|---|---|---|
| `TextLabelView.updateTrackingAreas()` | 147, 128 | 85, 82 |
| AppKit's `updateTrackingAreasWithInvalidCursorRect` | 431, 504 | 407, 396 |
| The whole sweep | 8587, 7765 | 7637, 7777 |

The label's own share fell by about 40%, to about 1% of the sweep. Most of what is left is the check itself: the `trackingAreas` bridge and the `userInfo` lookup. The larger cost is AppKit walking the view tree to update its tracking areas, which the label cannot avoid. The whole sweep moved within run-to-run noise.

## How it is tested

`Tests/LitextTests/LitextTrackingAreaAppKitTests.swift` checks that one area with `.inVisibleRect` and `.cursorUpdate` survives repeated updates across frame changes, and that an area a subclass adds survives the update. The second test fails against 3.3.1.
