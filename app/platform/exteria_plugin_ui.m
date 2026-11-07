#import "exteria_plugin_ui.h"

#import <CFNetwork/CFNetwork.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import "exteria_chat_controller.h"
#import "exteria_alert.h"
#import "exteria_dialog.h"
#import "exteria_emoji_label.h"
#import "exteria_language.h"
#import "exteria_plugin_account.h"
#import "exteria_platform.h"
#import "exteria_plugin_bitmap.h"
#import "exteria_plugin_sheet.h"
#import "exteria_profile_photo_picker.h"
#import "exteria_settings_controller.h"
#import "exteria_plugin_audio.h"
#import "exteria_plugin_music.h"
#import "exteria_plugin_story.h"
#import "exteria_date_time_picker.h"
#import "exteria_plugins.h"
#import "exteria_theme.h"
#include "exteria_surface.h"
#include "exteria_tl_schema.h"

/* a view a plugin made. it draws a background, optionally a label or an image, and forwards touches to python */
@protocol ExteriaPluginSurface <NSObject>
@property (nonatomic, assign) long long viewId;
@property (nonatomic, assign) BOOL wantsTouch;
@end

typedef struct {
    CGFloat pad[4];
    CGFloat tx, ty, sx, sy, rotation;
    CGRect frame;
    BOOL oval;
    CGFloat clip;
} PluginState;

/* the part of CMMotionManager used here. CoreMotion is weak linked and found by name, so the compiler needs these types to read a BOOL as a BOOL */
@protocol ExteriaMotionManager <NSObject>
- (BOOL)isAccelerometerAvailable;
- (BOOL)isAccelerometerActive;
- (void)setAccelerometerUpdateInterval:(NSTimeInterval)interval;
- (void)startAccelerometerUpdatesToQueue:(NSOperationQueue *)queue withHandler:(void (^)(id data, NSError *error))handler;
- (void)stopAccelerometerUpdates;
@end

static NSMutableDictionary *g_views;
static UIView *g_overlay;
static id<ExteriaMotionManager> g_motion;
static double g_sensor_interval = 0.1;

static void forward_touch(UIView *view, long long viewId, int action, NSSet *touches);

#define SURFACE_TOUCHES \
    - (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event { forward_touch(self, _viewId, 0, touches); } \
    - (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event { forward_touch(self, _viewId, 2, touches); } \
    - (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event { forward_touch(self, _viewId, 1, touches); } \
    - (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event { forward_touch(self, _viewId, 3, touches); }

@interface ExteriaPluginView : UIView <ExteriaPluginSurface> {
    long long _viewId;
    BOOL _wantsTouch;
@public
    ExteriaEmojiLabel *label;
    CALayer *tint;
    PluginState state;
}
@end

@implementation ExteriaPluginView
@synthesize viewId = _viewId, wantsTouch = _wantsTouch;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        state.sx = state.sy = 1;
        /* uikit skips the subviews of a view that refuses touches, so every view takes part and hitTest below decides which one answers */
        self.userInteractionEnabled = YES;
        self.layer.magnificationFilter = kCAFilterNearest;
    }
    return self;
}

- (void)dealloc {
    [label release];
    [tint release];
    [super dealloc];
}

/* a view that did not ask for touches lets them through to what is behind it, its subviews still get theirs */
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self && !_wantsTouch ? nil : hit;
}

SURFACE_TOUCHES
@end

@interface ExteriaPluginScroll : UIScrollView <ExteriaPluginSurface> {
    long long _viewId;
    BOOL _wantsTouch;
@public
    PluginState state;
}
@end

@implementation ExteriaPluginScroll
@synthesize viewId = _viewId, wantsTouch = _wantsTouch;
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        state.sx = state.sy = 1;
        self.showsHorizontalScrollIndicator = NO;
    }
    return self;
}
SURFACE_TOUCHES
@end

/* lets every touch through that does not land on a view of a plugin */
@interface ExteriaPluginOverlay : UIView
@end

@implementation ExteriaPluginOverlay
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

#pragma mark helpers

static UIColor *color_of(unsigned long long argb) {
    return [UIColor colorWithRed:((argb >> 16) & 255) / 255.0 green:((argb >> 8) & 255) / 255.0 blue:(argb & 255) / 255.0 alpha:((argb >> 24) & 255) / 255.0];
}

static unsigned long long argb_of(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        if ([color getWhite:&white alpha:&a]) r = g = b = white;
    }
    return ((unsigned long long)(a * 255 + 0.5) << 24) | ((unsigned long long)(r * 255 + 0.5) << 16) | ((unsigned long long)(g * 255 + 0.5) << 8) | (unsigned long long)(b * 255 + 0.5);
}

static UIFont *font_of(CGFloat size, BOOL bold) {
    return bold ? ExteriaFontBold(size) : ExteriaFontRegular(size);
}

/* the overlay lives in the view of the top controller, like every popup of the app: before ios 8 the window stays in portrait and only that view is turned
   with the interface, so a view added to the window itself shows sideways on an ipad held wide. a controller that is presented later takes the overlay
   along on the next call of a plugin, since the view under the presented one would hide it */
static UIView *overlay(void) {
    UIView *host = ExteriaOverlayHost();
    if (!host) return nil;
    if (!g_overlay) {
        g_overlay = [[ExteriaPluginOverlay alloc] initWithFrame:host.bounds];
        g_overlay.backgroundColor = [UIColor clearColor];
        g_overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    /* the overlay stays on top of whatever the app puts on the same view later */
    if (g_overlay.superview != host) {
        [g_overlay removeFromSuperview];
        g_overlay.frame = host.bounds;
        [host addSubview:g_overlay];
    } else if ([host.subviews lastObject] != g_overlay) {
        [host bringSubviewToFront:g_overlay];
    }
    return g_overlay;
}

static UIView *view_for(long long viewId) {
    if (viewId == 0) return overlay();
    return [g_views objectForKey:[NSNumber numberWithLongLong:viewId]];
}

static PluginState *state_of(UIView *view) {
    return [view isKindOfClass:[ExteriaPluginView class]] ? &((ExteriaPluginView *)view)->state : &((ExteriaPluginScroll *)view)->state;
}

static void apply_geometry(UIView *view) {
    PluginState *st = state_of(view);
    CGSize size = st->frame.size;
    view.transform = CGAffineTransformIdentity;
    CGPoint offset = [view isKindOfClass:[UIScrollView class]] ? ((UIScrollView *)view).contentOffset : CGPointZero;
    view.bounds = CGRectMake(offset.x, offset.y, size.width, size.height);
    view.center = CGPointMake(st->frame.origin.x + size.width / 2 + st->tx, st->frame.origin.y + size.height / 2 + st->ty);
    view.transform = CGAffineTransformScale(CGAffineTransformMakeRotation(st->rotation * (CGFloat)M_PI / 180), st->sx, st->sy);
    if ([view isKindOfClass:[ExteriaPluginView class]]) {
        ExteriaPluginView *v = (ExteriaPluginView *)view;
        if (st->oval) v.layer.cornerRadius = MIN(size.width, size.height) / 2;
        if (v->label) v->label.frame = CGRectMake(st->pad[0], st->pad[1], MAX(0, size.width - st->pad[0] - st->pad[2]), MAX(0, size.height - st->pad[1] - st->pad[3]));
        if (v->tint) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            v->tint.frame = CGRectMake(0, 0, size.width, size.height);
            [CATransaction commit];
        }
    }
}

