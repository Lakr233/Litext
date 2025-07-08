//
//  LTXAttachmentViewProviderButton.swift
//  LitextSamples
//
//  Created by 秋星桥 on 7/8/25.
//

import Foundation
import Litext
import UIKit

class LTXAttachmentViewProviderButton: LTXAttachmentViewProvider {
    let title: String
    init(title: String) {
        self.title = title
    }

    func reuseIdentifier() -> String {
        #fileID
    }

    func createView() -> Litext.LTXPlatformView {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.systemBlue, for: .normal)
        return button
    }

    func configureView(_ view: Litext.LTXPlatformView, for _: Litext.LTXAttachment) {
        print(#function, view)
    }

    func boundingSize(for _: Litext.LTXAttachment) -> CGSize {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.systemBlue, for: .normal)
        return button.intrinsicContentSize
    }

    func textRepresentation() -> String {
        "Button"
    }
}
