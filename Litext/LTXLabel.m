//
//  LTXLabel.m
//  Litext
//
//  Created by Cyandev on 2022/5/8.
//

#import "LTXLabel.h"
#import "LTXTextLayout.h"
#import "LTXHighlightRegion.h"
#import "LTXAttachment.h"

@implementation LTXLabel {
    LTXTextLayout *_textLayout;
    NSMutableSet<UIView *> *_attachmentViews;
    NSArray<LTXHighlightRegion *> *_highlightRegions;
    LTXHighlightRegion *_activeHighlightRegion;
    CGSize _lastContainerSize;
    BOOL _layoutIsDirty;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self _commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self _commonInit];
    }
    return self;
}

- (void)_commonInit {
    _attachmentViews = [NSMutableSet set];
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    _textLayout = [LTXTextLayout textLayoutWithAttributedString:attributedText];
}

- (NSAttributedString *)attributedText {
    return _textLayout.attributedString;
}

- (CGSize)intrinsicContentSize {
    CGSize constraintSize = { CGFLOAT_MAX, CGFLOAT_MAX };
    if (_lastContainerSize.width > 0) {
        // We have a preferred layout width here.
        // TODO: add an option to control this behavior.
        constraintSize.width = _lastContainerSize.width;
    }
    return [_textLayout suggestContainerSizeWithSize:constraintSize];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // Only update layout when the view's bounds changed.
    CGSize containerSize = self.bounds.size;
    if (!CGSizeEqualToSize(_lastContainerSize, containerSize)) {
        if (containerSize.width != _lastContainerSize.width) {
            // This is the magic that makes Auto Layout works with this view.
            // See `intrinsicContentSize` method for more details.
            [self invalidateIntrinsicContentSize];
        }
        
        _lastContainerSize = containerSize;
        _layoutIsDirty = YES;
        _textLayout.containerSize = containerSize;
        
        // Must display once after the layout changed, that will also update
        // the text layout and highlight regions.
        [self setNeedsDisplay];
    }
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
     
    if (_layoutIsDirty) {
        // We need to update highlight regions within `drawRect:` because an
        // `CGContextRef` is required for getting the image bounds of glyph
        // runs. This process will make our view's layout dirty, but that will
        // not trigger this process again, which is ensured by `layoutSubviews`
        // implementation.
        [_textLayout updateHighlightRegionsWithContext:context];
        _highlightRegions = _textLayout.highlightRegions;
        
        // Also update attachment views when highlight regions changed.
        [self _updateAttachmentViews];
        
        _layoutIsDirty = NO;
    }
    
    [_textLayout drawInContext:context];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (!CGRectContainsPoint(self.bounds, point)) {
        return NO;
    }
    
    return [self _highlightRegionAtPoint:point] != nil;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *firstTouch = [touches allObjects].firstObject;
    CGPoint touchLocation = [firstTouch locationInView:self];
    
    __auto_type hitHighlightRegion = [self _highlightRegionAtPoint:touchLocation];
    if (hitHighlightRegion) {
        [self _addActiveHighlightRegion:hitHighlightRegion];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self _removeActiveHighlightRegion];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self _removeActiveHighlightRegion];
}

- (LTXHighlightRegion *)_highlightRegionAtPoint:(CGPoint)point {
    for (LTXHighlightRegion *highlightRegion in _highlightRegions) {
        for (NSValue *boxedRect in highlightRegion.rects) {
            CGRect convertedRect = [self _convertRectFromTextLayout:boxedRect.CGRectValue forInteraction:YES];
            if (CGRectContainsPoint(convertedRect, point)) {
                return highlightRegion;
            }
        }
    }
    return nil;
}

- (CGRect)_convertRectFromTextLayout:(CGRect)rect forInteraction:(BOOL)interaction {
    rect.origin.y = CGRectGetHeight(self.bounds) - rect.origin.y - rect.size.height;
    if (interaction) {
        rect = CGRectInset(rect, -4, -4);
    }
    return rect;
}

- (void)_updateAttachmentViews {
    // The set holds views that are no longer reusable by the new layout. Reusable
    // views are updated in-place without being removed from its superview, which
    // can improve the updating performance.
    NSMutableSet<UIView *> *viewsToRemove = [_attachmentViews mutableCopy];
    
    for (LTXHighlightRegion *highlightRegion in _highlightRegions) {
        LTXAttachment *attachment = highlightRegion.attributes[LTXAttachmentAttributeName];
        if (!attachment) {
            continue;
        }
        
        UIView *view = attachment.view;
        if (view.superview == self) {
            // The view is reused, remove it from the garbage set.
            [viewsToRemove removeObject:view];
        } else {
            [self addSubview:view];
            [_attachmentViews addObject:view];
        }
        
        CGRect convertedRect =
        [self _convertRectFromTextLayout:highlightRegion.rects.firstObject.CGRectValue
                          forInteraction:NO];
        view.frame = convertedRect;
    }
    
    // Evict the garbage views.
    __auto_type attachmentViews = _attachmentViews;
    [viewsToRemove enumerateObjectsUsingBlock:^(UIView *obj, BOOL *stop) {
        [obj removeFromSuperview];
        [attachmentViews removeObject:obj];
    }];
}

- (void)_addActiveHighlightRegion:(LTXHighlightRegion *)highlightRegion {
    [self _removeActiveHighlightRegion];
    
    if (!highlightRegion) {
        return;
    }
    
    _activeHighlightRegion = highlightRegion;
    
    // Construct the highlight path.
    UIBezierPath *highlightPath = [[UIBezierPath alloc] init];
    for (NSValue *boxedRect in highlightRegion.rects) {
        CGRect convertedRect = [self _convertRectFromTextLayout:boxedRect.CGRectValue forInteraction:YES];
        UIBezierPath *subpath = [UIBezierPath bezierPathWithRoundedRect:convertedRect cornerRadius:4];
        [highlightPath appendPath:subpath];
    }
    
    // Determine the highlight color.
    CGColorRef highlightCGColor = (__bridge CGColorRef) highlightRegion.attributes[NSForegroundColorAttributeName];
    UIColor *highlightColor;
    if (highlightCGColor) {
        highlightColor = [UIColor colorWithCGColor:highlightCGColor];
    } else {
        highlightColor = [UIColor linkColor];
    }
    
    CAShapeLayer *highlightLayer = [CAShapeLayer layer];
    highlightLayer.path = highlightPath.CGPath;
    highlightLayer.fillColor = [highlightColor colorWithAlphaComponent:0.3].CGColor;
    [self.layer addSublayer:highlightLayer];
    
    highlightRegion.associatedObject = highlightLayer;
}

- (void)_removeActiveHighlightRegion {
    __auto_type activeHighlightRegion = _activeHighlightRegion;
    if (!activeHighlightRegion) {
        return;
    }
    
    CALayer *highlightLayer = activeHighlightRegion.associatedObject;
    highlightLayer.opacity = 0;
    // Defer the remove operation for implicit animations.
    [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:NO block:^(NSTimer *timer) {
        [highlightLayer removeFromSuperlayer];
    }];
    activeHighlightRegion.associatedObject = nil;
    
    _activeHighlightRegion = nil;
}

@end