/* the color a plugin lays over a picture with setColorFilter (SRC_ATOP, SRC_OVER): a layer above the picture and under the text. alpha 0 takes it away */
static void apply_tint(ExteriaPluginView *view, unsigned long long argb) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!((argb >> 24) & 255)) {
        [view->tint removeFromSuperlayer];
        [view->tint release];
        view->tint = nil;
    } else {
        if (!view->tint) {
            view->tint = [[CALayer alloc] init];
            [view.layer insertSublayer:view->tint atIndex:0];
        }
        view->tint.backgroundColor = color_of(argb).CGColor;
        view->tint.frame = CGRectMake(0, 0, state_of(view)->frame.size.width, state_of(view)->frame.size.height);
    }
    [CATransaction commit];
}

/* clipToOutline with a round rect: the picture on the layer and the children are cut at the corners */
static void apply_clip(ExteriaPluginView *view) {
    CGFloat clip = state_of(view)->clip;
    view.layer.masksToBounds = clip > 0;
    if (clip > 0) view.layer.cornerRadius = clip;
}

static CGFloat num(NSDictionary *props, NSString *key, CGFloat fallback) {
    id value = [props objectForKey:key];
    return [value isKindOfClass:[NSNumber class]] ? (CGFloat)[value doubleValue] : fallback;
}

static void apply_background(ExteriaPluginView *view, NSDictionary *bg) {
    view.layer.borderWidth = 0;
    view.layer.cornerRadius = 0;
    state_of(view)->oval = NO;
    if (![bg isKindOfClass:[NSDictionary class]]) {
        view.backgroundColor = [UIColor clearColor];
        return;
    }
    view.backgroundColor = color_of([[bg objectForKey:@"color"] unsignedLongLongValue]);
    if ([[bg objectForKey:@"type"] isEqualToString:@"shape"]) {
        state_of(view)->oval = [[bg objectForKey:@"oval"] boolValue];
        view.layer.cornerRadius = (CGFloat)[[bg objectForKey:@"radius"] doubleValue];
        view.layer.borderWidth = (CGFloat)[[bg objectForKey:@"stroke"] doubleValue];
        view.layer.borderColor = color_of([[bg objectForKey:@"stroke_color"] unsignedLongLongValue]).CGColor;
    }
    apply_clip(view);
}

static void apply_props(UIView *view, NSDictionary *props) {
    BOOL moved = NO;
    ExteriaPluginView *flat = [view isKindOfClass:[ExteriaPluginView class]] ? (ExteriaPluginView *)view : nil;
    id<ExteriaPluginSurface> surface = (id<ExteriaPluginSurface>)view;
    PluginState *st = state_of(view);
    for (NSString *key in props) {
        id value = [props objectForKey:key];
        CGFloat number = [value respondsToSelector:@selector(doubleValue)] ? (CGFloat)[value doubleValue] : 0;
        if ([key isEqualToString:@"x"]) { st->frame.origin.x = number; moved = YES; }
        else if ([key isEqualToString:@"y"]) { st->frame.origin.y = number; moved = YES; }
        else if ([key isEqualToString:@"w"]) { st->frame.size.width = number; moved = YES; }
        else if ([key isEqualToString:@"h"]) { st->frame.size.height = number; moved = YES; }
        else if ([key isEqualToString:@"tx"]) { st->tx = number; moved = YES; }
        else if ([key isEqualToString:@"ty"]) { st->ty = number; moved = YES; }
        else if ([key isEqualToString:@"sx"]) { st->sx = number; moved = YES; }
        else if ([key isEqualToString:@"sy"]) { st->sy = number; moved = YES; }
        else if ([key isEqualToString:@"rot"]) { st->rotation = number; moved = YES; }
        else if ([key isEqualToString:@"alpha"]) view.alpha = number;
        else if ([key isEqualToString:@"vis"]) view.hidden = [value intValue] != 0;
        else if ([key isEqualToString:@"touch"]) {
            surface.wantsTouch = [value boolValue];
        } else if ([key isEqualToString:@"elev"]) {
            view.layer.shadowOpacity = number > 0 ? 0.3f : 0;
            view.layer.shadowRadius = number / 2;
            view.layer.shadowOffset = CGSizeMake(0, number / 3);
        } else if ([key isEqualToString:@"pad"] && [value isKindOfClass:[NSArray class]] && [(NSArray *)value count] == 4) {
            for (int i = 0; i < 4; ++i) st->pad[i] = (CGFloat)[[value objectAtIndex:i] doubleValue];
            moved = YES;
        } else if ([key isEqualToString:@"clip"] && flat) {
            st->clip = number > 0 ? number : 0;
            apply_clip(flat);
        } else if ([key isEqualToString:@"bg"] && flat) {
            apply_background(flat, value);
        } else if ([key isEqualToString:@"content"] && !flat && [value isKindOfClass:[NSArray class]] && [(NSArray *)value count] == 2) {
            ((ExteriaPluginScroll *)view).contentSize = CGSizeMake((CGFloat)[[value objectAtIndex:0] doubleValue], (CGFloat)[[value objectAtIndex:1] doubleValue]);
        }
    }
    if (flat) {
        /* the text kinds carry a label, made when one of its properties first arrives */
        id text = [props objectForKey:@"text"];
        BOOL styled = text || [props objectForKey:@"color"] || [props objectForKey:@"size"] || [props objectForKey:@"bold"] || [props objectForKey:@"gravity"] || [props objectForKey:@"lines"];
        if (styled) {
            if (!flat->label) {
                /* the label of the app: it draws the emoji of its own pack, which a UILabel shows as boxes on older systems */
                flat->label = [[ExteriaEmojiLabel alloc] init];
                flat->label.backgroundColor = [UIColor clearColor];
                flat->label.numberOfLines = 0;
                flat->label.userInteractionEnabled = NO;
                [flat addSubview:flat->label];
            }
            ExteriaEmojiLabel *label = flat->label;
            if (text) label.text = text;
            /* setMaxLines and setSingleLine: the lines the label may take, 0 for as many as the text needs */
            if ([props objectForKey:@"lines"]) label.numberOfLines = (NSInteger)num(props, @"lines", 0);
            if ([props objectForKey:@"color"]) label.textColor = color_of([[props objectForKey:@"color"] unsignedLongLongValue]);
            if ([props objectForKey:@"size"] || [props objectForKey:@"bold"]) {
                CGFloat size = [props objectForKey:@"size"] ? num(props, @"size", 14) : label.font.pointSize;
                BOOL bold = [props objectForKey:@"bold"] ? [[props objectForKey:@"bold"] boolValue] : NO;
                if (![props objectForKey:@"bold"] && label.font) bold = label.tag == 1;
                label.font = font_of(size, bold);
                label.tag = bold ? 1 : 0;
            }
            if ([props objectForKey:@"gravity"]) {
                int gravity = [[props objectForKey:@"gravity"] intValue];
                int horizontal = gravity & 7;
                label.textAlignment = horizontal == 1 ? ExteriaTextAlignmentCenter : (horizontal == 5 ? ExteriaTextAlignmentRight : ExteriaTextAlignmentLeft);
            }
            moved = YES;
        }
        id scale = [props objectForKey:@"scale"];
        if ([scale isKindOfClass:[NSString class]]) {
            if ([scale isEqualToString:@"fill"]) flat.layer.contentsGravity = kCAGravityResize;
            else if ([scale isEqualToString:@"crop"]) flat.layer.contentsGravity = kCAGravityResizeAspectFill;
            else if ([scale isEqualToString:@"center"]) flat.layer.contentsGravity = kCAGravityCenter;
            else flat.layer.contentsGravity = kCAGravityResizeAspect;
        }
        if ([[props objectForKey:@"image"] isEqual:[NSNumber numberWithBool:NO]]) flat.layer.contents = nil;
        id tint = [props objectForKey:@"tint"];
        if ([tint isKindOfClass:[NSNumber class]]) apply_tint(flat, [tint unsignedLongLongValue]);
    }
    if (moved) apply_geometry(view);
}

