//
//  Created by ktiays on 2025/2/18.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import AppKit
import Litext

final class ViewController: NSViewController {

    let label: LTXLabel = .init()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(label)
        
        let attributedString: NSMutableAttributedString = .init()
        attributedString.append(
            .init(
                string: "Lorem ipsum",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 18, weight: .bold)
                ]
            )
        )
        attributedString.append(
            .init(
                string: " dolor sit amet, consectetur adipiscing elit. ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14)
                ]
            )
        )
        attributedString.append(
            .init(
                string: "Proin eu aliquet orci.",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14),
                    .link: URL(string: "https://www.lipsum.com/")!,
                    .foregroundColor: NSColor.linkColor,
                ]
            )
        )
        attributedString.append(
            .init(
                string: "中文测试，那只敏捷的棕毛狐狸🦊跳上了那只懒狗🐶。",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14),
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: NSColor.red,
                ]
            )
        )

        let attachment: LTXAttachment = .init()
        attachment.view = NSSwitch()
        attachment.size = attachment.view.intrinsicContentSize
        attributedString.append(
            .init(
                string: LTXReplacementText,
                attributes: [
                    .LTXAttachmentAttributeName: attachment,
                    kCTRunDelegateAttributeName as NSAttributedString.Key: attachment.runDelegate,
                ]
            )
        )
        attributedString.append(
            .init(
                string:
                    " Sed quis pretium ligula. Duis dictum faucibus turpis, et sagittis dolor. Ut dapibus fermentum sollicitudin. Nulla commodo pulvinar lobortis. Nunc vel justo ornare nisi pulvinar rhoncus. Duis ornare gravida mauris, sed scelerisque nibh dapibus id.\nNew line test.",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 16),
                    .foregroundColor: NSColor.systemOrange,
                ]
            )
        )

        let paragraphStyle: NSMutableParagraphStyle = .init()
        paragraphStyle.lineSpacing = 4
        attributedString.addAttributes(
            [
                .paragraphStyle: paragraphStyle
            ],
            range: NSRange(location: 0, length: attributedString.length)
        )
        
        self.label.attributedText = attributedString
    }

    override func viewWillLayout() {
        super.viewWillLayout()

        let bounds = view.bounds
        label.preferredMaxLayoutWidth = bounds.width
        let contentSize = label.intrinsicContentSize
        let height = ceil(contentSize.height)
        label.frame = .init(
            x: view.safeAreaInsets.left,
            y: bounds.height - view.safeAreaInsets.top - height,
            width: ceil(contentSize.width),
            height: height
        )
    }
}
