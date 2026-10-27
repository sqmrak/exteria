#import "exteria_call_controller.h"

#import <AudioToolbox/AudioToolbox.h>

#import "exteria_app_sounds.h"
#import <QuartzCore/QuartzCore.h>

#import "exteria_audio_session.h"
#import "exteria_avatar_view.h"
#import "exteria_call_tones.h"
#import "exteria_call_video.h"
#import "exteria_emoji_label.h"
#import "exteria_lite_mode.h"
#import "exteria_person.h"
#import "exteria_notify_store.h"
#import "exteria_platform.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#include "exteria_call_screen.h"

#define BUTTON_SIZE 52.0
#define ANSWER_SIZE 64.0
#define ENDED_HOLD_SECONDS 1.4
/* the tone of an ended call plays to its end before the screen goes */
#define TONE_TAIL_SECONDS 0.2
#define VIBRATE_EVERY_TICKS 3
#define MESH_WIDTH 16
#define MESH_HEIGHT 24
#define MOOD_FADE_SECONDS 0.5
#define CARD_FADE_SECONDS 0.2

static UIButton *CallButton(ExteriaSymbol symbol, UIColor *fill, CGFloat size, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, size, size);
    button.backgroundColor = fill;
    button.layer.cornerRadius = size / 2;
    [button setImage:ExteriaSymbolImage(symbol, 26, [UIColor whiteColor]) forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

/* a button resets its image view's frame whenever it lays out, which a rotated transform on that view turns into
   wrong bounds on ios 6, so the handset is turned in the picture itself */
static UIImage *CallRotatedImage(UIImage *image, CGFloat angle) {
    CGFloat side = ceil(hypot(image.size.width, image.size.height));
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, image.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(context, side / 2, side / 2);
    CGContextRotateCTM(context, angle);
    [image drawInRect:CGRectMake(-image.size.width / 2, -image.size.height / 2, image.size.width, image.size.height)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

static UILabel *CallLabel(CGFloat size, BOOL bold, CGFloat alpha) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [UIColor colorWithWhite:1 alpha:alpha];
    label.textAlignment = ExteriaTextAlignmentCenter;
    label.font = bold ? ExteriaFontSemibold(size) : ExteriaFontRegular(size);
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumFontSize = size * 0.7;
    return label;
}

/* the peer's name and the key emoji are drawn from the app's own pictures: the system font lacks some of them on old iOS */
static ExteriaEmojiLabel *CallEmojiLabel(CGFloat size, BOOL bold) {
    ExteriaEmojiLabel *label = [[[ExteriaEmojiLabel alloc] init] autorelease];
    label.textColor = [UIColor whiteColor];
    label.textAlignment = ExteriaTextAlignmentCenter;
    label.font = bold ? ExteriaFontSemibold(size) : ExteriaFontRegular(size);
    label.userInteractionEnabled = NO;
    return label;
}

static CGRect CallRect(exteria_rect r, CGFloat dx) {
    return CGRectMake((CGFloat)r.x + dx, (CGFloat)r.y, (CGFloat)r.width, (CGFloat)r.height);
}

/* the mesh is 16 by 24 pixels and the layer stretches it with linear filtering, which is what blends the four colors smoothly */
static CGImageRef CreateMeshImage(exteria_call_mood mood, BOOL dark) {
    uint32_t colors[4];
    uint8_t pixels[MESH_WIDTH * MESH_HEIGHT * 4];
    if (exteria_call_mood_colors(mood, dark, colors) != EXTERIA_OK) return NULL;
    if (exteria_call_mesh_fill(pixels, sizeof(pixels), MESH_WIDTH, MESH_HEIGHT, colors) != EXTERIA_OK) return NULL;
    CFDataRef data = CFDataCreate(NULL, pixels, (CFIndex)sizeof(pixels));
    CGDataProviderRef provider = data ? CGDataProviderCreateWithCFData(data) : NULL;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = provider && space ? CGImageCreate(MESH_WIDTH, MESH_HEIGHT, 8, 32, MESH_WIDTH * 4, space,
                                                          (CGBitmapInfo)kCGImageAlphaNoneSkipLast, provider, NULL, false, kCGRenderingIntentDefault) : NULL;
    if (space) CGColorSpaceRelease(space);
    if (provider) CGDataProviderRelease(provider);
    if (data) CFRelease(data);
    return image;
}

@interface ExteriaCallController () {
    ExteriaSession *_session;
    ExteriaCall *_call;
    UIView *_backdrop;
    ExteriaAvatarView *_avatarView;
    ExteriaEmojiLabel *_name;
    UILabel *_status;
    UIButton *_emojiPill;
    NSMutableArray *_emojiLabels;
    UIView *_card;
    UILabel *_cardTitle;
    ExteriaEmojiLabel *_cardText;
    UIImageView *_remoteView;
    CAGradientLayer *_videoShade;
    UIView *_previewHost;
    ExteriaCallVideo *_video;
    UIButton *_camera;
    UIButton *_minimize;
    UILabel *_cameraCaption;
    UIButton *_mute;
    UIButton *_speaker;
    UIButton *_end;
    UIButton *_accept;
    UIView *_acceptRing;
    UILabel *_muteCaption;
    UILabel *_speakerCaption;
    UILabel *_endCaption;
    UILabel *_acceptCaption;
    NSTimer *_tick;
    NSUInteger _ticks;
    int _mood;
    BOOL _speakerOn;
    BOOL _cardShown;
    BOOL _audioHeld;
    BOOL _closing;
    BOOL _appeared;
    BOOL _visible;
    BOOL _dismissing;
    BOOL _finished;
    /* the tone that plays now, or -1: a change of the call that keeps its phase must not start it again */
    int _tone;
    void (^_onFinish)(void);
    void (^_onMinimize)(void);
}
@end

@implementation ExteriaCallController

@synthesize photo = _photo;
@synthesize avatars = _avatars;
@synthesize onFinish = _onFinish;
@synthesize onMinimize = _onMinimize;

- (long long)callId {
    return _call.callId;
}

- (BOOL)finishing {
    return _closing || _dismissing;
}

- (id)initWithSession:(ExteriaSession *)session {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _session = session;
    _mood = -1;
    _tone = -1;
    return self;
}

- (void)dealloc {
    [_tick invalidate];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    ExteriaCallToneStop();
    [self detachVideo];
    [_call release];
    [_photo release];
    [_avatars release];
    [_onFinish release];
    [_onMinimize release];
    [self releaseViews];
    [super dealloc];
}

- (void)releaseViews {
    [_backdrop release]; _backdrop = nil;
    [_remoteView release]; _remoteView = nil;
    [_videoShade release]; _videoShade = nil;
    [_previewHost release]; _previewHost = nil;
    [_camera release]; _camera = nil;
    [_minimize release]; _minimize = nil;
    [_cameraCaption release]; _cameraCaption = nil;
    [_name release]; _name = nil;
    [_status release]; _status = nil;
    [_emojiPill release]; _emojiPill = nil;
    [_emojiLabels release]; _emojiLabels = nil;
    [_card release]; _card = nil;
    [_cardTitle release]; _cardTitle = nil;
    [_cardText release]; _cardText = nil;
    [_mute release]; _mute = nil;
    [_speaker release]; _speaker = nil;
    [_end release]; _end = nil;
    [_accept release]; _accept = nil;
    [_acceptRing release]; _acceptRing = nil;
    [_muteCaption release]; _muteCaption = nil;
    [_speakerCaption release]; _speakerCaption = nil;
    [_endCaption release]; _endCaption = nil;
    [_acceptCaption release]; _acceptCaption = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return ExteriaAllowsOrientation(orientation); }
- (BOOL)shouldAutorotate { return YES; }
/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations { return ExteriaOrientationMask(); }
#pragma clang diagnostic pop
/* light status bar text over the dark mesh on ios 7 and later; the method is absent from the ios 6 sdk, the value is UIStatusBarStyleLightContent */
- (UIStatusBarStyle)preferredStatusBarStyle { return (UIStatusBarStyle)1; }

- (void)loadView {
    UIView *root = [[[UIView alloc] init] autorelease];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    root.backgroundColor = [UIColor blackColor];
    _backdrop = [[UIView alloc] init];
    _backdrop.userInteractionEnabled = NO;
    [root addSubview:_backdrop];

    /* the other side's picture fills the screen under the texts, with a shade at the top and the bottom that keeps them readable */
    _remoteView = [[UIImageView alloc] init];
    _remoteView.contentMode = UIViewContentModeScaleAspectFill;
    _remoteView.clipsToBounds = YES;
    _remoteView.backgroundColor = [UIColor blackColor];
    _remoteView.hidden = YES;
    _remoteView.userInteractionEnabled = NO;
    [root addSubview:_remoteView];
    _videoShade = [[CAGradientLayer layer] retain];
    _videoShade.colors = [NSArray arrayWithObjects:(id)[UIColor colorWithWhite:0 alpha:0.45].CGColor, (id)[UIColor colorWithWhite:0 alpha:0].CGColor,
                                                    (id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.55].CGColor, nil];
    _videoShade.locations = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:0.25f], [NSNumber numberWithFloat:0.65f],
                                                       [NSNumber numberWithFloat:1], nil];
    _videoShade.hidden = YES;
    [root.layer addSublayer:_videoShade];

    _avatarView = [[[ExteriaAvatarView alloc] init] autorelease];
    _avatarView.circular = YES;
    [root addSubview:_avatarView];
    _name = [CallEmojiLabel(28, YES) retain];
    [root addSubview:_name];
    _status = [CallLabel(15, NO, 0.85) retain];
    [root addSubview:_status];

    _emojiPill = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _emojiPill.backgroundColor = [UIColor colorWithWhite:0 alpha:0.22];
    _emojiPill.layer.cornerRadius = 18;
    _emojiPill.alpha = 0;
    _emojiPill.hidden = YES;
    [_emojiPill addTarget:self action:@selector(toggleCard) forControlEvents:UIControlEventTouchUpInside];
    _emojiLabels = [[NSMutableArray alloc] init];
    for (int i = 0; i < 4; ++i) {
        ExteriaEmojiLabel *glyph = CallEmojiLabel(22, NO);
        [_emojiPill addSubview:glyph];
        [_emojiLabels addObject:glyph];
    }
    [root addSubview:_emojiPill];

    _card = [[UIView alloc] init];
    _card.backgroundColor = [UIColor colorWithWhite:0 alpha:0.38];
    _card.layer.cornerRadius = 14;
    _card.alpha = 0;
    _card.hidden = YES;
    UITapGestureRecognizer *cardTap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleCard)] autorelease];
    [_card addGestureRecognizer:cardTap];
    _cardTitle = [CallLabel(15, YES, 1) retain];
    _cardTitle.text = NSLocalizedString(@"call.key.title", nil);
    _cardText = [CallEmojiLabel(15, NO) retain];
    _cardText.textColor = [UIColor colorWithWhite:1 alpha:0.9];
    _cardText.numberOfLines = 0;
    [_card addSubview:_cardTitle];
    [_card addSubview:_cardText];
    [root addSubview:_card];

    UIColor *glass = [UIColor colorWithWhite:1 alpha:0.2];
    _mute = [CallButton(ExteriaSymbolMicrophone, glass, BUTTON_SIZE, self, @selector(toggleMute)) retain];
    _speaker = [CallButton(ExteriaSymbolSpeaker, glass, BUTTON_SIZE, self, @selector(toggleSpeaker)) retain];
    _end = [CallButton(ExteriaSymbolPhone, [UIColor colorWithRed:0.93 green:0.26 blue:0.26 alpha:1], BUTTON_SIZE, self, @selector(endTapped)) retain];
    _accept = [CallButton(ExteriaSymbolPhone, [UIColor colorWithRed:0.20 green:0.74 blue:0.36 alpha:1], ANSWER_SIZE, self, @selector(acceptTapped)) retain];
    /* the handset of the end button lies down, as on the original screen */
    [_end setImage:CallRotatedImage(ExteriaSymbolImage(ExteriaSymbolPhone, 26, [UIColor whiteColor]), (CGFloat)(M_PI * 3.0 / 4.0)) forState:UIControlStateNormal];
    _acceptRing = [[UIView alloc] init];
    _acceptRing.userInteractionEnabled = NO;
    _acceptRing.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.6].CGColor;
    _acceptRing.layer.borderWidth = 2;
    _acceptRing.hidden = YES;
    _mute.accessibilityLabel = NSLocalizedString(@"call.mute", nil);
    _speaker.accessibilityLabel = NSLocalizedString(@"call.speaker", nil);
    _accept.accessibilityLabel = NSLocalizedString(@"call.accept", nil);
    _muteCaption = [CallLabel(11, NO, 1) retain];
    _speakerCaption = [CallLabel(11, NO, 1) retain];
    _endCaption = [CallLabel(11, NO, 1) retain];
    _acceptCaption = [CallLabel(11, NO, 1) retain];
    _muteCaption.text = NSLocalizedString(@"call.mute", nil);
    _speakerCaption.text = NSLocalizedString(@"call.speaker", nil);
    _acceptCaption.text = NSLocalizedString(@"call.accept", nil);
    /* the call goes on under the chats: the screen folds away to a bar that brings it back */
    _minimize = [CallButton(ExteriaSymbolArrowDown, [UIColor colorWithWhite:1 alpha:0.2], 40, self, @selector(minimizeTapped)) retain];
    _minimize.accessibilityLabel = NSLocalizedString(@"call.minimize", nil);
    _camera = [CallButton(ExteriaSymbolVideoCamera, glass, BUTTON_SIZE, self, @selector(toggleCamera)) retain];
    _camera.accessibilityLabel = NSLocalizedString(@"call.video", nil);
    _cameraCaption = [CallLabel(11, NO, 1) retain];
    _cameraCaption.text = NSLocalizedString(@"call.video", nil);
    /* a tap on the own picture turns to the other camera */
    _previewHost = [[UIView alloc] init];
    _previewHost.backgroundColor = [UIColor blackColor];
    _previewHost.layer.cornerRadius = 10;
    _previewHost.layer.masksToBounds = YES;
    _previewHost.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.5].CGColor;
    _previewHost.layer.borderWidth = 1;
    _previewHost.hidden = YES;
    _previewHost.accessibilityLabel = NSLocalizedString(@"call.flip", nil);
    [_previewHost addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(flipCamera)] autorelease]];
    for (UIView *view in [NSArray arrayWithObjects:_previewHost, _minimize, _camera, _cameraCaption, _acceptRing, _mute, _speaker, _end, _accept, _muteCaption, _speakerCaption, _endCaption, _acceptCaption, nil]) [root addSubview:view];
    self.view = root;
}

