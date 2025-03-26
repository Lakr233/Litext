//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Litext
import UIKit

class ViewController: UIViewController {
    let label = LTXLabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        view.addSubview(label)

        let attributedString = NSMutableAttributedString()
        attributedString.append(
            NSAttributedString(
                string: "Hello, Litext!",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                    .foregroundColor: UIColor.label,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: " This is a rich text label supporting ",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 16),
                    .foregroundColor: UIColor.label,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: "clickable links",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 16),
                    .link: URL(string: "https://example.com")!,
                    .foregroundColor: UIColor.systemBlue,
                ]
            )
        )

        attributedString.append(
            NSAttributedString(
                string: " and embedded views:",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 16),
                    .foregroundColor: UIColor.label,
                ]
            )
        )

        // 添加一个开关控件
        let attachment = LTXAttachment()
        let switchView = UISwitch()
        attachment.view = switchView
        attachment.size = switchView.intrinsicContentSize

        attributedString.append(
            NSAttributedString(
                string: LTXReplacementText,
                attributes: [
                    LTXAttachmentAttributeName: attachment,
                    kCTRunDelegateAttributeName as NSAttributedString.Key: attachment.runDelegate,
                ]
            )
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        attributedString.addAttributes(
            [.paragraphStyle: paragraphStyle],
            range: NSRange(location: 0, length: attributedString.length)
        )

        label.attributedText = attributedString
        label.tapHandler = { highlightRegion, _ in
            if let url = highlightRegion?.attributes[.link] as? URL {
                UIApplication.shared.open(url)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let margins = view.layoutMargins
        label.preferredMaxLayoutWidth = view.bounds.width - margins.left - margins.right

        let labelSize = label.intrinsicContentSize
        label.frame = CGRect(
            x: margins.left,
            y: margins.top + 20,
            width: label.preferredMaxLayoutWidth,
            height: labelSize.height
        )
    }
}
