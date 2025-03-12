//
//  Created by Cyandev on 2022/5/8.
//  Copyright (c) 2025 Helixform. All rights reserved.
//

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

@class LTXHighlightRegion;

NS_ASSUME_NONNULL_BEGIN

@interface LTXTextLayout : NSObject

@property (nonatomic, readonly, copy) NSAttributedString *attributedString;
@property (nonatomic, readonly, copy) NSArray<LTXHighlightRegion *> *highlightRegions;

@property (nonatomic, assign) CGSize containerSize;

+ (instancetype)textLayoutWithAttributedString:(NSAttributedString *)attributedString;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithAttributedString:(NSAttributedString *)attributedString NS_DESIGNATED_INITIALIZER;

- (void)invalidateLayout;

/// Determines and returns the container size needed for this layout.
///
/// @param size The constraint size. A value of `CGFLOAT_MAX` for either dimension
///             indicates that it should be treated as unconstrained.
- (CGSize)suggestContainerSizeWithSize:(CGSize)size;

- (void)drawInContext:(CGContextRef)context;

- (void)updateHighlightRegionsWithContext:(CGContextRef)context;

@end

NS_ASSUME_NONNULL_END
