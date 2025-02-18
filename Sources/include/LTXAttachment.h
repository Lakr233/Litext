//
//  Created by Cyandev on 2022/5/9.
//  Copyright (c) 2024 Helixform. All rights reserved.
//

#import "LTXPlatformTypes.h"

NS_ASSUME_NONNULL_BEGIN

extern NSAttributedStringKey const LTXAttachmentAttributeName;
extern NSAttributedStringKey const LTXLineDrawingCallbackName;

@interface LTXAttachment : NSObject

@property (nonatomic, readonly, strong) id runDelegate;

@property (nonatomic, assign) CGSize size;
@property (nonatomic, strong) LTXPlatformView *view;

@end

NS_ASSUME_NONNULL_END
