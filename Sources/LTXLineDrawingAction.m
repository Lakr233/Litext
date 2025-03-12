//
//  Created by ktiays on 2025/1/22.
//  Copyright (c) 2025 Helixform. All rights reserved.
//

#import "LTXLineDrawingAction.h"

@implementation LTXLineDrawingAction

- (instancetype)initWithAction:(void (^)(CGContextRef, CTLineRef, CGPoint))action {
    self = [self initWithMultilineAction:action];
    if (self) {
        // For backward-compatibility.
        _performOncePerAttribute = YES;
    }
    return self;
}

- (instancetype)initWithMultilineAction:(void (^)(CGContextRef context, CTLineRef line, CGPoint lineOrigin))action {
    self = [super init];
    if (self) {
        _action = action;
    }
    return self;
}

@end
