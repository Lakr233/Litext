//
//  LTXHighlightRegion.m
//  Litext
//
//  Created by Cyandev on 2022/5/8.
//

#import "LTXHighlightRegion.h"

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

@end
