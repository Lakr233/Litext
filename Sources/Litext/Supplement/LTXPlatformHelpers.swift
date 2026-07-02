//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !os(watchOS)
    import UIKit

    let LTXDefaultSelectionTint = UIColor.systemBlue.withAlphaComponent(0.1)
    let LTXDefaultLinkHighlightFallbackColor = UIColor.systemBlue
    let LTXDefaultSelectionHandleTint = UIColor.systemBlue
#elseif canImport(AppKit)
    import AppKit

    let LTXDefaultSelectionTint = NSColor.linkColor.withAlphaComponent(0.1)
    let LTXDefaultLinkHighlightFallbackColor = NSColor.systemBlue

    extension NSColor {
        static var label: NSColor {
            .labelColor
        }
    }
#endif
