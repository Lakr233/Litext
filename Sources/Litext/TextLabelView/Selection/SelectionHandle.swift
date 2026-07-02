//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation

#if canImport(UIKit) && !os(tvOS) && !os(watchOS)

    @MainActor
    protocol SelectionHandleDelegate: AnyObject {
        func selectionHandleDidMove(_ kind: SelectionHandle.Kind, toLocationInSuperView point: CGPoint)
    }

    public class SelectionHandle: UIView {
        static let knobRadius: CGFloat = 12
        static let knobExtraResponsiveArea: CGFloat = 20

        public enum Kind {
            case start
            case end
        }

        public let kind: Kind

        weak var delegate: SelectionHandleDelegate?

        private(set) var handleColor: UIColor = defaultSelectionHandleTint {
            didSet {
                knobView.backgroundColor = handleColor
                stickView.backgroundColor = handleColor
            }
        }

        private lazy var knobView: UIView = {
            let view = UIView()
            view.backgroundColor = handleColor
            view.layer.cornerRadius = Self.knobRadius / 2
            view.layer.shadowColor = UIColor.black.cgColor
            view.layer.shadowOffset = CGSize(width: 0, height: 1)
            view.layer.shadowOpacity = 0.25
            view.layer.shadowRadius = 1.5
            return view
        }()

        private lazy var stickView: UIView = {
            let view = UIView()
            view.backgroundColor = handleColor
            return view
        }()

        func updateHandleColor(_ color: UIColor?) {
            handleColor = color ?? defaultSelectionHandleTint
        }

        public init(kind: Kind) {
            self.kind = kind
            super.init(frame: .zero)
            setupView()
        }

        required init?(coder: NSCoder) {
            kind = .start
            super.init(coder: coder)
            setupView()
        }

        private func setupView() {
            backgroundColor = .clear
            isUserInteractionEnabled = true
            addSubview(stickView)
            addSubview(knobView)
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            panGesture.cancelsTouchesInView = true
            addGestureRecognizer(panGesture)
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            let stickWidth = 2
            stickView.frame = .init(
                x: bounds.midX - CGFloat(stickWidth) / 2,
                y: bounds.minY,
                width: CGFloat(stickWidth),
                height: bounds.height
            )

            let knobRadius: CGFloat = knobView.layer.cornerRadius
            switch kind {
            case .start:
                knobView.frame = .init(
                    x: bounds.midX - knobRadius,
                    y: 0,
                    width: knobRadius * 2,
                    height: knobRadius * 2
                )
            case .end:
                knobView.frame = .init(
                    x: bounds.midX - knobRadius,
                    y: bounds.height - knobRadius * 2,
                    width: knobRadius * 2,
                    height: knobRadius * 2
                )
            }
        }

        private var frameAtGestureBegin: CGRect = .zero

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                frameAtGestureBegin = frame
                fallthrough
            case .changed:
                let translation = gesture.translation(in: superview)
                let newFrame = CGRect(
                    x: frameAtGestureBegin.origin.x + translation.x,
                    y: frameAtGestureBegin.origin.y + translation.y,
                    width: frameAtGestureBegin.width,
                    height: frameAtGestureBegin.height
                )
                delegate?.selectionHandleDidMove(kind, toLocationInSuperView: .init(x: newFrame.midX, y: newFrame.midY))
            default: return
            }
        }

        override public func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
            let touchRect = bounds.insetBy(
                dx: -Self.knobExtraResponsiveArea,
                dy: -Self.knobExtraResponsiveArea
            )
            return touchRect.contains(point)
        }
    }
#endif
