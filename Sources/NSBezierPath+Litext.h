//
//  Created by ktiays on 2024/9/29.
//  Copyright (c) 2024 ktiays. All rights reserved.
//

#import <TargetConditionals.h>

#if TARGET_OS_OSX

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSBezierPath (Litext)

+ (instancetype)bezierPathWithRoundedRect:(CGRect)rect cornerRadius:(CGFloat)radius;
- (void)appendPath:(NSBezierPath *)path;
- (CGPathRef)quartzPath;

@end

NS_ASSUME_NONNULL_END

#endif
