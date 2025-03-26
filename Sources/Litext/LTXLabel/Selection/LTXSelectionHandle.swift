//
//  Created by Litext Team.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

import Foundation

#if canImport(UIKit)
    public class LTXSelectionHandle: UIView {
        public enum HandleType {
            case start
            case end
        }

        public let type: HandleType

        private let knobView: UIView = {
            let view = UIView()
            view.backgroundColor = .systemBlue
            view.layer.cornerRadius = 6
            view.layer.shadowColor = UIColor.black.cgColor
            view.layer.shadowOffset = CGSize(width: 0, height: 1)
            view.layer.shadowOpacity = 0.3
            view.layer.shadowRadius = 1.5
            return view
        }()

        private let stickView: UIView = {
            let view = UIView()
            view.backgroundColor = .systemBlue
            return view
        }()

        public var dragHandler: ((CGPoint) -> Void)?

        public init(type: HandleType) {
            self.type = type
            super.init(frame: CGRect(x: 0, y: 0, width: 12, height: 24))
            setupView()
        }

        required init?(coder: NSCoder) {
            type = .start
            super.init(coder: coder)
            setupView()
        }

        private func setupView() {
            backgroundColor = .clear
            isUserInteractionEnabled = true
            addSubview(stickView)
            stickView.frame = CGRect(x: 6 - 1, y: 0, width: 2, height: 14)
            addSubview(knobView)
            knobView.frame = CGRect(x: 0, y: 14, width: 12, height: 12)
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            addGestureRecognizer(panGesture)
            if type == .start {
                stickView.center.x = 7
                transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
            } else {
                stickView.center.x = 5
                transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
            }
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: superview)
            dragHandler?(point)
        }

        override public func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
            let touchRect = bounds.insetBy(dx: -20, dy: -20)
            return touchRect.contains(point)
        }
    }
#endif
