#import "exteria_name_badge.h"
#import "exteria_story_viewer_controller.h"
#import "exteria_string_drawing.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_view.h"
#import "exteria_audio_session.h"
#import "exteria_classic_chrome.h"
#import "exteria_emoji_label.h"
#import "exteria_platform.h"
#import "exteria_music_player.h"
#import "exteria_premium_gate_view.h"
#import "exteria_session_profile.h"
#import "exteria_popup_menu.h"
#import "exteria_story.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_time.h"
#import "exteria_weak_reference.h"

#define TICK 0.04
#define PHOTO_SECONDS 5.0
#define IMAGE_SIDE 1280.0
#define HEADER_HEIGHT 64.0
#define BAR_HEIGHT 54.0
#define TAP_ZONE 0.3
#define CAPTION_LINES 4
#define CHIP_HEIGHT 30.0
#define SIDE_BUTTON 44.0
#define STORY_HEART_SIDE 26.0
#define TURN_SECONDS 0.2
#define TURN_ANGLE (M_PI / 2.2)
#define TURN_DEPTH 900.0
/* the classic chrome is the black translucent bar of the old photo viewer: a bar of 44 points with the progress groove under it */
#define CLASSIC_BAR 44.0
#define CLASSIC_HEADER 58.0
#define CLASSIC_TOOLBAR 44.0
#define CLASSIC_SEGMENT 6.0
#define CLASSIC_BUTTON_HEIGHT 30.0

/* NSTimer retains its target, the weak bridge lets a closed viewer release its timer */
@interface ExteriaStoryTickTarget : NSObject {
    ExteriaWeakReference *_weak;
}
- (id)initWithReference:(ExteriaWeakReference *)weak;
- (void)fire:(NSTimer *)timer;
@end

/* the reply pill: the text and the placeholder start at its left edge, and the line sits on the vertical middle by its own height, since a
   field puts a tall font line high in a short rect */
#define REPLY_INSET 16.0

@interface ExteriaStoryReplyField : UITextField {
    UILabel *_hint;
}
@end

@implementation ExteriaStoryReplyField

/* the hint is a label of the field: the system placeholder of a subclass is drawn through drawPlaceholderInRect on ios 5 to 12 only,
   and the newer systems leave the pill empty */
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _hint = [[UILabel alloc] init];
    _hint.backgroundColor = [UIColor clearColor];
    _hint.userInteractionEnabled = NO;
    [self addSubview:_hint];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textChanged) name:UITextFieldTextDidChangeNotification object:self];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_hint release];
    [super dealloc];
}

- (void)setPlaceholder:(NSString *)placeholder {
    _hint.text = placeholder;
    self.accessibilityLabel = placeholder;
    [self setNeedsLayout];
}

- (NSString *)placeholder { return _hint.text; }

- (void)setText:(NSString *)text {
    [super setText:text];
    [self textChanged];
}

- (void)textChanged {
    _hint.hidden = self.text.length > 0;
}

- (CGRect)textAreaForBounds:(CGRect)bounds {
    CGFloat line = ceil(self.font.lineHeight) + 2;
    return CGRectMake(REPLY_INSET, floor((bounds.size.height - line) / 2), MAX(0, bounds.size.width - 2 * REPLY_INSET), line);
}

- (CGRect)textRectForBounds:(CGRect)bounds { return [self textAreaForBounds:bounds]; }
- (CGRect)editingRectForBounds:(CGRect)bounds { return [self textAreaForBounds:bounds]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    _hint.font = self.font;
    _hint.textColor = self.borderStyle == UITextBorderStyleRoundedRect ? [UIColor colorWithWhite:0.6 alpha:1] : [UIColor colorWithWhite:1 alpha:0.7];
    _hint.frame = [self textAreaForBounds:self.bounds];
    [self textChanged];
}

@end

@interface ExteriaStoryViewerController (Tick)
- (void)tick;
@end

@implementation ExteriaStoryTickTarget
- (id)initWithReference:(ExteriaWeakReference *)weak {
    self = [super init];
    if (self) _weak = [weak retain];
    return self;
}
- (void)dealloc { [_weak release]; [super dealloc]; }
- (void)fire:(NSTimer *)timer { (void)timer; [(ExteriaStoryViewerController *)_weak.target tick]; }
@end

/* the layer of the player has to track the size of its view */
@interface ExteriaStoryVideoView : UIView
@end

@implementation ExteriaStoryVideoView
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

@interface ExteriaStoryViewerController () <UITextFieldDelegate, UIGestureRecognizerDelegate> {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    NSArray *_peers;
    NSMutableDictionary *_stories;
    NSUInteger _peerIndex;
    NSUInteger _storyIndex;
    /* the story to start at when the stories came with the viewer, NSNotFound when the first unseen one is wanted */
    NSUInteger _startStory;
    NSUInteger _loadToken;
    NSUInteger _pathRequest;
    BOOL _loadingPeer;
    BOOL _closed;
    BOOL _paused;
    BOOL _editing;
    BOOL _statusWasHidden;
    BOOL _failed;
    BOOL _classic;
    BOOL _turning;
    NSString *_previousAudioCategory;

    UIImageView *_image;
    ExteriaStoryVideoView *_videoView;
    UIActivityIndicatorView *_spinner;
    UILabel *_notice;
    UIView *_scrim;
    UIView *_scrimBottom;
    UIView *_top;
    NSMutableArray *_segments;
    NSMutableArray *_fills;
    ExteriaAvatarView *_avatar;
    ExteriaEmojiLabel *_name;
    UILabel *_time;
    UIButton *_sound;
    UIButton *_menu;
    UIButton *_done;
    /* a poster who takes replies only from Premium users: the pill that says so instead of the reply field, and the line that explains it */
    UIButton *_locked;
    UIView *_banner;
    NSMutableDictionary *_gated;
    UIView *_captionPlate;
    UIView *_chip;
    UIImageView *_chipIcon;
    UILabel *_chipText;
    /* an AVAudioPlayer, found by name: the arm64 slice is built against an sdk that keeps the class in a framework ios 10 and 11 do not have, and naming it
       in the code makes the app refuse to start there */
    id _music;
    NSUInteger _musicRequest;
    /* the sound of the stories, the video's and the track's, stays off for the rest of the viewing once it is turned off */
    BOOL _muted;
    ExteriaEmojiLabel *_caption;
    UIView *_bottom;
    ExteriaStoryReplyField *_reply;
    UIButton *_heart;
    UILabel *_views;
    UILabel *_toast;
    NSTimer *_timer;
    ExteriaStoryTickTarget *_tickTarget;

    ExteriaStory *_current;
    double _elapsed;
    double _duration;
    AVPlayer *_player;
    NSURL *_videoURL;
    AVPlayerItem *_item;
    BOOL _videoStarted;
    NSMutableDictionary *_reacted;
    NSMutableDictionary *_readUpTo;
    ExteriaReaction *_heartReaction;
    CGFloat _keyboardOverlap;
}
@end

@implementation ExteriaStoryViewerController

@synthesize closeHandler = _closeHandler;

- (id)initWithSession:(ExteriaSession *)session peers:(NSArray *)peers index:(NSUInteger)index avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _peers = [peers copy];
    _peerIndex = index < _peers.count ? index : 0;
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _stories = [[NSMutableDictionary alloc] init];
    _reacted = [[NSMutableDictionary alloc] init];
    _readUpTo = [[NSMutableDictionary alloc] init];
    _segments = [[NSMutableArray alloc] init];
    _fills = [[NSMutableArray alloc] init];
    _gated = [[NSMutableDictionary alloc] init];
    _startStory = NSNotFound;
    _classic = ExteriaThemeIsClassic();
    return self;
}

