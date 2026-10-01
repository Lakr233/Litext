//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import Foundation

#if canImport(UIKit) && !os(watchOS)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#if !os(watchOS)

    /// Labels that share one selection, such as the cells of a table.
    ///
    /// A drag or a selection handle that leaves one member continues into the member
    /// under the pointer, and the menu, Copy, Look Up, Translate and Share act on the
    /// text of every member in the selection, joined by `separator`.
    ///
    /// The order of `labels` is the reading order: a selection runs from its start in
    /// one member through every member between to its end in another, whatever their
    /// positions on screen. A table lists its cells row by row.
    ///
    /// The group holds its labels weakly and each label holds its group, so the host
    /// only needs to keep the labels alive. Selecting text in a label outside the group
    /// clears the group's selection, as it clears any other label's.
    @MainActor
    public final class TextSelectionGroup {
        /// The part of the selection in one label.
        public struct Segment {
            public let label: TextLabelView
            public let range: NSRange
        }

        /// A caret position: a text index in the member at `member`.
        struct Position: Comparable {
            var member: Int
            var offset: Int

            static func < (lhs: Position, rhs: Position) -> Bool {
                (lhs.member, lhs.offset) < (rhs.member, rhs.offset)
            }
        }

        struct Selection: Equatable {
            var start: Position
            var end: Position
        }

        private final class WeakLabel {
            weak var label: TextLabelView?

            init(_ label: TextLabelView) {
                self.label = label
            }
        }

        private var members: [WeakLabel] = [] {
            didSet {
                memberIndices = Dictionary(
                    members.enumerated().compactMap { index, box in
                        box.label.map { (ObjectIdentifier($0), index) }
                    },
                    uniquingKeysWith: { first, _ in first },
                )
            }
        }

        /// Each member's index, so a lookup does not walk the members: every member
        /// asks for its own while the selection updates.
        private var memberIndices: [ObjectIdentifier: Int] = [:]
        private(set) var selection: Selection?

        /// The text put between the parts of two adjacent members in copied text, and
        /// in the text the menu commands read. The default is a line break; a table
        /// would use a tab between cells of a row and a line break between rows.
        public var separator: (_ previous: TextLabelView, _ next: TextLabelView) -> String = { _, _ in "\n" }

        public weak var delegate: TextSelectionGroupDelegate?

        public init(labels: [TextLabelView] = []) {
            self.labels = labels
        }

        /// The member labels in reading order. Assigning clears the selection, moves
        /// each label out of any group it was in, and clears the label's own selection.
        /// A label listed twice joins once, at its first place.
        public var labels: [TextLabelView] {
            get { members.compactMap(\.label) }
            set {
                clearSelection()
                for old in labels where !newValue.contains(where: { $0 === old }) {
                    old.selectionGroup = nil
                }
                for label in newValue where label.selectionGroup !== self {
                    label.selectionGroup?.remove(label)
                    label.clearSelection()
                    label.selectionGroup = self
                }
                var seen = Set<ObjectIdentifier>()
                members = newValue.filter { seen.insert(ObjectIdentifier($0)).inserted }.map(WeakLabel.init)
            }
        }

        /// The selection, one segment per member that has selected text, in order.
        public var selectedSegments: [Segment] {
            guard let selection else { return [] }
            return (selection.start.member ... selection.end.member).compactMap { member in
                guard let label = label(at: member), let range = range(of: member, in: selection) else { return nil }
                return Segment(label: label, range: range)
            }
        }

        public var hasSelection: Bool {
            selection != nil
        }

        public func clearSelection() {
            setSelection(nil, presentsMenu: false)
        }

        /// Selects the text of every selectable member.
        public func selectAll() {
            setSelection(entireSelection, presentsMenu: true)
        }

        /// The selected text of every member, joined by `separator`, with attachments
        /// in their text form.
        public func selectedAttributedText() -> NSAttributedString? {
            guard let selection else { return nil }
            let result = NSMutableAttributedString()
            var previous: TextLabelView?
            for member in selection.start.member ... selection.end.member {
                guard let label = label(at: member), label.isSelectable else { continue }
                if let previous {
                    result.append(NSAttributedString(string: separator(previous, label)))
                }
                if let text = label.selectedAttributedText() {
                    result.append(text)
                }
                previous = label
            }
            return result.length > 0 ? result : nil
        }

        public func selectedPlainText() -> String? {
            selectedAttributedText()?.string
        }

        /// Copies the selected text to the pasteboard and returns it.
        @discardableResult
        public func copySelection() -> NSAttributedString {
            guard let text = selectedAttributedText(), let label = selectedSegments.first?.label else {
                return .init()
            }
            label.writeToPasteboard(text.string)
            return text
        }
    }

    // MARK: - Members

    extension TextSelectionGroup {
        func index(of label: TextLabelView) -> Int? {
            // The identifier of a released member can come back for a new object, so
            // the box must still hold this label.
            guard let index = memberIndices[ObjectIdentifier(label)], members[index].label === label else {
                return nil
            }
            return index
        }

        func label(at member: Int) -> TextLabelView? {
            members.indices.contains(member) ? members[member].label : nil
        }

        func remove(_ label: TextLabelView) {
            guard let index = index(of: label) else { return }
            clearSelection()
            members.remove(at: index)
            label.selectionGroup = nil
        }

        /// The length of a member's text, or zero for a member that is not selectable,
        /// which the selection passes over.
        private func length(of member: Int) -> Int {
            guard let label = label(at: member), label.isSelectable else { return 0 }
            return label.attributedText.length
        }

        /// The selection of every selectable member's whole text, or nil when they
        /// have no text.
        private var entireSelection: Selection? {
            guard let last = members.indices.last else { return nil }
            return selection(
                from: Position(member: 0, offset: 0),
                to: Position(member: last, offset: length(of: last)),
            )
        }

        /// The members a selection covers.
        private func span(of selection: Selection?) -> ClosedRange<Int>? {
            selection.map { $0.start.member ... $0.end.member }
        }

        /// The part of `selection` in `member`, or nil when it has no selected text.
        func range(of member: Int, in selection: Selection) -> NSRange? {
            guard (selection.start.member ... selection.end.member).contains(member) else { return nil }
            let lower = member == selection.start.member ? selection.start.offset : 0
            let upper = member == selection.end.member ? selection.end.offset : length(of: member)
            guard upper > lower else { return nil }
            return NSRange(location: lower, length: upper - lower)
        }

        /// The ordered selection between two positions, with ends that sit at the edge
        /// of a member moved into the next one, so the first and last members always
        /// have selected text. Nil when the positions select nothing.
        func selection(from anchor: Position, to focus: Position) -> Selection? {
            var start = min(anchor, focus)
            var end = max(anchor, focus)
            while start.member < end.member, start.offset >= length(of: start.member) {
                start = Position(member: start.member + 1, offset: 0)
            }
            while end.member > start.member, end.offset <= 0 {
                end = Position(member: end.member - 1, offset: length(of: end.member - 1))
            }
            guard start < end else { return nil }
            return Selection(start: start, end: end)
        }

        /// The member the selection ends in, which shows the menu.
        var menuLabel: TextLabelView? {
            selection.flatMap { label(at: $0.end.member) }
        }

        func showsHandle(_ isStart: Bool, in label: TextLabelView) -> Bool {
            guard let selection, let member = index(of: label) else { return false }
            return member == (isStart ? selection.start.member : selection.end.member)
        }
    }

    // MARK: - Changing the selection

    extension TextSelectionGroup {
        /// Replaces the selection and gives every member it touched, before or after,
        /// its new part. With `presentsMenu`, the last member shows the menu and the
        /// labels outside the group drop their selections.
        func setSelection(_ newValue: Selection?, presentsMenu: Bool) {
            let oldValue = selection
            if newValue != oldValue {
                selection = newValue
                // Redraw only the members whose part changed and those that show or
                // showed a handle; a drag keeps the members in the middle unchanged.
                var affected = Set<Int>()
                for span in [span(of: oldValue), span(of: newValue)].compactMap(\.self) {
                    affected.formUnion(span)
                }
                let handleMembers = Set([oldValue, newValue].compactMap(\.self).flatMap { [$0.start.member, $0.end.member] })
                for member in affected.sorted() {
                    guard let label = label(at: member) else { continue }
                    let range = newValue.flatMap { range(of: member, in: $0) }
                    if range == label.selectionRange, !handleMembers.contains(member) {
                        continue
                    }
                    label.applyGroupSegment(range)
                }
                delegate?.textSelectionGroupDidChangeSelection(self)
            }
            // Like a label's own selection, an unchanged one presents nothing, so a drag
            // that stays within one character does not broadcast on every event.
            guard newValue != oldValue else { return }
            if newValue == nil {
                hideMenu()
            } else if presentsMenu {
                presentSelection()
            }
        }

        /// Selects `range` in one member only, as a tap or a double tap in it does.
        func select(_ range: NSRange?, in label: TextLabelView, presentsMenu: Bool) {
            guard let member = index(of: label),
                  let range = NSRange.sanitized(range, within: label.attributedText.length)
            else {
                clearSelection()
                return
            }
            setSelection(
                selection(
                    from: Position(member: member, offset: range.location),
                    to: Position(member: member, offset: NSMaxRange(range)),
                ),
                presentsMenu: presentsMenu,
            )
        }

        /// The member and text index nearest `point`, in window coordinates: in the
        /// visible member that contains the point, or else the nearest one.
        func position(atWindowPoint point: CGPoint) -> Position? {
            var nearest: (member: Int, distance: CGFloat)?
            for (member, box) in members.enumerated() {
                guard let label = box.label, label.isSelectable, label.window != nil, !label.isHidden else {
                    continue
                }
                let local = label.convert(point, from: nil)
                let dx = max(label.bounds.minX - local.x, 0, local.x - label.bounds.maxX)
                let dy = max(label.bounds.minY - local.y, 0, local.y - label.bounds.maxY)
                let distance = hypot(dx, dy)
                if nearest == nil || distance < nearest!.distance {
                    nearest = (member, distance)
                }
                if distance == 0 {
                    break
                }
            }
            guard let member = nearest?.member, let label = label(at: member),
                  let offset = label.nearestTextIndexAtPoint(label.convert(point, from: nil))
            else { return nil }
            return Position(member: member, offset: offset)
        }

        /// Extends a drag that began at `anchorPoint` in `label` to `point`, in window
        /// coordinates.
        func extendDrag(from anchorPoint: CGPoint, in label: TextLabelView, toWindowPoint point: CGPoint) {
            guard let member = index(of: label),
                  let anchorOffset = label.nearestTextIndexAtPoint(anchorPoint),
                  let focus = position(atWindowPoint: point)
            else { return }
            setSelection(
                selection(from: Position(member: member, offset: anchorOffset), to: focus),
                presentsMenu: true,
            )
        }

        /// Moves one end of the selection to `point`, in window coordinates, keeping at
        /// least one character selected.
        func moveEnd(isStart: Bool, toWindowPoint point: CGPoint) {
            guard let current = selection, let target = position(atWindowPoint: point) else { return }
            var start = current.start
            var end = current.end
            if isStart {
                start = target < end ? target : position(before: end)
            } else {
                end = start < target ? target : position(after: start)
            }
            setSelection(selection(from: start, to: end) ?? current, presentsMenu: false)
        }

        private func position(before position: Position) -> Position {
            if position.offset > 0 {
                return Position(member: position.member, offset: position.offset - 1)
            }
            guard position.member > 0 else { return position }
            let member = position.member - 1
            return Position(member: member, offset: max(length(of: member) - 1, 0))
        }

        private func position(after position: Position) -> Position {
            if position.offset < length(of: position.member) {
                return Position(member: position.member, offset: position.offset + 1)
            }
            guard position.member + 1 < members.count else { return position }
            let member = position.member + 1
            return Position(member: member, offset: min(1, length(of: member)))
        }

        /// Shows the menu from the last member and clears the selection of every
        /// label outside the group.
        func presentSelection() {
            guard let label = menuLabel else { return }
            label.broadcastSelection()
            #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS)
                label.showSelectionMenuController()
            #endif
        }

        func hideMenu() {
            #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS)
                for box in members {
                    box.label?.hideSelectionMenuController()
                }
            #endif
        }

        /// Whether every selectable member's whole text is selected.
        var isEntireTextSelected: Bool {
            selection != nil && selection == entireSelection
        }

        /// The selected rects of the members in `view`'s window, in `view`'s
        /// coordinates. A member out of the window, such as a reused cell, has no
        /// place on screen to add.
        func selectionRects(in view: PlatformView) -> [CGRect] {
            selectedSegments.filter { $0.label.window != nil && $0.label.window === view.window }.flatMap { segment in
                segment.label.textLayout.rects(for: segment.range).map { rect in
                    segment.label.convert(
                        segment.label.convertRectFromTextLayout(rect, insetForInteraction: true),
                        to: view,
                    )
                }
            }
        }
    }

    // MARK: - Delegate

    @MainActor
    public protocol TextSelectionGroupDelegate: AnyObject {
        /// Called once for every change of the group's selection.
        func textSelectionGroupDidChangeSelection(_ group: TextSelectionGroup)

        /// Called while a drag extends the selection, with `location` in the
        /// coordinates of `label`, the member the drag began in. Useful for
        /// scrolling a containing scroll view.
        func textSelectionGroup(
            _ group: TextSelectionGroup,
            didDragSelectionIn label: TextLabelView,
            at location: CGPoint,
        )

        #if canImport(UIKit) && !os(tvOS)
            /// Returns the menu to show for the selection, or nil for the system's menu.
            ///
            /// `suggestedActions` are the system's commands for the selection, such as
            /// Copy, Look Up, Translate and Share, without the editing ones; they act on
            /// the text of the whole selection. Called on iOS 16 and Mac Catalyst 16 or
            /// later; earlier systems show a fixed menu.
            @available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *)
            func textSelectionGroup(
                _ group: TextSelectionGroup,
                editMenuForSuggestedActions suggestedActions: [UIMenuElement],
            ) -> UIMenu?
        #elseif canImport(AppKit)
            /// Returns the menu to show for a right click on the selection, or nil for
            /// `menu`, the menu the label built for the whole selection.
            func textSelectionGroup(
                _ group: TextSelectionGroup,
                menu: NSMenu,
                event: NSEvent,
            ) -> NSMenu?
        #endif
    }

    public extension TextSelectionGroupDelegate {
        func textSelectionGroupDidChangeSelection(_: TextSelectionGroup) {}

        func textSelectionGroup(
            _: TextSelectionGroup,
            didDragSelectionIn _: TextLabelView,
            at _: CGPoint,
        ) {}

        #if canImport(UIKit) && !os(tvOS)
            @available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *)
            func textSelectionGroup(
                _: TextSelectionGroup,
                editMenuForSuggestedActions _: [UIMenuElement],
            ) -> UIMenu? {
                nil
            }
        #elseif canImport(AppKit)
            func textSelectionGroup(
                _: TextSelectionGroup,
                menu _: NSMenu,
                event _: NSEvent,
            ) -> NSMenu? {
                nil
            }
        #endif
    }

#endif // !os(watchOS)
