#import "exteria_story_strip.h"
#import "exteria_animation.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_chat_settings.h"
#import "exteria_avatar_view.h"
#import "exteria_classic_chrome.h"
#import "exteria_alert.h"
#import "exteria_emoji_label.h"
#import "exteria_person.h"
#import "exteria_profile_photo_picker.h"
#import "exteria_story.h"
#import "exteria_story_camera_controller.h"
#import "exteria_story_ring.h"
#import "exteria_story_viewer_controller.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define STRIP_HEIGHT 92.0
#define ITEM_WIDTH 72.0
#define RING 58.0
#define PHOTO 50.0
#define REFRESH_SECONDS 45.0
#define RING_WIDTH 2.0
#define SEEN_WIDTH 1.3
#define CLASSIC_STRIP_HEIGHT 90.0
#define CLASSIC_ITEM_WIDTH 76.0
#define CLASSIC_TILE 58.0
#define CLASSIC_MAT 3.0

static UIColor *ExteriaStoryRGB(CGFloat red, CGFloat green, CGFloat blue) {
    return [UIColor colorWithRed:red / 255 green:green / 255 blue:blue / 255 alpha:1];
}

/* the ring of the Telegram story cell: an unseen story is a stroke that runs from blue to green, one for close
   friends from lime to green, and a seen one a thin grey line */
@interface ExteriaStoryRingView : UIControl {
    ExteriaAvatarView *_avatar;
    ExteriaEmojiLabel *_name;
    CAGradientLayer *_gradient;
    CAShapeLayer *_stroke;
    BOOL _classic;
    UIView *_mat;
    CAGradientLayer *_gloss;
    UIImageView *_badge;
    UILabel *_count;
    UIButton *_plus;
}
- (id)initWithFrame:(CGRect)frame classic:(BOOL)classic;
/* selfDialog is the account as a chat with oneself, which has the photo that the own cell shows: the story list names the own cell by a chat that has none */
- (void)configureWithPeer:(ExteriaStoryPeer *)peer avatars:(ExteriaAvatarCache *)avatars selfDialog:(ExteriaDialog *)selfDialog;
/* the plus of the own cell, which adds a story; hidden on every other cell */
@property (nonatomic, readonly) UIButton *plus;
@end

@implementation ExteriaStoryRingView

@synthesize plus = _plus;

- (id)initWithFrame:(CGRect)frame classic:(BOOL)classic {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    ExteriaAttachBounce(self, 0.06);
    _classic = classic;
    CGFloat itemWidth = classic ? CLASSIC_ITEM_WIDTH : ITEM_WIDTH;
    if (classic) {
        [self buildClassicTileInWidth:itemWidth];
    } else {
        CGRect box = CGRectMake((itemWidth - RING) / 2, 6, RING, RING);
        _gradient = [[CAGradientLayer layer] retain];
        _gradient.frame = box;
        _gradient.startPoint = CGPointMake(1, 0);
        _gradient.endPoint = CGPointMake(0, 1);
        _stroke = [[CAShapeLayer layer] retain];
        _stroke.frame = CGRectMake(0, 0, RING, RING);
        _stroke.fillColor = nil;
        _stroke.strokeColor = [UIColor blackColor].CGColor;
        _gradient.mask = _stroke;
        [self.layer addSublayer:_gradient];
        _avatar = [[ExteriaAvatarView alloc] initWithFrame:CGRectMake((itemWidth - PHOTO) / 2, 6 + (RING - PHOTO) / 2, PHOTO, PHOTO)];
        _avatar.circular = YES;
        [self addSubview:_avatar];
    }
    [self buildPlusInWidth:itemWidth];
    /* a name stays inside its cell with two points to spare on either side, so the name next to it never touches it; one that does not fit ends in dots */
    _name = [[ExteriaEmojiLabel alloc] initWithFrame:CGRectMake(2, classic ? 72 : 68, itemWidth - 4, 16)];
    _name.font = classic ? [UIFont boldSystemFontOfSize:10.5] : ExteriaFontRegular(10.5);
    _name.textAlignment = ExteriaTextAlignmentCenter;
    _name.textColor = ExteriaColorSecondary();
    [self addSubview:_name];
    return self;
}