- (id)initWithSession:(ExteriaSession *)session owner:(ExteriaDialog *)owner stories:(NSArray *)stories index:(NSUInteger)index
              avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    NSArray *peers = [NSArray arrayWithObject:[ExteriaStoryPeer peerWithOwner:owner count:(int32_t)stories.count]];
    self = [self initWithSession:session peers:peers index:0 avatars:avatars media:media];
    if (!self) return nil;
    [_stories setObject:stories forKey:[NSNumber numberWithUnsignedInteger:0]];
    /* nothing of these is marked seen: they are ours, or already past */
    [_readUpTo setObject:[NSNumber numberWithInt:INT32_MAX] forKey:[NSNumber numberWithUnsignedInteger:0]];
    _startStory = index < stories.count ? index : 0;
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideBanner) object:nil];
    [_weak clear];
    [_media cancelPathRequest:_pathRequest];
    [self stopTimer];
    [self releasePlayer];
    [_session release];
    [_avatars release];
    [_media release];
    [_weak release];
    [_peers release];
    [_stories release];
    [_reacted release];
    [_readUpTo release];
    [_segments release];
    [_fills release];
    [_previousAudioCategory release];
    [_closeHandler release];
    [_image release];
    [_videoView release];
    [_spinner release];
    [_notice release];
    [_scrim release];
    [_scrimBottom release];
    [_top release];
    [_avatar release];
    [_name release];
    [_time release];
    [_sound release];
    [_menu release];
    [_done release];
    [_locked release];
    [_banner release];
    [_gated release];
    [_captionPlate release];
    [_chip release];
    [_chipIcon release];
    [_chipText release];
    [_music release];
    [_caption release];
    [_bottom release];
    [_reply release];
    [_heart release];
    [_views release];
    [_toast release];
    [_tickTarget release];
    [_current release];
    [_heartReaction release];
    [super dealloc];
}

#pragma mark view

static UILabel *ExteriaStoryLabel(CGFloat size, BOOL bold) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [UIColor whiteColor];
    label.font = bold ? ExteriaFontSemibold(size) : ExteriaFontRegular(size);
    label.shadowColor = [UIColor colorWithWhite:0 alpha:0.6];
    label.shadowOffset = CGSizeMake(0, 1);
    return label;
}

/* the name and the caption are the author's own text, so they go through the layer that finds a font for any character; it draws
   no shadow, and the shades below keep the white text readable */
static ExteriaEmojiLabel *ExteriaStoryTextLabel(CGFloat size, BOOL bold) {
    ExteriaEmojiLabel *label = [[[ExteriaEmojiLabel alloc] init] autorelease];
    label.textColor = [UIColor whiteColor];
    label.font = bold ? ExteriaFontSemibold(size) : ExteriaFontRegular(size);
    return label;
}

/* a dark fade along the top or the bottom edge, so the text over a bright picture stays readable */
static UIView *ExteriaStoryShade(BOOL fromTop, BOOL classic) {
    UIView *view = [[UIView alloc] init];
    view.userInteractionEnabled = NO;
    CAGradientLayer *shade = [CAGradientLayer layer];
    if (classic) {
        shade.colors = [NSArray arrayWithObjects:(id)[UIColor colorWithWhite:0.36 alpha:0.82].CGColor, (id)[UIColor colorWithWhite:0.20 alpha:0.82].CGColor,
                                                 (id)[UIColor colorWithWhite:0.07 alpha:0.82].CGColor, (id)[UIColor colorWithWhite:0.0 alpha:0.82].CGColor, nil];
        shade.locations = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:0.5f], [NSNumber numberWithFloat:0.5f],
                                                    [NSNumber numberWithFloat:1], nil];
        [view.layer addSublayer:shade];
        return view;
    }
    id dark = (id)[UIColor colorWithWhite:0 alpha:0.55].CGColor, clear = (id)[UIColor colorWithWhite:0 alpha:0].CGColor;
    shade.colors = fromTop ? [NSArray arrayWithObjects:dark, clear, nil] : [NSArray arrayWithObjects:clear, dark, nil];
    [view.layer addSublayer:shade];
    return view;
}

/* a glossy bar button of the classic chrome: a violet grey plate with a white bold title engraved under a dark shadow */
static UIButton *ExteriaStoryClassicButton(NSString *title) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setBackgroundImage:ExteriaClassicGlossButtonImage(ExteriaClassicGlossSlate, NO) forState:UIControlStateNormal];
    [button setBackgroundImage:ExteriaClassicGlossButtonImage(ExteriaClassicGlossSlate, YES) forState:UIControlStateHighlighted];
    if (title) {
        button.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        [button setTitle:title forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [button setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.5] forState:UIControlStateNormal];
        button.titleLabel.shadowOffset = CGSizeMake(0, -1);
    }
    return button;
}

