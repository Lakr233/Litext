//
//  Created by ktiays on 2024/9/29.
//  Copyright (c) 2024 ktiays. All rights reserved.
// 

#ifndef LTXPlatformView_h
#define LTXPlatformView_h

#if __has_include(<UIKit/UIKit.h>)
    #import <UIKit/UIKit.h>

    typedef UIView LTXPlatformView;
#elif __has_include(<AppKit/AppKit.h>)
    #import <AppKit/AppKit.h>

    typedef NSView LTXPlatformView;
#else
    #error "The target OS is not supported!"
#endif

#endif /* LTXPlatformView_h */
