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
        /// Sized and placed like the grabbers of the system text views, measured on
        /// iOS 18 and later: a 16.5 pt knob that reaches 3 pt into the line it caps, over
        /// a 2 pt stick with rounded ends that spans the whole line.
        static let knobDiameter: CGFloat = 16.5
        static var knobRadius: CGFloat {
            knobDiameter / 2
        }

        /// How far the knob reaches into the line it caps, hiding the end of the stick.
        static let knobOverlap: CGFloat = 3
        /// How far the handle reaches past the line, above it for the start handle and
        /// below it for the end handle.
        static var knobExtent: CGFloat {
            knobDiameter - knobOverlap
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
            view.layer.shadowOffset = CGSize(width: 0, height: 2)
            view.layer.shadowOpacity = 0.3
            view.layer.shadowRadius = 8
            return view
        }()

        private lazy var stickView: UIView = {
            let view = UIView()
            view.backgroundColor = handleColor
            view.layer.cornerRadius = Self.stickWidth / 2
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

        /// The handle's frame for the selection edge on `lineRect`, the rect of the
        /// first selected character for the start handle or the last one for the end
        /// handle, in the label's coordinates.
        func frame(forLineRect lineRect: CGRect) -> CGRect {
            switch kind {
            case .start:
                CGRect(
                    x: lineRect.minX - Self.handleWidth / 2 - Self.stickOutset,
                    y: lineRect.minY - Self.knobExtent,
                    width: Self.handleWidth,
                    height: lineRect.height + Self.knobExtent,
                )
            case .end:
                CGRect(
                    x: lineRect.maxX - Self.handleWidth / 2 + Self.stickOutset,
                    y: lineRect.minY,
                    width: Self.handleWidth,
                    height: lineRect.height + Self.knobExtent,
                )
            }
        }

        /// The part of the handle beside the selected line, in the handle's coordinates.
        private var lineSpan: (minY: CGFloat, maxY: CGFloat) {
            switch kind {
            case .start: (Self.knobExtent, bounds.height)
            case .end: (0, bounds.height - Self.knobExtent)
            }
        }

        /// The middle of the selected line beside the stick, in the handle's
        /// coordinates. A drag reports this point so it stays on the line however
        /// short the line is next to the knob.
        var lineAnchor: CGPoint {
            CGPoint(x: bounds.midX, y: (lineSpan.minY + lineSpan.maxY) / 2)
        }

        override open func layoutSubviews() {
            super.layoutSubviews()
            // The stick runs from the knob's centre, where the knob hides its end, to
            // the far edge of the line, where its rounded end finishes flush.
            let stickMinY: CGFloat = switch kind {
            case .start: Self.knobRadius
            case .end: 0
            }
            let stickMaxY: CGFloat = switch kind {
            case .start: bounds.height
            case .end: bounds.height - Self.knobRadius
            }
            stickView.frame = .init(
                x: bounds.midX - Self.stickWidth / 2,
                y: stickMinY,
                width: Self.stickWidth,
                height: max(0, stickMaxY - stickMinY),
            )

            let knobY: CGFloat = switch kind {
            case .start: 0
            case .end: bounds.height - Self.knobDiameter
            }
            knobView.frame = .init(
                x: bounds.midX - Self.knobRadius,
                y: knobY,
                width: Self.knobDiameter,
                height: Self.knobDiameter,
            )
            knobView.layer.shadowPath = UIBezierPath(ovalIn: knobView.bounds).cgPath
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
                    height: frameAtGestureBegin.height,
                )
                let anchor = lineAnchor
                delegate?.selectionHandleDidMove(
                    kind,
                    toLocationInSuperView: .init(x: newFrame.minX + anchor.x, y: newFrame.minY + anchor.y),
                )
            case .ended, .cancelled, .failed:
                delegate?.selectionHandleDidEndDrag(kind)
            default: return
            }
        }

        override open func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
            let touchRect = bounds.insetBy(
                dx: -Self.knobExtraResponsiveArea,
                dy: -Self.knobExtraResponsiveArea,
            )
            return touchRect.contains(point)
        }
    }
#endif
