//
//  Litext.swift
//  Litext
//
//  Created by 秋星桥 on 3/27/25.
//

import Foundation

/// The raw values predate the Swift names and stay unchanged for compatibility with
/// attributed strings built or archived by earlier versions.
public extension NSAttributedString.Key {
    /// Carries the `TextLabel.Attachment` shown in place of its replacement character.
    static let litextAttachment = NSAttributedString.Key("LTXAttachment")
    /// Carries a `TextLabel.LineDrawingAction`, called once for each line the range touches.
    static let litextLineDrawingAction = NSAttributedString.Key("LTXLineDrawingCallback")
}
