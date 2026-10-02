//
//  CatalogRegistryTests.swift
//  LitextCatalogTests
//
//  Created by Litext Team.
//
//  The catalog's table of contents and its launch arguments: every page is
//  reachable from the sidebar and from `-page`, and the older `-demo` names
//  still open the animation pages.
//

import Foundation
import Testing

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct CatalogRegistryTests {
    @Test
    func `every page has a unique identifier, title and symbol`() {
        let pages = CatalogPageID.allCases
        #expect(Set(pages.map(\.rawValue)).count == pages.count)
        #expect(Set(pages.map(\.title)).count == pages.count)
        for page in pages {
            #expect(!page.title.isEmpty)
            #expect(!page.summary.isEmpty)
            #expect(!page.systemImage.isEmpty)
        }
    }

    @Test
    func `every identifier names its group`() {
        let prefixes: [CatalogGroup: String] = [
            .basics: "basics.",
            .typography: "typography.",
            .international: "international.",
            .interaction: "interaction.",
            .attachments: "attachments.",
            .layout: "layout.",
            .listsAndPerformance: "lists.",
            .animation: "animation.",
        ]
        #expect(prefixes.count == CatalogGroup.allCases.count)
        for page in CatalogPageID.allCases {
            let prefix = prefixes[page.group] ?? "?"
            #expect(page.rawValue.hasPrefix(prefix), "\(page.rawValue) is not in \(prefix)")
        }
    }

    @Test
    func `the groups list every page exactly once, in order`() {
        let listed = CatalogGroup.allCases.flatMap(\.pages)
        #expect(listed == CatalogPageID.allCases)
        for group in CatalogGroup.allCases {
            #expect(!group.pages.isEmpty, "\(group.title) has no pages")
        }
    }

    @Test(arguments: CatalogPageID.allCases)
    func `every page opens from -page`(page: CatalogPageID) {
        let options = CatalogLaunchOptions(arguments: ["LitextCatalog", "-page", page.rawValue])
        #expect(options.page == page)
    }

    @Test
    func `the -demo names open the animation pages`() {
        let expected: [String: CatalogPageID] = [
            "streaming": .streaming,
            "numeric": .numericTransition,
            "reuse": .cellReuse,
        ]
        for (name, page) in expected {
            #expect(CatalogLaunchOptions(arguments: ["app", "-demo", name]).page == page)
        }
        #expect(CatalogLaunchOptions(arguments: ["app", "-demo", "gallery"]).page == nil)
    }

    @Test
    func `-page wins over -demo, and unknown pages open nothing`() {
        let both = CatalogLaunchOptions(arguments: ["app", "-demo", "reuse", "-page", "basics.markdown"])
        #expect(both.page == .markdown)
        let unknownPage = CatalogLaunchOptions(arguments: ["app", "-page", "nope", "-demo", "numeric"])
        #expect(unknownPage.page == .numericTransition)
        #expect(CatalogLaunchOptions(arguments: ["app", "-page", "nope"]).page == nil)
        #expect(CatalogLaunchOptions(arguments: ["app"]).page == nil)
        #expect(CatalogLaunchOptions(arguments: []).page == nil)
    }

    @Test
    func `the animation flags read like UserDefaults booleans`() {
        let options = CatalogLaunchOptions(arguments: [
            "app", "-slowMotion", "YES", "-effect", "fadeUp", "-autoScroll", "true",
        ])
        #expect(options.isSlowMotion)
        #expect(options.isAutoScrolling)
        #expect(options.streamingEffect == .fadeUp)

        let off = CatalogLaunchOptions(arguments: ["app", "-slowMotion", "NO", "-effect", "sparkle", "-autoScroll", "0"])
        #expect(!off.isSlowMotion)
        #expect(!off.isAutoScrolling)
        #expect(off.streamingEffect == nil)
    }

    @Test
    func `a flag without a value and system arguments are skipped`() {
        let options = CatalogLaunchOptions(arguments: [
            "app", "-NSDocumentRevisionsDebugMode", "YES", "-page", "layout.sizing", "-slowMotion",
        ])
        #expect(options.page == .sizing)
        #expect(!options.isSlowMotion)
    }

    @Test
    func `every sidebar symbol exists`() {
        for page in CatalogPageID.allCases {
            #if canImport(UIKit)
                let image = UIImage(systemName: page.systemImage)
            #else
                let image = NSImage(systemSymbolName: page.systemImage, accessibilityDescription: nil)
            #endif
            #expect(image != nil, "\(page.systemImage) for \(page.rawValue) is not an SF Symbol")
        }
    }
}
