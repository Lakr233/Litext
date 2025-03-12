//
//  Created by ktiays on 2025/1/22.
//  Copyright (c) 2025 Helixform. All rights reserved.
//

#import <CoreText/CoreText.h>

#import "LTXPlatformTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface LTXLineDrawingAction : NSObject

@property (nonatomic, copy) void (^action)(CGContextRef context, CTLineRef line, CGPoint lineOrigin);
@property (nonatomic, assign) BOOL performOncePerAttribute;

- (instancetype)initWithAction:(void (^)(CGContextRef context, CTLineRef line, CGPoint lineOrigin))action;
- (instancetype)initWithMultilineAction:(void (^)(CGContextRef context, CTLineRef line, CGPoint lineOrigin))action NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
