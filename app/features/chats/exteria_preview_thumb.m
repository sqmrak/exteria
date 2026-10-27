#import "exteria_preview_thumb.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define SIDE 18.0
#define GAP 6.0

@interface ExteriaPreviewThumb () {
    NSString *_key;
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaPreviewThumb

+ (CGFloat)side {
    return SIDE;
}

+ (CGFloat)room {
    return SIDE + GAP;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.contentMode = UIViewContentModeScaleAspectFill;
    self.clipsToBounds = YES;
    self.layer.cornerRadius = 3;
    self.hidden = YES;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_key release];
    [super dealloc];
}

- (void)showFile:(ExteriaRemoteFile *)file cache:(ExteriaMediaCache *)cache {
    if (!file || !cache) {
        [_key release];
        _key = nil;
        self.image = nil;
        self.hidden = YES;
        return;
    }
    if ([_key isEqualToString:file.key] && self.image) {
        self.hidden = NO;
        return;
    }
    [_key release];
    _key = [file.key copy];
    self.hidden = NO;
    /* the picture is drawn at three pixels to the point on the largest screens, which 64 covers */
    CGFloat side = 64;
    UIImage *held = [cache cachedImageForFile:file maxSide:side];
    self.image = held;
    self.backgroundColor = held ? [UIColor clearColor] : ExteriaColorField();
    if (held) return;
    ExteriaWeakReference *me = _weak;
    NSString *wanted = [[_key copy] autorelease];
    [cache loadImageForFile:file maxSide:side completion:^(UIImage *image) {
        ExteriaPreviewThumb *thumb = me.target;
        if (!thumb || !image || ![thumb->_key isEqualToString:wanted]) return;
        thumb.image = image;
        thumb.backgroundColor = [UIColor clearColor];
    }];
}

@end