/* the classic tile is a slide in a white mount: a rounded square photo with a glass cap over its upper half, a
   shadow under the mount, and a lit outline while a story is unseen */
- (void)buildClassicTileInWidth:(CGFloat)itemWidth {
    CGFloat mat = CLASSIC_MAT;
    _mat = [[UIView alloc] initWithFrame:CGRectMake((itemWidth - CLASSIC_TILE) / 2, 8, CLASSIC_TILE, CLASSIC_TILE)];
    _mat.userInteractionEnabled = NO;
    _mat.backgroundColor = ExteriaThemeIsDark() ? [UIColor colorWithWhite:0.86 alpha:1] : [UIColor whiteColor];
    _mat.layer.cornerRadius = 11;
    _mat.layer.borderWidth = 1;
    _mat.layer.shadowOffset = CGSizeMake(0, 1);
    _mat.layer.shadowRadius = 2;
    [self addSubview:_mat];
    _avatar = [[ExteriaAvatarView alloc] initWithFrame:CGRectMake(mat, mat, CLASSIC_TILE - 2 * mat, CLASSIC_TILE - 2 * mat)];
    _avatar.userInteractionEnabled = NO;
    _avatar.layer.cornerRadius = 8;
    _avatar.layer.masksToBounds = YES;
    [_mat addSubview:_avatar];
    _gloss = [[CAGradientLayer layer] retain];
    _gloss.frame = CGRectMake(mat, mat, CLASSIC_TILE - 2 * mat, (CLASSIC_TILE - 2 * mat) / 2);
    _gloss.colors = [NSArray arrayWithObjects:(id)[UIColor colorWithWhite:1 alpha:0.42].CGColor, (id)[UIColor colorWithWhite:1 alpha:0.06].CGColor, nil];
    _gloss.cornerRadius = 8;
    [_mat.layer addSublayer:_gloss];
    _badge = [[UIImageView alloc] initWithImage:ExteriaClassicGlossButtonImage(ExteriaClassicGlossRed, NO)];
    _badge.hidden = YES;
    _badge.userInteractionEnabled = NO;
    [self addSubview:_badge];
    _count = [[UILabel alloc] init];
    _count.backgroundColor = [UIColor clearColor];
    _count.font = [UIFont boldSystemFontOfSize:12];
    _count.textColor = [UIColor whiteColor];
    _count.textAlignment = ExteriaTextAlignmentCenter;
    [_badge addSubview:_count];
}

/* the plus on the corner of the own photo; the button is wider than the disc so a finger finds it */
- (void)buildPlusInWidth:(CGFloat)itemWidth {
    _plus = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _plus.hidden = YES;
    _plus.accessibilityLabel = NSLocalizedString(@"story.add", nil);
    CGFloat disc = _classic ? 22 : 24;
    CGFloat hit = 34;
    CGFloat photoRight = _classic ? CGRectGetMaxX(_mat.frame) : (itemWidth + PHOTO) / 2;
    CGFloat photoBottom = _classic ? CGRectGetMaxY(_mat.frame) : 6 + (RING - PHOTO) / 2 + PHOTO;
    _plus.frame = CGRectMake(photoRight - disc / 2 - hit / 2 + 2, photoBottom - disc / 2 - hit / 2 + 2, hit, hit);
    CGFloat inset = (hit - disc) / 2;
    UIImageView *face = [[[UIImageView alloc] initWithFrame:CGRectMake(inset, inset, disc, disc)] autorelease];
    face.userInteractionEnabled = NO;
    if (_classic) {
        face.image = ExteriaClassicGlossButtonImage(ExteriaClassicGlossGreen, NO);
    } else {
        face.backgroundColor = ExteriaStoryRGB(0x2c, 0x9e, 0xfc);
        face.layer.cornerRadius = disc / 2;
        face.layer.borderWidth = 2.5;
        face.layer.borderColor = ExteriaColorScreen().CGColor;
    }
    UIColor *ink = _classic ? [UIColor whiteColor] : [UIColor colorWithWhite:0.08 alpha:1];
    CGFloat arm = _classic ? 12 : 11, thick = _classic ? 3 : 2.5;
    for (int i = 0; i < 2; ++i) {
        CALayer *bar = [CALayer layer];
        bar.backgroundColor = ink.CGColor;
        bar.cornerRadius = thick / 2;
        bar.frame = i ? CGRectMake((disc - arm) / 2, (disc - thick) / 2, arm, thick) : CGRectMake((disc - thick) / 2, (disc - arm) / 2, thick, arm);
        [face.layer addSublayer:bar];
    }
    [_plus addSubview:face];
    [self addSubview:_plus];
}

