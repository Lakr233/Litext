//
//  Created by Cyandev on 2022/5/9.
//  Copyright (c) 2024 ktiays. All rights reserved.
//

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LTXHighlightRegion : NSObject

@property (nonatomic, readonly, copy) NSArray<NSValue *> *rects;
@property (nonatomic, readonly, copy) NSDictionary *attributes;
@property (nonatomic, readonly, assign) NSRange stringRange;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
