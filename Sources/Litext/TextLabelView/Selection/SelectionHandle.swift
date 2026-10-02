//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation

#if canImport(UIKit) && !os(tvOS) && !os(watchOS)

    /// One of the two grabbers at the ends of a selection on iOS and visionOS.
    ///
    /// The label creates and places its own pair, colored by
    /// `selectionBackgroundColor`; there is no hook that substitutes a subclass, so
    /// the class stays `open` only for source compatibility.
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

        /// Which end of the selection a handle marks.
        public enum Kind {
            case start
            case end
        }

        /// The end of the selection this handle marks.
        public let kind: Kind

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

        /// Creates a handle for one end of a selection.
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
            // The label's window takes the touches on a handle. See SelectionHandleGrabGesture.
            isUserInteractionEnabled = false
            addSubview(stickView)
            addSubview(knobView)
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

        /// Lays out the knob and the stick for the handle's kind.
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

        /// Where a touch grabs the handle, in the superview's coordinates: the handle
        /// enlarged on every side so the thin stick and small knob are easy to hit.
        var grabArea: CGRect {
            frame.insetBy(dx: -Self.knobExtraResponsiveArea, dy: -Self.knobExtraResponsiveArea)
        }

        /// The distance from `point`, in the superview's coordinates, to the knob's centre.
        func knobDistance(to point: CGPoint) -> CGFloat {
            let centerY: CGFloat = switch kind {
            case .start: frame.minY + Self.knobRadius
            case .end: frame.maxY - Self.knobRadius
            }
            return hypot(point.x - frame.midX, point.y - centerY)
        }
    }
#endif