static int base64_value(unsigned char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

/* NSData has no base64 decoder before ios 7 */
static NSData *decode_base64(NSString *text) {
    const char *in = [text UTF8String];
    size_t length = in ? strlen(in) : 0;
    NSMutableData *out = [NSMutableData dataWithCapacity:length / 4 * 3];
    unsigned int accumulator = 0;
    int bits = 0;
    for (size_t i = 0; i < length; ++i) {
        int value = base64_value((unsigned char)in[i]);
        if (value < 0) continue;
        accumulator = (accumulator << 6) | (unsigned int)value;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            unsigned char byte = (unsigned char)((accumulator >> bits) & 255);
            [out appendBytes:&byte length:1];
        }
    }
    return out;
}

static void release_pixels(void *info, const void *data, size_t size) {
    (void)data;
    (void)size;
    [(NSData *)info release];
}

static void apply_image(UIView *view, int width, int height, NSString *encoded) {
    if (![view isKindOfClass:[ExteriaPluginView class]] || width <= 0 || height <= 0 || width > 2048 || height > 2048) return;
    NSData *pixels = decode_base64(encoded);
    if (pixels.length != (NSUInteger)width * (NSUInteger)height * 4) {
        ExteriaPluginsLog(@"exteria: a plugin image of %dx%d came with %lu bytes", width, height, (unsigned long)pixels.length);
        return;
    }
    CGDataProviderRef provider = CGDataProviderCreateWithData([pixels retain], pixels.bytes, pixels.length, release_pixels);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    /* the plugin's pixels are straight rgba, not premultiplied */
    CGImageRef image = CGImageCreate((size_t)width, (size_t)height, 8, 32, (size_t)width * 4, space, kCGBitmapByteOrderDefault | kCGImageAlphaLast, provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    view.layer.contents = (id)image;
    CGImageRelease(image);
}

CGImageRef ExteriaPluginSurfaceImage(NSString *name) {
    const uint32_t *pixels = NULL;
    int width = 0, height = 0;
    if (![name isKindOfClass:[NSString class]] || !exteria_surface_get([name UTF8String], &pixels, &width, &height) || width <= 0 || height <= 0) return NULL;
    /* copied, since the module draws the next frame into the same buffer */
    NSData *copy = [[NSData alloc] initWithBytes:pixels length:(NSUInteger)width * (NSUInteger)height * 4];
    CGDataProviderRef provider = CGDataProviderCreateWithData(copy, copy.bytes, copy.length, release_pixels);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate((size_t)width, (size_t)height, 8, 32, (size_t)width * 4, space, kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst, provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    return image;
}

static void apply_native(UIView *view, NSString *name) {
    if (![view isKindOfClass:[ExteriaPluginView class]]) return;
    CGImageRef image = ExteriaPluginSurfaceImage(name);
    if (!image) return;
    view.layer.contents = (id)image;
    CGImageRelease(image);
}

/* a picture the app holds for python (exteria_plugin_bitmap.h) on the layer of a view */
static void apply_bitmap(UIView *view, long long handle) {
    if (![view isKindOfClass:[ExteriaPluginView class]]) return;
    CGImageRef image = ExteriaPluginBitmapCreateImage(handle);
    if (!image) {
        ExteriaPluginsLog(@"exteria: a plugin showed picture %lld, which the app does not hold", handle);
        return;
    }
    view.layer.contents = (id)image;
    CGImageRelease(image);
}

/* a page of the app lays out again when what a plugin put in its layer changed, so it can hide the background the views now cover */
static void page_layer_changed(UIView *layer) {
    if ([layer isKindOfClass:[ExteriaPluginView class]] && ((ExteriaPluginView *)layer).viewId < 0) [layer.superview setNeedsLayout];
}

/* a view taken off its parent is held by g_views alone, so dropping its key frees it, and reading its subviews after that sent sublayers to a freed layer on ios 6 */
static void purge(UIView *view) {
    [view retain];
    if ([view conformsToProtocol:@protocol(ExteriaPluginSurface)]) {
        [g_views removeObjectForKey:[NSNumber numberWithLongLong:((id<ExteriaPluginSurface>)view).viewId]];
    }
    for (UIView *child in view.subviews) purge(child);
    [view release];
}

static UIViewAnimationOptions curve_options(NSString *curve) {
    if ([curve isEqualToString:@"linear"]) return UIViewAnimationOptionCurveLinear;
    if ([curve isEqualToString:@"accel"]) return UIViewAnimationOptionCurveEaseIn;
    if ([curve isEqualToString:@"ease"]) return UIViewAnimationOptionCurveEaseInOut;
    /* decelerate, and overshoot, which has no spring before ios 7 */
    return UIViewAnimationOptionCurveEaseOut;
}

static void apply_operation(NSArray *op) {
    if (!op.count || ![[op objectAtIndex:0] isKindOfClass:[NSString class]]) return;
    NSString *kind = [op objectAtIndex:0];
    if (!g_views) g_views = [[NSMutableDictionary alloc] init];
    if ([kind isEqualToString:@"new"] && op.count == 3) {
        long long viewId = [[op objectAtIndex:1] longLongValue];
        BOOL scroll = [[op objectAtIndex:2] isEqualToString:@"scroll"];
        UIView<ExteriaPluginSurface> *view = [[(scroll ? [ExteriaPluginScroll alloc] : [ExteriaPluginView alloc]) initWithFrame:CGRectZero] autorelease];
        view.viewId = viewId;
        [g_views setObject:view forKey:[NSNumber numberWithLongLong:viewId]];
    } else if ([kind isEqualToString:@"set"] && op.count == 3) {
        UIView *view = view_for([[op objectAtIndex:1] longLongValue]);
        if (view && [[op objectAtIndex:2] isKindOfClass:[NSDictionary class]] && view != g_overlay) apply_props(view, [op objectAtIndex:2]);
    } else if ([kind isEqualToString:@"add"] && op.count == 4) {
        UIView *parent = view_for([[op objectAtIndex:1] longLongValue]);
        UIView *child = view_for([[op objectAtIndex:2] longLongValue]);
        NSInteger index = [[op objectAtIndex:3] integerValue];
        if (!parent || !child) return;
        /* a scroll view or a plain view holds its children directly */
        if (index >= 0 && (NSUInteger)index < parent.subviews.count) [parent insertSubview:child atIndex:(NSInteger)index];
        else [parent addSubview:child];
        page_layer_changed(parent);
    } else if ([kind isEqualToString:@"rm"] && op.count == 2) {
        UIView *child = view_for([[op objectAtIndex:1] longLongValue]);
        if (!child) return;
        UIView *old_parent = child.superview;
        [child removeFromSuperview];
        purge(child);
        if (old_parent) page_layer_changed(old_parent);
    } else if ([kind isEqualToString:@"img"] && op.count == 5) {
        UIView *view = view_for([[op objectAtIndex:1] longLongValue]);
        if (view) apply_image(view, [[op objectAtIndex:2] intValue], [[op objectAtIndex:3] intValue], [op objectAtIndex:4]);
    } else if ([kind isEqualToString:@"nimg"] && op.count == 3) {
        UIView *view = view_for([[op objectAtIndex:1] longLongValue]);
        if (view) apply_bitmap(view, [[op objectAtIndex:2] longLongValue]);
    } else if ([kind isEqualToString:@"native"] && op.count == 3) {
        UIView *view = view_for([[op objectAtIndex:1] longLongValue]);
        if (view) apply_native(view, [op objectAtIndex:2]);
    } else if ([kind isEqualToString:@"anim"] && op.count == 6) {
        UIView *view = view_for([[op objectAtIndex:1] longLongValue]);
        if (!view) return;
        NSDictionary *props = [op objectAtIndex:2];
        NSTimeInterval duration = [[op objectAtIndex:3] doubleValue] / 1000.0;
        NSTimeInterval delay = [[op objectAtIndex:4] doubleValue] / 1000.0;
        [UIView animateWithDuration:duration delay:delay options:curve_options([op objectAtIndex:5]) | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ apply_props(view, props); } completion:nil];
    } else if ([kind isEqualToString:@"stop"] && op.count == 2) {
        UIView *view = view_for([[op objectAtIndex:1] longLongValue]);
        [view.layer removeAllAnimations];
    }
}

#pragma mark touches

static void forward_touch(UIView *view, long long viewId, int action, NSSet *touches) {
    UITouch *touch = [touches anyObject];
    if (!touch || !g_overlay) return;
    CGPoint point = [touch locationInView:g_overlay];
    NSArray *arguments = [NSArray arrayWithObjects:[NSNumber numberWithLongLong:viewId], [NSNumber numberWithInt:action], [NSNumber numberWithDouble:point.x], [NSNumber numberWithDouble:point.y], [NSNumber numberWithDouble:touch.timestamp], nil];
    ExteriaPluginsCallHost(@"touch", arguments);
}

NSString *const ExteriaPluginPickNotification = @"ExteriaPluginPick";

#pragma mark pages

NSString *const ExteriaPluginCardsNotification = @"ExteriaPluginCards";
static CGFloat g_card_alpha = 1;

CGFloat ExteriaPluginCardAlpha(void) {
    return g_card_alpha;
}

static void set_card_alpha(CGFloat alpha) {
    CGFloat clamped = alpha < 0 ? 0 : (alpha > 1 ? 1 : alpha);
    if (clamped == g_card_alpha) return;
    g_card_alpha = clamped;
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaPluginCardsNotification object:nil];
}