- (void)viewDidUnload {
    [self releaseViews];
    [super viewDidUnload];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self render];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _visible = YES;
    [self bindRemoteVideo];
    [self renderVideo];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    if (!_tick) _tick = [[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tickFired) userInfo:nil repeats:YES] retain];
}

/* a dismissal asked for while the screen was still sliding in is ignored by UIKit, so it waits for the end of the slide */
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _appeared = YES;
    if (_dismissing) [self dismiss];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _visible = NO;
    _video.remoteImageHandler = nil;
    [_video.previewLayer removeFromSuperlayer];
    [self stopClock];
}

- (void)stopClock {
    [_tick invalidate];
    [_tick release];
    _tick = nil;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutScreen];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration {
    [super willAnimateRotationToInterfaceOrientation:orientation duration:duration];
    [_video setInterfaceOrientation:orientation];
    [self layoutScreen];
}

#pragma mark layout

/* the rows of buttons by phase: the answer pair while it rings, else speaker, mute and the red end button */
- (void)layoutScreen {
    if (![self isViewLoaded] || !_call) return;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGSize size = self.view.bounds.size;
    /* the picture and the backdrop are the whole screen; the buttons and the words are laid out in the strip clear of the notch in landscape, then moved to it */
    CGRect column = ExteriaContentColumn(size, insets, 0);
    CGFloat dx = column.origin.x;
    BOOL incoming = _call.phase == ExteriaCallPhaseIncoming;
    exteria_call_screen_metrics metrics;
    exteria_call_screen_layout layout;
    metrics.width = column.size.width;
    metrics.height = size.height;
    metrics.top_inset = insets.top;
    metrics.bottom_inset = insets.bottom;
    metrics.incoming = incoming;
    metrics.button_count = 4;
    /* the same test as the one that hides the avatar: a call that ended keeps its avatar, and the name must not move up onto it */
    metrics.video = _call.remoteVideo && !incoming && _call.phase != ExteriaCallPhaseEnded;
    if (exteria_call_screen_layout_compute(&metrics, &layout) != EXTERIA_OK) return;

    _backdrop.frame = self.view.bounds;
    _remoteView.frame = self.view.bounds;
    _videoShade.frame = self.view.bounds;
    _previewHost.frame = CallRect(layout.preview, dx);
    _video.previewLayer.frame = _previewHost.bounds;
    _avatarView.frame = CallRect(layout.avatar, dx);
    _name.frame = CallRect(layout.title, dx);
    _status.frame = CallRect(layout.status, dx);
    _emojiPill.frame = CallRect(layout.emoji, dx);
    for (int i = 0; i < 4; ++i) {
        ExteriaEmojiLabel *glyph = [_emojiLabels objectAtIndex:(NSUInteger)i];
        glyph.frame = CGRectMake(14 + i * 31, 0, 25, _emojiPill.bounds.size.height);
    }
    CGRect card = CallRect(layout.card, dx);
    _card.frame = card;
    _cardTitle.frame = CGRectMake(14, 12, card.size.width - 28, 20);
    _cardText.frame = CGRectMake(14, 38, card.size.width - 28, card.size.height - 50);

    NSArray *buttons = incoming ? [NSArray arrayWithObjects:_end, _accept, nil] : [NSArray arrayWithObjects:_speaker, _camera, _mute, _end, nil];
    NSArray *captions = incoming ? [NSArray arrayWithObjects:_endCaption, _acceptCaption, nil] : [NSArray arrayWithObjects:_speakerCaption, _cameraCaption, _muteCaption, _endCaption, nil];
    for (int i = 0; i < layout.button_count; ++i) {
        UIButton *button = [buttons objectAtIndex:(NSUInteger)i];
        button.frame = CallRect(layout.buttons[i], dx);
        button.layer.cornerRadius = button.bounds.size.width / 2;
        [[captions objectAtIndex:(NSUInteger)i] setFrame:CallRect(layout.captions[i], dx)];
    }
    _minimize.frame = CGRectMake(column.origin.x + 12, insets.top + 10, 40, 40);
    _acceptRing.frame = _accept.frame;
    _acceptRing.layer.cornerRadius = _accept.frame.size.width / 2;
}

