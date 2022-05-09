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

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
