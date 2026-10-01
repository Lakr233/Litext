# Selection across labels

How `TextSelectionGroup` shares one selection between labels, why it is built that way, and what it costs. Measured on 2026-10-01 with release builds on an Apple silicon Mac running macOS 27, through AppKit. The tests also ran on an iOS 27 simulator.

## Design

- **The order is the host's.** `labels` lists the members in reading order. A table lists its cells row by row. Geometry is never used to order members: tables, multi-column layouts and right-to-left text all break a top-to-bottom, left-to-right guess.
- **A selection is linear.** It runs from a position in one member through every member listed between to a position in another, as on the web. Selecting a rectangle of cells is not supported.
- **The group owns the state.** The selection is two positions, each a member and a text index. Each member's `selectionRange` is derived from them, and the ends are normalized so the first and last members always have selected text.
- **Every member's input proxy answers for the whole group.** The proxy that lends a label the system text menu returns the group's joined text from `text(in:)` for the selected range, so Look Up, Translate and Share act on the whole selection. A proxy over a container was rejected: on Mac Catalyst the proxy has to take touches to open the right-click menu, and a container-wide proxy would take every click in a table.
- **The member where the selection ends shows the menu,** anchored on the union of every member's selection rects. The first member shows the start handle and the last member the end handle.
- **Drags stay with the label they began in.** UIKit and AppKit deliver a whole touch or mouse sequence to the view it began in. The label converts the pointer to window coordinates, and the group picks the member that contains the point, or else the nearest visible one. A handle's recognizer stays on its window until the drag ends, even after the handle moves to another member.
- **Clearing:**
  - Any member's `clearSelection()` clears the group.
  - New text in a member clears the group when that member holds part of the selection.
  - A member that leaves its window clears the group only when it holds part of the selection, so cells that are reused or scrolled away elsewhere leave the selection alone.
  - Selecting text outside the group clears it, as it clears any other label.

## Presentation gate

Selection UI must never open over a controller or view that covers the label. Before this change, the UIKit menu checked only `parentViewController?.presentedViewController`, and Share presented with no check at all. `canPresentSelectionUI(from:)` now gates the edit menu, the iOS 15 Share sheet, and the AppKit Look Up and Translate popovers:

- **On UIKit,** it fails when:
  - the label is outside a window, or the window is hidden;
  - the label's controller or an ancestor has presented a controller, or is being dismissed or removed;
  - hit tests at the middle, top and bottom of the part of the selection inside the window all land outside the controller's view, such as on a bar or on a view the host laid over the window, or no part of the selection is inside the window. A selection taller than the screen still gets its menu. The hit test is skipped while a menu is already visible, because the menu can cover the selection itself.
- **On AppKit,** it fails when the window is not visible, the window has an attached sheet, or a hit test does not land on the label. The hit test uses the visible part of the anchor, or the label's visible rect when the anchor is scrolled out of view.
- **The selection handles** use the same on-screen hit test.

The gate does not dismiss a menu that is already showing when a controller is presented over it afterward. That case was not measured.

## Cost

Release builds, the median of 15 samples after 3 warm-ups, three runs interleaved with the previous revision (3.1.1). Ranges are the three runs' medians.

| Scenario | 3.1.1 | With groups |
|---|---|---|
| 100-step drag, 200 selectable siblings | 5.69–5.79 ms | 5.71–6.09 ms |
| One label cycled through 200 cell contents | 16.9–17.3 ms | 17.3–17.8 ms |
| 200 sibling labels selected in turn | 9.06–9.68 ms | 9.44–9.71 ms |

Labels outside a group are within noise of 3.1.1.

For a 30 × 10 table in one group:

| Scenario | Time |
|---|---|
| Select all, then clear | 0.53–0.57 ms |
| 100-step drag across the table | 13.9–14.2 ms (about 0.14 ms a step) |
| 100 outside labels selected while the group has a selection | 10.2–10.5 ms |
| Joined text of the whole table | 0.28 ms |

Two costs were removed before these numbers were taken:

- **Every broadcast cost O(n²).** Each member hid the menu across the whole group whenever any label in the app selected text. Now a member does nothing unless the group has a selection.
- **Updating the selection cost O(n²).** Member lookups were linear, and every member looks itself up while the selection updates. Lookups now use an index map, and a drag redraws only the members whose part or handles changed.