#pragma mark mood

- (int)moodForPhase {
    switch (_call.phase) {
    case ExteriaCallPhaseActive: return EXTERIA_CALL_MOOD_TALKING;
    case ExteriaCallPhaseReconnecting: return EXTERIA_CALL_MOOD_WEAK;
    case ExteriaCallPhaseEnded: return _mood >= 0 ? _mood : EXTERIA_CALL_MOOD_CONNECTING;
    default: return EXTERIA_CALL_MOOD_CONNECTING;
    }
}

- (void)applyMood {
    int mood = [self moodForPhase];
    if (mood == _mood) return;
    CGImageRef image = CreateMeshImage((exteria_call_mood)mood, ExteriaThemeIsClassic());
    if (!image) return;
    if (_mood >= 0 && !ExteriaReduceMotionEnabled() && ExteriaLiteEnabled(EXTERIA_LITE_CALLS)) {
        CATransition *fade = [CATransition animation];
        fade.type = kCATransitionFade;
        fade.duration = MOOD_FADE_SECONDS;
        [_backdrop.layer addAnimation:fade forKey:@"mood"];
    }
    _backdrop.layer.contents = (id)image;
    CGImageRelease(image);
    _mood = mood;
}

/* the answer button breathes while the phone rings; reduce motion and the power saving settings for calls leave the ring still */
- (void)updateAcceptRing:(BOOL)incoming {
    _acceptRing.hidden = !incoming;
    if (!incoming || ExteriaReduceMotionEnabled() || !ExteriaLiteEnabled(EXTERIA_LITE_CALLS)) {
        [_acceptRing.layer removeAllAnimations];
        return;
    }
    if ([_acceptRing.layer animationForKey:@"pulse"]) return;
    CABasicAnimation *scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scale.fromValue = [NSNumber numberWithFloat:1.0f];
    scale.toValue = [NSNumber numberWithFloat:1.45f];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = [NSNumber numberWithFloat:0.8f];
    fade.toValue = [NSNumber numberWithFloat:0.0f];
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = [NSArray arrayWithObjects:scale, fade, nil];
    group.duration = 1.4;
    group.repeatCount = HUGE_VALF;
    [_acceptRing.layer addAnimation:group forKey:@"pulse"];
}

