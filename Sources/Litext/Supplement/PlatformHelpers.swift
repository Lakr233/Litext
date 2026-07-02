//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if canImport(UIKit) && !os(watchOS)
    import UIKit

    let defaultSelectionTint = UIColor.systemBlue.withAlphaComponent(0.1)
    let defaultLinkHighlightFallbackColor = UIColor.systemBlue
    let defaultSelectionHandleTint = UIColor.systemBlue
#elseif canImport(AppKit)
    import AppKit

    let defaultSelectionTint = NSColor.linkColor.withAlphaComponent(0.1)
    let defaultLinkHighlightFallbackColor = NSColor.systemBlue

    extension NSColor {
        static var label: NSColor {
            .labelColor
        }
    }
#endif
