//
//  LTXLabel+Draw.swift
//  Litext
//
//  Created by 秋星桥 on 3/27/25.
//

import Foundation

public extension LTXLabel {
    #if canImport(UIKit)
        override func draw(_: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else { return }

            if flags.needsUpdateHighlightRegions {
                textLayout?.updateHighlightRegions(with: context)
                highlightRegions = textLayout?.highlightRegions ?? []
                updateAttachmentViews()
                flags.needsUpdateHighlightRegions = false
            }

            textLayout?.draw(in: context)
        }

    #elseif canImport(AppKit)
        override func draw(_: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }

            if flags.needsUpdateHighlightRegions {
                textLayout?.updateHighlightRegions(with: context)
                highlightRegions = textLayout?.highlightRegions ?? []
                updateAttachmentViews()
                flags.needsUpdateHighlightRegions = false
            }

            textLayout?.draw(in: context)
        }
    #endif
}
