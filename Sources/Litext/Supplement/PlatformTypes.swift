//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

@_exported import CoreGraphics
@_exported import CoreText
@_exported import Foundation

#if canImport(UIKit) && !os(watchOS)
    @_exported import UIKit

    public typealias PlatformView = UIView
    public typealias PlatformBezierPath = UIBezierPath

    public typealias PlatformColor = UIColor
    public typealias PlatformFont = UIFont
    public typealias PlatformApplication = UIApplication
#elseif canImport(AppKit)
    @_exported import AppKit

    public typealias PlatformView = NSView
    public typealias PlatformBezierPath = NSBezierPath

    public typealias PlatformColor = NSColor
    public typealias PlatformFont = NSFont
    public typealias PlatformApplication = NSApplication
#endif
// watchOS: canImport(UIKit) is true but UIView/UIApplication etc. are unavailable.
// None of the above platform types are defined on watchOS - this is intentional.
