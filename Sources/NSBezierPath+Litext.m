//
//  Created by ktiays on 2024/9/29.
//  Copyright (c) 2024 ktiays. All rights reserved.
//

#import <TargetConditionals.h>

#if TARGET_OS_OSX

#import "NSBezierPath+Litext.h"

@implementation NSBezierPath (Litext)

+ (instancetype)bezierPathWithRoundedRect:(CGRect)rect cornerRadius:(CGFloat)radius {
    return [self bezierPathWithRoundedRect:NSRectFromCGRect(rect) xRadius:radius yRadius:radius];
}

- (void)appendPath:(NSBezierPath *)path {
    return [self appendBezierPath:path];
}

- (CGPathRef)quartzPath {
    if (@available(macOS 14.0, *)) {
        return [self CGPath];
    }

    NSInteger i, numElements;

    // Need to begin a path here.
    CGPathRef immutablePath = NULL;

    // Then draw the path elements.
    numElements = [self elementCount];
    if (numElements > 0) {
        CGMutablePathRef path = CGPathCreateMutable();
        NSPoint points[3];
        BOOL didClosePath = YES;

        for (i = 0; i < numElements; i++) {
            switch ([self elementAtIndex:i associatedPoints:points]) {
            case NSBezierPathElementMoveTo:
                CGPathMoveToPoint(path, NULL, points[0].x, points[0].y);
                break;

            case NSBezierPathElementLineTo:
                CGPathAddLineToPoint(path, NULL, points[0].x, points[0].y);
                didClosePath = NO;
                break;

            case NSBezierPathElementCurveTo:
                CGPathAddCurveToPoint(path, NULL, points[0].x, points[0].y, points[1].x, points[1].y, points[2].x, points[2].y);
                didClosePath = NO;
                break;

            case NSBezierPathElementQuadraticCurveTo:
                CGPathAddQuadCurveToPoint(path, NULL, points[0].x, points[0].y, points[1].x, points[1].y);
                didClosePath = NO;
                break;

            case NSBezierPathElementClosePath:
                CGPathCloseSubpath(path);
                didClosePath = YES;
                break;
            }
        }

        // Be sure the path is closed or Quartz may not do valid hit detection.
        if (!didClosePath) {
            CGPathCloseSubpath(path);
        }

        immutablePath = CGPathCreateCopy(path);
        CGPathRelease(path);
    }

    return immutablePath;
}

@end

#endif
