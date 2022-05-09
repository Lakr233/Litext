//
//  LTXHighlightRegion.h
//  Litext
//
//  Created by Cyandev on 2022/5/8.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface LTXHighlightRegion : NSObject

@property (nonatomic, readonly, copy) NSArray<NSValue *> *rects;
@property (nonatomic, readonly, copy) NSDictionary *attributes;
@property (nonatomic, readonly, assign) NSRange stringRange;

@property (nonatomic, nullable, strong) id associatedObject;

+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithAttributes:(NSDictionary *)attributes stringRange:(NSRange)stringRange NS_DESIGNATED_INITIALIZER;

- (void)addRect:(CGRect)rect;

@end

NS_ASSUME_NONNULL_END
