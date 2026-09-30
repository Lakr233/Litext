//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation

#if canImport(UIKit) && !os(tvOS) && !os(watchOS)

    @MainActor
    protocol SelectionHandleDelegate: AnyObject {
        func selectionHandleDidBeginDrag(_ kind: SelectionHandle.Kind)
        func selectionHandleDidMove(_ kind: SelectionHandle.Kind, toLocationInSuperView point: CGPoint)
        func selectionHandleDidEndDrag(_ kind: SelectionHandle.Kind)
    }

    open class SelectionHandle: UIView {
        static let knobDiameter: CGFloat = 12
        static var knobRadius: CGFloat {
            knobDiameter / 2
        }

        /// The handle view's width. It is wider than the knob so the handle is
        /// easier to grab, and the knob and stick are centred in it.
        static let handleWidth: CGFloat = knobDiameter * 2
        /// How far each handle's stick sits outside the selection edge, in points.
        static let stickOutset: CGFloat = 1
        static let stickWidth: CGFloat = 2
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
            view.layer.cornerRadius = Self.knobRadius
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

        public required init?(coder: NSCoder) {
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

        override open func layoutSubviews() {
            super.layoutSubviews()
            stickView.frame = .init(
                x: bounds.midX - Self.stickWidth / 2,
                y: bounds.minY,
                width: Self.stickWidth,
                height: bounds.height
            )

            let knobY: CGFloat = switch kind {
            case .start: 0
            case .end: bounds.height - Self.knobDiameter
            }
            knobView.frame = .init(
                x: bounds.midX - Self.knobRadius,
                y: knobY,
                width: Self.knobDiameter,
                height: Self.knobDiameter
            )
        }

        private var frameAtGestureBegin: CGRect = .zero

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                frameAtGestureBegin = frame
                delegate?.selectionHandleDidBeginDrag(kind)
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
            case .ended, .cancelled, .failed:
                delegate?.selectionHandleDidEndDrag(kind)
            default: return
            }
        }

        override open func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
            let touchRect = bounds.insetBy(
                dx: -Self.knobExtraResponsiveArea,
                dy: -Self.knobExtraResponsiveArea
            )
            return touchRect.contains(point)
        }
    }
#endif