#pragma mark state

/* the tone of the end of a call, as the original plays them; busy for a phone that was busy or did not answer, the
   failure sound for a call that broke, the end sound for any other */
- (int)endToneAfterPhase:(ExteriaCallPhase)previous {
    if (!_call.outgoing && (previous == ExteriaCallPhaseIncoming || _call.end == ExteriaCallEndMissed)) return -1;
    switch (_call.end) {
    case ExteriaCallEndBusy:
    case ExteriaCallEndMissed:
        return _call.outgoing ? ExteriaCallToneBusy : -1;
    case ExteriaCallEndFailed:
    case ExteriaCallEndOutdated:
    case ExteriaCallEndPrivacy:
        return ExteriaCallToneFailed;
    default:
        return ExteriaCallToneEnded;
    }
}

- (void)playTone:(int)tone {
    if (tone == _tone) return;
    _tone = tone;
    if (tone < 0) {
        ExteriaCallToneStop();
        return;
    }
    /* the ringback is heard in the earpiece, like the call itself, so the session is taken now and not when the media starts */
    if (!_audioHeld) _audioHeld = ExteriaAudioSessionBeginCall();
    ExteriaCallToneStart((ExteriaCallTone)tone);
}

- (void)updateWithCall:(ExteriaCall *)call {
    BOOL first = _call == nil;
    ExteriaCallPhase previous = _call ? _call.phase : call.phase;
    [_call release];
    _call = [call retain];
    if (call.phase == ExteriaCallPhaseEnded) {
        int tone = _closing ? _tone : [self endToneAfterPhase:previous];
        [self playTone:tone];
        /* the audio session stays for the tone and is let go when the screen closes */
        if (tone < 0) [self endAudio];
        [self render];
        if (!_closing) {
            _closing = YES;
            NSTimeInterval hold = tone >= 0 ? ExteriaCallToneDuration((ExteriaCallTone)tone) + TONE_TAIL_SECONDS : 0;
            [self performSelector:@selector(close) withObject:nil afterDelay:MAX(ENDED_HOLD_SECONDS, hold)];
        }
        return;
    }
    switch (call.phase) {
    case ExteriaCallPhaseRinging: [self playTone:ExteriaCallToneRingback]; break;
    case ExteriaCallPhaseExchanging:
    case ExteriaCallPhaseConnecting: [self playTone:ExteriaCallToneConnecting]; break;
    case ExteriaCallPhaseActive:
    case ExteriaCallPhaseReconnecting: [self playTone:-1]; break;
    default: break;
    }
    if (first || !_audioHeld) [self beginAudioIfNeeded];
    [self attachVideo];
    [self render];
}

