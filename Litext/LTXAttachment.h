//
//  LTXAttachment.h
//  Litext
//
//  Created by Cyandev on 2022/5/9.
//

#import <UIKit/UIKit.h>

typedef UIView LTXPlatformView;

NS_ASSUME_NONNULL_BEGIN

extern NSAttributedStringKey LTXAttachmentAttributeName;

@interface LTXAttachment : NSObject

@property (nonatomic, readonly, strong) id runDelegate;

@property (nonatomic, assign) CGSize size;
@property (nonatomic, strong) LTXPlatformView *view;

@end

NS_ASSUME_NONNULL_END
