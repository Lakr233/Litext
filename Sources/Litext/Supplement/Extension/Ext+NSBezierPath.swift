//
//  Created by Lakr233 & Helixform on 2025/2/18.
//  Copyright (c) 2025 Litext Team. All rights reserved.
//

#if !canImport(UIKit) && canImport(AppKit)
    extension NSBezierPath {
        func appendPath(_ path: NSBezierPath) {
            append(path)
        }

        var quartzPath: CGPath {
            if #available(macOS 14.0, *) {
                return cgPath
            }

            let path = CGMutablePath()
            var points = [NSPoint](repeating: .zero, count: 3)

            for i in 0 ..< elementCount {
                let type = element(at: i, associatedPoints: &points)

                switch type {
                case .moveTo:
                    path.move(to: points[0])
                case .lineTo:
                    path.addLine(to: points[0])
                case .curveTo:
                    path.addCurve(to: points[2], control1: points[0], control2: points[1])
                case .closePath:
                    path.closeSubpath()
                case .cubicCurveTo:
                    assertionFailure() // we do not use cubic curves in Litext
                case .quadraticCurveTo:
                    assertionFailure() // we do not use quadratic curves in Litext
                    break
                @unknown default:
                    break
                }
            }

            return path
        }

        static func bezierPath(withRoundedRect rect: CGRect, cornerRadius: CGFloat) -> NSBezierPath {
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        }
    }
#endif
