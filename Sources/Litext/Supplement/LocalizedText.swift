//
//  LocalizedText.swift
//  Litext
//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation

/// Menu titles, localized from the package's own resource bundle.
///
/// A host app localized in fewer languages than Litext shows these titles in its
/// own development language unless the app's Info.plist sets
/// `CFBundleAllowMixedLocalizations` ("Localized resources can be mixed") to `true`.
/// The key is read from the host app's bundle, not from this package.
enum LocalizedText {
    static let copy = NSLocalizedString("Copy", bundle: .module, comment: "Copy menu item")
    static let selectAll = NSLocalizedString("Select All", bundle: .module, comment: "Select all menu item")
    static let share = NSLocalizedString("Share", bundle: .module, comment: "Share menu item")
    static let openLink = NSLocalizedString("Open Link", bundle: .module, comment: "Open link menu item")
    static let copyLink = NSLocalizedString("Copy Link", bundle: .module, comment: "Copy link menu item")
}