- (void)dealloc {
    [_plus release];
    [_avatar release];
    [_name release];
    [_gradient release];
    [_stroke release];
    [_mat release];
    [_gloss release];
    [_badge release];
    [_count release];
    [super dealloc];
}

- (void)configureRingForPeer:(ExteriaStoryPeer *)peer {
    BOOL unseen = peer.unread > 0;
    CGFloat width = unseen ? RING_WIDTH : SEEN_WIDTH;
    CGFloat inset = width / 2;
    _stroke.lineWidth = width;
    _stroke.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(inset, inset, RING - width, RING - width)].CGPath;
    UIColor *from, *to;
    ExteriaStoryRingColors(unseen, peer.closeFriends, &from, &to);
    _gradient.colors = [NSArray arrayWithObjects:(id)from.CGColor, (id)to.CGColor, nil];
}

- (void)configureClassicRingForPeer:(ExteriaStoryPeer *)peer {
    BOOL unseen = peer.unread > 0;
    UIColor *lit = peer.closeFriends ? [UIColor colorWithRed:0.30 green:0.78 blue:0.30 alpha:1] : ExteriaColorAccent();
    _mat.layer.borderColor = (unseen ? lit : [UIColor colorWithWhite:0 alpha:0.28]).CGColor;
    _mat.layer.borderWidth = unseen ? 2 : 1;
    _mat.layer.shadowColor = (unseen ? lit : [UIColor blackColor]).CGColor;
    _mat.layer.shadowOpacity = unseen ? 0.95f : 0.4f;
    _mat.layer.shadowRadius = unseen ? 4 : 2;
    _mat.layer.shadowOffset = unseen ? CGSizeZero : CGSizeMake(0, 1);
    _badge.hidden = !unseen || peer.owner.saved;
    if (_badge.hidden) return;
    _count.text = peer.unread > 99 ? @"99+" : [NSString stringWithFormat:@"%d", (int)peer.unread];
    CGFloat width = MAX(20, ceil([_count sizeThatFits:CGSizeMake(100, 20)].width) + 12);
    _badge.frame = CGRectMake(CGRectGetMaxX(_mat.frame) - width + 7, 1, width, 20);
    _count.frame = _badge.bounds;
}

