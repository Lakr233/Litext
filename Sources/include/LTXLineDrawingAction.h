//
//  Created by ktiays on 2025/1/22.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

#import <CoreText/CoreText.h>

#import "LTXPlatformTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface LTXLineDrawingAction : NSObject

@property (nonatomic, copy) void (^action)(CGContextRef context, CTLineRef line, CGPoint lineOrigin);

- (instancetype)initWithAction:(void (^)(CGContextRef context, CTLineRef line, CGPoint lineOrigin))action;

@end

NS_ASSUME_NONNULL_END
