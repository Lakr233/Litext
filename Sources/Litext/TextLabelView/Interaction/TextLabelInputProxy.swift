//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !os(tvOS) && !os(watchOS)

    import UIKit

    /// A read-only text input that lends a label the system's text menu.
    ///
    /// UIKit offers Look Up, Translate, Share and Speak only to a first responder
    /// that adopts `UITextInput` and carries a `UITextInteraction`. The label keeps
    /// its own gestures, highlight and handles; this view sits under its content,
    /// takes first responder while the label has a selection, and answers the
    /// system's questions about the text from the label's layout.
    ///
    /// `interactionShouldBegin` returns false, so the text interaction never
    /// selects, draws or shows a loupe. On iOS the view ignores touches, which keep
    /// reaching the label directly. On Mac Catalyst it takes them, because a right
    /// click opens the system text menu only on the view that owns the interaction;
    /// the touches it does not use still travel up the responder chain to the label.
    @available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *)
    @MainActor
    final class TextLabelInputProxy: UIView, UITextInteractionDelegate {
        weak var label: TextLabelView?
        weak var inputDelegate: UITextInputDelegate?
        private let textInteraction = UITextInteraction(for: .nonEditable)
        private lazy var stringTokenizer = UITextInputStringTokenizer(textInput: self)
        var markedTextStyle: [NSAttributedString.Key: Any]?

        // The label is read-only; nothing it shows is typed, corrected or replaced.
        var autocorrectionType: UITextAutocorrectionType = .no
        var spellCheckingType: UITextSpellCheckingType = .no
        var smartQuotesType: UITextSmartQuotesType = .no
        var smartDashesType: UITextSmartDashesType = .no
        var smartInsertDeleteType: UITextSmartInsertDeleteType = .no

        #if !targetEnvironment(macCatalyst)
            /// Presents the menu on iOS. It must sit on the first responder, or the
            /// system leaves its commands out of the menu.
            private(set) lazy var editMenuInteraction: UIEditMenuInteraction = {
                let interaction = UIEditMenuInteraction(delegate: label)
                addInteraction(interaction)
                return interaction
            }()
        #endif

        init(label: TextLabelView) {
            self.label = label
            super.init(frame: label.bounds)
            autoresizingMask = [.flexibleWidth, .flexibleHeight]
            backgroundColor = .clear
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            #if targetEnvironment(macCatalyst)
                isUserInteractionEnabled = true
            #else
                isUserInteractionEnabled = false
            #endif
            textInteraction.textInput = self
            textInteraction.delegate = self
            addInteraction(textInteraction)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        func interactionShouldBegin(_: UITextInteraction, at _: CGPoint) -> Bool {
            false
        }

        // MARK: - Responder

        override var canBecomeFirstResponder: Bool {
            label?.isSelectable == true
        }

        override func copy(_: Any?) {
            label?.copySelectionOrNestedSelection()
        }

        override func selectAll(_: Any?) {
            guard let label else { return }
            label.selectAll()
            // The menu closes after running a command; bring it back for the new range.
            DispatchQueue.main.async { [weak label] in
                label?.showSelectionMenuController()
            }
        }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            guard let label, label.isSelectable else { return false }
            guard label.hasCommandSelection else {
                return action == #selector(selectAll(_:)) && label.selectAllRange() != nil
            }
            switch action {
            case #selector(copy(_:)):
                return true
            case #selector(selectAll(_:)):
                return !label.isEntireTextSelected
            case #selector(cut(_:)), #selector(paste(_:)), #selector(delete(_:)):
                return false
            default:
                // Look Up, Translate, Share and Speak are the system's to decide.
                return super.canPerformAction(action, withSender: sender)
            }
        }

        /// Wraps a selection change so the system reads the new range.
        func performSelectionChange(_ change: () -> Void) {
            inputDelegate?.selectionWillChange(self)
            change()
            inputDelegate?.selectionDidChange(self)
        }
    }

    // MARK: - Positions

    @available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *)
    final class TextLabelTextPosition: UITextPosition {
        let index: Int

        init(_ index: Int) {
            self.index = index
        }
    }

    @available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *)
    final class TextLabelTextRange: UITextRange {
        let range: NSRange

        init(_ range: NSRange) {
            self.range = range
        }

        override var start: UITextPosition {
            TextLabelTextPosition(range.location)
        }

        override var end: UITextPosition {
            TextLabelTextPosition(NSMaxRange(range))
        }

        override var isEmpty: Bool {
            range.length == 0
        }
    }

    @available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *)
    final class TextLabelSelectionRect: UITextSelectionRect {
        private let storedRect: CGRect
        private let storedContainsStart: Bool
        private let storedContainsEnd: Bool

        init(rect: CGRect, containsStart: Bool, containsEnd: Bool) {
            storedRect = rect
            storedContainsStart = containsStart
            storedContainsEnd = containsEnd
        }

        override var rect: CGRect {
            storedRect
        }

        override var writingDirection: NSWritingDirection {
            .natural
        }

        override var containsStart: Bool {
            storedContainsStart
        }

        override var containsEnd: Bool {
            storedContainsEnd
        }

        override var isVertical: Bool {
            false
        }
    }

    // MARK: - UITextInput

    @available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *)
    extension TextLabelInputProxy: UITextInput {
        private var string: NSString {
            (label?.textLayout.attributedString.string ?? "") as NSString
        }

        private func index(of position: UITextPosition) -> Int? {
            (position as? TextLabelTextPosition)?.index
        }

        private func clamped(_ index: Int) -> Int {
            min(max(index, 0), string.length)
        }

        func text(in range: UITextRange) -> String? {
            guard let label, let range = (range as? TextLabelTextRange)?.range else { return nil }
            // Look Up, Translate and Share read the selection; give them the text Copy
            // would give, with attachments in their text form, and in a group the text of
            // the whole selection.
            if range == label.selectionRange {
                return label.commandSelectedText()?.string
            }
            guard let safeRange = NSRange.sanitized(range, within: string.length) else { return nil }
            return string.substring(with: safeRange)
        }

        func replace(_: UITextRange, withText _: String) {}

        /// The menu the system builds for the selection, minus the editing commands a
        /// read-only label cannot run. Mac Catalyst asks for it on a right click.
        func editMenu(for _: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            label?.selectionMenu(suggestedActions: suggestedActions)
        }

        var selectedTextRange: UITextRange? {
            get {
                guard let range = label?.selectionRange else { return nil }
                return TextLabelTextRange(range)
            }
            set {
                // The label's own gestures own the selection. Accept a real range the
                // system picks, such as for Look Up, and ignore the caret it may park.
                guard let range = (newValue as? TextLabelTextRange)?.range, range.length > 0 else { return }
                label?.setSelectionRange(range, presentsMenu: false)
            }
        }

        var markedTextRange: UITextRange? {
            nil
        }

        func setMarkedText(_: String?, selectedRange _: NSRange) {}

        func unmarkText() {}

        var beginningOfDocument: UITextPosition {
            TextLabelTextPosition(0)
        }

        var endOfDocument: UITextPosition {
            TextLabelTextPosition(string.length)
        }

        func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
            guard let from = index(of: fromPosition), let to = index(of: toPosition) else { return nil }
            let start = clamped(min(from, to))
            let end = clamped(max(from, to))
            return TextLabelTextRange(NSRange(location: start, length: end - start))
        }

        func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
            guard let index = index(of: position) else { return nil }
            let target = index + offset
            guard target >= 0, target <= string.length else { return nil }
            return TextLabelTextPosition(target)
        }

        func position(
            from position: UITextPosition,
            in direction: UITextLayoutDirection,
            offset: Int,
        ) -> UITextPosition? {
            guard let index = index(of: position) else { return nil }
            switch direction {
            case .left:
                return self.position(from: position, offset: -offset)
            case .right:
                return self.position(from: position, offset: offset)
            case .up, .down:
                guard let label else { return nil }
                let caret = caretRect(for: position)
                guard !caret.isNull else { return nil }
                let step = caret.height * CGFloat(offset)
                let y = direction == .up ? caret.midY - step : caret.midY + step
                return label.nearestTextIndexAtPoint(CGPoint(x: caret.midX, y: y))
                    .map { TextLabelTextPosition($0) } ?? TextLabelTextPosition(index)
            @unknown default:
                return nil
            }
        }

        func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
            let lhs = index(of: position) ?? 0
            let rhs = index(of: other) ?? 0
            if lhs < rhs {
                return .orderedAscending
            }
            if lhs > rhs {
                return .orderedDescending
            }
            return .orderedSame
        }

        func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
            (index(of: toPosition) ?? 0) - (index(of: from) ?? 0)
        }

        var tokenizer: UITextInputTokenizer {
            stringTokenizer
        }

        func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
            switch direction {
            case .left, .up:
                range.start
            default:
                range.end
            }
        }

        func characterRange(
            byExtending position: UITextPosition,
            in direction: UITextLayoutDirection,
        ) -> UITextRange? {
            guard let index = index(of: position) else { return nil }
            switch direction {
            case .left, .up:
                return TextLabelTextRange(NSRange(location: 0, length: clamped(index)))
            default:
                let start = clamped(index)
                return TextLabelTextRange(NSRange(location: start, length: string.length - start))
            }
        }

        func baseWritingDirection(
            for _: UITextPosition,
            in _: UITextStorageDirection,
        ) -> NSWritingDirection {
            .natural
        }

        func setBaseWritingDirection(_: NSWritingDirection, for _: UITextRange) {}

        func firstRect(for range: UITextRange) -> CGRect {
            guard let label, let range = (range as? TextLabelTextRange)?.range else { return .null }
            if let rect = label.textLayout.rects(for: range).first {
                return label.viewRect(fromLayoutRect: rect)
            }
            return caretRect(for: TextLabelTextPosition(range.location))
        }

        func caretRect(for position: UITextPosition) -> CGRect {
            guard let label, let position = index(of: position) else { return .null }
            let caretIndex = clamped(position)
            let lineCharacter = caretIndex < string.length ? caretIndex : max(caretIndex - 1, 0)
            guard let rect = label.textLayout.caretRect(at: caretIndex, onLineOf: lineCharacter) else { return .null }
            return label.viewRect(fromLayoutRect: rect)
        }

        func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
            guard let label, let range = (range as? TextLabelTextRange)?.range else { return [] }
            let rects = label.textLayout.rects(for: range).map { label.viewRect(fromLayoutRect: $0) }
            return rects.enumerated().map { offset, rect in
                TextLabelSelectionRect(
                    rect: rect,
                    containsStart: offset == 0,
                    containsEnd: offset == rects.count - 1,
                )
            }
        }

        func closestPosition(to point: CGPoint) -> UITextPosition? {
            guard let index = label?.nearestTextIndexAtPoint(point) else { return nil }
            return TextLabelTextPosition(index)
        }

        func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
            guard let index = (closestPosition(to: point) as? TextLabelTextPosition)?.index,
                  let range = (range as? TextLabelTextRange)?.range
            else { return nil }
            return TextLabelTextPosition(min(max(index, range.location), NSMaxRange(range)))
        }

        func characterRange(at point: CGPoint) -> UITextRange? {
            guard let index = label?.characterIndexAtPoint(point), index < string.length else { return nil }
            return TextLabelTextRange(string.rangeOfComposedCharacterSequence(at: index))
        }

        // MARK: UIKeyInput

        var hasText: Bool {
            string.length > 0
        }

        func insertText(_: String) {}

        func deleteBackward() {}
    }

#endif
