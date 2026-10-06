#if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(tvOS) && !os(watchOS) && !os(visionOS)
    import UIKit

    /// A group has one display interaction and one pair of UIKit handles, rather
    /// than a separate selection UI for each of its labels.
    @available(iOS 17.0, *)
    @MainActor
    final class SystemSelectionDisplay: NSObject {
        private let interaction: UITextSelectionDisplayInteraction
        private weak var proxy: TextLabelInputProxy?

        /// The label whose proxy the display reads.
        var owner: TextLabelView? {
            proxy?.label
        }

        init(proxy: TextLabelInputProxy) {
            self.proxy = proxy
            // UIKit holds its delegate weakly; the label/group retains this owner.
            interaction = UITextSelectionDisplayInteraction(textInput: proxy, delegate: proxy)
            super.init()
        }

        func update() {
            guard let proxy else { detach(); return }
            let view = proxy.textInputView
            let hiddenSelection = proxy.documentLabels.contains {
                $0.isHidden && ($0.selectionRange?.length ?? 0) > 0
            }
            guard proxy.selectedTextRange?.isEmpty == false, view.window != nil,
                  !view.isHidden, !hiddenSelection
            else {
                interaction.isActivated = false
                return
            }
            if interaction.view !== view {
                detach()
                view.addInteraction(interaction)
            }
            interaction.isActivated = true
            interaction.setNeedsSelectionUpdate()
            interaction.layoutManagedSubviews()
            // These are display affordances. The existing window recognizer owns
            // their touch gestures, including grabs outside a label's bounds.
            interaction.highlightView.isUserInteractionEnabled = false
            for handle in interaction.handleViews {
                handle.isUserInteractionEnabled = false
            }
        }

        func handle(_ kind: SelectionHandle.Kind, in label: TextLabelView) -> UIView? {
            guard interaction.isActivated else { return nil }
            if let group = label.selectionGroup, !group.showsHandle(kind == .start, in: label) {
                return nil
            }
            let edge: NSDirectionalRectEdge = kind == .start ? .leading : .trailing
            return interaction.handleViews.first { $0.direction.contains(edge) && !$0.isHidden }
        }

        func detach() {
            interaction.isActivated = false
            interaction.view?.removeInteraction(interaction)
        }

        isolated deinit { detach() }
    }

    @available(iOS 17.0, *)
    extension TextLabelInputProxy: UITextSelectionDisplayInteractionDelegate {}

    extension TextLabelView {
        /// Explicit colors retain the existing drawing contract, including alpha.
        /// UIKit's highlight view exposes geometry, but no exact fill-color API.
        var usesSystemSelectionDisplay: Bool {
            guard #available(iOS 17.0, *) else { return false }
            let members = selectionGroup?.labels ?? [self]
            return members.allSatisfy { $0.selectionBackgroundColor == nil }
        }

        @available(iOS 17.0, *)
        var systemSelectionDisplay: SystemSelectionDisplay? {
            if let group = selectionGroup {
                return group.systemSelectionDisplayStorage as? SystemSelectionDisplay
            }
            return systemSelectionDisplayStorage as? SystemSelectionDisplay
        }

        /// Returns true when UIKit owns selection drawing on this OS.
        func updateSystemSelectionDisplay(presentsMenu: Bool) -> Bool {
            guard #available(iOS 17.0, *) else { return false }
            guard usesSystemSelectionDisplay else {
                systemSelectionDisplay?.detach()
                if let group = selectionGroup {
                    group.systemSelectionDisplayStorage = nil
                } else {
                    systemSelectionDisplayStorage = nil
                }
                return false
            }
            selectionLayer?.removeFromSuperlayer()
            selectionLayer = nil
            selectionHandleStart.isHidden = true
            selectionHandleEnd.isHidden = true
            let hasSelection = selectionGroup?.hasSelection ?? ((selectionRange?.length ?? 0) > 0)
            let owner = selectionDisplayOwner
            if hasSelection, systemSelectionDisplay?.owner !== owner {
                systemSelectionDisplay?.detach()
                owner.updateInputProxy()
                let display = owner.inputProxy.map { SystemSelectionDisplay(proxy: $0) }
                if let group = selectionGroup {
                    group.systemSelectionDisplayStorage = display
                } else {
                    systemSelectionDisplayStorage = display
                }
            }
            systemSelectionDisplay?.update()
            updateSelectionHandleGrabGesture()
            if !hasSelection {
                endSelectionLoupe()
            }
            if presentsMenu {
                if hasSelection {
                    showSelectionMenuController()
                    broadcastSelection()
                } else {
                    hideSelectionMenuController()
                }
            }
            return true
        }

        /// The member whose proxy a group's display reads. Only a selectable member
        /// has a proxy, and only one in a window shares an ancestor with the others,
        /// so the first member is not enough: a header may not be selectable, and a
        /// cell may have scrolled away.
        private var selectionDisplayOwner: TextLabelView {
            guard let group = selectionGroup else { return self }
            let selectable = group.labels.filter(\.isSelectable)
            return selectable.first { $0.window != nil && !$0.isHidden } ?? selectable.first ?? self
        }

        func displayedSelectionHandle(_ kind: SelectionHandle.Kind) -> UIView? {
            if #available(iOS 17.0, *), usesSystemSelectionDisplay {
                return systemSelectionDisplay?.handle(kind, in: self)
            }
            let handle = selectionHandle(kind)
            return handle.isHidden ? nil : handle
        }

        func selectionHandleAnchor(_ kind: SelectionHandle.Kind) -> CGPoint? {
            guard displayedSelectionHandle(kind) != nil else { return nil }
            if #available(iOS 17.0, *), usesSystemSelectionDisplay, let proxy = inputProxy, let range = selectionRange {
                let local = kind == .start ? range.location : NSMaxRange(range)
                let position = TextLabelTextPosition(proxy.documentOffset(in: self) + local)
                let rect = proxy.caretRect(for: position)
                guard !rect.isNull else { return nil }
                let point = CGPoint(x: rect.midX, y: rect.midY)
                return proxy.textInputView.convert(point, to: self)
            }
            let old = selectionHandle(kind)
            return old.convert(old.lineAnchor, to: self)
        }
    }
#endif
