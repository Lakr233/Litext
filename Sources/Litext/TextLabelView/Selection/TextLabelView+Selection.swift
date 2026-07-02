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
        @objc func clearSelection() {
            selectionRange = nil
            updateSelectionLayer()
        }

        @discardableResult
        func copySelection() -> NSAttributedString {
            guard let selectedText = selectedAttributedText() else {
                return .init()
            }

            #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
                UIPasteboard.general.string = selectedText.string
            #elseif canImport(AppKit)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(selectedText.string, forType: .string)
            #endif

            return selectedText.copy() as! NSAttributedString
        }
    }

    extension TextLabelView {
        func updateSelectionRange(withLocation location: CGPoint) {
            guard let startIndex = textLayout.nearestTextIndex(at: convertPointForTextLayout(interactionState.initialTouchLocation)),
                  let endIndex = textLayout.nearestTextIndex(at: convertPointForTextLayout(location))
            else { return }
            selectionRange = NSRange(
                location: min(startIndex, endIndex),
                length: abs(endIndex - startIndex)
            )
        }

        func nearestTextIndexAtPoint(_ point: CGPoint) -> Int? {
            textLayout.nearestTextIndex(at: convertPointForTextLayout(point))
        }

        func textIndexAtPoint(_ point: CGPoint) -> Int? {
            textLayout.textIndex(at: convertPointForTextLayout(point))
        }

        func convertPointForTextLayout(_ point: CGPoint) -> CGPoint {
            // Must mirror convertRectFromTextLayout: flip against the layout
            // container height, not the live view bounds.
            CGPoint(x: point.x, y: textLayout.containerSize.height - point.y)
        }

        public func selectionContains(_ location: CGPoint) -> Bool {
            guard let range = selectionRange, range.length > 0 else { return false }
            let rects = textLayout.rects(for: range)
            return rects.map {
                convertRectFromTextLayout($0, insetForInteraction: true)
            }.contains { $0.contains(location) }
        }

        public func selectedAttributedText() -> NSAttributedString? {
            guard let safeRange = NSRange.sanitized(
                selectionRange,
                within: textLayout.attributedString.length
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
                options: []
            ) { value, range, _ in
                if let attachment = value as? TextLabel.Attachment {
                    mutableResult.replaceCharacters(
                        in: range,
                        with: attachment.attributedStringRepresentation()
                    )
                }
            }

            return mutableResult
        }

        public func selectedPlainText() -> String? {
            selectedAttributedText()?.string
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