/* the progress groove and its fill are one pixel wide patterns, so they repeat along any width; the groove is sunk and the fill a lit purple bead */
static UIColor *ExteriaStoryClassicPattern(BOOL fill) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(2, CLASSIC_SEGMENT), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat groove[] = {0.02, 0.02, 0.03, 1, 0.22, 0.22, 0.25, 1};
    CGFloat bead[] = {0.82, 0.68, 0.97, 1, 0.50, 0.30, 0.76, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, fill ? bead : groove, NULL, 2);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(0, CLASSIC_SEGMENT), 0);
    CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:1 alpha:fill ? 0.55 : 0.14].CGColor);
    CGContextFillRect(context, CGRectMake(0, fill ? 0 : CLASSIC_SEGMENT - 1, 2, 1));
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [UIColor colorWithPatternImage:image];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = [UIColor blackColor];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _image = [[UIImageView alloc] init];
    _image.contentMode = UIViewContentModeScaleAspectFit;
    [root addSubview:_image];
    _videoView = [[ExteriaStoryVideoView alloc] init];
    _videoView.hidden = YES;
    ((AVPlayerLayer *)_videoView.layer).videoGravity = AVLayerVideoGravityResizeAspect;
    [root addSubview:_videoView];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.hidesWhenStopped = YES;
    [root addSubview:_spinner];
    _notice = [ExteriaStoryLabel(15, NO) retain];
    _notice.textAlignment = ExteriaTextAlignmentCenter;
    _notice.numberOfLines = 0;
    _notice.hidden = YES;
    [root addSubview:_notice];

    _scrim = ExteriaStoryShade(YES, _classic);
    [root addSubview:_scrim];
    _scrimBottom = ExteriaStoryShade(NO, _classic);
    [root addSubview:_scrimBottom];
    if (_classic) {
        /* a caption sits on a plate of its own, since the bottom bar is only as tall as the reply row */
        _captionPlate = [[UIView alloc] init];
        _captionPlate.userInteractionEnabled = NO;
        _captionPlate.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        _captionPlate.hidden = YES;
        [root addSubview:_captionPlate];
    }
    _top = [[UIView alloc] init];
    [root addSubview:_top];
    _avatar = [[ExteriaAvatarView alloc] init];
    _avatar.circular = YES;
    [_top addSubview:_avatar];
    _name = [ExteriaStoryTextLabel(15, YES) retain];
    [_top addSubview:_name];
    _time = [ExteriaStoryLabel(12, NO) retain];
    ExteriaLabelFitToWidth(_time, 9);
    _time.textColor = [UIColor colorWithWhite:1 alpha:0.8];
    [_top addSubview:_time];
    _sound = [(_classic ? ExteriaStoryClassicButton(nil) : [UIButton buttonWithType:UIButtonTypeCustom]) retain];
    [_sound addTarget:self action:@selector(soundTapped) forControlEvents:UIControlEventTouchUpInside];
    [_top addSubview:_sound];
    [self refreshSoundButton];
    _menu = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_menu setImage:ExteriaSymbolImage(ExteriaSymbolEllipsisVertical, 22, [UIColor whiteColor]) forState:UIControlStateNormal];
    [_menu addTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
    _menu.accessibilityLabel = NSLocalizedString(@"story.menu", nil);
    if (_classic) {
        /* the bar has a close button of its own at the left, so there is no menu */
        _menu.hidden = YES;
        _done = [ExteriaStoryClassicButton(NSLocalizedString(@"story.close", nil)) retain];
        [_done addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [_top addSubview:_done];
    }
    [_top addSubview:_menu];

    _caption = [ExteriaStoryTextLabel(15, NO) retain];
    _caption.numberOfLines = CAPTION_LINES;
    [root addSubview:_caption];

    _bottom = [[UIView alloc] init];
    [root addSubview:_bottom];
    _reply = [[ExteriaStoryReplyField alloc] init];
    _reply.delegate = self;
    _reply.placeholder = NSLocalizedString(@"story.reply", nil);
    _reply.font = ExteriaFontRegular(15);
    _reply.textAlignment = ExteriaTextAlignmentLeft;
    if (_classic) {
        /* the white rounded field of the old toolbars, with its own sunken edge from the system */
        _reply.borderStyle = UITextBorderStyleRoundedRect;
        _reply.textColor = [UIColor blackColor];
    } else {
        _reply.textColor = [UIColor whiteColor];
        _reply.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
        _reply.layer.cornerRadius = 18;
        _reply.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.5].CGColor;
        _reply.layer.borderWidth = 1;
    }
    _reply.returnKeyType = UIReturnKeySend;
    _reply.keyboardAppearance = UIKeyboardAppearanceAlert;
    _reply.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    [_bottom addSubview:_reply];
    _locked = [(_classic ? ExteriaStoryClassicButton(nil) : [UIButton buttonWithType:UIButtonTypeCustom]) retain];
    [_locked setImage:ExteriaSymbolImage(ExteriaSymbolLock, 15, [UIColor colorWithWhite:1 alpha:0.55]) forState:UIControlStateNormal];
    [_locked setTitle:NSLocalizedString(@"story.locked", nil) forState:UIControlStateNormal];
    [_locked setTitleColor:[UIColor colorWithWhite:1 alpha:0.6] forState:UIControlStateNormal];
    _locked.titleLabel.font = ExteriaFontRegular(15);
    _locked.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    _locked.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
    _locked.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
    if (!_classic) {
        _locked.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
        _locked.layer.cornerRadius = 18;
        _locked.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
        _locked.layer.borderWidth = 1;
    }
    _locked.hidden = YES;
    [_locked addTarget:self action:@selector(lockedTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bottom addSubview:_locked];
    _heart = [(_classic ? ExteriaStoryClassicButton(nil) : [UIButton buttonWithType:UIButtonTypeCustom]) retain];
    [_heart addTarget:self action:@selector(heartTapped) forControlEvents:UIControlEventTouchUpInside];
    _heart.accessibilityLabel = NSLocalizedString(@"story.like", nil);
    /* the heart is a button of its own at the right of the pill */
    _heart.contentMode = UIViewContentModeCenter;
    [_bottom addSubview:_heart];
    _views = [ExteriaStoryLabel(14, NO) retain];
    [_bottom addSubview:_views];
    /* the track of the story: a note and "PERFORMER · TITLE" on a dark capsule over the left end of the picture, above the reply bar */
    _chip = [[UIView alloc] init];
    _chip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    _chip.layer.cornerRadius = CHIP_HEIGHT / 2;
    _chip.hidden = YES;
    _chip.userInteractionEnabled = NO;
    _chipIcon = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolMusic, 14, [UIColor whiteColor])];
    _chipIcon.contentMode = UIViewContentModeCenter;
    [_chip addSubview:_chipIcon];
    _chipText = [ExteriaStoryLabel(12, YES) retain];
    _chipText.shadowColor = nil;
    [_chip addSubview:_chipText];
    [root addSubview:_chip];

    _toast = [ExteriaStoryLabel(14, YES) retain];
    _toast.textAlignment = ExteriaTextAlignmentCenter;
    _toast.alpha = 0;
    [root addSubview:_toast];

    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(stageTapped:)] autorelease];
    tap.delegate = self;
    [root addGestureRecognizer:tap];
    UILongPressGestureRecognizer *hold = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(stageHeld:)] autorelease];
    hold.minimumPressDuration = 0.25;
    hold.delegate = self;
    [root addGestureRecognizer:hold];
    UISwipeGestureRecognizer *swipe = [[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(stageSwiped:)] autorelease];
    swipe.direction = UISwipeGestureRecognizerDirectionDown;
    swipe.delegate = self;
    [root addGestureRecognizer:swipe];
    /* a swipe to the side turns to the next or the previous poster, as the cube of the Telegram viewer does */
    UISwipeGestureRecognizer *next = [[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(stageSwipedSideways:)] autorelease];
    next.direction = UISwipeGestureRecognizerDirectionLeft;
    next.delegate = self;
    [root addGestureRecognizer:next];
    UISwipeGestureRecognizer *previous = [[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(stageSwipedSideways:)] autorelease];
    previous.direction = UISwipeGestureRecognizerDirectionRight;
    previous.delegate = self;
    [root addGestureRecognizer:previous];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    /* the bars and the field take their own touches */
    UIView *hit = touch.view;
    return !([hit isDescendantOfView:_bottom] || [hit isDescendantOfView:_top] || (_banner && [hit isDescendantOfView:_banner]));
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self refreshHeart];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect bounds = self.view.bounds;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    /* the picture, the shades and the touch zones are the whole screen; the controls and the words stand in one
       column, clear of the notch in landscape and no wider than a page on a tablet */
    /* a tablet shows the story as the card of a phone, 9 to 16 and centered, with the controls on it, as the app of Telegram does; a story spread over the whole
       tablet screen stretched its bars across and left the picture small in the middle of them */
    BOOL card = ExteriaIsPad();
    CGRect stage = bounds;
    if (card) {
        CGFloat margin = MAX(MAX(insets.top, 0), 20);
        CGFloat stageHeight = bounds.size.height - 2 * margin;
        CGFloat stageWidth = floor(stageHeight * 9 / 16);
        if (stageWidth > bounds.size.width - 2 * margin) {
            stageWidth = bounds.size.width - 2 * margin;
            stageHeight = floor(stageWidth * 16 / 9);
        }
        stage = CGRectMake(floor((bounds.size.width - stageWidth) / 2), floor((bounds.size.height - stageHeight) / 2), stageWidth, stageHeight);
    }
    CGRect column = card ? CGRectMake(stage.origin.x, 0, stage.size.width, bounds.size.height) : ExteriaContentColumn(bounds.size, insets, EXTERIA_COLUMN_PAGE);
    CGFloat left = column.origin.x, width = column.size.width;
    CGFloat shadeLeft = card ? left : 0, shadeWidth = card ? width : bounds.size.width;
    CGFloat top = card ? stage.origin.y : MAX(insets.top, 0);
    _image.frame = stage;
    _videoView.frame = stage;
    _image.layer.cornerRadius = _videoView.layer.cornerRadius = card ? 16 : 0;
    _image.clipsToBounds = _videoView.clipsToBounds = card;
    _spinner.center = CGPointMake(CGRectGetMidX(column), bounds.size.height / 2);
    _notice.frame = CGRectMake(left + 24, bounds.size.height / 2 - 40, width - 48, 80);
    _sound.hidden = !_current.music && _current.media.kind != EXTERIA_PREVIEW_VIDEO;
    CGFloat barHeight = _classic ? CLASSIC_TOOLBAR : BAR_HEIGHT;
    if (_classic) {
        _scrim.frame = CGRectMake(shadeLeft, card ? stage.origin.y : 0, shadeWidth, CLASSIC_HEADER + (card ? 0 : top));
        _top.frame = CGRectMake(left, top, width, CLASSIC_HEADER);
        _done.frame = CGRectMake(8, 7, 72, CLASSIC_BUTTON_HEIGHT);
        _avatar.frame = CGRectMake(90, 7, 30, 30);
        _sound.frame = CGRectMake(width - 8 - 46, 7, 46, CLASSIC_BUTTON_HEIGHT);
        CGFloat right = _sound.hidden ? 8 : 62;
        _name.frame = CGRectMake(128, 4, MAX(0, width - 128 - right), 20);
        _time.frame = CGRectMake(128, 24, MAX(0, width - 128 - right), 14);
    } else {
        _scrim.frame = CGRectMake(shadeLeft, card ? stage.origin.y : 0, shadeWidth, HEADER_HEIGHT + 24 + (card ? 0 : top));
        _top.frame = CGRectMake(left, top, width, HEADER_HEIGHT);
        _avatar.frame = CGRectMake(12, 16, 36, 36);
        _menu.frame = CGRectMake(width - 8 - SIDE_BUTTON, 10, SIDE_BUTTON, SIDE_BUTTON);
        _sound.frame = CGRectMake(width - 8 - 2 * SIDE_BUTTON, 10, SIDE_BUTTON, SIDE_BUTTON);
        CGFloat headerRight = _sound.hidden ? 56 : 100;
        _name.frame = CGRectMake(58, 14, width - 58 - headerRight, 20);
        _time.frame = CGRectMake(58, 33, width - 58 - headerRight, 16);
    }
    ((CALayer *)[_scrim.layer.sublayers objectAtIndex:0]).frame = _scrim.bounds;
    [self layoutSegmentsInWidth:width];
    CGFloat bottomInset = card ? 0 : MAX(insets.bottom, 0);
    CGFloat stageBottom = CGRectGetMaxY(stage);
    CGFloat barY = stageBottom - bottomInset - barHeight - _keyboardOverlap;
    _bottom.frame = CGRectMake(left, barY, width, barHeight);
    BOOL own = _current.outgoing;
    BOOL gated = !own && [self repliesClosed];
    _reply.hidden = own || gated;
    _locked.hidden = own || !gated;
    _heart.hidden = own;
    _views.hidden = !own;
    /* the pill and the heart beside it: the heart is a button of its own at the right end of the bar */
    if (_classic) {
        _reply.frame = CGRectMake(8, 7, width - 8 - 52 - 8, CLASSIC_BUTTON_HEIGHT);
        _locked.frame = _reply.frame;
        _heart.frame = CGRectMake(width - 8 - 44, 7, 44, CLASSIC_BUTTON_HEIGHT);
        _views.frame = CGRectMake(16, 11, width - 32, 22);
    } else {
        _reply.frame = CGRectMake(12, 9, width - 12 - SIDE_BUTTON - 12, 36);
        _locked.frame = _reply.frame;
        _heart.frame = CGRectMake(width - 8 - SIDE_BUTTON, 5, SIDE_BUTTON, 44);
        _views.frame = CGRectMake(16, 16, width - 32, 22);
    }
    /* the track sits right over the bar and the caption over the track */
    NSString *musicLine = _current.musicLine;
    _chip.hidden = musicLine.length == 0;
    CGFloat chipTop = barY - 6;
    if (!_chip.hidden) {
        _chipText.text = musicLine;
        CGSize text = [_chipText sizeThatFits:CGSizeMake(width, CHIP_HEIGHT)];
        CGFloat chipWidth = MIN(width - 24, ceil(text.width) + 40);
        chipTop = barY - CHIP_HEIGHT - 8;
        _chip.frame = CGRectMake(left + 12, chipTop, chipWidth, CHIP_HEIGHT);
        _chipIcon.frame = CGRectMake(8, 0, 22, CHIP_HEIGHT);
        _chipText.frame = CGRectMake(34, 0, chipWidth - 34 - 10, CHIP_HEIGHT);
    }
    CGSize room = CGSizeMake(width - 32, 100);
    CGSize fit = [_caption sizeThatFits:room];
    CGFloat captionHeight = MIN(fit.height, 100);
    _caption.frame = CGRectMake(left + 16, chipTop - captionHeight - 8, width - 32, captionHeight);
    if (_classic) {
        _scrimBottom.frame = CGRectMake(shadeLeft, barY, shadeWidth, stageBottom - barY - _keyboardOverlap);
        _captionPlate.hidden = _caption.hidden;
        _captionPlate.frame = CGRectMake(shadeLeft, _caption.frame.origin.y - 8, shadeWidth, captionHeight + 16);
    } else {
        CGFloat shadeTop = (_caption.hidden ? barY : _caption.frame.origin.y) - 28;
        _scrimBottom.frame = CGRectMake(shadeLeft, shadeTop, shadeWidth, stageBottom - shadeTop);
    }
    ((CALayer *)[_scrimBottom.layer.sublayers objectAtIndex:0]).frame = _scrimBottom.bounds;
    _toast.frame = CGRectMake(left + 24, barY - captionHeight - 44, width - 48, 28);
    if (_banner) [self layoutBannerAtBarY:barY left:left width:width];
}