- (void)configureWithPeer:(ExteriaStoryPeer *)peer avatars:(ExteriaAvatarCache *)avatars selfDialog:(ExteriaDialog *)selfDialog {
    ExteriaDialog *owner = peer.owner;
    BOOL unseen = peer.unread > 0;
    if (_classic) [self configureClassicRingForPeer:peer];
    else [self configureRingForPeer:peer];
    /* the own cell without a story of its own has no ring at all, only the photo and the plus; the classic tile is already a quiet mount for it */
    _gradient.hidden = owner.saved && peer.count == 0;
    _plus.hidden = !owner.saved;
    BOOL borrows = owner.saved && !owner.photo && selfDialog;
    ExteriaChatTrace([NSString stringWithFormat:@"story cell saved %d photo %@ self %@ borrows %d", (int)owner.saved, owner.photo.key, selfDialog.photo.key, (int)borrows]);
    _avatar.initials = owner.initials.length || !borrows ? owner.initials : selfDialog.initials;
    _avatar.seed = owner.avatarSeed;
    [_avatar setPhoto:borrows ? selfDialog.photo : owner.photo cache:avatars];
    NSString *title = owner.saved ? NSLocalizedString(@"story.mine", nil) : owner.title;
    _name.text = title;
    _name.textColor = unseen ? ExteriaColorTitle() : ExteriaColorSecondary();
    if (_classic) {
        /* the light theme prints the name into the shelf, with a pale shadow under it */
        _name.shadowColor = ExteriaThemeIsDark() ? nil : [UIColor colorWithWhite:1 alpha:0.85];
        _name.shadowOffset = CGSizeMake(0, 1);
    }
    self.accessibilityLabel = unseen ? [NSString stringWithFormat:@"%@, %d", title, (int)peer.unread] : title;
}

@end

/* the shelf the classic rings stand on: a pale metal band with a lit upper edge and a dark lower one, one pixel wide so that it repeats along the row */
static UIColor *ExteriaStoryShelfColor(CGFloat height) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(2, height), YES, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    BOOL dark = ExteriaThemeIsDark();
    CGFloat light[] = {0.97, 0.97, 0.98, 1, 0.86, 0.86, 0.89, 1};
    CGFloat night[] = {0.24, 0.23, 0.27, 1, 0.13, 0.12, 0.16, 1};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, dark ? night : light, NULL, 2);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(0, height), 0);
    CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:1 alpha:dark ? 0.12 : 0.9].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, 2, 1));
    CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0 alpha:dark ? 0.7 : 0.38].CGColor);
    CGContextFillRect(context, CGRectMake(0, height - 1, 2, 1));
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [UIColor colorWithPatternImage:image];
}

@interface ExteriaStoryStrip () {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_host;
    void (^_changed)(void);
    void (^_peersChanged)(void);
    ExteriaWeakReference *_weak;
    UIScrollView *_scroll;
    NSArray *_peers;
    CGFloat _height;
    BOOL _classic;
    BOOL _loading;
    BOOL _viewerOpen;
    /* the signed in person as a chat with oneself, which stands for the own cell when the server lists no story of ours */
    ExteriaDialog *_selfDialog;
    BOOL _selfAsked;
    BOOL _posting;
    /* what the row shows: the server's list, with an own cell in front when it has none */
    NSArray *_cells;
    CFAbsoluteTime _loadedAt;
}
@end

@implementation ExteriaStoryStrip

@synthesize height = _height;

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
                 host:(UIViewController *)host changed:(void (^)(void))changed {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _host = [[ExteriaWeakReference referenceTo:host] retain];
    _changed = [changed copy];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, 320, 0)];
    _scroll.showsHorizontalScrollIndicator = NO;
    _classic = ExteriaThemeIsClassic();
    _scroll.backgroundColor = _classic ? ExteriaStoryShelfColor(CLASSIC_STRIP_HEIGHT) : [UIColor clearColor];
    _scroll.clipsToBounds = YES;
    _peers = [[NSArray alloc] init];
    _cells = [[NSArray alloc] init];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_session release];
    [_avatars release];
    [_media release];
    [_host release];
    [_changed release];
    [_peersChanged release];
    [_weak release];
    [_scroll release];
    [_peers release];
    [_cells release];
    [_selfDialog release];
    [super dealloc];
}

- (UIView *)view { return _scroll; }

@synthesize peersChanged = _peersChanged;

- (ExteriaStoryPeer *)peerForDialog:(ExteriaDialog *)dialog {
    if (dialog.kind != EXTERIA_DIALOG_USER || dialog.saved) return nil;
    for (ExteriaStoryPeer *peer in _peers) {
        if (peer.owner.saved) continue;
        if (peer.owner.peerKind == dialog.peerKind && peer.owner.peerId == dialog.peerId) return peer;
    }
    return nil;
}

