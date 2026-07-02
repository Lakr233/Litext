//
//  LocalizedText.swift
//  Litext
//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation

//
// Make sure to add following key to Info.plist
//
// **Localized resources can be mixed** -> true
//

enum LocalizedText {
    static let copy = NSLocalizedString("Copy", bundle: .module, comment: "Copy menu item")
    static let selectAll = NSLocalizedString("Select All", bundle: .module, comment: "Select all menu item")
    static let share = NSLocalizedString("Share", bundle: .module, comment: "Share menu item")
    static let openLink = NSLocalizedString("Open Link", bundle: .module, comment: "Open link menu item")
    static let copyLink = NSLocalizedString("Copy Link", bundle: .module, comment: "Copy link menu item")
}
