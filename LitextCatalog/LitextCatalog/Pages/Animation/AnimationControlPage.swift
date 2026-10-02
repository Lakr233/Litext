//
//  AnimationControlPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): LTXAnimatableLabel controls: finishAnimations() button, isAnimating readout (KVO or polling),
// setAttributedText(_:animated:) with an 'animated' toggle, preferredFrameRateRange picker (e.g.
// 30/60/120 — DisplayLinkFrameRateRange needs `import DisplayLink`), animationIdentity change button.
// Host LTXAnimatableLabel via PlatformViewHost.label so the page can call its methods. tvOS:
// CatalogUnavailableView.
struct AnimationControlPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .animationControl)
    }
}