#pragma mark video

/* the pictures of the other side go to the image view and the own camera to the preview, for as long as the call has a runtime; the handler holds the screen
   without retaining it, and the screen lets the video go before it goes itself */
- (void)attachVideo {
    ExteriaCallVideo *video = _call.phase == ExteriaCallPhaseEnded ? nil : [_session activeCallVideo];
    if (video == _video) return;
    [self detachVideo];
    if (!video) return;
    _video = [video retain];
    [self bindRemoteVideo];
}

- (void)bindRemoteVideo {
    if (!_visible || !_video) return;
    ExteriaCallController *controller = self;
    _video.remoteImageHandler = ^(CGImageRef image) {
        UIImage *picture = [UIImage imageWithCGImage:image];
        controller->_remoteView.image = picture;
    };
}

- (void)detachVideo {
    if (!_video) return;
    _video.remoteImageHandler = nil;
    [_video.previewLayer removeFromSuperlayer];
    [_video release];
    _video = nil;
    _remoteView.image = nil;
}

/* the own camera is a layer of the video object; it sits in the preview while the camera runs */
- (void)renderVideo {
    BOOL showRemote = _call.remoteVideo && _call.phase != ExteriaCallPhaseEnded && _call.phase != ExteriaCallPhaseIncoming;
    BOOL showPreview = _call.cameraOn && _video.previewLayer && _call.phase != ExteriaCallPhaseEnded;
    CALayer *layer = _video.previewLayer;
    _remoteView.hidden = !showRemote;
    _videoShade.hidden = !showRemote;
    _avatarView.hidden = showRemote;
    _previewHost.hidden = !showPreview;
    if (showPreview && layer.superlayer != _previewHost.layer) {
        [layer removeFromSuperlayer];
        layer.frame = _previewHost.bounds;
        [_previewHost.layer addSublayer:layer];
    } else if (!showPreview) {
        [layer removeFromSuperlayer];
    }
    if (!showRemote) _remoteView.image = nil;
}

