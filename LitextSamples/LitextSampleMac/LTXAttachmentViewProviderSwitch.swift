//
//  LTXAttachmentViewProviderSwitch.swift
//  LitextSampleMac
//
//  Created by 秋星桥 on 7/8/25.
//

import AppKit
import Foundation
import Litext

class LTXAttachmentViewProviderSwitch: LTXAttachmentViewProvider {
    func reuseIdentifier() -> String {
        #fileID
    }

    func createView() -> Litext.LTXPlatformView {
        NSSwitch(frame: .zero)
    }

    func configureView(_ view: Litext.LTXPlatformView, for _: Litext.LTXAttachment) {
        guard let switchView = view as? NSSwitch else { return }
        print(switchView)
    }

    func boundingSize(for _: Litext.LTXAttachment) -> CGSize {
        NSSwitch(frame: .zero).intrinsicContentSize
    }

    func textRepresentation() -> String {
        "Switch"
    }
}