- (void)layoutSegmentsInWidth:(CGFloat)width {
    NSUInteger count = _segments.count;
    if (!count) return;
    CGFloat gap = _classic ? 4 : 3, left = 8, right = 8;
    CGFloat thickness = _classic ? CLASSIC_SEGMENT : 3;
    CGFloat y = _classic ? CLASSIC_BAR - 1 : 6;
    CGFloat each = (width - left - right - gap * (count - 1)) / count;
    for (NSUInteger i = 0; i < count; ++i) {
        UIView *segment = [_segments objectAtIndex:i];
        segment.frame = CGRectMake(left + i * (each + gap), y, each, thickness);
        UIView *fill = [_fills objectAtIndex:i];
        double done = i < _storyIndex ? 1 : (i == _storyIndex ? [self progress] : 0);
        fill.frame = CGRectMake(0, 0, each * (CGFloat)done, thickness);
    }
}

#pragma mark lifecycle

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIApplication *application = [UIApplication sharedApplication];
    _statusWasHidden = application.statusBarHidden;
    if ([application respondsToSelector:@selector(setStatusBarHidden:withAnimation:)]) [application setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
    [self takeAudioSession];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillHideNotification object:nil];
    [center addObserver:self selector:@selector(didEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!_current && !_loadingPeer && !_closed) [self openPeerAtIndex:_peerIndex];
    else [self resume];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self pause];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [center removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    [center removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    UIApplication *application = [UIApplication sharedApplication];
    if ([application respondsToSelector:@selector(setStatusBarHidden:withAnimation:)]) [application setStatusBarHidden:_statusWasHidden withAnimation:UIStatusBarAnimationFade];
    [self giveBackAudioSession];
}

- (BOOL)prefersStatusBarHidden { return YES; }

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return ExteriaAllowsOrientation(orientation); }
- (BOOL)shouldAutorotate { return YES; }
/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations { return ExteriaOrientationMask(); }
#pragma clang diagnostic pop

- (void)didEnterBackground:(NSNotification *)note {
    (void)note;
    [self pause];
}

/* the silent switch mutes the default session, and a story with sound is not a notification */
- (void)takeAudioSession {
    AVAudioSession *audio = ExteriaAudioSession();
    [_previousAudioCategory release];
    _previousAudioCategory = [audio.category copy];
    NSError *error = nil;
    if (![audio setCategory:ExteriaAudioCategoryPlayback() error:&error] || ![audio setActive:YES error:&error]) NSLog(@"exteria: story audio session: %@", error);
}

- (void)giveBackAudioSession {
    if (!_previousAudioCategory) return;
    NSError *error = nil;
    if (![ExteriaAudioSession() setCategory:_previousAudioCategory error:&error]) NSLog(@"exteria: audio session restore: %@", error);
    [_previousAudioCategory release];
    _previousAudioCategory = nil;
}

#pragma mark loading

- (ExteriaStoryPeer *)peer {
    return _peerIndex < _peers.count ? [_peers objectAtIndex:_peerIndex] : nil;
}

- (NSArray *)storiesOfCurrentPeer {
    return [_stories objectForKey:[NSNumber numberWithUnsignedInteger:_peerIndex]];
}

