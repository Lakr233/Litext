//
//  LitextCatalogApp.swift
//  LitextCatalog
//
//  Created by 秋星桥 on 2026/02/01.
//

import SwiftUI

@main
struct LitextCatalogApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS) || os(visionOS) || targetEnvironment(macCatalyst)
        .windowResizability(.contentMinSize)
        #endif
    }
}
