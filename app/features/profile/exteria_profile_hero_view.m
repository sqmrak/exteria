#import "exteria_profile_hero_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_platform.h"
#import "exteria_remote_file.h"
#import "exteria_session_profile.h"
#import "exteria_theme.h"

#define STRIP_HEIGHT 3.0
#define STRIP_GAP 4.0
#define SIDE_MARGIN 10.0
#define PHOTO_MAX_SIDE 1600.0
/* the buttons of the profile stand over the lower edge of the photo; the words stand over them */
#define ACTIONS_ROOM 84.0
#define SWITCH_CIRCLE 26.0
#define SWITCH_REACH 10.0

@interface ExteriaProfileHeroView () {
    ExteriaSession *_session;
    ExteriaDialog *_dialog;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    NSArray *_photos;
    UIImageView *_cover;
    UIScrollView *_pager;
    NSMutableArray *_pages;
    NSMutableArray *_asked;
    UIView *_strips;
    NSMutableArray *_stripFills;
    CAGradientLayer *_scrim;
    ExteriaEmojiLabel *_name;
    UILabel *_status;
    ExteriaRatingBadge *_ratingBadge;
    ExteriaMedia *_publicPhoto;
    /* the public photo as a page: the last of _photos, once the list is in */
    BOOL _hasPublicPage;
    UIControl *_switch;
    UIImageView *_switchThumb;
    UILabel *_switchLabel;
    UIImage *_publicImage;
    NSInteger _index;
    BOOL _moving;
    NSUInteger _token;
}
@end

@implementation ExteriaProfileHeroView

@synthesize bottomRoom = _bottomRoom;
@synthesize publicPhoto = _publicPhoto;

@synthesize name = _name;
@synthesize status = _status;
@synthesize stripTop = _stripTop;

+ (CGFloat)heightForWidth:(CGFloat)width screenHeight:(CGFloat)screenHeight {
    return MIN(ceil(width * 1.05), MAX(width * 0.8, screenHeight * 0.62));
}

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _session = [session retain];
    _dialog = [dialog retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _bottomRoom = ACTIONS_ROOM;
    _pages = [[NSMutableArray alloc] init];
    _asked = [[NSMutableArray alloc] init];
    _stripFills = [[NSMutableArray alloc] init];
    _moving = YES;
    _stripTop = 8;
    /* no ground of its own: a black one showed round the shrinking picture */
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = YES;
    _cover = [[UIImageView alloc] init];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_cover];
    _pager = [[UIScrollView alloc] init];
    _pager.pagingEnabled = YES;
    _pager.showsHorizontalScrollIndicator = NO;
    _pager.showsVerticalScrollIndicator = NO;
    _pager.bounces = NO;
    _pager.scrollsToTop = NO;
    _pager.delegate = self;
    _pager.hidden = YES;
    [self addSubview:_pager];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease];
    tap.delegate = self;
    [self addGestureRecognizer:tap];
    _scrim = [[CAGradientLayer layer] retain];
    _scrim.colors = [NSArray arrayWithObjects:(id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.62].CGColor, nil];
    _scrim.opacity = 0;
    [self.layer addSublayer:_scrim];
    _strips = [[UIView alloc] init];
    _strips.userInteractionEnabled = NO;
    _strips.hidden = YES;
    _strips.alpha = 0;
    [self addSubview:_strips];
    _name = [[ExteriaEmojiLabel alloc] init];
    _name.textColor = [UIColor whiteColor];
    _name.font = ExteriaFontBold(24);
    _name.dropsUndrawable = YES;
    _name.alpha = 0;
    [self addSubview:_name];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = [UIColor colorWithWhite:1 alpha:0.78];
    _status.font = ExteriaFontRegular(15);
    _status.alpha = 0;
    [self addSubview:_status];
    _ratingBadge = [[ExteriaRatingBadge alloc] initWithFrame:CGRectZero];
    _ratingBadge.hidden = YES;
    _ratingBadge.alpha = 0;
    [self addSubview:_ratingBadge];
    _switch = [[UIControl alloc] init];
    _switch.hidden = YES;
    _switch.alpha = 0;
    [_switch addTarget:self action:@selector(switchTapped) forControlEvents:UIControlEventTouchUpInside];
    _switchThumb = [[UIImageView alloc] init];
    _switchThumb.contentMode = UIViewContentModeScaleAspectFill;
    _switchThumb.clipsToBounds = YES;
    _switchThumb.layer.cornerRadius = SWITCH_CIRCLE / 2;
    _switchThumb.layer.borderWidth = 1.5;
    _switchThumb.layer.borderColor = [UIColor whiteColor].CGColor;
    _switchThumb.userInteractionEnabled = NO;
    [_switch addSubview:_switchThumb];
    _switchLabel = [[UILabel alloc] init];
    _switchLabel.backgroundColor = [UIColor clearColor];
    _switchLabel.textColor = [UIColor whiteColor];
    _switchLabel.font = ExteriaFontMedium(13);
    _switchLabel.userInteractionEnabled = NO;
    [_switch addSubview:_switchLabel];
    [self addSubview:_switch];
    [self showSmallPhoto];
    return self;
}