- (void)openPeerAtIndex:(NSUInteger)index {
    if (index >= _peers.count) { [self close]; return; }
    [_media cancelPathRequest:_pathRequest];
    _pathRequest = 0;
    ++_loadToken;
    [self stopTimer];
    [self releasePlayer];
    _peerIndex = index;
    [_current release];
    _current = nil;
    ExteriaStoryPeer *peer = [self peer];
    [self showOwner:peer];
    [self loadGateOfPeerAtIndex:index];
    NSArray *known = [self storiesOfCurrentPeer];
    if (known) { [self startPeerAtUnread:peer]; return; }
    _loadingPeer = YES;
    [_spinner startAnimating];
    NSUInteger token = _loadToken;
    ExteriaWeakReference *weak = _weak;
    [_session loadStoriesOfDialog:peer.owner completion:^(ExteriaStoryPeer *fresh, NSArray *stories, NSString *errorName) {
        ExteriaStoryViewerController *me = weak.target;
        if (!me || me->_closed || token != me->_loadToken) return;
        me->_loadingPeer = NO;
        if (errorName || !stories.count) {
            NSLog(@"exteria: stories of %lld not shown: %@", peer.owner.peerId, errorName ? errorName : @"none");
            [me->_spinner stopAnimating];
            /* a poster who has nothing to show is stepped over, a failed load is said out loud */
            if (!errorName) {
                if (index + 1 >= me->_peers.count) [me close];
                else [me openPeerAtIndex:index + 1];
                return;
            }
            [me showNotice:NSLocalizedString(@"story.failed", nil)];
            return;
        }
        [me->_stories setObject:stories forKey:[NSNumber numberWithUnsignedInteger:index]];
        if (fresh) [me->_readUpTo setObject:[NSNumber numberWithInt:fresh.maxReadId] forKey:[NSNumber numberWithUnsignedInteger:index]];
        [me startPeerAtUnread:peer];
    }];
}

- (BOOL)repliesClosed {
    return [[_gated objectForKey:[NSNumber numberWithUnsignedInteger:_peerIndex]] boolValue];
}

/* asks once per poster whether they take replies from Premium users only; until it answers the reply field is shown, and the server judges a reply */
- (void)loadGateOfPeerAtIndex:(NSUInteger)index {
    NSNumber *key = [NSNumber numberWithUnsignedInteger:index];
    ExteriaDialog *owner = [[_peers objectAtIndex:index] owner];
    if ([_gated objectForKey:key] || owner.saved) return;
    [_gated setObject:[NSNumber numberWithBool:NO] forKey:key];
    ExteriaWeakReference *weak = _weak;
    [_session loadPremiumGateOfDialog:owner completion:^(BOOL blocked) {
        ExteriaStoryViewerController *me = weak.target;
        if (!me || !blocked) return;
        [me->_gated setObject:[NSNumber numberWithBool:YES] forKey:key];
        if (me->_peerIndex == index) [me.view setNeedsLayout];
    }];
}

- (void)startPeerAtUnread:(ExteriaStoryPeer *)peer {
    NSArray *stories = [self storiesOfCurrentPeer];
    NSUInteger start = 0;
    int32_t read = [[_readUpTo objectForKey:[NSNumber numberWithUnsignedInteger:_peerIndex]] intValue];
    for (NSUInteger i = 0; i < stories.count; ++i) {
        if ([(ExteriaStory *)[stories objectAtIndex:i] storyId] > read) { start = i; break; }
        start = stories.count - 1;
    }
    /* a poster who is all seen starts again from the first story */
    if (peer.unread == 0) start = 0;
    if (_startStory != NSNotFound) {
        start = _startStory;
        _startStory = NSNotFound;
    }
    [self buildSegments:stories.count];
    [self showStoryAtIndex:start];
}

- (void)showOwner:(ExteriaStoryPeer *)peer {
    ExteriaDialog *owner = peer.owner;
    if (owner.saved) {
        _name.entities = nil;
        _name.text = NSLocalizedString(@"story.mine", nil);
    } else {
        ExteriaShowNameWithBadges(_name, owner.title, owner.peerKind == 1 ? owner.peerId : 0, owner.peerKind == 1 ? _session : nil, _media);
    }
    _time.text = @"";
    _avatar.initials = owner.saved ? @"" : owner.initials;
    _avatar.seed = owner.avatarSeed;
    [_avatar setPhoto:owner.photo cache:_avatars];
}

- (void)buildSegments:(NSUInteger)count {
    for (UIView *segment in _segments) [segment removeFromSuperview];
    [_segments removeAllObjects];
    [_fills removeAllObjects];
    UIColor *groove = _classic ? ExteriaStoryClassicPattern(NO) : nil;
    UIColor *bead = _classic ? ExteriaStoryClassicPattern(YES) : nil;
    for (NSUInteger i = 0; i < count; ++i) {
        UIView *segment = [[[UIView alloc] init] autorelease];
        segment.backgroundColor = _classic ? groove : [UIColor colorWithWhite:1 alpha:0.35];
        segment.layer.cornerRadius = _classic ? CLASSIC_SEGMENT / 2 : 1.5;
        segment.layer.masksToBounds = YES;
        UIView *fill = [[[UIView alloc] init] autorelease];
        fill.backgroundColor = _classic ? bead : [UIColor whiteColor];
        [segment addSubview:fill];
        [_top addSubview:segment];
        [_segments addObject:segment];
        [_fills addObject:fill];
    }
    [self.view setNeedsLayout];
}

- (void)showNotice:(NSString *)text {
    _notice.text = text;
    _notice.hidden = text.length == 0;
}

- (void)showStoryAtIndex:(NSUInteger)index {
    NSArray *stories = [self storiesOfCurrentPeer];
    if (index >= stories.count) { [self stepToNextPeer]; return; }
    ++_loadToken;
    [self stopTimer];
    [self releasePlayer];
    [_media cancelPathRequest:_pathRequest];
    _pathRequest = 0;
    _storyIndex = index;
    [_current release];
    _current = [[stories objectAtIndex:index] retain];
    _elapsed = 0;
    _failed = NO;
    _videoStarted = NO;
    _duration = PHOTO_SECONDS;
    _image.image = nil;
    _image.hidden = NO;
    _videoView.hidden = YES;
    [self showNotice:nil];
    _time.text = ExteriaListTimeText(_current.date);
    _caption.text = _current.caption;
    _caption.hidden = _current.caption.length == 0;
    _views.text = _current.views ? [NSString stringWithFormat:NSLocalizedString(@"story.views", nil), (int)_current.views] : NSLocalizedString(@"story.noviews", nil);
    [self refreshHeart];
    [self markSeen];
    [self.view setNeedsLayout];
    if (_current.media.kind == EXTERIA_PREVIEW_VIDEO) [self loadVideo];
    else [self loadPhoto];
    [self loadMusic];
    [self prefetchNext];
}

- (void)markSeen {
    int32_t storyId = _current.storyId;
    NSNumber *key = [NSNumber numberWithUnsignedInteger:_peerIndex];
    if (_current.outgoing || storyId <= [[_readUpTo objectForKey:key] intValue]) return;
    [_readUpTo setObject:[NSNumber numberWithInt:storyId] forKey:key];
    [_session markStoriesSeenOfDialog:[self peer].owner upTo:storyId];
}

- (void)loadPhoto {
    ExteriaRemoteFile *file = _current.media.file;
    if (!file) { [self showFailure]; return; }
    UIImage *cached = [_media cachedImageForFile:file maxSide:IMAGE_SIDE];
    if (cached) { _image.image = cached; [self startTimer]; return; }
    /* the small picture of the same story, if there is one, fills the screen until the big one decodes */
    [_spinner startAnimating];
    NSUInteger token = _loadToken;
    int32_t storyId = _current.storyId;
    ExteriaWeakReference *weak = _weak;
    [_media loadImageForFile:file maxSide:IMAGE_SIDE completion:^(UIImage *image) {
        ExteriaStoryViewerController *me = weak.target;
        if (!me || me->_closed || token != me->_loadToken || me->_current.storyId != storyId) return;
        [me->_spinner stopAnimating];
        if (!image) { [me showFailure]; return; }
        me->_image.image = image;
        [me startTimer];
    }];
}

