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
    NSInteger _index;
    BOOL _moving;
    NSUInteger _token;
}
@end

@implementation ExteriaProfileHeroView

@synthesize name = _name;
@synthesize status = _status;
@synthesize stripTop = _stripTop;
@synthesize closeRequestHandler = _closeRequestHandler;

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
    [self addGestureRecognizer:tap];
    /* a swipe down takes the photo away, as a pull of the list down does */
    UISwipeGestureRecognizer *down = [[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipedDown:)] autorelease];
    down.direction = UISwipeGestureRecognizerDirectionDown;
    down.delegate = self;
    [self addGestureRecognizer:down];
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
    [self showSmallPhoto];
    return self;
}

- (void)dealloc {
    ++_token;
    _pager.delegate = nil;
    [_closeRequestHandler release];
    [_session release]; [_dialog release]; [_avatars release]; [_media release]; [_photos release];
    [_cover release]; [_pager release]; [_pages release]; [_asked release]; [_strips release]; [_stripFills release]; [_scrim release];
    [_name release]; [_status release]; [_ratingBadge release];
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

- (void)loadList {
    NSUInteger token = _token;
    [_session loadAvatarsOfDialog:_dialog completion:^(NSArray *photos, NSString *errorName) {
        if (token != _token || errorName || photos.count == 0) return;
        [_photos release];
        _photos = [photos retain];
        _index = 0;
        [self buildPages:photos.count];
        [self buildStrips];
        [self loadAround:0];
        [self refreshStrips];
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
    _ratingBadge.frame = CGRectMake(20, size.height - ACTIONS_ROOM - 22, 22, 20);
    _status.frame = CGRectMake(statusLeft, size.height - ACTIONS_ROOM - 22, MAX(0, size.width - statusLeft - 20), 20);
    _name.frame = CGRectMake(20, size.height - ACTIONS_ROOM - 22 - 32, MAX(0, size.width - 40), 30);
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
}

/* a tap anywhere on the photo goes to the next one, and after the last one comes the first; the photo is taken away by a pull down, not by a tap */
- (void)tapped:(UITapGestureRecognizer *)tap {
    (void)tap;
    if (_moving || _pages.count < 2) return;
    [self goToIndex:(_index + 1) % (NSInteger)_pages.count];
}

- (void)swipedDown:(UISwipeGestureRecognizer *)swipe {
    (void)swipe;
    if (!_moving && _closeRequestHandler) _closeRequestHandler();
}

/* the swipe runs beside the scrolling of the list, which also sees the finger */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    (void)gesture; (void)other;
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
}

#pragma mark moving

- (void)setContentAlpha:(CGFloat)alpha {
    _strips.alpha = alpha;
    _name.alpha = alpha;
    _status.alpha = alpha;
    _ratingBadge.alpha = alpha;
    _scrim.opacity = (float)alpha;
}

- (void)beginMove {
    _moving = YES;
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
    [self setNeedsLayout];
    [UIView animateWithDuration:0.2 animations:^{ [self setContentAlpha:1]; }];
}

- (void)beginClose {
    _moving = YES;
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
