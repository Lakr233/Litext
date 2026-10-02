//
//  CatalogLaunchOptions.swift
//  LitextCatalog
//
//  Created by Litext Team.
//
//  The command-line options scripted runs and screenshots use:
//
//    -page <id>                     open a page directly, by its CatalogPageID raw value
//    -demo streaming|numeric|reuse  older names for the three animation pages
//    -slowMotion YES                start the animation pages at a tenth of the speed
//    -effect none|fade|fadeUp       the streaming page's starting effect
//    -autoScroll YES                start the cell reuse page scrolling
//

import Foundation

/// The options the app was launched with.
nonisolated struct CatalogLaunchOptions: Equatable, Sendable {
    /// The streaming page's effects, as `-effect` names them.
    enum StreamingEffect: String, CaseIterable, Sendable {
        case none
        case fade
        case fadeUp
    }

    /// The page to open at launch, from `-page` or, failing that, `-demo`.
    var page: CatalogPageID?
    var isSlowMotion = false
    var streamingEffect: StreamingEffect?
    var isAutoScrolling = false

    /// The speed the animation effects play at in slow motion.
    static let slowMotionSpeed = 0.1

    /// The options of this process.
    static let current = CatalogLaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    /// Reads `-name value` pairs from `arguments`, skipping the executable path and
    /// anything it does not know. A later value for the same name wins.
    init(arguments: [String]) {
        var values: [String: String] = [:]
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            let next = arguments.index(after: index)
            guard argument.hasPrefix("-"), next < arguments.endIndex else {
                index = next
                continue
            }
            values[String(argument.dropFirst())] = arguments[next]
            index = arguments.index(after: next)
        }

        page = values["page"].flatMap(CatalogPageID.init(rawValue:))
            ?? values["demo"].flatMap(Self.page(forDemo:))
        isSlowMotion = values["slowMotion"].map(Self.isTrue) ?? false
        streamingEffect = values["effect"].flatMap(StreamingEffect.init(rawValue:))
        isAutoScrolling = values["autoScroll"].map(Self.isTrue) ?? false
    }

    /// The page an older `-demo` name stands for.
    static func page(forDemo name: String) -> CatalogPageID? {
        switch name {
        case "streaming": .streaming
        case "numeric": .numericTransition
        case "reuse": .cellReuse
        default: nil
        }
    }

    /// Reads a Boolean the way `UserDefaults` reads one from the command line.
    private static func isTrue(_ value: String) -> Bool {
        switch value.lowercased() {
        case "yes", "true", "1": true
        default: false
        }
    }
}