- (void)loadVideo {
    ExteriaMedia *media = _current.media;
    ExteriaRemoteFile *preview = media.previewFile;
    if (preview) {
        UIImage *cached = [_media cachedImageForFile:preview maxSide:IMAGE_SIDE];
        if (cached) _image.image = cached;
        else {
            int32_t storyId = _current.storyId;
            ExteriaWeakReference *weak = _weak;
            [_media loadImageForFile:preview maxSide:IMAGE_SIDE completion:^(UIImage *image) {
                ExteriaStoryViewerController *me = weak.target;
                if (me && !me->_closed && me->_current.storyId == storyId && !me->_videoStarted && image) me->_image.image = image;
            }];
        }
    }
    ExteriaRemoteFile *file = media.file;
    if (!file) { [self showFailure]; return; }
    [_spinner startAnimating];
    NSUInteger token = _loadToken;
    int32_t storyId = _current.storyId;
    ExteriaWeakReference *weak = _weak;
    _pathRequest = [_media loadPathForFile:file size:media.size progress:^(float fraction) {
        (void)fraction;
    } completion:^(NSString *path) {
        ExteriaStoryViewerController *me = weak.target;
        if (!me || me->_closed || token != me->_loadToken || me->_current.storyId != storyId) return;
        me->_pathRequest = 0;
        [me->_spinner stopAnimating];
        if (!path) { [me showFailure]; return; }
        [me playFileAtPath:path];
    }];
}

- (void)playFileAtPath:(NSString *)path {
    NSString *slot = [NSString stringWithFormat:@"story-%p", self];
    _videoURL = [ExteriaPlayableLink(path, @"mp4", slot) retain];
    if (!_videoURL) { [self showFailure]; return; }
    _item = [[AVPlayerItem playerItemWithURL:_videoURL] retain];
    _player = [[AVPlayer playerWithPlayerItem:_item] retain];
    ((AVPlayerLayer *)_videoView.layer).player = _player;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    _videoStarted = NO;
    /* the timer waits for the item to be ready, then starts the player and follows it */
    [self startTimer];
}

- (void)videoEnded:(NSNotification *)note {
    (void)note;
    if (!_closed) [self showStoryAtIndex:_storyIndex + 1];
}

- (void)releasePlayer {
    [self releaseMusic];
    if (_item) [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    [_player pause];
    ((AVPlayerLayer *)_videoView.layer).player = nil;
    [_player release];
    _player = nil;
    [_item release];
    _item = nil;
    if (_videoURL) [[NSFileManager defaultManager] removeItemAtPath:_videoURL.path.stringByDeletingLastPathComponent error:NULL];
    [_videoURL release];
    _videoURL = nil;
}

/* a story that cannot be shown is said so and left after the usual time, so the strip never gets stuck on it */
- (void)showFailure {
    _failed = YES;
    [_spinner stopAnimating];
    [self showNotice:NSLocalizedString(_current.media.kind == EXTERIA_PREVIEW_VIDEO ? @"story.video.failed" : @"story.failed", nil)];
    [self startTimer];
}

- (void)prefetchNext {
    NSArray *stories = [self storiesOfCurrentPeer];
    if (_storyIndex + 1 >= stories.count) return;
    ExteriaStory *next = [stories objectAtIndex:_storyIndex + 1];
    if (next.media.kind == EXTERIA_PREVIEW_PHOTO) {
        ExteriaRemoteFile *file = next.media.file;
        if (file && ![_media cachedImageForFile:file maxSide:IMAGE_SIDE]) [_media loadImageForFile:file maxSide:IMAGE_SIDE completion:^(UIImage *image) { (void)image; }];
    }
}

/* the poster after this one, turned to like a cube; the last poster closes the viewer */
- (void)stepToNextPeer {
    if (_peerIndex + 1 >= _peers.count) { [self close]; return; }
    [self turnToPeer:_peerIndex + 1 forward:YES];
}

/* the face of the cube, hinged on the edge it shares with its neighbour: it swings away from the viewer around the pivot x (0 is the middle of the
   screen) with the perspective in front */
static CATransform3D ExteriaStoryCubeFace(CGFloat pivot, CGFloat angle) {
    CATransform3D transform = CATransform3DIdentity;
    transform.m34 = (CGFloat)(-1.0 / TURN_DEPTH);
    transform = CATransform3DTranslate(transform, pivot, 0, 0);
    transform = CATransform3DRotate(transform, angle, 0, 1, 0);
    return CATransform3DTranslate(transform, -pivot, 0, 0);
}

/* the picture of this poster swings away around the edge toward the next one, then the next one swings in around
   the edge it shares */
- (void)turnToPeer:(NSUInteger)index forward:(BOOL)forward {
    if (_turning || index >= _peers.count) return;
    if (ExteriaReduceMotionEnabled()) { [self openPeerAtIndex:index]; return; }
    _turning = YES;
    UIView *stage = self.view;
    CGFloat half = stage.bounds.size.width / 2;
    CGFloat sign = forward ? 1 : -1;
    ExteriaWeakReference *weak = _weak;
    [UIView animateWithDuration:TURN_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        stage.layer.transform = ExteriaStoryCubeFace(sign * half, (CGFloat)(-sign * TURN_ANGLE));
    } completion:^(BOOL finished) {
        (void)finished;
        ExteriaStoryViewerController *me = weak.target;
        if (!me || me->_closed) { stage.layer.transform = CATransform3DIdentity; if (me) me->_turning = NO; return; }
        [me openPeerAtIndex:index];
        stage.layer.transform = ExteriaStoryCubeFace(-sign * half, (CGFloat)(sign * TURN_ANGLE));
        [UIView animateWithDuration:TURN_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            stage.layer.transform = CATransform3DIdentity;
        } completion:^(BOOL done) {
            (void)done;
            stage.layer.transform = CATransform3DIdentity;
            /* the viewer may have been released while the second half ran */
            ExteriaStoryViewerController *again = weak.target;
            if (again) again->_turning = NO;
        }];
    }];
}

#pragma mark sound

- (void)refreshSoundButton {
    [_sound setImage:ExteriaSymbolImage(_muted ? ExteriaSymbolSpeakerSlash : ExteriaSymbolSpeaker, _classic ? 18 : 24, [UIColor whiteColor]) forState:UIControlStateNormal];
    _sound.accessibilityLabel = NSLocalizedString(_muted ? @"story.unmute" : @"story.mute", nil);
}

/* the video's sound is switched off through an audio mix with no volume, which the systems back to ios 5 know; the track's own player
   has a volume */
- (void)applyMute {
    [_music setVolume:_muted ? 0.0f : 1.0f];
    if (!_item) return;
    if (!_muted) {
        _item.audioMix = nil;
        return;
    }
    AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
    NSMutableArray *parameters = [NSMutableArray array];
    for (AVAssetTrack *track in [_item.asset tracksWithMediaType:AVMediaTypeAudio]) {
        AVMutableAudioMixInputParameters *silent = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
        [silent setVolume:0 atTime:kCMTimeZero];
        [parameters addObject:silent];
    }
    mix.inputParameters = parameters;
    _item.audioMix = mix;
}

- (void)soundTapped {
    _muted = !_muted;
    [self refreshSoundButton];
    [self applyMute];
}

/* the track plays while the story runs: not while it is held, not while a reply is typed, not after the viewer left */
- (void)syncMusic {
    if (!_music) return;
    if (!_paused && !_editing && !_closed) [_music play];
    else [_music pause];
}

