//
//  AnimationDemo.swift
//  OhMyLitext
//
//  Created by Litext Team.
//
//  The LitextAnimation demos and how to reach them. Launch the app with
//  `-demo streaming`, `-demo numeric` or `-demo reuse` to open one directly,
//  and add `-slowMotion YES` to start it at a tenth of the speed. The
//  streaming demo also takes `-effect none|fade|fadeUp`, and the reuse demo
//  `-autoScroll YES`.
//

import SwiftUI

#if !os(tvOS)

    /// A page of the animation gallery.
    enum AnimationDemo: String, CaseIterable, Identifiable, Hashable {
        case streaming
        case numeric
        case reuse

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .streaming: "Streaming Text"
            case .numeric: "Numeric Transition"
            case .reuse: "Cell Reuse"
            }
        }

        var summary: String {
            switch self {
            case .streaming: "Simulated model output that fades in as it arrives."
            case .numeric: "A title and a counter that roll from one value to the next."
            case .reuse: "Reused cells show their text at once while one row keeps streaming."
            }
        }

        var systemImage: String {
            switch self {
            case .streaming: "text.bubble"
            case .numeric: "textformat.123"
            case .reuse: "list.bullet.rectangle"
            }
        }

        @ViewBuilder
        var page: some View {
            switch self {
            case .streaming: StreamingDemoView()
            case .numeric: NumericDemoView()
            case .reuse: ReuseDemoView()
            }
        }

        /// The demo named by `-demo <name>` on the command line.
        static var launchDemo: AnimationDemo? {
            UserDefaults.standard.string(forKey: "demo").flatMap(AnimationDemo.init(rawValue:))
        }

        /// Whether `-slowMotion YES` was passed on the command line.
        static var launchesInSlowMotion: Bool {
            UserDefaults.standard.bool(forKey: "slowMotion")
        }

        /// The speed the effects play at in slow motion.
        static let slowMotionSpeed = 0.1
    }

    /// A place in the main navigation stack.
    enum AnimationRoute: Hashable {
        case gallery
        case demo(AnimationDemo)

        /// The stack to open at launch: the gallery and the demo `-demo` names, if any.
        static var launchPath: [AnimationRoute] {
            guard let demo = AnimationDemo.launchDemo else { return [] }
            return [.gallery, .demo(demo)]
        }

        @ViewBuilder
        var page: some View {
            switch self {
            case .gallery: AnimationGalleryView()
            case let .demo(demo): demo.page
            }
        }
    }

    /// Lists the animation demos.
    struct AnimationGalleryView: View {
        var body: some View {
            List {
                Section {
                    ForEach(AnimationDemo.allCases) { demo in
                        NavigationLink(value: AnimationRoute.demo(demo)) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(demo.title)
                                    Text(demo.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: demo.systemImage)
                            }
                        }
                        .accessibilityIdentifier("demo.animation.\(demo.rawValue)")
                    }
                } footer: {
                    Text("Every effect here is an LTXTextAnimator written in the sample app. LitextAnimation itself ships none.")
                }
            }
            .navigationTitle("Animation")
        }
    }

#endif
