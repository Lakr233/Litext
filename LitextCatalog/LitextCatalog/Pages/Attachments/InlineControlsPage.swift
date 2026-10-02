//
//  InlineControlsPage.swift
//  LitextCatalog
//
//  Created by Litext Team.
//

import SwiftUI

// swiftlint:disable:next todo
// TODO(K2): Live controls as attachments: a UIButton/NSButton, a UISwitch/NSSwitch, a progress indicator, inside
// a sentence; tapping works and the text around stays selectable. Readout of the control state.
// Mention isLocationAboveAttachmentView keeps touches on the control.
struct InlineControlsPage: View {
    var body: some View {
        CatalogPlaceholderView(page: .inlineControls)
    }
}
