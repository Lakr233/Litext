//
//  LTXTextLayout.h
//  Litext
//
//  Created by Cyandev on 2022/5/8.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

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

/// Determines and returns the container size needed for this layout.
///
/// @param size The constraint size. A value of `CGFLOAT_MAX` for either dimension
///             indicates that it should be treated as unconstrained.
- (CGSize)suggestContainerSizeWithSize:(CGSize)size;

- (void)drawInContext:(CGContextRef)context;

- (void)updateHighlightRegionsWithContext:(CGContextRef)context;

@end

NS_ASSUME_NONNULL_END
