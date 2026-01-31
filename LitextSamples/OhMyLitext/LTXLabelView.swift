//
//  LTXLabelView.swift
//  OhMyLitext
//
//  Created by Litext Team.
//

import Litext
import SwiftUI

#if canImport(UIKit)
    public struct LTXLabelView: UIViewRepresentable {
        public var attributedText: NSAttributedString
        public var isSelectable: Bool
        public var onTapLink: ((URL) -> Void)?

        public init(
            attributedText: NSAttributedString,
            isSelectable: Bool = true,
            onTapLink: ((URL) -> Void)? = nil
        ) {
            self.attributedText = attributedText
            self.isSelectable = isSelectable
            self.onTapLink = onTapLink
        }

        public func makeUIView(context: Context) -> LTXLabel {
            let label = LTXLabel()
            label.delegate = context.coordinator
            label.setContentHuggingPriority(.required, for: .vertical)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            return label
        }

        public func updateUIView(_ uiView: LTXLabel, context: Context) {
            uiView.attributedText = attributedText
            uiView.isSelectable = isSelectable
            context.coordinator.onTapLink = onTapLink
        }

        public func makeCoordinator() -> Coordinator {
            Coordinator(onTapLink: onTapLink)
        }

        public class Coordinator: NSObject, LTXLabelDelegate {
            var onTapLink: ((URL) -> Void)?

            init(onTapLink: ((URL) -> Void)?) {
                self.onTapLink = onTapLink
            }

            public func ltxLabelDidTapOnHighlightContent(
                _: LTXLabel,
                region: LTXHighlightRegion?,
                location _: CGPoint
            ) {
                guard let region else { return }
                if let url = region.attributes[.link] as? URL {
                    if let onTapLink {
                        onTapLink(url)
                    } else {
                        #if os(iOS) || os(visionOS)
                            UIApplication.shared.open(url)
                        #elseif os(tvOS)
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        #elseif os(watchOS)
                            // watchOS doesn't support opening URLs directly
                        #endif
                    }
                }
            }

            public func ltxLabelSelectionDidChange(_: LTXLabel, selection _: NSRange?) {}

            public func ltxLabelDetectedUserEventMovingAtLocation(_: LTXLabel, location _: CGPoint) {}
        }
    }

#elseif canImport(AppKit)
    public struct LTXLabelView: NSViewRepresentable {
        public var attributedText: NSAttributedString
        public var isSelectable: Bool
        public var onTapLink: ((URL) -> Void)?

        public init(
            attributedText: NSAttributedString,
            isSelectable: Bool = true,
            onTapLink: ((URL) -> Void)? = nil
        ) {
            self.attributedText = attributedText
            self.isSelectable = isSelectable
            self.onTapLink = onTapLink
        }

        public func makeNSView(context: Context) -> LTXLabel {
            let label = LTXLabel()
            label.delegate = context.coordinator
            label.setContentHuggingPriority(.required, for: .vertical)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            return label
        }

        public func updateNSView(_ nsView: LTXLabel, context: Context) {
            nsView.attributedText = attributedText
            nsView.isSelectable = isSelectable
            context.coordinator.onTapLink = onTapLink
        }

        public func makeCoordinator() -> Coordinator {
            Coordinator(onTapLink: onTapLink)
        }

        public class Coordinator: NSObject, LTXLabelDelegate {
            var onTapLink: ((URL) -> Void)?

            init(onTapLink: ((URL) -> Void)?) {
                self.onTapLink = onTapLink
            }

            public func ltxLabelDidTapOnHighlightContent(
                _: LTXLabel,
                region: LTXHighlightRegion?,
                location _: CGPoint
            ) {
                guard let region else { return }
                if let url = region.attributes[.link] as? URL {
                    if let onTapLink {
                        onTapLink(url)
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            public func ltxLabelSelectionDidChange(_: LTXLabel, selection _: NSRange?) {}

            public func ltxLabelDetectedUserEventMovingAtLocation(_: LTXLabel, location _: CGPoint) {}
        }
    }
#endif

// MARK: - Convenience Extensions

public extension LTXLabelView {
    init(_ text: String, isSelectable: Bool = true) {
        self.init(
            attributedText: NSAttributedString(string: text),
            isSelectable: isSelectable
        )
    }
}