- (void)loadMusic {
    ExteriaMedia *music = _current.music;
    ExteriaRemoteFile *file = music.file;
    if (!file) return;
    NSUInteger token = _loadToken;
    int32_t storyId = _current.storyId;
    ExteriaWeakReference *weak = _weak;
    _musicRequest = [_media loadPathForFile:file size:music.size progress:^(float fraction) { (void)fraction; } completion:^(NSString *path) {
        ExteriaStoryViewerController *me = weak.target;
        if (!me || me->_closed || token != me->_loadToken || me->_current.storyId != storyId) return;
        me->_musicRequest = 0;
        if (!path) {
            NSLog(@"exteria: the music of story %d could not be loaded", (int)storyId);
            return;
        }
        NSError *error = nil;
        Class playerClass = NSClassFromString(@"AVAudioPlayer");
        me->_music = playerClass ? [[playerClass alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error] : nil;
        if (!me->_music) {
            NSLog(@"exteria: the music of story %d cannot be played: %@", (int)storyId, error);
            return;
        }
        [me->_music prepareToPlay];
        [me applyMute];
        [me syncMusic];
    }];
}

- (void)releaseMusic {
    [_media cancelPathRequest:_musicRequest];
    _musicRequest = 0;
    [_music stop];
    [_music release];
    _music = nil;
}

- (void)menuTapped {
    ExteriaSymbol symbols[1] = {ExteriaSymbolClose};
    ExteriaPopupMenu *menu = [[[ExteriaPopupMenu alloc] initWithTitles:[NSArray arrayWithObject:NSLocalizedString(@"story.close", nil)] symbols:symbols
                                                                 handler:^(NSUInteger index) { (void)index; [self close]; }] autorelease];
    CGPoint anchor = [_menu.superview convertPoint:CGPointMake(CGRectGetMaxX(_menu.frame) - 6, CGRectGetMaxY(_menu.frame) - 8) toView:self.view];
    [menu showInView:self.view anchor:anchor];
}

#pragma mark progress

- (double)progress {
    if (!_current || _duration <= 0) return 0;
    double value = _elapsed / _duration;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
}

- (void)startTimer {
    if (_timer || _closed) return;
    _tickTarget = [[ExteriaStoryTickTarget alloc] initWithReference:_weak];
    _timer = [NSTimer scheduledTimerWithTimeInterval:TICK target:_tickTarget selector:@selector(fire:) userInfo:nil repeats:YES];
}

- (void)stopTimer {
    [_timer invalidate];
    _timer = nil;
    [_tickTarget release];
    _tickTarget = nil;
}

- (void)tick {
    if (_closed || !_current) return;
    if (_player) {
        if (_item.status == AVPlayerItemStatusFailed) {
            NSLog(@"exteria: story video failed: %@", _item.error);
            [self releasePlayer];
            [self showFailure];
            return;
        }
        if (_item.status != AVPlayerItemStatusReadyToPlay) return;
        if (!_videoStarted) {
            _videoStarted = YES;
            double seconds = CMTimeGetSeconds(_item.duration);
            _duration = seconds > 0 && seconds < 600 ? seconds : PHOTO_SECONDS;
            _videoView.hidden = NO;
            _image.hidden = YES;
            [self applyMute];
            if (!_paused) [_player play];
        }
        double now = CMTimeGetSeconds(_player.currentTime);
        _elapsed = now > 0 ? now : 0;
    } else if (!_paused && !_editing) {
        _elapsed += TICK;
        if (_elapsed >= _duration) { [self showStoryAtIndex:_storyIndex + 1]; return; }
    }
    [self updateProgressBar];
}

/* only the fill of the running segment moves, so a tick never lays the whole screen out again */
- (void)updateProgressBar {
    if (_storyIndex >= _fills.count) return;
    UIView *segment = [_segments objectAtIndex:_storyIndex];
    UIView *fill = [_fills objectAtIndex:_storyIndex];
    fill.frame = CGRectMake(0, 0, segment.bounds.size.width * (CGFloat)[self progress], segment.bounds.size.height);
}

- (void)pause {
    _paused = YES;
    [_player pause];
    [self syncMusic];
}

- (void)resume {
    _paused = NO;
    if (_videoStarted && !_editing) [_player play];
    [self syncMusic];
}

#pragma mark gestures

- (void)stageTapped:(UITapGestureRecognizer *)tap {
    if (_turning) return;
    if (_editing) { [_reply resignFirstResponder]; return; }
    CGFloat x = [tap locationInView:self.view].x;
    CGFloat width = self.view.bounds.size.width;
    if (x < width * TAP_ZONE) {
        /* back to the start of this story, or to the one before when it has just begun */
        if (_elapsed > 1 || _storyIndex == 0) {
            if (_storyIndex == 0 && _peerIndex > 0 && _elapsed <= 1) [self turnToPeer:_peerIndex - 1 forward:NO];
            else [self showStoryAtIndex:_storyIndex];
        } else {
            [self showStoryAtIndex:_storyIndex - 1];
        }
    } else {
        [self showStoryAtIndex:_storyIndex + 1];
    }
}

/* a held story shows only its picture: the bars, the caption and the track fade out until the finger lifts */
- (void)setChromeShown:(BOOL)shown {
    CGFloat alpha = shown ? 1 : 0;
    NSMutableArray *chrome = [NSMutableArray arrayWithObjects:_top, _scrim, _scrimBottom, _bottom, _caption, _chip, nil];
    if (_captionPlate) [chrome addObject:_captionPlate];
    [UIView animateWithDuration:0.15 animations:^{
        for (UIView *view in chrome) view.alpha = alpha;
    }];
}

- (void)stageHeld:(UILongPressGestureRecognizer *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) {
        [self pause];
        [self setChromeShown:NO];
    } else if (hold.state == UIGestureRecognizerStateEnded || hold.state == UIGestureRecognizerStateCancelled) {
        [self setChromeShown:YES];
        [self resume];
    }
}

- (void)stageSwipedSideways:(UISwipeGestureRecognizer *)swipe {
    if (_editing || _turning || _closed) return;
    BOOL forward = swipe.direction == UISwipeGestureRecognizerDirectionLeft;
    if (forward) [self stepToNextPeer];
    else if (_peerIndex > 0) [self turnToPeer:_peerIndex - 1 forward:NO];
}

- (void)stageSwiped:(UISwipeGestureRecognizer *)swipe {
    (void)swipe;
    [self close];
}

- (void)closeTapped {
    [self close];
}

- (void)close {
    if (_closed) return;
    _closed = YES;
    [self stopTimer];
    [self releasePlayer];
    [_media cancelPathRequest:_pathRequest];
    _pathRequest = 0;
    [_reply resignFirstResponder];
    void (^handler)(void) = [_closeHandler retain];
    void (^finished)(void) = ^{
        if (handler) { handler(); [handler release]; }
    };
    if ([self respondsToSelector:@selector(dismissViewControllerAnimated:completion:)]) {
        [self dismissViewControllerAnimated:YES completion:finished];
    } else {
        [self dismissModalViewControllerAnimated:YES];
        finished();
    }
}

#pragma mark reaction and reply

- (void)refreshHeart {
    NSNumber *override = _current ? [_reacted objectForKey:[NSNumber numberWithInt:_current.storyId]] : nil;
    BOOL liked = override ? override.boolValue : _current.reaction != nil;
    if (_classic) {
        /* a liked story turns the plate red, as the old badges did; the glyph stays white on either */
        ExteriaClassicGloss plate = liked ? ExteriaClassicGlossRed : ExteriaClassicGlossSlate;
        [_heart setBackgroundImage:ExteriaClassicGlossButtonImage(plate, NO) forState:UIControlStateNormal];
        [_heart setBackgroundImage:ExteriaClassicGlossButtonImage(plate, YES) forState:UIControlStateHighlighted];
        [_heart setImage:ExteriaSymbolImage(liked ? ExteriaSymbolHeart : ExteriaSymbolHeartOutline, 18, [UIColor whiteColor]) forState:UIControlStateNormal];
        return;
    }
    [_heart setImage:liked ? ExteriaSymbolImage(ExteriaSymbolHeart, STORY_HEART_SIDE, [UIColor colorWithRed:230.0 / 255 green:62.0 / 255 blue:72.0 / 255 alpha:1])
                       : ExteriaSymbolImage(ExteriaSymbolHeartOutline, STORY_HEART_SIDE, [UIColor whiteColor])
          forState:UIControlStateNormal];
}

