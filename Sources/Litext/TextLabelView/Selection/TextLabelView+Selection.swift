//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation
import QuartzCore

#if !os(watchOS)

    public extension TextLabelView {
        /// Removes the selection.
        ///
        /// A reusing host such as a table or collection view cell should call this in
        /// `prepareForReuse()`: new text that shares a prefix with the old one would
        /// otherwise keep the previous content's selection.
        /// In a group, this clears the whole group's selection.
        @objc func clearSelection() {
            if let selectionGroup {
                selectionGroup.clearSelection()
            } else {
                selectionRange = nil
            }
            updateSelectionLayer()
        }

        /// Copies the selection, or in a group the whole group's selection, and
        /// returns it.
        @discardableResult
        func copySelection() -> NSAttributedString {
            if let selectionGroup {
                return selectionGroup.copySelection()
            }
            guard let selectedText = selectedAttributedText() else {
                return .init()
            }

            writeToPasteboard(selectedText.string)
            return selectedText.copy() as! NSAttributedString
        }

        /// The index of the character under `point`, in the label's coordinates,
        /// on the nearest line, or `nil` when there is no text. This is the
        /// character a double-click there selects the word of.
        ///
        /// - Important: Performance-sensitive on very long text: see
        ///   `TextLabel.Layout.characterIndex(at:)`.
        func characterIndex(at point: CGPoint) -> Int? {
            characterIndexAtPoint(point)
        }
    }

    extension TextLabelView {
        func updateSelectionRange(withLocation location: CGPoint) {
            if let selectionGroup {
                selectionGroup.extendDrag(
                    from: interactionState.initialTouchLocation,
                    in: self,
                    toWindowPoint: convert(location, to: nil),
                )
                return
            }
            guard let startIndex = textLayout.nearestTextIndex(at: convertPointForTextLayout(interactionState.initialTouchLocation)),
                  let endIndex = textLayout.nearestTextIndex(at: convertPointForTextLayout(location))
            else { return }
            selectionRange = NSRange(
                location: min(startIndex, endIndex),
                length: abs(endIndex - startIndex),
            )
        }

        func nearestTextIndexAtPoint(_ point: CGPoint) -> Int? {
            textLayout.nearestTextIndex(at: convertPointForTextLayout(point))
        }

        /// The character under `point`, for word and line selection. Unlike
        /// `nearestTextIndexAtPoint(_:)`, it never resolves to the next line.
        func characterIndexAtPoint(_ point: CGPoint) -> Int? {
            textLayout.characterIndex(at: convertPointForTextLayout(point))
        }

        func textIndexAtPoint(_ point: CGPoint) -> Int? {
            textLayout.textIndex(at: convertPointForTextLayout(point))
        }

        /// Whether `location`, in the label's coordinates, falls on the selected
        /// text, using the slightly enlarged rects a tap uses.
        public func selectionContains(_ location: CGPoint) -> Bool {
            guard let range = selectionRange, range.length > 0 else { return false }
            let rects = textLayout.rects(for: range)
            return rects.map {
                convertRectFromTextLayout($0, insetForInteraction: true)
            }.contains { $0.contains(location) }
        }

        /// The selected text of this label, with each attachment replaced by its
        /// `attributedStringRepresentation()`, or `nil` without a selection. In a
        /// group, use `TextSelectionGroup.selectedAttributedText()` for the whole
        /// selection.
        public func selectedAttributedText() -> NSAttributedString? {
            guard let safeRange = NSRange.sanitized(
                selectionRange,
                within: textLayout.attributedString.length,
            ) else {
                return nil
            }

            let selectedText = textLayout
                .attributedString
                .attributedSubstring(from: safeRange)

            let mutableResult = NSMutableAttributedString(attributedString: selectedText)
            mutableResult.enumerateAttribute(
                .litextAttachment,
                in: NSRange(location: 0, length: mutableResult.length),
                options: [],
            ) { value, range, _ in
                if let attachment = value as? TextLabel.Attachment {
                    mutableResult.replaceCharacters(
                        in: range,
                        with: attachment.attributedStringRepresentation(),
                    )
                }
            }

            return mutableResult
        }

        /// The plain string of `selectedAttributedText()`.
        public func selectedPlainText() -> String? {
            selectedAttributedText()?.string
        }

        /// Whether there is a selection for Copy and the menu commands to act on: the
        /// label's own, or its group's.
        var hasCommandSelection: Bool {
            if let selectionGroup {
                return selectionGroup.hasSelection
            }
            return (selectionRange?.length ?? 0) > 0
        }

        /// Whether a right click at `point` should leave its context menu to the views
        /// behind the label: there is no selection, and the click is not on a visible
        /// character but past the end of a line, on a blank line, a space or a line
        /// break. Otherwise the label would select the nearest word and show its own menu.
        func secondaryClickPassesThrough(at point: CGPoint) -> Bool {
            !hasCommandSelection && visibleCharacterIndexAtPoint(point) == nil
        }

        /// The character whose box holds `point`, in the label's coordinates, unless
        /// it is whitespace or a line break. Unlike `characterIndexAtPoint(_:)`, a
        /// point past the end of a line or between lines resolves to nothing.
        func visibleCharacterIndexAtPoint(_ point: CGPoint) -> Int? {
            guard let index = characterIndexAtPoint(point) else { return nil }
            let string = textLayout.attributedString.string as NSString
            guard index < string.length else { return nil }
            let range = string.rangeOfComposedCharacterSequence(at: index)
            let isBlank = string.substring(with: range).unicodeScalars
                .allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
            guard !isBlank else { return nil }
            let isOnCharacter = textLayout.rects(for: range).contains {
                convertRectFromTextLayout($0, insetForInteraction: false).contains(point)
            }
            return isOnCharacter ? index : nil
        }

        /// Whether the whole text is selected already, so Select All has nothing to do.
        var isEntireTextSelected: Bool {
            if let selectionGroup {
                return selectionGroup.isEntireTextSelected
            }
            return selectionRange == selectAllRange()
        }

        /// The text Copy and the menu commands act on: the label's selection, or its
        /// group's.
        func commandSelectedText() -> NSAttributedString? {
            if let selectionGroup {
                return selectionGroup.selectedAttributedText()
            }
            return selectedAttributedText()
        }

        /// Whether a drag in progress has a selection to report to the delegates.
        func reportSelectionDrag(at location: CGPoint) {
            if let selectionGroup {
                guard selectionGroup.hasSelection else { return }
                selectionGroup.delegate?.textSelectionGroup(selectionGroup, didDragSelectionIn: self, at: location)
                return
            }
            if selectionRange != nil {
                delegate?.textLabelView(self, didDragSelectionAt: location)
            }
        }

        /// Copies this label's selection, or else the first nested label
        /// selection found in its subviews. Returns whether anything was copied.
        @discardableResult
        func copySelectionOrNestedSelection() -> Bool {
            copySelection().length > 0 || copyFromSubviewsRecursively()
        }

        func writeToPasteboard(_ string: String) {
            #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
                UIPasteboard.general.string = string
            #elseif canImport(AppKit)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(string, forType: .string)
            #endif
        }

        func copyFromSubviewsRecursively() -> Bool {
            copyFromSubviewsRecursively(in: self)
        }

        private func copyFromSubviewsRecursively(in view: PlatformView) -> Bool {
            for subview in view.subviews {
                if let textLabelView = subview as? TextLabelView {
                    let copiedText = textLabelView.copySelection()
                    if copiedText.length > 0 {
                        return true
                    }
                    continue
                }

                if copyFromSubviewsRecursively(in: subview) {
                    return true
                }
            }
            return false
        }
    }

#endif // !os(watchOS)