UIView *ExteriaPluginPageLayer(long long pageId) {
    if (!g_views) g_views = [[NSMutableDictionary alloc] init];
    ExteriaPluginView *layer = [[[ExteriaPluginView alloc] initWithFrame:CGRectZero] autorelease];
    layer.viewId = pageId;
    layer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [g_views setObject:layer forKey:[NSNumber numberWithLongLong:pageId]];
    return layer;
}

static long long g_own_user;
static NSString *g_own_name;

void ExteriaPluginUISetOwnUser(long long userId, NSString *firstName) {
    g_own_user = userId;
    [g_own_name release];
    g_own_name = [firstName copy];
}

#pragma mark services

static UIViewController *top_controller(void) {
    UIViewController *controller = [[[UIApplication sharedApplication] keyWindow] rootViewController];
    for (int depth = 0; controller && depth < 16; ++depth) {
        if (controller.presentedViewController) controller = controller.presentedViewController;
        else if ([controller isKindOfClass:[UINavigationController class]]) controller = [(UINavigationController *)controller topViewController];
        else if ([controller isKindOfClass:[UITabBarController class]]) controller = [(UITabBarController *)controller selectedViewController];
        else break;
    }
    return controller;
}

static NSNumber *argb_number(UIColor *color) {
    return [NSNumber numberWithUnsignedLongLong:argb_of(color)];
}

static UIColor *theme_color(NSString *key) {
    static NSDictionary *table;
    if (!table) {
        table = [[NSDictionary alloc] initWithObjectsAndKeys:
            @"screen", @"windowBackgroundWhite", @"backdrop", @"windowBackgroundGray", @"title", @"windowBackgroundWhiteBlackText",
            @"secondary", @"windowBackgroundWhiteGrayText", @"secondary", @"windowBackgroundWhiteGrayText2", @"secondary", @"windowBackgroundWhiteGrayText3",
            @"accent", @"windowBackgroundWhiteBlueText", @"accent", @"windowBackgroundWhiteBlueText4", @"accent", @"windowBackgroundWhiteLinkText",
            @"hairline", @"divider", @"bar", @"actionBarDefault", @"title", @"actionBarDefaultTitle", @"field", @"chat_messagePanelBackground",
            @"title", @"chat_messagePanelText", @"in", @"chat_inBubble", @"out", @"chat_outBubble", @"message", @"chat_messageTextIn",
            @"message", @"chat_messageTextOut", @"card", @"dialogBackground", @"title", @"dialogTextBlack", @"secondary", @"dialogTextGray",
            @"accent", @"dialogTextBlue", @"accent", @"chats_actionBackground", @"accent", @"featuredStickers_addButton", @"secondary", @"dialogTextGray2", @"onaccent", @"featuredStickers_buttonText",
            @"red", @"text_RedBold", nil];
    }
    NSString *name = [table objectForKey:key];
    if (!name) return nil;
    if ([name isEqualToString:@"screen"]) return ExteriaColorScreen();
    if ([name isEqualToString:@"backdrop"]) return ExteriaColorBackdrop();
    if ([name isEqualToString:@"title"]) return ExteriaColorTitle();
    if ([name isEqualToString:@"secondary"]) return ExteriaColorSecondary();
    if ([name isEqualToString:@"accent"]) return ExteriaColorAccent();
    if ([name isEqualToString:@"hairline"]) return ExteriaColorHairline();
    if ([name isEqualToString:@"bar"]) return ExteriaColorBar();
    if ([name isEqualToString:@"field"]) return ExteriaColorField();
    if ([name isEqualToString:@"in"]) return ExteriaColorBubbleIn();
    if ([name isEqualToString:@"out"]) return ExteriaColorBubbleOut();
    if ([name isEqualToString:@"message"]) return ExteriaColorMessage();
    if ([name isEqualToString:@"onaccent"]) return [UIColor whiteColor];
    if ([name isEqualToString:@"red"]) return ExteriaColorBadgeRed();
    return ExteriaColorCard();
}