#pragma mark premium only replies

- (void)hideBanner {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideBanner) object:nil];
    UIView *banner = _banner;
    _banner = nil;
    [UIView animateWithDuration:0.2 animations:^{ banner.alpha = 0; } completion:^(BOOL finished) {
        (void)finished;
        [banner removeFromSuperview];
        [banner release];
    }];
}

- (void)premiumDetails {
    [self hideBanner];
    ExteriaOpenPremiumPage();
}

/* the line over the reply bar: a star, what is not allowed with the poster's name in bold, and the button that explains it */
- (void)lockedTapped {
    if (_banner) return;
    NSString *name = [self peer].owner.title;
    UIView *banner = [[UIView alloc] init];
    banner.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.94];
    banner.layer.cornerRadius = _classic ? 10 : 20;
    UIImageView *star = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolStar, 26, [UIColor whiteColor])] autorelease];
    star.contentMode = UIViewContentModeCenter;
    star.tag = 1;
    [banner addSubview:star];
    ExteriaEmojiLabel *text = [[[ExteriaEmojiLabel alloc] init] autorelease];
    text.tag = 2;
    text.font = ExteriaFontRegular(15);
    text.textColor = [UIColor whiteColor];
    text.numberOfLines = 3;
    NSString *line = [NSString stringWithFormat:NSLocalizedString(@"story.premium", nil), name];
    text.text = line;
    NSMutableArray *bold = [NSMutableArray array];
    NSRange nameRange = [line rangeOfString:name];
    if (nameRange.location != NSNotFound) [bold addObject:[[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleBold range:nameRange url:nil] autorelease]];
    NSRange premiumRange = [line rangeOfString:@"Premium" options:NSBackwardsSearch];
    if (premiumRange.location != NSNotFound) [bold addObject:[[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleBold range:premiumRange url:nil] autorelease]];
    text.entities = bold;
    [banner addSubview:text];
    UIButton *more = [UIButton buttonWithType:UIButtonTypeCustom];
    more.tag = 3;
    more.titleLabel.font = ExteriaFontMedium(15);
    [more setTitle:NSLocalizedString(@"story.more", nil) forState:UIControlStateNormal];
    [more setTitleColor:[UIColor colorWithRed:0.45 green:0.72 blue:0.95 alpha:1] forState:UIControlStateNormal];
    [more addTarget:self action:@selector(premiumDetails) forControlEvents:UIControlEventTouchUpInside];
    [banner addSubview:more];
    banner.alpha = 0;
    [self.view insertSubview:banner belowSubview:_toast];
    _banner = banner;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [UIView animateWithDuration:0.2 animations:^{ banner.alpha = 1; }];
    [self performSelector:@selector(hideBanner) withObject:nil afterDelay:6];
}

- (void)layoutBannerAtBarY:(CGFloat)barY left:(CGFloat)left width:(CGFloat)width {
    ExteriaEmojiLabel *text = (ExteriaEmojiLabel *)[_banner viewWithTag:2];
    UIButton *more = (UIButton *)[_banner viewWithTag:3];
    CGFloat side = 12, star = 52, moreWidth = 96;
    CGFloat boxWidth = width - 2 * side;
    CGFloat textWidth = boxWidth - star - moreWidth - 8;
    CGFloat textHeight = ceil([text sizeThatFits:CGSizeMake(textWidth, 200)].height);
    CGFloat height = MAX(56, textHeight + 24);
    _banner.frame = CGRectMake(left + side, barY - 8 - height, boxWidth, height);
    [_banner viewWithTag:1].frame = CGRectMake(8, 0, 40, height);
    text.frame = CGRectMake(star, (height - textHeight) / 2, textWidth, textHeight);
    more.frame = CGRectMake(boxWidth - moreWidth - 4, 0, moreWidth, height);
}

- (void)toast:(NSString *)text {
    _toast.text = text;
    _toast.alpha = 1;
    [UIView animateWithDuration:0.3 delay:1.5 options:0 animations:^{ _toast.alpha = 0; } completion:nil];
}

/* the heart of the catalog: the server spells it with a variation selector, so the spelling comes from its own list */
- (void)findHeartThen:(void (^)(ExteriaReaction *heart))then {
    if (_heartReaction) { then(_heartReaction); return; }
    ExteriaWeakReference *weak = _weak;
    ExteriaDialog *owner = [self peer].owner;
    void (^done)(ExteriaReaction *) = [then copy];
    [_session loadAvailableReactionsForDialog:owner premium:NO completion:^(NSArray *items, NSString *errorName) {
        ExteriaStoryViewerController *me = weak.target;
        ExteriaReaction *found = nil;
        for (ExteriaReaction *reaction in items) {
            if ([reaction.emoji hasPrefix:@"❤"]) { found = reaction; break; }
        }
        if (found && me) me->_heartReaction = [found retain];
        done(found);
        [done release];
    }];
}

- (void)heartTapped {
    if (!_current || _current.outgoing) return;
    int32_t storyId = _current.storyId;
    NSNumber *key = [NSNumber numberWithInt:storyId];
    NSNumber *override = [_reacted objectForKey:key];
    BOOL wasLiked = override ? override.boolValue : _current.reaction != nil;
    BOOL liked = !wasLiked;
    [_reacted setObject:[NSNumber numberWithBool:liked] forKey:key];
    [self refreshHeart];
    ExteriaDialog *owner = [self peer].owner;
    ExteriaWeakReference *weak = _weak;
    void (^revert)(NSString *) = ^(NSString *errorName) {
        ExteriaStoryViewerController *me = weak.target;
        NSLog(@"exteria: story reaction failed: %@", errorName);
        if (!me) return;
        [me->_reacted setObject:[NSNumber numberWithBool:wasLiked] forKey:key];
        [me refreshHeart];
        [me toast:NSLocalizedString(@"story.react.failed", nil)];
    };
    void (^revertCopy)(NSString *) = [revert copy];
    if (!liked) {
        [_session reactToStory:storyId ofDialog:owner reaction:nil completion:^(NSString *errorName) {
            if (errorName) revertCopy(errorName);
            [revertCopy release];
        }];
        return;
    }
    [self findHeartThen:^(ExteriaReaction *heart) {
        if (!heart) { revertCopy(@"NO_HEART"); [revertCopy release]; return; }
        [_session reactToStory:storyId ofDialog:owner reaction:heart completion:^(NSString *errorName) {
            if (errorName) revertCopy(errorName);
            [revertCopy release];
        }];
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    NSString *text = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length || !_current) { [field resignFirstResponder]; return NO; }
    field.text = @"";
    [field resignFirstResponder];
    long long randomId = ((long long)arc4random() << 32) | arc4random();
    ExteriaWeakReference *weak = _weak;
    [_session replyToStory:_current.storyId ofDialog:[self peer].owner text:text randomId:randomId completion:^(NSString *errorName) {
        ExteriaStoryViewerController *me = weak.target;
        if (errorName) NSLog(@"exteria: story reply failed: %@", errorName);
        [me toast:NSLocalizedString(errorName ? @"story.reply.failed" : @"story.reply.sent", nil)];
    }];
    return NO;
}

- (void)textFieldDidBeginEditing:(UITextField *)field {
    (void)field;
    _editing = YES;
    [_player pause];
    [self syncMusic];
}

- (void)textFieldDidEndEditing:(UITextField *)field {
    (void)field;
    _editing = NO;
    if (!_paused && _videoStarted) [_player play];
    [self syncMusic];
}

- (void)keyboardWillChange:(NSNotification *)note {
    CGRect frame = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    frame = [self.view convertRect:[self.view.window convertRect:frame fromWindow:nil] fromView:nil];
    BOOL showing = [note.name isEqualToString:UIKeyboardWillShowNotification];
    _keyboardOverlap = showing ? MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(frame)) : 0;
    NSTimeInterval duration = [[note.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }];
}

@end
