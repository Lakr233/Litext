//
//  Created by ktiays on 2024/9/29.
//  Copyright (c) 2024 ktiays. All rights reserved.
//

#ifndef LTXPlatformType_h
#define LTXPlatformType_h

#import <TargetConditionals.h>

#if !TARGET_OS_OSX
#import <UIKit/UIKit.h>

typedef UIView LTXPlatformView;
typedef UIBezierPath LTXPlatformBezierPath;
typedef UIColor PlatformColor;
#else
#import <AppKit/AppKit.h>

typedef NSView LTXPlatformView;
typedef NSBezierPath LTXPlatformBezierPath;
typedef NSColor PlatformColor;
#endif

#endif /* LTXPlatformType_h */
