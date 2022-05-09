//
//  LTXAttachment.m
//  Litext
//
//  Created by Cyandev on 2022/5/9.
//

#import <CoreText/CoreText.h>

#import "LTXAttachment.h"

NSAttributedStringKey LTXAttachmentAttributeName = @"LTXAttachment";

static void _LTXRunDelegateDeallocCallback(void *refCon) {
    // Stub.
}

static double _LTXRunDelegateGetAscentCallback(void *refCon) {
    LTXAttachment *attachment = (__bridge id) refCon;
    return attachment.size.height * 0.9;
}

static double _LTXRunDelegateGetDescentCallback(void *refCon) {
    LTXAttachment *attachment = (__bridge id) refCon;
    return attachment.size.height * 0.1;
}

static double _LTXRunDelegateGetWidthCallback(void *refCon) {
    LTXAttachment *attachment = (__bridge id) refCon;
    return attachment.size.width;
}

@implementation LTXAttachment {
    CTRunDelegateRef _ctRunDelegate;
}

- (void)dealloc {
    if (_ctRunDelegate) {
        CFRelease(_ctRunDelegate);
        _ctRunDelegate = nil;
    }
}

- (id)runDelegate {
    if (!_ctRunDelegate) {
        CTRunDelegateCallbacks callbacks = { kCTRunDelegateVersion1, NULL, NULL, NULL, NULL };
        callbacks.dealloc = &_LTXRunDelegateDeallocCallback;
        callbacks.getAscent = &_LTXRunDelegateGetAscentCallback;
        callbacks.getDescent = &_LTXRunDelegateGetDescentCallback;
        callbacks.getWidth = &_LTXRunDelegateGetWidthCallback;
        // TODO: use a weak proxy instead of passing an unsafe unretained opaque pointer.
        _ctRunDelegate = CTRunDelegateCreate(&callbacks, (__bridge void *) self);
    }
    return (__bridge id) _ctRunDelegate;
}

@end
