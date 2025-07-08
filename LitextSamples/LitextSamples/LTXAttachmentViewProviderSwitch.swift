//
//  LTXAttachmentViewProviderSwitch.swift
//  LitextSampleMac
//
//  Created by 秋星桥 on 7/8/25.
//

import Foundation
import Litext
import UIKit

class LTXAttachmentViewProviderSwitch: LTXAttachmentViewProvider {
    func reuseIdentifier() -> String {
        #fileID
    }

    func createView() -> Litext.LTXPlatformView {
        UISwitch(frame: .zero)
    }

    func configureView(_ view: Litext.LTXPlatformView, for _: Litext.LTXAttachment) {
        print(#function, view)
    }

    func boundingSize(for _: Litext.LTXAttachment) -> CGSize {
        UISwitch(frame: .zero).intrinsicContentSize
    }

    func textRepresentation() -> String {
        "Switch"
    }
}
