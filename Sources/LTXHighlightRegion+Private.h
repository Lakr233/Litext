//
//  Created by Cyandev on 2022/5/10.
//  Copyright (c) 2025 Helixform. All rights reserved.
//

#import "LTXHighlightRegion.h"

NS_ASSUME_NONNULL_BEGIN

@interface LTXHighlightRegion ()

@property (nonatomic, nullable, strong) id associatedObject;

- (instancetype)initWithAttributes:(NSDictionary *)attributes stringRange:(NSRange)stringRange NS_DESIGNATED_INITIALIZER;

- (void)addRect:(CGRect)rect;

@end

NS_ASSUME_NONNULL_END
