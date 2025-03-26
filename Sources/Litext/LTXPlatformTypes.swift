//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation

#if canImport(UIKit)
    import UIKit

    public typealias LTXPlatformView = UIView
    public typealias LTXPlatformBezierPath = UIBezierPath
    public typealias PlatformColor = UIColor
    public typealias PlatformFont = UIFont
    public typealias PlatformSwitch = UISwitch
    public typealias PlatformApplication = UIApplication
#elseif canImport(AppKit)
    import AppKit

    public typealias LTXPlatformView = NSView
    public typealias LTXPlatformBezierPath = NSBezierPath
    public typealias PlatformColor = NSColor
    public typealias PlatformFont = NSFont
    public typealias PlatformSwitch = NSSwitch
    public typealias PlatformApplication = NSApplication
#else
    #error("unsupported platform")
#endif
