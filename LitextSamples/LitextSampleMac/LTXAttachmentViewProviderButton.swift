//
//  LTXAttachmentViewProviderButton.swift
//  LitextSamples
//
//  Created by 秋星桥 on 7/8/25.
//

import AppKit
import Foundation
import Litext

class LTXAttachmentViewProviderButton: LTXAttachmentViewProvider {
    let title: String
    init(title: String) {
        self.title = title
    }

    func reuseIdentifier() -> String {
        #fileID
    }

    func createView() -> Litext.LTXPlatformView {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        return button
    }

    func configureView(_ view: Litext.LTXPlatformView, for _: Litext.LTXAttachment) {
        print(#function, view)
    }

    func boundingSize(for _: Litext.LTXAttachment) -> CGSize {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        return button.intrinsicContentSize
    }

    func textRepresentation() -> String {
        "Button"
    }
}
