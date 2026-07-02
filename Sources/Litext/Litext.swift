//
//  Litext.swift
//  Litext
//
//  Created by 秋星桥 on 3/27/25.
//

import Foundation

public extension NSAttributedString.Key {
    @inline(__always) static let litextAttachment = NSAttributedString.Key("LTXAttachment")
    @inline(__always) static let litextLineDrawingAction = NSAttributedString.Key("LTXLineDrawingCallback")
}
