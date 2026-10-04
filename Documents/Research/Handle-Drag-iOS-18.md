# Selection handle drags on iOS 18

Why a selection handle sometimes did not move on iOS 18, and what was measured to fix it. The checks ran on iOS 18.6 and iOS 27 simulators, with touches injected into the sample app.

## The symptom

On iOS 18 a handle drag often did nothing. The recognizer that grabs handles, a `UILongPressGestureRecognizer` with no minimum duration on the label's window, received the touch and reached `.began`, but its action ran only when the finger lifted, so the whole drag was lost. The end handle failed far more often than the start handle. iOS 27 never showed it.

Drags of the end handle straight down:

| Build | iOS 18.6 | iOS 27 |
| --- | --- | --- |
| 3.1.1 | 1 of 2 moved | not run |
| 3.2.0 with the scroll views' recognizers switched off | 1 of 5 moved | 3 of 3 moved |
| With the fix | 4 of 4 moved | 4 of 4 moved |

A sideways drag moved more often, because the scroll view's pan fails early on sideways movement and its failure also released the grab.

## The cause

Listing the touch's `gestureRecognizers` 0.3 seconds into a stuck drag showed, on the label:

- `_UITouchDurationObservingGestureRecognizer` from `_UILongPressTimeoutClickInteractionDriver`
- `_UISecondaryClickDriverGestureRecognizer`
- two `_UIRelationshipGestureRecognizer`s from `_UIClickPresentationInteraction`, still possible

All of them belong to the `UIContextMenuInteraction` the label installed for right clicks. It watches every touch for a long press, and on iOS 18 its relationship recognizers hold back other recognizers' actions while they stay possible. The end handle usually sits over the label's last line, so its touches reach the label and its interaction. The start handle's knob sits above the first line, often outside the label.

Switching off the recognizers of the scroll views around the label did not help, as the table shows.

## The fix

The label installs the context menu interaction only on Mac Catalyst, where there are no handles. On iOS:

- A right click selects the word under it in `touchesBegan`, as before, and shows the selection menu in `touchesEnded`, which the interaction used to do.
- A long press, which the interaction used to take, selects the word under the finger. It is a `UILongPressGestureRecognizer` for direct touches only, and begins only over a word in a selectable label, so a long press on a link in a label that is not selectable still taps it.

With the fix, the touch on a handle carries only the label's long press, which fails at once, and the window's system gate. The grab begins on the first touch event. `UIPointerInteraction` adds no recognizer that sees direct touches.

Hosts that call `installContextMenuInteraction()` themselves on iOS bring the problem back.

## Context menus in the host

The fix above removed only the label's own interaction. A host can put a `UIContextMenuInteraction` on a view that contains the label, such as a chat row that offers a menu for the whole message, and on iOS 18 its recognizers hold back the grab the same way. On an iPad simulator running iOS 18.6, in an app whose message rows carry such an interaction, a handle that the finger rested on for 0.3 seconds before moving did not move at all: the grab recognizer reached `.began` at once, but its action ran only when the finger lifted. The same drag on an iPhone simulator moved the handle, which is why the problem first showed on an iPad.

Listing the touch's recognizers 0.2 seconds into the drag showed the row's `_UITouchDurationObservingGestureRecognizer` still changing and its two `_UIRelationshipGestureRecognizer`s still possible. Turning those recognizers off and on again from the grab recognizer's `gestureRecognizerShouldBegin(_:)` did not fail them, and the action still waited for the lift.

A recognizer's `touchesBegan`, `touchesMoved` and `touchesEnded` arrive as the finger moves even while its action messages are held back. The grab recognizer is now a `UILongPressGestureRecognizer` subclass that drives the drag from those calls and has no action target. Whatever the host installs around the label, the handle follows the finger. Holding the knob for a second before dragging does not open the host's menu either, because the grab recognizer has already begun and the menu's recognizers wait for it.