/* the earpiece and microphone are claimed when the call gets going, so the ringing phase leaves music alone */
- (void)beginAudioIfNeeded {
    if (_audioHeld) return;
    if (_call.phase == ExteriaCallPhaseRequesting || _call.phase == ExteriaCallPhaseIncoming || _call.phase == ExteriaCallPhaseCalling ||
        _call.phase == ExteriaCallPhaseRinging) return;
    _audioHeld = ExteriaAudioSessionBeginCall();
}

- (void)endAudio {
    if (!_audioHeld) return;
    _audioHeld = NO;
    ExteriaAudioSessionEndCall();
}

- (NSString *)clockText {
    NSInteger seconds = (NSInteger)([NSDate timeIntervalSinceReferenceDate] - _call.startedAt);
    if (seconds < 0) seconds = 0;
    if (seconds >= 3600) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(seconds / 3600), (long)(seconds / 60 % 60), (long)(seconds % 60)];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
}

- (NSString *)statusText {
    switch (_call.phase) {
    case ExteriaCallPhaseRequesting: return NSLocalizedString(@"call.requesting", nil);
    case ExteriaCallPhaseCalling: return NSLocalizedString(@"call.calling", nil);
    case ExteriaCallPhaseRinging: return NSLocalizedString(@"call.ringing", nil);
    case ExteriaCallPhaseIncoming: return NSLocalizedString(_call.video ? @"call.incoming.video" : @"call.incoming", nil);
    case ExteriaCallPhaseExchanging: return NSLocalizedString(@"call.exchanging", nil);
    case ExteriaCallPhaseConnecting: return NSLocalizedString(@"call.connecting", nil);
    case ExteriaCallPhaseActive: return [self clockText];
    case ExteriaCallPhaseReconnecting: return NSLocalizedString(@"call.reconnecting", nil);
    case ExteriaCallPhaseEnded:
        switch (_call.end) {
        case ExteriaCallEndDeclined: return NSLocalizedString(@"call.declined", nil);
        case ExteriaCallEndBusy: return NSLocalizedString(@"call.busy", nil);
        case ExteriaCallEndMissed: return NSLocalizedString(@"call.missed", nil);
        case ExteriaCallEndFailed: return NSLocalizedString(@"call.failed", nil);
        case ExteriaCallEndOutdated: return [NSString stringWithFormat:NSLocalizedString(@"call.outdated", nil), _call.peerName];
        case ExteriaCallEndPrivacy: return [NSString stringWithFormat:NSLocalizedString(@"call.privacy", nil), _call.peerName];
        default: return NSLocalizedString(@"call.ended", nil);
        }
    }
    return @"";
}