- (void)reload {
    if (_loading) return;
    _loading = YES;
    ExteriaWeakReference *weak = _weak;
    [_session loadStoryPeers:^(NSArray *peers, NSString *errorName) {
        ExteriaStoryStrip *me = weak.target;
        if (!me) return;
        me->_loading = NO;
        me->_loadedAt = CFAbsoluteTimeGetCurrent();
        if (errorName) {
            NSLog(@"exteria: story strip not refreshed: %@", errorName);
            return;
        }
        [me showPeers:peers];
    }];
}

- (void)refresh {
    if (CFAbsoluteTimeGetCurrent() - _loadedAt < REFRESH_SECONDS) return;
    [self reload];
}

/* the own story first, always: the server lists it only while we have one, and the cell is also where a new one starts */
- (void)loadSelfDialog {
    if (_selfAsked) return;
    _selfAsked = YES;
    /* the own cell wears the photo of the last time at once, and the answer replaces it */
    ExteriaPerson *known = _selfDialog ? nil : [_session ownPerson];
    if (known) {
        _selfDialog = [[ExteriaDialog savedMessagesWithPerson:known] retain];
        [self showPeers:_peers];
    }
    ExteriaWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        ExteriaStoryStrip *me = weak.target;
        if (!me) return;
        ExteriaPerson *person = items.count ? [items objectAtIndex:0] : nil;
        ExteriaDialog *dialog = person ? [ExteriaDialog savedMessagesWithPerson:person] : nil;
        if (!dialog) {
            NSLog(@"exteria: the own story cell has no profile to stand on: %@", errorName);
            me->_selfAsked = NO;
            return;
        }
        [me->_selfDialog release];
        me->_selfDialog = [dialog retain];
        [me showPeers:me->_peers];
    }];
}

- (BOOL)hasOwnStories {
    ExteriaStoryPeer *first = _peers.count ? [_peers objectAtIndex:0] : nil;
    return first.owner.saved;
}

- (void)showPeers:(NSArray *)peers {
    /* the caller may hand over _peers itself, so the copy is made before the old list is let go */
    NSArray *kept = [peers copy];
    [_peers release];
    _peers = kept;
    NSMutableArray *cells = [NSMutableArray arrayWithArray:_peers];
    if (![self hasOwnStories] && _selfDialog) [cells insertObject:[ExteriaStoryPeer peerWithOwner:_selfDialog count:0] atIndex:0];
    /* the own cell wears the photo of the account in either case, so the account is asked for once, whether or not it has stories */
    if (!_selfDialog) [self loadSelfDialog];
    [_cells release];
    _cells = [cells copy];
    for (UIView *old in [[_scroll.subviews copy] autorelease]) [old removeFromSuperview];
    CGFloat rowHeight = _classic ? CLASSIC_STRIP_HEIGHT : STRIP_HEIGHT;
    CGFloat itemWidth = _classic ? CLASSIC_ITEM_WIDTH : ITEM_WIDTH;
    CGFloat height = _cells.count ? rowHeight : 0;
    for (NSUInteger i = 0; i < _cells.count; ++i) {
        ExteriaStoryRingView *ring = [[[ExteriaStoryRingView alloc] initWithFrame:CGRectMake(8 + i * itemWidth, 2, itemWidth, rowHeight - 4) classic:_classic] autorelease];
        ring.tag = (NSInteger)i;
        [ring configureWithPeer:[_cells objectAtIndex:i] avatars:_avatars selfDialog:_selfDialog];
        [ring addTarget:self action:@selector(ringTapped:) forControlEvents:UIControlEventTouchUpInside];
        [ring.plus addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:ring];
    }
    _scroll.contentSize = CGSizeMake(16 + _cells.count * itemWidth, height);
    if (height != _height) {
        _height = height;
        CGRect frame = _scroll.frame;
        frame.size.height = height;
        _scroll.frame = frame;
        if (_changed) _changed();
    }
    if (_peersChanged) _peersChanged();
}

