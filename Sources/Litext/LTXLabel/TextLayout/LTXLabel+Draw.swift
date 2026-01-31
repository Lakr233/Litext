//
//  LTXLabel+Draw.swift
//  Litext
//
//  Created by 秋星桥 on 3/27/25.
//

import Foundation

#if canImport(UIKit)
    import UIKit

    public extension LTXLabel {
        override func draw(_: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else { return }
            UIGraphicsPushContext(context)
            textLayout.draw(in: context)
            UIGraphicsPopContext()
        }
    }

#elseif canImport(AppKit)
    import AppKit

    public extension LTXLabel {
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            textLayout.draw(in: context)
        }

        override var isFlipped: Bool {
            true
        }
    }
#endif