- (void)render {
    if (![self isViewLoaded] || !_call) return;
    [self applyMood];
    _name.text = _call.peerName;
    _status.text = [self statusText];
    _avatarView.seed = (NSUInteger)(_call.peerId < 0 ? -_call.peerId : _call.peerId);
    _avatarView.initials = ExteriaInitialsOfName(_call.peerName);
    [_avatarView setPhoto:_photo cache:_avatars];

    BOOL incoming = _call.phase == ExteriaCallPhaseIncoming;
    BOOL ended = _call.phase == ExteriaCallPhaseEnded;
    [self renderEmoji];
    [self renderVideo];
    _accept.hidden = _acceptCaption.hidden = !incoming || ended;
    _mute.hidden = _muteCaption.hidden = _speaker.hidden = _speakerCaption.hidden = _camera.hidden = _cameraCaption.hidden = incoming || ended;
    _end.hidden = _endCaption.hidden = ended;
    _minimize.hidden = incoming || ended || !_onMinimize;
    [self updateAcceptRing:incoming && !ended];
    _endCaption.text = NSLocalizedString(incoming ? @"call.decline" : @"call.end", nil);
    _end.accessibilityLabel = _endCaption.text;
    UIColor *dark = [UIColor colorWithWhite:0.18 alpha:1];
    _mute.backgroundColor = [UIColor colorWithWhite:1 alpha:_call.muted ? 0.92 : 0.2];
    [_mute setImage:ExteriaSymbolImage(ExteriaSymbolMicrophone, 26, _call.muted ? dark : [UIColor whiteColor]) forState:UIControlStateNormal];
    _camera.backgroundColor = [UIColor colorWithWhite:1 alpha:_call.cameraOn ? 0.92 : 0.2];
    [_camera setImage:ExteriaSymbolImage(ExteriaSymbolVideoCamera, 26, _call.cameraOn ? dark : [UIColor whiteColor]) forState:UIControlStateNormal];
    _speaker.backgroundColor = [UIColor colorWithWhite:1 alpha:_speakerOn ? 0.92 : 0.2];
    [_speaker setImage:ExteriaSymbolImage(ExteriaSymbolSpeaker, 26, _speakerOn ? dark : [UIColor whiteColor]) forState:UIControlStateNormal];
    [self layoutScreen];
}