- (void)layoutInWidth:(CGFloat)width {
    CGRect frame = _scroll.frame;
    frame.size.width = width;
    frame.size.height = _height;
    _scroll.frame = frame;
}

/* the server's list is what the viewer pages through; an own cell that was put in front is not in it, and a tap on it starts a story */
- (void)ringTapped:(UIControl *)ring {
    UIViewController *host = _host.target;
    if (!host || _viewerOpen || (NSUInteger)ring.tag >= _cells.count) return;
    ExteriaStoryPeer *cell = [_cells objectAtIndex:(NSUInteger)ring.tag];
    if (cell.count == 0) { [self addTapped]; return; }
    NSUInteger offset = _cells.count - _peers.count;
    _viewerOpen = YES;
    ExteriaStoryViewerController *viewer = [[[ExteriaStoryViewerController alloc] initWithSession:_session peers:_peers index:(NSUInteger)ring.tag - offset
                                                                                          avatars:_avatars media:_media] autorelease];
    ExteriaWeakReference *weak = _weak;
    viewer.closeHandler = ^{
        ExteriaStoryStrip *me = weak.target;
        if (!me) return;
        me->_viewerOpen = NO;
        /* what was seen now has quiet rings */
        [me reload];
    };
    [host presentViewController:viewer animated:YES completion:nil];
}

/* the camera screen makes the story; a device without a camera, or the library button of the screen, picks a photo
   instead */
- (void)addTapped {
    UIViewController *host = _host.target;
    if (!host || _posting || _viewerOpen) return;
    if (![ExteriaStoryCameraController cameraAvailable]) { [self pickFromLibraryIn:host]; return; }
    ExteriaStoryCameraController *camera = [[[ExteriaStoryCameraController alloc] init] autorelease];
    ExteriaWeakReference *weak = _weak;
    camera.publishHandler = ^(NSString *path) {
        ExteriaStoryStrip *me = weak.target;
        UIViewController *top = me ? me->_host.target : nil;
        [top dismissViewControllerAnimated:YES completion:nil];
        [me postStoryAtPath:path];
    };
    camera.closeHandler = ^{
        ExteriaStoryStrip *me = weak.target;
        UIViewController *top = me ? me->_host.target : nil;
        [top dismissViewControllerAnimated:YES completion:nil];
    };
    camera.galleryHandler = ^{
        ExteriaStoryStrip *me = weak.target;
        UIViewController *top = me ? me->_host.target : nil;
        if (!top) return;
        [top dismissViewControllerAnimated:YES completion:^{ [me pickFromLibraryIn:top]; }];
    };
    [host presentViewController:camera animated:YES completion:nil];
}

- (void)pickFromLibraryIn:(UIViewController *)host {
    ExteriaWeakReference *weak = _weak;
    [ExteriaProfilePhotoPicker pickWholeFrom:host picked:^(NSString *path) {
        if (!path) {
            NSLog(@"exteria: the story photo could not be prepared");
            ExteriaShowNotice(nil, NSLocalizedString(@"story.add.failed", nil));
            return;
        }
        ExteriaStoryStrip *me = weak.target;
        if (!me) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            return;
        }
        [me postStoryAtPath:path];
    } unavailable:^{
        ExteriaShowNotice(nil, NSLocalizedString(@"attach.gallery.unavailable", nil));
    }];
}

/* the file goes up as a story for everyone and is deleted either way; the row is asked again when it is live */
- (void)postStoryAtPath:(NSString *)path {
    if (_posting) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        return;
    }
    _posting = YES;
    ExteriaWeakReference *weak = _weak;
    [_session postStoryPhotoAtPath:path completion:^(NSString *errorName) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        ExteriaStoryStrip *again = weak.target;
        if (!again) return;
        again->_posting = NO;
        if (errorName) {
            NSLog(@"exteria: the story was not published: %@", errorName);
            ExteriaShowNotice(nil, NSLocalizedString(@"story.add.failed", nil));
            return;
        }
        [again reload];
    }];
}

@end
