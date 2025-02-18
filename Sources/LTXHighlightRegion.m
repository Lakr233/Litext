//
//  Created by Cyandev on 2022/5/8.
//  Copyright (c) 2024 ktiays. All rights reserved.
//

#import "LTXHighlightRegion.h"
#import "LTXHighlightRegion+Private.h"

@implementation LTXHighlightRegion {
    NSMutableArray<NSValue *> *_rects;
}

- (instancetype)initWithAttributes:(NSDictionary *)attributes stringRange:(NSRange)stringRange {
    self = [super init];
    if (self) {
        _rects = [NSMutableArray array];
        _attributes = attributes;
        _stringRange = stringRange;
    }
    return self;
}

- (NSArray<NSValue *> *)rects {
    return [_rects copy];
}

- (void)addRect:(CGRect)rect {
    [_rects addObject:@(rect)];
}

- (NSString *)description {
    NSMutableString *description = [NSMutableString string];
    [description appendFormat:@"<%@: %p;", NSStringFromClass([self class]), self];
    [description appendFormat:@" attributes = %@;", self.attributes];
    [description appendFormat:@" rects = %@;", self.rects];
    [description appendFormat:@" stringRange = %@>", NSStringFromRange(self.stringRange)];
    return [description copy];
}

@end