/* the pill appears once the key exists and stays out of the way of the ended screen */
- (void)renderEmoji {
    NSArray *emoji = _call.emoji;
    BOOL show = emoji.count == 4 && _call.phase != ExteriaCallPhaseEnded;
    if (show) {
        for (NSUInteger i = 0; i < 4; ++i) [[_emojiLabels objectAtIndex:i] setText:[emoji objectAtIndex:i]];
        _emojiPill.accessibilityLabel = [emoji componentsJoinedByString:@" "];
        _emojiPill.accessibilityHint = NSLocalizedString(@"call.key.title", nil);
        _cardText.text = [NSString stringWithFormat:NSLocalizedString(@"call.key.text", nil), _call.peerName];
    }
    if (!show && _cardShown) [self setCardShown:NO animated:NO];
    if (show == !_emojiPill.hidden) return;
    if (show) _emojiPill.hidden = NO;
    NSTimeInterval duration = ExteriaReduceMotionEnabled() ? 0 : CARD_FADE_SECONDS;
    [UIView animateWithDuration:duration animations:^{
        _emojiPill.alpha = show ? 1 : 0;
    } completion:^(BOOL finished) {
        if (finished && !show) _emojiPill.hidden = YES;
    }];
}

- (void)toggleCard {
    [self setCardShown:!_cardShown animated:YES];
}

- (void)setCardShown:(BOOL)shown animated:(BOOL)animated {
    if (shown == _cardShown) return;
    _cardShown = shown;
    if (shown) _card.hidden = NO;
    NSTimeInterval duration = animated && !ExteriaReduceMotionEnabled() ? CARD_FADE_SECONDS : 0;
    [UIView animateWithDuration:duration animations:^{
        _card.alpha = shown ? 1 : 0;
    } completion:^(BOOL finished) {
        if (finished && !_cardShown) _card.hidden = YES;
    }];
}

- (void)tickFired {
    ++_ticks;
    if (_call.phase == ExteriaCallPhaseActive) _status.text = [self clockText];
    /* the ringer is a buzz, as the app plays no sound while it is in front */
    if (_call.phase == ExteriaCallPhaseIncoming && _ticks % VIBRATE_EVERY_TICKS == 0) ExteriaVibrateForCall();
}

#pragma mark actions

- (void)toggleMute {
    [_session setCallMuted:!_call.muted];
}

- (void)minimizeTapped {
    if (_onMinimize) _onMinimize();
}

- (void)toggleCamera {
    [_session setCallCameraOn:!_call.cameraOn];
}

- (void)flipCamera {
    if (![_video switchCamera]) NSLog(@"exteria: this device has one camera only");
}

- (void)toggleSpeaker {
    _speakerOn = !_speakerOn;
    ExteriaAudioSessionSetSpeaker(_speakerOn);
    [self render];
}

- (void)endTapped {
    if (_call.phase == ExteriaCallPhaseIncoming) [_session declineCall];
    else [_session hangUpCall];
}

- (void)acceptTapped {
    [_session acceptCall];
}

- (void)close {
    if (_dismissing) return;
    _dismissing = YES;
    [self stopClock];
    ExteriaCallToneStop();
    _tone = -1;
    [self endAudio];
    [self detachVideo];
    if (_appeared) [self dismiss];
}

/* the owner lets go of the screen in its finish block, and only once the screen is off the window */
- (void)dismiss {
    if (_finished) return;
    _finished = YES;
    [[self retain] autorelease];
    if (!self.presentingViewController) {
        [self finishDismissal];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:^{
        [self finishDismissal];
    }];
}

- (void)finishDismissal {
    void (^finish)(void) = [[_onFinish retain] autorelease];
    [self setOnFinish:nil];
    if (finish) finish();
}

@end
