#if canImport(UIKit) && !os(tvOS) && !os(watchOS)
    import UIKit

    /// Projects a selection group as one read-only UITextInput document. Geometry
    /// comes from each label's CoreText layout, in their common ancestor's space.
    @available(iOS 16.0, macCatalyst 16.0, visionOS 1.0, *)
    extension TextLabelInputProxy {
        struct DocumentEntry {
            let label: TextLabelView
            let offset: Int
            let length: Int
        }

        /// The labels the document spans. A group's selection passes over members
        /// that are not selectable, and so does the document, so its offsets match
        /// the group's.
        var documentLabels: [TextLabelView] {
            guard let label else { return [] }
            #if !targetEnvironment(macCatalyst) && !os(visionOS)
                if #available(iOS 17.0, *), let group = label.selectionGroup {
                    return group.labels.filter(\.isSelectable)
                }
            #endif
            return [label]
        }

        var documentEntries: [DocumentEntry] {
            let labels = documentLabels
            let group = label?.selectionGroup
            var offset = 0
            return labels.enumerated().map { index, member in
                if index > 0, let group {
                    offset += (group.separator(labels[index - 1], member) as NSString).length
                }
                let length = member.attributedText.length
                let entry = DocumentEntry(label: member, offset: offset, length: length)
                offset += length
                return entry
            }
        }

        var documentLength: Int {
            guard let last = documentEntries.last else { return 0 }
            return last.offset + last.length
        }

        /// The text the offsets index: each member's `attributedText`, the string the
        /// group measures its selection in, joined by the group's separator.
        var documentString: NSString {
            let labels = documentLabels
            guard labels.count > 1, let group = label?.selectionGroup else {
                return (labels.first?.attributedText.string ?? "") as NSString
            }
            let result = NSMutableString()
            for (index, member) in labels.enumerated() {
                if index > 0 {
                    result.append(group.separator(labels[index - 1], member))
                }
                result.append(member.attributedText.string)
            }
            return result
        }

        func documentOffset(in label: TextLabelView) -> Int {
            documentEntries.first { $0.label === label }?.offset ?? 0
        }

        var documentSelectionRange: NSRange? {
            let entries = documentEntries
            guard entries.count > 1, let group = label?.selectionGroup, let selection = group.selection,
                  let first = entries.first(where: { $0.label === group.memberLabel(at: selection.start.member) }),
                  let last = entries.first(where: { $0.label === group.memberLabel(at: selection.end.member) })
            else { return label?.selectionRange }
            let start = first.offset + selection.start.offset
            let end = last.offset + selection.end.offset
            return NSRange(location: start, length: end - start)
        }

        func selectDocumentRange(_ range: NSRange) {
            guard let label else { return }
            if documentLabels.count > 1, let group = label.selectionGroup,
               let start = documentPosition(at: range.location),
               let end = documentPosition(at: NSMaxRange(range), preferPrevious: true),
               let startMember = group.index(of: start.label), let endMember = group.index(of: end.label)
            {
                group.setSelection(group.normalizedSelection(
                    from: .init(member: startMember, offset: start.index),
                    to: .init(member: endMember, offset: end.index),
                ), presentsMenu: false)
                return
            }
            label.setSelectionRange(range, presentsMenu: false)
        }

        func documentPosition(at index: Int, preferPrevious: Bool = false) -> (label: TextLabelView, index: Int)? {
            let entries = documentEntries
            for (order, entry) in entries.enumerated() {
                let end = entry.offset + entry.length
                if index < end || (index == end && preferPrevious) || order == entries.count - 1 {
                    return (entry.label, min(max(0, index - entry.offset), entry.length))
                }
                if index < entries[order + 1].offset, preferPrevious {
                    return (entry.label, entry.length)
                }
            }
            return nil
        }

        /// The members' closest common ancestor, the space the document's geometry
        /// is in. Members off the label's window, such as cells scrolled away and
        /// removed, share no ancestor with the rest and are left out.
        var textInputView: UIView {
            #if !targetEnvironment(macCatalyst) && !os(visionOS)
                guard #available(iOS 17.0, *), let label else { return self }
                guard let window = label.window else { return label }
                var candidate: UIView = label
                for member in documentLabels where member.window === window {
                    while !member.isDescendant(of: candidate), let parent = candidate.superview {
                        candidate = parent
                    }
                }
                return candidate
            #else
                return self
            #endif
        }

        func documentPosition(at point: CGPoint) -> Int? {
            guard let label else { return nil }
            if documentLabels.count > 1, let group = label.selectionGroup,
               let position = group.position(atWindowPoint: textInputView.convert(point, to: nil)),
               let member = group.memberLabel(at: position.member)
            {
                return documentOffset(in: member) + position.offset
            }
            return label.nearestTextIndexAtPoint(textInputView.convert(point, to: label))
        }

        func documentRects(for range: NSRange) -> [CGRect] {
            let view = textInputView
            let window = view.window
            return documentEntries.flatMap { entry -> [CGRect] in
                let lower = max(range.location, entry.offset)
                let upper = min(NSMaxRange(range), entry.offset + entry.length)
                guard lower < upper, entry.label.window === window else { return [] }
                return entry.label.textLayout.rects(for: NSRange(location: lower - entry.offset, length: upper - lower)).map {
                    entry.label.convert(entry.label.viewRect(fromLayoutRect: $0), to: view)
                }
            }
        }
    }
#endif