- (void)dealloc {
    ++_token;
    _pager.delegate = nil;
    [_session release]; [_dialog release]; [_avatars release]; [_media release]; [_photos release];
    [_cover release]; [_pager release]; [_pages release]; [_asked release]; [_strips release]; [_stripFills release]; [_scrim release];
    [_name release]; [_status release]; [_ratingBadge release];
    [_publicPhoto release]; [_switch release]; [_switchThumb release]; [_switchLabel release]; [_publicImage release];
    [super dealloc];
}

- (void)setRatingLevel:(int32_t)level target:(id)target action:(SEL)action {
    _ratingBadge.level = level;
    _ratingBadge.hidden = level <= 0;
    [_ratingBadge removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    if (level > 0 && target) [_ratingBadge addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [self setNeedsLayout];
}

#pragma mark photos

/* the photo the profile already shows is on the view at once; the sharp one takes its place when it is loaded */
- (void)showSmallPhoto {
    ExteriaPhoto *small = _dialog.photo;
    if (!small) return;
    UIImage *cached = [_avatars cachedImageForPhoto:small];
    if (cached) { _cover.image = cached; return; }
    NSUInteger token = _token;
    [_avatars loadImageForPhoto:small completion:^(UIImage *image) {
        if (token != _token || _cover.image) return;
        _cover.image = image;
    }];
}

- (void)buildPages:(NSUInteger)count {
    for (UIView *page in _pages) [page removeFromSuperview];
    [_pages removeAllObjects];
    [_asked removeAllObjects];
    for (NSUInteger i = 0; i < count; ++i) {
        UIImageView *page = [[[UIImageView alloc] init] autorelease];
        page.contentMode = UIViewContentModeScaleAspectFill;
        page.clipsToBounds = YES;
        [_pager addSubview:page];
        [_pages addObject:page];
        [_asked addObject:[NSNumber numberWithBool:NO]];
    }
    [self setNeedsLayout];
}

/* the public photo is the page after the last profile photo; it is left out when the list already holds it */
- (NSArray *)pagesWithPublicPhoto:(NSArray *)photos {
    _hasPublicPage = NO;
    if (!_publicPhoto || _publicPhoto.ref.id == 0) return photos;
    for (ExteriaMedia *photo in photos) {
        if (photo.ref.id == _publicPhoto.ref.id) return photos;
    }
    _hasPublicPage = YES;
    return [photos arrayByAddingObject:_publicPhoto];
}

- (void)setPublicPhoto:(ExteriaMedia *)photo {
    if (photo == _publicPhoto || (photo && _publicPhoto && photo.ref.id == _publicPhoto.ref.id)) return;
    [_publicPhoto release];
    _publicPhoto = [photo retain];
    [_publicImage release];
    _publicImage = nil;
    if (_photos.count || _hasPublicPage) {
        /* the list came before the photo: its pages are built again with the new last one */
        NSMutableArray *own = [NSMutableArray arrayWithArray:_photos];
        if (_hasPublicPage && own.count) [own removeLastObject];
        [_photos release];
        _photos = [[self pagesWithPublicPhoto:own] retain];
        [self buildPages:_photos.count];
        [self buildStrips];
        _index = MIN(_index, (NSInteger)_photos.count - 1);
        [self loadAround:_index];
        [self loadPublicThumb];
        [self refreshStrips];
        [self refreshSwitch];
    }
}

- (void)loadPublicThumb {
    if (!_hasPublicPage || _publicImage) return;
    exteria_media_ref ref = _publicPhoto.ref;
    ExteriaRemoteFile *file = [ExteriaRemoteFile fileForMedia:&ref];
    if (!file) return;
    NSUInteger token = _token;
    [_media loadImageForFile:file maxSide:PHOTO_MAX_SIDE completion:^(UIImage *image) {
        if (token != _token || !image) return;
        [_publicImage release];
        _publicImage = [image retain];
        [self refreshSwitch];
    }];
}

/* on the public page the circle shows the first profile photo and leads back to it; on any other page it shows the public one and leads there */
- (BOOL)onPublicPage {
    return _hasPublicPage && _index == (NSInteger)_photos.count - 1;
}

- (void)refreshSwitch {
    /* with a single photo there is nothing to lead to and the circle would name the page that is already shown */
    BOOL shown = _hasPublicPage && _photos.count > 1 && !_moving;
    _switch.hidden = !shown;
    if (!shown) return;
    BOOL onPublic = [self onPublicPage];
    UIImage *first = _pages.count ? [[_pages objectAtIndex:0] image] : nil;
    _switchThumb.image = onPublic ? (first ? first : _cover.image) : _publicImage;
    _switchLabel.text = NSLocalizedString(onPublic ? @"profile.photo.main" : @"profile.photo.public", nil);
    [self setNeedsLayout];
}

- (void)switchTapped {
    if (_moving || !_hasPublicPage) return;
    [self goToIndex:[self onPublicPage] ? 0 : (NSInteger)_photos.count - 1];
}

- (void)loadList {
    NSUInteger token = _token;
    [_session loadAvatarsOfDialog:_dialog completion:^(NSArray *photos, NSString *errorName) {
        if (token != _token || errorName) return;
        photos = [self pagesWithPublicPhoto:photos];
        if (photos.count == 0) return;
        [_photos release];
        _photos = [photos retain];
        _index = 0;
        [self buildPages:photos.count];
        [self buildStrips];
        [self loadAround:0];
        [self refreshStrips];
        [self loadPublicThumb];
        /* the first page shows what the cover shows until its own sharp picture comes */
        if (_pages.count) [[_pages objectAtIndex:0] setImage:_cover.image];
        if (!_moving) {
            _pager.hidden = NO;
            _cover.hidden = YES;
        }
    }];
}

- (void)loadAround:(NSInteger)index {
    for (NSInteger i = index - 1; i <= index + 1; ++i) {
        if (i < 0 || i >= (NSInteger)_pages.count || i >= (NSInteger)_photos.count) continue;
        if ([[_asked objectAtIndex:(NSUInteger)i] boolValue]) continue;
        ExteriaMedia *photo = [_photos objectAtIndex:(NSUInteger)i];
        exteria_media_ref ref = photo.ref;
        ExteriaRemoteFile *file = [ExteriaRemoteFile fileForMedia:&ref];
        if (!file) continue;
        [_asked replaceObjectAtIndex:(NSUInteger)i withObject:[NSNumber numberWithBool:YES]];
        NSUInteger token = _token;
        UIImageView *page = [_pages objectAtIndex:(NSUInteger)i];
        [_media loadImageForFile:file maxSide:PHOTO_MAX_SIDE completion:^(UIImage *image) {
            if (token != _token || !image) return;
            page.image = image;
            if (i == _index) _cover.image = image;
            if (i == 0) [self refreshSwitch];
        }];
    }
}

#pragma mark strips

/* a strip for each photo along the top, and only the shown photo's one is white; none when there is a single photo */
- (void)buildStrips {
    for (UIView *view in [[_strips.subviews copy] autorelease]) [view removeFromSuperview];
    [_stripFills removeAllObjects];
    NSUInteger count = _photos.count;
    _strips.hidden = count < 2;
    for (NSUInteger i = 0; i < count; ++i) {
        UIView *track = [[[UIView alloc] init] autorelease];
        track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
        track.layer.cornerRadius = STRIP_HEIGHT / 2;
        track.clipsToBounds = YES;
        UIView *fill = [[[UIView alloc] init] autorelease];
        fill.backgroundColor = [UIColor whiteColor];
        [track addSubview:fill];
        [_strips addSubview:track];
        [_stripFills addObject:fill];
    }
    [self setNeedsLayout];
}

- (void)refreshStrips {
    for (NSUInteger i = 0; i < _stripFills.count; ++i) {
        UIView *fill = [_stripFills objectAtIndex:i];
        fill.frame = CGRectMake(0, 0, (NSInteger)i == _index ? fill.superview.bounds.size.width : 0, STRIP_HEIGHT);
    }
}

#pragma mark layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _pager.frame = self.bounds;
    _pager.contentSize = CGSizeMake(size.width * (CGFloat)_pages.count, size.height);
    for (NSUInteger i = 0; i < _pages.count; ++i) [[_pages objectAtIndex:i] setFrame:CGRectMake(size.width * (CGFloat)i, 0, size.width, size.height)];
    if (!_moving) _pager.contentOffset = CGPointMake(size.width * (CGFloat)_index, 0);
    CGFloat scrimHeight = MIN(size.height, 200);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _scrim.frame = CGRectMake(0, size.height - scrimHeight, size.width, scrimHeight);
    [CATransaction commit];
    /* the words stand over the buttons that the screen puts on the lower edge */
    /* the badge of the rating stands before the status, and the status moves over by the room it takes */
    CGFloat statusLeft = _ratingBadge.hidden ? 20 : 20 + 26;
    /* the circle of the public photo and its name take the right end of the status line */
    CGFloat switchWidth = 0;
    if (!_switch.hidden) {
        switchWidth = MIN(ceil([_switchLabel sizeThatFits:CGSizeMake(size.width, SWITCH_CIRCLE)].width), size.width / 2) + SWITCH_CIRCLE + 8;
        /* the control reaches a fingertip past the circle and the words, which are small, and they stand inside it where they stood */
        _switch.frame = CGRectMake(size.width - 20 - switchWidth - SWITCH_REACH, size.height - _bottomRoom - 22 + 10 - SWITCH_CIRCLE / 2 - 2 - SWITCH_REACH, switchWidth + 2 * SWITCH_REACH, SWITCH_CIRCLE + 4 + 2 * SWITCH_REACH);
        _switchThumb.frame = CGRectMake(SWITCH_REACH, 2 + SWITCH_REACH, SWITCH_CIRCLE, SWITCH_CIRCLE);
        _switchLabel.frame = CGRectMake(SWITCH_REACH + SWITCH_CIRCLE + 8, 2 + SWITCH_REACH, switchWidth - SWITCH_CIRCLE - 8, SWITCH_CIRCLE);
        switchWidth += 10;
    }
    _ratingBadge.frame = CGRectMake(20, size.height - _bottomRoom - 22, 22, 20);
    _status.frame = CGRectMake(statusLeft, size.height - _bottomRoom - 22, MAX(0, size.width - statusLeft - 20 - switchWidth), 20);
    _name.frame = CGRectMake(20, size.height - _bottomRoom - 22 - 32, MAX(0, size.width - 40), 30);
    CGFloat count = (CGFloat)_stripFills.count;
    if (count > 0) {
        _strips.frame = CGRectMake(SIDE_MARGIN, _stripTop, MAX(0, size.width - 2 * SIDE_MARGIN), STRIP_HEIGHT);
        CGFloat each = (_strips.bounds.size.width - STRIP_GAP * (count - 1)) / count;
        for (NSUInteger i = 0; i < _stripFills.count; ++i) [[(UIView *)[_stripFills objectAtIndex:i] superview] setFrame:CGRectMake((each + STRIP_GAP) * (CGFloat)i, 0, each, STRIP_HEIGHT)];
        [self refreshStrips];
    }
}

#pragma mark gestures

- (void)goToIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_pages.count || index == _index) return;
    _index = index;
    [_pager setContentOffset:CGPointMake(_pager.bounds.size.width * (CGFloat)index, 0) animated:YES];
    [self loadAround:index];
    [self refreshStrips];
    [self refreshSwitch];
}

