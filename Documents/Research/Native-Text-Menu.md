# Native text menu

How Litext gets the system's own selection menu, and what was measured to choose that design. The checks ran on iOS 18.6 and iOS 27 simulators, Mac Catalyst on macOS 27 with the Mac idiom, and macOS 27.

## UIKit: a read-only text input under the label

UIKit offers Look Up, Translate, Share and Speak only to a first responder that adopts `UITextInput` **and** carries a `UITextInteraction`. A view that adopts `UITextInput` without the interaction gets none of them, and becomes a key input that brings up the software keyboard.

`TextLabelInputProxy` is that view. It is an internal subview of a selectable label, the size of the label and under its other subviews, with a `UITextInteraction(for: .nonEditable)` whose delegate returns false from `interactionShouldBegin`. Litext's own gestures, highlight and handles stay in charge:

- The system draws no selection of its own: the proxy's `UITextSelectionDisplayInteraction` is not activated, and no selection, highlight or grabber view appears in the window.
- No keyboard appears.
- `UIEditMenuInteraction` must be installed on the proxy, the first responder. Installed on the label, the system leaves its commands out of the menu.
- On iOS the proxy ignores touches, so taps, links and handles reach the label as before.

The menu the label presents is the system's `suggestedActions`, with cut, paste and delete removed, passed through `TextLabelViewDelegate.textLabelView(_:editMenuForSelection:suggestedActions:)`. On iOS 27 it shows Copy, Select All, Look Up, then Translate and Share… behind the overflow button. All of them were tapped in a running app and opened the expected system UI. Copy keeps the selection, as `UITextView` does.

iOS 15 and Mac Catalyst 15 keep the label's earlier Copy, Select All and Share menu.

### Mac Catalyst

`UIEditMenuInteraction.presentEditMenu` shows nothing on Mac Catalyst. Instead the proxy takes touches there: a right click on it opens the system text menu from its `UITextInteraction`, and the touches it does not use travel up the responder chain to the label. `canPerformAction` returning false only dims Cut and Paste on Mac Catalyst, so `UITextInput.editMenu(for:suggestedActions:)` removes them. A right click away from the selection first selects the word under it.

Measured right-click menu: Look Up “brave”, Translate “brave”, Copy, Share…, Speech. The menu bar's Edit > Copy and Select All are enabled and reach the proxy. Compared with `UITextView`, Search With … and Services are missing; UIKit has no public API for them.

## AppKit: the menu built from public API

`NSTextView`'s Look Up and Translate items target private classes, and lifting them from a hidden donor text view fails when the donor is off screen or hidden. The label builds the menu itself in `menu(for:)`:

| Item | API |
|---|---|
| Look Up “…” | `showDefinition(for:at:)`, at the selection's first baseline origin |
| Translate “…” | SwiftUI `translationPresentation` in an `NSHostingView` over the selection, macOS 14.4 or later |
| Copy | `copy(_:)` through the responder chain |
| Share… | `NSSharingServicePicker.standardShareMenuItem` from macOS 13, a submenu of `NSSharingService`s on macOS 12 |
| Speech | `AVSpeechSynthesizer` |
| Services | Appended by AppKit when the label is an `NSServicesMenuRequestor` and the app has registered its send types |

Item titles, separators and the quoting of the selection (whitespace collapsed, cut to 30 characters plus an ellipsis) match `NSTextView`, and the localized titles were taken from `NSTextView`'s menu in each language. `Translation` is weak-linked automatically, so importing it keeps the macOS 12 floor.

Measured: a right click and a control-click both open the menu, a right click away from the selection selects the word under it, the Look Up highlight lines up with the word, and the translation popover opens.
