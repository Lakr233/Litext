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

/// A view that displays the multiline rich text.
@interface LTXLabel : UIView

/// The styled text that the label displays.
@property (nonatomic, copy) NSAttributedString *attributedText;

/// The preferred maximum width, in points, for a multiline label.
@property (nonatomic, assign) CGFloat preferredMaxLayoutWidth;

/// A block that is invoked when the user taps an interactive element.
@property (nonatomic, copy) LTXLabelTapHandler tapHandler;

@end

NS_ASSUME_NONNULL_END
