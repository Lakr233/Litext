import Foundation

#if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS) && !os(visionOS)
    import UIKit

    /// One session per gesture, even when its active endpoint moves to another label.
    @MainActor
    final class SelectionLoupe {
        // Erased so the package can still deploy to iOS 15.
        private var sessionStorage: AnyObject?
        private(set) weak var coordinateView: UIView?

        func begin(at point: CGPoint, from widget: UIView?, in view: UIView) {
            invalidate()
            coordinateView = view
            if #available(iOS 17.0, *) {
                sessionStorage = UITextLoupeSession.begin(at: point, fromSelectionWidgetView: widget, in: view)
            }
        }

        func move(to point: CGPoint, caret: CGRect) {
            if #available(iOS 17.0, *), let session = sessionStorage as? UITextLoupeSession {
                session.move(to: point, withCaretRect: caret, trackingCaret: !caret.isNull)
            }
        }

        func invalidate() {
            if #available(iOS 17.0, *) {
                (sessionStorage as? UITextLoupeSession)?.invalidate()
            }
            sessionStorage = nil
            coordinateView = nil
        }

        isolated deinit { invalidate() }
    }

    extension TextLabelView {
        func beginSelectionLoupe(at point: CGPoint, kind: SelectionHandle.Kind, fromHandle: Bool = false) {
            guard window != nil else { return }
            let loupe = SelectionLoupe()
            selectionLoupe?.invalidate()
            selectionLoupe = loupe
            // UIKit resolves the containing controller/keyboard scene from this
            // view. A UIWindow is not a valid interaction view for that lookup.
            let widget = fromHandle ? displayedSelectionHandle(kind) : nil
            loupe.begin(at: point, from: widget, in: self)
            moveSelectionLoupe(at: point, kind: kind)
        }

        func moveSelectionLoupe(at point: CGPoint, kind: SelectionHandle.Kind) {
            guard let window, let loupe = selectionLoupe, let coordinateView = loupe.coordinateView else { return }
            var endpointLabel = self
            if let group = selectionGroup, let selection = group.selection {
                let position = kind == .start ? selection.start : selection.end
                guard let member = group.memberLabel(at: position.member) else {
                    endSelectionLoupe()
                    return
                }
                endpointLabel = member
            }
            guard endpointLabel.window === window, let range = endpointLabel.selectionRange,
                  range.length > 0
            else {
                endSelectionLoupe()
                return
            }
            let index = kind == .start ? range.location : NSMaxRange(range)
            let lineIndex = kind == .start ? range.location : index - 1
            let caret = endpointLabel.textLayout.caretRect(at: index, onLineOf: lineIndex).map {
                var rect = endpointLabel.convertRectFromTextLayout($0, insetForInteraction: false)
                // CoreText reports a zero-width caret; UIKit expects a visible
                // caret/range-handle rectangle, as supplied by a UITextView.
                rect.size.width = max(1, rect.width)
                return endpointLabel.convert(rect, to: coordinateView)
            } ?? CGRect.null
            loupe.move(to: convert(point, to: coordinateView), caret: caret)
        }

        func endSelectionLoupe() {
            selectionLoupe?.invalidate()
            selectionLoupe = nil
        }
    }
#endif