/* a tap anywhere on the photo goes to the next one, and after the last one comes the first; the photo is taken away by a pull down, not by a tap */
- (void)tapped:(UITapGestureRecognizer *)tap {
    (void)tap;
    if (_moving || _pages.count < 2) return;
    [self goToIndex:(_index + 1) % (NSInteger)_pages.count];
}

/* the swipe runs beside the scrolling of the list, which also sees the finger */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    (void)other;
    return ![gesture isKindOfClass:[UITapGestureRecognizer class]];
}

/* a tap on the circle of the public photo or on the badge of the rating is theirs, and must not also turn the page */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    (void)gesture;
    for (UIView *view = touch.view; view && view != self; view = view.superview) {
        if ([view isKindOfClass:[UIControl class]]) return NO;
    }
    return YES;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat width = scrollView.bounds.size.width;
    if (width <= 0 || !_photos.count || _moving) return;
    NSInteger index = (NSInteger)floor((scrollView.contentOffset.x + width / 2) / width);
    index = MAX(0, MIN(index, (NSInteger)_photos.count - 1));
    if (index == _index) return;
    _index = index;
    [self loadAround:index];
    [self refreshStrips];
    [self refreshSwitch];
}

#pragma mark moving

- (void)setContentAlpha:(CGFloat)alpha {
    _strips.alpha = alpha;
    _name.alpha = alpha;
    _status.alpha = alpha;
    _ratingBadge.alpha = alpha;
    _switch.alpha = alpha;
    _scrim.opacity = (float)alpha;
}

