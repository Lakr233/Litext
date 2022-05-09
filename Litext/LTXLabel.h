//
//  LTXLabel.h
//  Litext
//
//  Created by Cyandev on 2022/5/8.
//

#import <UIKit/UIKit.h>

@class LTXHighlightRegion;

NS_ASSUME_NONNULL_BEGIN

typedef void(^LTXLabelTapHandler)(LTXHighlightRegion * _Nullable highlightRegion);

@interface LTXLabel : UIView

@property (nonatomic, copy) NSAttributedString *attributedText;

@property (nonatomic, copy) LTXLabelTapHandler tapHandler;

@end

NS_ASSUME_NONNULL_END
