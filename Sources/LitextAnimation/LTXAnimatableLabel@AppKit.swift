//
//  LTXAnimatableLabel@AppKit.swift
//  LitextAnimation
//
//  Created by Litext Team.
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    import AppKit
    import Litext

    extension LTXAnimatableLabel {
        /// Finishes the animations when the label leaves its window. Overrides must call
        /// `super`.
        override open func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowDidChange()
        }

        /// Moves the animation region with the laid-out lines. Overrides must call `super`.
        override open func layout() {
            super.layout()
            layoutDidChange()
        }
    }

#endif