static NSDictionary *screen_info(void) {
    UIView *host = overlay();
    CGSize size = host ? host.bounds.size : [[UIScreen mainScreen] bounds].size;
    UIApplication *application = [UIApplication sharedApplication];
    CGFloat top = application.statusBarHidden ? 0 : MIN(application.statusBarFrame.size.height, application.statusBarFrame.size.width);
    return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:(int)size.width], @"w", [NSNumber numberWithInt:(int)size.height], @"h",
            [NSNumber numberWithInt:(int)top], @"top", [NSNumber numberWithInt:0], @"bottom",
            [NSNumber numberWithBool:UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad], @"tablet", nil];
}

static BOOL start_sensor(double interval) {
    Class manager_class = NSClassFromString(@"CMMotionManager");
    if (!manager_class) return NO;
    if (!g_motion) g_motion = (id<ExteriaMotionManager>)[[manager_class alloc] init];
    if (![g_motion isAccelerometerAvailable]) return NO;
    [g_motion setAccelerometerUpdateInterval:interval];
    if ([g_motion isAccelerometerActive]) return YES;
    [g_motion startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(id data, NSError *error) {
        if (!data) return;
        /* android reports m/s2 with the axes of the phone and gravity pointing the other way than coremotion's g */
        struct { double x, y, z; } raw;
        [[data valueForKey:@"acceleration"] getValue:&raw];
        NSArray *arguments = [NSArray arrayWithObjects:[NSNumber numberWithDouble:-raw.x * 9.80665], [NSNumber numberWithDouble:-raw.y * 9.80665], [NSNumber numberWithDouble:-raw.z * 9.80665],
                              [NSNumber numberWithDouble:[[NSProcessInfo processInfo] systemUptime]], nil];
        ExteriaPluginsCallHost(@"sensor", arguments);
    }];
    return YES;
}

/* the short notice of a plugin: a card at the top that fades in, stays a moment and goes; a new one replaces the one on screen */
static UIView *g_banner;
static NSUInteger g_banner_serial;

static void show_banner(NSString *text) {
    UIView *host = overlay();
    if (!host || !text.length) return;
    [g_banner removeFromSuperview];
    [g_banner release];
    NSUInteger serial = ++g_banner_serial;
    CGFloat width = MIN(host.bounds.size.width - 32, 340);
    ExteriaEmojiLabel *label = [[[ExteriaEmojiLabel alloc] init] autorelease];
    label.numberOfLines = 0;
    label.font = ExteriaFontMedium(14);
    label.textColor = ExteriaColorTitle();
    label.text = text;
    label.userInteractionEnabled = NO;
    CGSize fit = [label sizeThatFits:CGSizeMake(width - 28, 1000)];
    UIView *card = [[UIView alloc] init];
    card.userInteractionEnabled = NO;
    card.backgroundColor = [ExteriaColorCard() colorWithAlphaComponent:0.97];
    card.layer.cornerRadius = 16;
    card.layer.shadowOpacity = 0.35f;
    card.layer.shadowRadius = 8;
    card.layer.shadowOffset = CGSizeMake(0, 3);
    CGFloat top = [UIApplication sharedApplication].statusBarHidden ? 8 : MIN([UIApplication sharedApplication].statusBarFrame.size.height, [UIApplication sharedApplication].statusBarFrame.size.width) + 8;
    card.frame = CGRectMake(floor((host.bounds.size.width - width) / 2), top, width, ceil(fit.height) + 24);
    label.frame = CGRectMake(14, 12, width - 28, ceil(fit.height));
    [card addSubview:label];
    card.alpha = 0;
    [host addSubview:card];
    g_banner = card;
    [UIView animateWithDuration:0.2 animations:^{ card.alpha = 1; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (serial != g_banner_serial) return;
        [UIView animateWithDuration:0.25 animations:^{ card.alpha = 0; } completion:^(BOOL finished) {
            (void)finished;
            if (serial == g_banner_serial) [card removeFromSuperview];
        }];
    });
}

/* the answer of the picture picker to python: Activity.RESULT_OK (-1) with the file: address of the kept picture, or RESULT_CANCELED (0) with none */
static void answer_picker(NSNumber *code, int result, NSString *address) {
    ExteriaPluginsCallHost(@"activity_result", [NSArray arrayWithObjects:code, [NSNumber numberWithInt:result], address ? address : @"", nil]);
}

/* the photo library, for a plugin that opened the picker of pictures (Activity.startActivityForResult in python). the picture is kept in the folder of the app and python is given its address */
static void pick_picture_for_plugin(NSNumber *code) {
    UIViewController *host = top_controller();
    if (!host) {
        ExteriaPluginsLog(@"exteria: a plugin asked for a picture while no screen is up");
        answer_picker(code, 0, nil);
        return;
    }
    [ExteriaProfilePhotoPicker pickWholeFrom:host picked:^(NSString *path) {
        NSString *reason = nil;
        NSString *kept = path ? ExteriaPluginPicksAdopt(path, &reason) : nil;
        if (!kept) {
            ExteriaPluginsLog(@"exteria: the picture a plugin asked for was not kept: %@", reason ? reason : @"the choice could not be written");
            answer_picker(code, 0, nil);
            return;
        }
        answer_picker(code, -1, [[NSURL fileURLWithPath:kept] absoluteString]);
    } cancelled:^{
        answer_picker(code, 0, nil);
    } unavailable:^{
        ExteriaPluginsLog(@"exteria: the photo library is not available for a plugin");
        answer_picker(code, 0, nil);
    }];
}

static exteria_status fail(NSString **failure, NSString *text, exteria_status status) {
    if (failure) *failure = text;
    return status;
}