- (void)beginMove {
    _moving = YES;
    [self refreshSwitch];
    _pager.hidden = YES;
    _cover.hidden = NO;
    [self setContentAlpha:0];
}

- (void)finishOpen {
    _moving = NO;
    if (!_photos) [self loadList];
    BOOL pages = _photos.count > 0;
    _pager.hidden = !pages;
    _cover.hidden = pages;
    [self refreshSwitch];
    [self setNeedsLayout];
    [UIView animateWithDuration:0.2 animations:^{ [self setContentAlpha:1]; }];
}

- (void)beginClose {
    _moving = YES;
    [self refreshSwitch];
    /* the picture that was shown stays under the shrinking frame, and the pages go: a pager resized in the middle of a move showed what lay behind it */
    if (_index < (NSInteger)_pages.count) {
        UIImage *shown = [[_pages objectAtIndex:(NSUInteger)_index] image];
        if (shown) _cover.image = shown;
    }
    _cover.hidden = NO;
    _pager.hidden = YES;
    [UIView animateWithDuration:0.15 animations:^{ [self setContentAlpha:0]; }];
}

- (void)animateCornerTo:(CGFloat)radius duration:(NSTimeInterval)duration {
    CABasicAnimation *round = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
    round.fromValue = [NSNumber numberWithDouble:self.layer.cornerRadius];
    round.toValue = [NSNumber numberWithDouble:radius];
    round.duration = duration;
    round.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:round forKey:@"exteria.corner"];
    self.layer.cornerRadius = radius;
}

@end