exteria_status ExteriaPluginUIService(NSString *name, NSDictionary *request, NSDictionary **reply, NSString **failure) {
    *reply = [NSDictionary dictionary];
    if ([name isEqualToString:@"ui.apply"]) {
        NSArray *operations = [request objectForKey:@"ops"];
        if (![operations isKindOfClass:[NSArray class]]) return fail(failure, @"no operations", EXTERIA_E_ARG);
        for (id op in operations) if ([op isKindOfClass:[NSArray class]]) apply_operation(op);
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"ui.screen"]) {
        *reply = screen_info();
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"ui.measure"]) {
        NSString *text = [request objectForKey:@"text"];
        CGFloat size = num(request, @"size", 14);
        CGFloat width = MAX(1, num(request, @"width", 100000));
        if (![text isKindOfClass:[NSString class]]) return fail(failure, @"no text", EXTERIA_E_ARG);
        /* the same label that draws the text measures it, so a line wraps where it will be drawn */
        ExteriaEmojiLabel *probe = [[[ExteriaEmojiLabel alloc] init] autorelease];
        probe.numberOfLines = 0;
        probe.font = font_of(size, [[request objectForKey:@"bold"] boolValue]);
        probe.text = text;
        CGSize fit = [probe sizeThatFits:CGSizeMake(width, 100000)];
        *reply = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:(int)ceil(fit.width)], @"w", [NSNumber numberWithInt:(int)ceil(fit.height)], @"h", nil];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"ui.toast"]) {
        id text = [request objectForKey:@"text"];
        show_banner([text isKindOfClass:[NSString class]] ? text : nil);
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"ui.alert"] || [name isEqualToString:@"ui.choose"]) {
        NSNumber *token = [request objectForKey:@"token"];
        id title = [request objectForKey:@"title"];
        id message = [request objectForKey:@"message"];
        NSArray *choices = [request objectForKey:@"items"] ? [request objectForKey:@"items"] : [request objectForKey:@"buttons"];
        if (![token isKindOfClass:[NSNumber class]] || ![choices isKindOfClass:[NSArray class]] || !choices.count) return fail(failure, @"no buttons", EXTERIA_E_ARG);
        NSString *heading = [title isKindOfClass:[NSString class]] ? title : @"";
        void (^answer)(NSInteger) = ^(NSInteger index) {
            ExteriaPluginsCallHost(@"alert_result", [NSArray arrayWithObjects:token, [NSNumber numberWithInteger:index], @"", nil]);
        };
        NSDictionary *field = [[request objectForKey:@"field"] isKindOfClass:[NSDictionary class]] ? [request objectForKey:@"field"] : nil;
        /* the dialog is shown after this call returns: it may be asked for from inside a touch, and python is still running */
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([name isEqualToString:@"ui.choose"]) {
                ExteriaChoose(heading, choices, -1, answer);
            } else {
                NSString *body = [message isKindOfClass:[NSString class]] ? message : @"";
                NSInteger cancel = [[request objectForKey:@"cancel"] integerValue];
                if (field) {
                    /* the text of the field goes back with the answer, the dialog of a plugin that holds an EditText */
                    id initial = [field objectForKey:@"initial"];
                    id placeholder = [field objectForKey:@"placeholder"];
                    ExteriaShowAlertWithField(heading, body, choices, cancel, [initial isKindOfClass:[NSString class]] ? initial : @"", [placeholder isKindOfClass:[NSString class]] ? placeholder : @"", ^(NSInteger index, NSString *text) {
                        ExteriaPluginsCallHost(@"alert_result", [NSArray arrayWithObjects:token, [NSNumber numberWithInteger:index], text ? text : @"", nil]);
                    });
                } else {
                    ExteriaShowAlert(heading, body, choices, cancel, NO, ^(NSInteger index, NSString *text) {
                        (void)text;
                        answer(index);
                    });
                }
            }
        });
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"sensor.available"]) {
        Class manager_class = NSClassFromString(@"CMMotionManager");
        id<ExteriaMotionManager> probe = manager_class ? [[[manager_class alloc] init] autorelease] : nil;
        BOOL ok = probe && [probe isAccelerometerAvailable];
        *reply = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:ok] forKey:@"value"];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"sensor.start"]) {
        int rate = [[request objectForKey:@"rate"] intValue];
        g_sensor_interval = rate <= 1 ? 0.05 : 0.1;
        return start_sensor(g_sensor_interval) ? EXTERIA_OK : fail(failure, @"no accelerometer", EXTERIA_E_UNSUPPORTED);
    }
    if ([name isEqualToString:@"sensor.stop"]) {
        [g_motion stopAccelerometerUpdates];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"theme.color"]) {
        UIColor *color = theme_color([request objectForKey:@"key"]);
        if (!color) return fail(failure, @"no such theme color", EXTERIA_E_NOTFOUND);
        *reply = [NSDictionary dictionaryWithObject:argb_number(color) forKey:@"value"];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"theme.dark"]) {
        CGFloat white = 1;
        [ExteriaColorScreen() getWhite:&white alpha:NULL];
        *reply = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:white < 0.5] forKey:@"value"];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"app.pick"]) {
        NSNumber *token = [request objectForKey:@"token"];
        NSNumber *types = [request objectForKey:@"types"];
        NSNumber *limit = [request objectForKey:@"limit"];
        if (![token isKindOfClass:[NSNumber class]] || ![types isKindOfClass:[NSNumber class]] || ![limit isKindOfClass:[NSNumber class]] || [limit integerValue] < 1 || ![types unsignedIntValue]) {
            return fail(failure, @"no token, kinds or limit", EXTERIA_E_ARG);
        }
        /* the picker is opened after this call returns: python is still running, and the main screen pushes it on its own stack */
        NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:token, @"token", types, @"types", limit, @"limit", nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaPluginPickNotification object:nil userInfo:info];
        });
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"app.current"]) {
        UIViewController *controller = top_controller();
        if ([controller isKindOfClass:[ExteriaChatController class]]) {
            ExteriaDialog *dialog = [(ExteriaChatController *)controller openDialog];
            NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"chat", @"kind", [NSNumber numberWithLongLong:dialog.peerId], @"dialog", [NSNumber numberWithBool:dialog.discussion], @"discussion", nil];
            NSString *title = dialog.title ? dialog.title : @"";
            NSArray *words = [title componentsSeparatedByString:@" "];
            NSDictionary *party = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithLongLong:dialog.peerId], @"id", [words objectAtIndex:0], @"first_name", title, @"title", nil];
            [info setObject:party forKey:dialog.kind == 0 ? @"user" : @"chat"];
            *reply = info;
        } else {
            *reply = [NSDictionary dictionaryWithObject:[controller isKindOfClass:[ExteriaSettingsController class]] ? @"settings" : (controller ? @"other" : @"none") forKey:@"kind"];
        }
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"app.pick_time"]) {
        NSNumber *token = [request objectForKey:@"token"];
        NSString *mode = [request objectForKey:@"mode"];
        /* the day and the time the wheel starts on as the phone's calendar reads them: year, month, day, hour, minute. python's own clock may not know the phone's zone */
        NSArray *initial = [request objectForKey:@"initial"];
        NSNumber *minimum = [request objectForKey:@"minimum"];
        if (![token isKindOfClass:[NSNumber class]] || ![mode isKindOfClass:[NSString class]]) return fail(failure, @"no token or mode", EXTERIA_E_ARG);
        NSDate *start = nil;
        if ([initial isKindOfClass:[NSArray class]] && initial.count == 5) {
            NSDateComponents *parts = [[[NSDateComponents alloc] init] autorelease];
            parts.year = [[initial objectAtIndex:0] integerValue];
            parts.month = [[initial objectAtIndex:1] integerValue];
            parts.day = [[initial objectAtIndex:2] integerValue];
            parts.hour = [[initial objectAtIndex:3] integerValue];
            parts.minute = [[initial objectAtIndex:4] integerValue];
            start = [[NSCalendar currentCalendar] dateFromComponents:parts];
        }
        UIDatePickerMode wheel;
        if ([mode isEqualToString:@"date"]) wheel = UIDatePickerModeDate;
        else if ([mode isEqualToString:@"time"]) wheel = UIDatePickerModeTime;
        else if ([mode isEqualToString:@"datetime"]) wheel = UIDatePickerModeDateAndTime;
        else return fail(failure, @"no such mode", EXTERIA_E_ARG);
        NSDate *earliest = [minimum isKindOfClass:[NSNumber class]] ? [NSDate dateWithTimeIntervalSince1970:[minimum doubleValue]] : nil;
        /* the wheel is shown after this call returns: python is still running, and the answer is a new call into python */
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *host = top_controller();
            if (!host) {
                ExteriaPluginsLog(@"exteria: a plugin asked for a date while no screen is up");
                ExteriaPluginsCallHost(@"time_picked", [NSArray arrayWithObjects:token, [NSNull null], nil]);
                return;
            }
            ExteriaDateTimePicker *picker = [[[ExteriaDateTimePicker alloc] initWithFrame:host.view.bounds mode:wheel initialDate:start minimumDate:earliest done:^(NSDate *date) {
                NSDateComponents *parts = [[NSCalendar currentCalendar] components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit fromDate:date];
                NSArray *chosen = [NSArray arrayWithObjects:[NSNumber numberWithLongLong:(long long)[date timeIntervalSince1970]], [NSNumber numberWithInteger:parts.year],
                                   [NSNumber numberWithInteger:parts.month], [NSNumber numberWithInteger:parts.day], [NSNumber numberWithInteger:parts.hour], [NSNumber numberWithInteger:parts.minute], nil];
                ExteriaPluginsCallHost(@"time_picked", [NSArray arrayWithObjects:token, chosen, nil]);
            } cancelled:^{
                ExteriaPluginsCallHost(@"time_picked", [NSArray arrayWithObjects:token, [NSNull null], nil]);
            }] autorelease];
            [host.view addSubview:picker];
        });
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"app.pick_root"]) {
        *reply = [NSDictionary dictionaryWithObject:ExteriaPluginPicksDirectory() forKey:@"value"];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"app.pick_image"]) {
        NSNumber *code = [request objectForKey:@"request"];
        if (![code isKindOfClass:[NSNumber class]]) return fail(failure, @"no request code", EXTERIA_E_ARG);
        /* the picker is shown after this call returns: python is still running, and its answer is a new call into python */
        dispatch_async(dispatch_get_main_queue(), ^{ pick_picture_for_plugin(code); });
        return EXTERIA_OK;
    }
    if ([name hasPrefix:@"account."]) {
        /* the main screen owns the session and answers through exteria_host.account_result once the server has */
        NSNumber *token = [request objectForKey:@"token"];
        if (![token isKindOfClass:[NSNumber class]]) return fail(failure, @"no token", EXTERIA_E_ARG);
        NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:request];
        [info setObject:[name substringFromIndex:[@"account." length]] forKey:@"op"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaPluginAccountNotification object:nil userInfo:info];
        });
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"page.cards"]) {
        id alpha = [request objectForKey:@"alpha"];
        if (![alpha isKindOfClass:[NSNumber class]] || !isfinite([alpha doubleValue])) return fail(failure, @"no alpha", EXTERIA_E_ARG);
        set_card_alpha((CGFloat)[alpha doubleValue]);
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"bitmap.decode"]) {
        id path = [request objectForKey:@"path"];
        id side = [request objectForKey:@"side"];
        if (![path isKindOfClass:[NSString class]] || ![side isKindOfClass:[NSNumber class]]) return fail(failure, @"no path or side", EXTERIA_E_ARG);
        NSString *reason = nil;
        exteria_status status = ExteriaPluginBitmapDecode(path, [side intValue], reply, &reason);
        return status == EXTERIA_OK ? status : fail(failure, reason, status);
    }
    if ([name isEqualToString:@"bitmap.scale"]) {
        NSString *reason = nil;
        exteria_status status = ExteriaPluginBitmapScale([[request objectForKey:@"handle"] longLongValue], [[request objectForKey:@"w"] intValue], [[request objectForKey:@"h"] intValue], reply, &reason);
        return status == EXTERIA_OK ? status : fail(failure, reason, status);
    }
    if ([name isEqualToString:@"bitmap.crop"]) {
        NSString *reason = nil;
        exteria_status status = ExteriaPluginBitmapCrop([[request objectForKey:@"handle"] longLongValue], [[request objectForKey:@"x"] intValue], [[request objectForKey:@"y"] intValue],
                                                        [[request objectForKey:@"w"] intValue], [[request objectForKey:@"h"] intValue], reply, &reason);
        return status == EXTERIA_OK ? status : fail(failure, reason, status);
    }
    if ([name isEqualToString:@"bitmap.encode"]) {
        id path = [request objectForKey:@"path"];
        if (![path isKindOfClass:[NSString class]]) return fail(failure, @"no path", EXTERIA_E_ARG);
        NSString *reason = nil;
        exteria_status status = ExteriaPluginBitmapEncode([[request objectForKey:@"handle"] longLongValue], [[request objectForKey:@"png"] boolValue], [[request objectForKey:@"quality"] intValue], path, &reason);
        return status == EXTERIA_OK ? status : fail(failure, reason, status);
    }
    if ([name isEqualToString:@"bitmap.copy"]) {
        NSString *reason = nil;
        exteria_status status = ExteriaPluginBitmapCopy([[request objectForKey:@"handle"] longLongValue], reply, &reason);
        return status == EXTERIA_OK ? status : fail(failure, reason, status);
    }
    if ([name isEqualToString:@"bitmap.blur"]) {
        NSString *reason = nil;
        exteria_status status = ExteriaPluginBitmapBlur([[request objectForKey:@"handle"] longLongValue], [[request objectForKey:@"radius"] intValue], &reason);
        return status == EXTERIA_OK ? status : fail(failure, reason, status);
    }
    if ([name isEqualToString:@"bitmap.release"]) {
        NSArray *handles = [request objectForKey:@"handles"];
        if (![handles isKindOfClass:[NSArray class]]) return fail(failure, @"no handles", EXTERIA_E_ARG);
        for (id handle in handles) if ([handle isKindOfClass:[NSNumber class]]) ExteriaPluginBitmapRelease([handle longLongValue]);
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"sheet.open"]) {
        NSInteger number = ExteriaPluginSheetOpen(request, top_controller());
        if (!number) return fail(failure, @"the sheet could not be shown", EXTERIA_E_STATE);
        *reply = [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:number] forKey:@"id"];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"sheet.ready"]) {
        ExteriaPluginSheetReady([[request objectForKey:@"id"] integerValue]);
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"sheet.fail"]) {
        id text = [request objectForKey:@"text"];
        ExteriaPluginSheetFail([[request objectForKey:@"id"] integerValue], [text isKindOfClass:[NSString class]] ? text : @"");
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"sheet.close"]) {
        ExteriaPluginSheetClose([[request objectForKey:@"id"] integerValue]);
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"app.me"]) {
        *reply = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithLongLong:g_own_user], @"id", g_own_name ? g_own_name : @"", @"first_name", nil];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"chat.rebuild"]) {
        /* a plugin changed what its hooks say about the messages on show: the open chat is laid out again */
        UIViewController *controller = top_controller();
        if ([controller isKindOfClass:[ExteriaChatController class]]) [(ExteriaChatController *)controller redrawForPlugins];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"app.language"]) {
        *reply = [NSDictionary dictionaryWithObject:ExteriaInterfaceLanguage() forKey:@"value"];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"app.version"]) {
        NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
        if (![version isKindOfClass:[NSString class]]) return fail(failure, @"the bundle has no version", EXTERIA_E_NOTFOUND);
        *reply = [NSDictionary dictionaryWithObject:version forKey:@"value"];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"net.proxies"]) {
        /* the proxies of the system settings, which urllib and requests read through _scproxy: for each scheme the host and port when it is switched on */
        NSDictionary *system = [(NSDictionary *)CFNetworkCopySystemProxySettings() autorelease];
        NSMutableDictionary *answer = [NSMutableDictionary dictionary];
        NSArray *schemes = [NSArray arrayWithObjects:@"HTTP", @"HTTPS", @"FTP", nil];
        for (NSString *scheme in schemes) {
            NSNumber *enabled = [system objectForKey:[scheme stringByAppendingString:@"Enable"]];
            NSString *host = [system objectForKey:[scheme stringByAppendingString:@"Proxy"]];
            NSNumber *port = [system objectForKey:[scheme stringByAppendingString:@"Port"]];
            if (![enabled isKindOfClass:[NSNumber class]] || ![enabled boolValue] || ![host isKindOfClass:[NSString class]] || !host.length) continue;
            NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObject:host forKey:@"host"];
            if ([port isKindOfClass:[NSNumber class]]) [entry setObject:port forKey:@"port"];
            [answer setObject:entry forKey:[scheme lowercaseString]];
        }
        NSNumber *simple = [system objectForKey:@"ExcludeSimpleHostnames"];
        [answer setObject:[NSNumber numberWithBool:[simple isKindOfClass:[NSNumber class]] && [simple boolValue]] forKey:@"exclude_simple"];
        NSArray *exceptions = [system objectForKey:@"ExceptionsList"];
        NSMutableArray *names = [NSMutableArray array];
        for (id one in [exceptions isKindOfClass:[NSArray class]] ? exceptions : [NSArray array]) if ([one isKindOfClass:[NSString class]]) [names addObject:one];
        [answer setObject:names forKey:@"exceptions"];
        *reply = answer;
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"app.protocol"]) {
        /* the layer the core speaks; the api id stays with the app */
        *reply = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:exteria_tl_layer] forKey:@"layer"];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"app.muted"]) {
        UIViewController *controller = top_controller();
        BOOL muted = NO;
        if ([controller isKindOfClass:[ExteriaChatController class]]) {
            ExteriaDialog *dialog = [(ExteriaChatController *)controller openDialog];
            muted = dialog.peerId == [[request objectForKey:@"dialog"] longLongValue] && dialog.muted;
        }
        *reply = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:muted] forKey:@"value"];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"chat.send"]) {
        UIViewController *controller = top_controller();
        NSString *text = [request objectForKey:@"text"];
        if (![controller isKindOfClass:[ExteriaChatController class]] || ![text isKindOfClass:[NSString class]] || !text.length) {
            return fail(failure, @"the chat is not open", EXTERIA_E_NOTFOUND);
        }
        ExteriaChatController *chat = (ExteriaChatController *)controller;
        if ([chat openDialog].peerId != [[request objectForKey:@"peer"] longLongValue]) return fail(failure, @"only the open chat can be written to", EXTERIA_E_NOTFOUND);
        [chat sendPluginText:text replyTo:(int32_t)[[request objectForKey:@"reply"] intValue]];
        return EXTERIA_OK;
    }
    if ([name hasPrefix:@"story."]) return ExteriaPluginStoryService(name, request, reply, failure);
    if ([name hasPrefix:@"audio."]) return ExteriaPluginAudioService(name, request, reply, failure);
    if ([name hasPrefix:@"music."]) return ExteriaPluginMusicService(name, request, reply, failure);
    if ([name isEqualToString:@"chat.send_photo"]) {
        UIViewController *controller = top_controller();
        NSString *path = [request objectForKey:@"path"];
        NSString *caption = [request objectForKey:@"caption"];
        if (![controller isKindOfClass:[ExteriaChatController class]] || ![path isKindOfClass:[NSString class]] || !path.length) {
            return fail(failure, @"the chat is not open", EXTERIA_E_NOTFOUND);
        }
        ExteriaChatController *chat = (ExteriaChatController *)controller;
        if ([chat openDialog].peerId != [[request objectForKey:@"peer"] longLongValue]) return fail(failure, @"only the open chat can be written to", EXTERIA_E_NOTFOUND);
        if (!ExteriaPluginsPathInCache(path)) return fail(failure, @"a photo can only be sent from the plugin files folder", EXTERIA_E_ARG);
        NSString *reason = [chat sendPluginPhotoAtPath:path caption:[caption isKindOfClass:[NSString class]] ? caption : nil replyTo:(int32_t)[[request objectForKey:@"reply"] intValue]];
        return reason ? fail(failure, reason, EXTERIA_E_IO) : EXTERIA_OK;
    }
    return EXTERIA_E_UNSUPPORTED;
}

void ExteriaPluginUIReset(void) {
    ExteriaPluginAudioReset();
    ExteriaPluginMusicReset();
    ExteriaPluginSheetCloseAll();
    [g_motion stopAccelerometerUpdates];
    for (UIView *child in [[g_overlay.subviews copy] autorelease]) [child removeFromSuperview];
    /* the layers of the pages belong to the pages, which keep them: they are emptied and stay registered for the next plugin */
    NSMutableDictionary *pages = [NSMutableDictionary dictionary];
    for (NSNumber *key in g_views) if ([key longLongValue] < 0) [pages setObject:[g_views objectForKey:key] forKey:key];
    for (UIView *layer in pages.allValues) {
        for (UIView *child in [[layer.subviews copy] autorelease]) [child removeFromSuperview];
        page_layer_changed(layer);
    }
    [g_views removeAllObjects];
    [g_views addEntriesFromDictionary:pages];
    set_card_alpha(1);
}
