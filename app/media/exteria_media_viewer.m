#import "exteria_name_badge.h"
#import "exteria_media_action_view.h"
#import "exteria_progress_bar.h"
#import "exteria_slider.h"
#import "exteria_string_drawing.h"
#import "exteria_centered_hint_field.h"
#import "exteria_theme.h"
#import "exteria_media_viewer.h"
#import "exteria_burn_effect.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import "exteria_audio_session.h"
#import "exteria_chat_settings.h"
#import "exteria_emoji_label.h"
#import "exteria_image_decoder.h"
#import "exteria_music_player.h"
#import "exteria_photo_editor.h"
#import "exteria_platform.h"
#import "exteria_popup_menu.h"
#import "exteria_time.h"
#import "exteria_symbol.h"
#import "exteria_weak_reference.h"

#define EXTERIA_VIEWER_PHOTO_SIDE_MAX 2048.0

static char ExteriaMediaPlayerStatusContext;

@interface ExteriaMediaVideoView : UIView
@end
@implementation ExteriaMediaVideoView
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

@interface ExteriaMediaViewer () <UIScrollViewDelegate, UIGestureRecognizerDelegate, UITextFieldDelegate, UIDocumentInteractionControllerDelegate> {
    NSArray *_messages;
    NSDictionary *_senderNames;
    NSString *_chatTitle;
    NSInteger _index;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    UIImage *_localImage;
    NSURL *_localURL;
    NSString *_loadedPath;
    NSURL *_playableURL;
    void (^_sendPhoto)(UIImage *, NSString *);
    void (^_sendVideo)(NSString *);
    void (^_cancelHandler)(void);
    UIDocumentInteractionController *_document;
    NSString *_sharePath;
    BOOL _observingStatus;
    UIView *_page;
    UIImageView *_pageTransition;
    BOOL _paging;
    UIScrollView *_zoom;
    UIImageView *_image;
    ExteriaMediaVideoView *_video;
    UIView *_top;
    UIView *_bottom;
    ExteriaEmojiLabel *_title;
    UILabel *_date;
    UILabel *_count;
    ExteriaEmojiLabel *_caption;
    UITextField *_captionInput;
    UIButton *_play;
    UIButton *_mute;
    UIButton *_more;
    /* owned by the top bar, which holds it as a subview */
    UIButton *_close;
    UIButton *_headerEdit;
    UIButton *_send;
    UIButton *_forward;
    UIButton *_retry;
    UILabel *_time;
    UISlider *_seek;
    UIActivityIndicatorView *_spinner;
    ExteriaProgressBar *_progress;
    ExteriaMediaActionView *_playGlyph;
    AVPlayer *_player;
    AVPlayerItem *_playerItem;
    id _timeObserver;
    NSUInteger _request;
    NSUInteger _generation;
    BOOL _closed;
    BOOL _chromeHidden;
    BOOL _scrubbing;
    BOOL _resumeAfterSeek;
    BOOL _wantsPlay;
    BOOL _muted;
    BOOL _statusHidden;
    BOOL _saving;
    BOOL _photoReady;
    /* the one-time mode: set by the initializer, and the burn that runs before the viewer leaves */
    BOOL _oneTime;
    BOOL _opened;
    BOOL _burning;
    BOOL _previewOnly;
    void (^_openedHandler)(void);
    CGFloat _keyboardHeight;
    CGSize _layoutSize;
}
@end

@implementation ExteriaMediaViewer
@synthesize cancelHandler = _cancelHandler;

- (id)init {
    self = [super init];
    if (self) {
        _weak = [[ExteriaWeakReference referenceTo:self] retain];
        self.wantsFullScreenLayout = YES;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        /* the slide up of ios 6 shows the bar over a half drawn picture on the ipad, so the viewer fades in instead */
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (id)initWithMessages:(NSArray *)messages selected:(ExteriaMessage *)message media:(ExteriaMediaCache *)media {
    return [self initWithMessages:messages selected:message media:media senderNames:nil chatTitle:nil];
}

- (id)initWithMessages:(NSArray *)messages selected:(ExteriaMessage *)message media:(ExteriaMediaCache *)media
           senderNames:(NSDictionary *)senderNames chatTitle:(NSString *)chatTitle {
    self = [self init];
    if (self) {
        _messages = [messages copy];
        _senderNames = [senderNames copy];
        _chatTitle = [chatTitle copy];
        NSUInteger index = [messages indexOfObjectIdenticalTo:message];
        /* a list that was rebuilt holds fresh copies of the messages, and the one that was tapped is found by its id; without that the viewer opened on the first picture */
        if (index == NSNotFound && message.messageId > 0) {
            for (NSUInteger i = 0; i < messages.count; ++i) {
                if (((ExteriaMessage *)[messages objectAtIndex:i]).messageId == message.messageId) { index = i; break; }
            }
        }
        _index = index == NSNotFound ? 0 : (NSInteger)index;
        _media = [media retain];
    }
    return self;
}

- (id)initWithOneTimeMessage:(ExteriaMessage *)message media:(ExteriaMediaCache *)media opened:(void (^)(void))opened closed:(void (^)(void))closed {
    self = [self initWithMessages:[NSArray arrayWithObject:message] selected:message media:media];
    if (self) {
        _oneTime = YES;
        _openedHandler = [opened copy];
        _cancelHandler = [closed copy];
    }
    return self;
}

- (id)initWithOneTimePreviewOfMessage:(ExteriaMessage *)message media:(ExteriaMediaCache *)media {
    self = [self initWithMessages:[NSArray arrayWithObject:message] selected:message media:media];
    if (self) {
        _oneTime = YES;
        _previewOnly = YES;
    }
    return self;
}

- (void)noteOpened {
    if (!_oneTime || _opened || _previewOnly) return;
    _opened = YES;
    if (_openedHandler) _openedHandler();
}

- (id)initWithImage:(UIImage *)image send:(void (^)(UIImage *, NSString *))send {
    self = [self init];
    if (self) { _localImage = [image retain]; _sendPhoto = [send copy]; }
    return self;
}

- (id)initWithVideoURL:(NSURL *)url send:(void (^)(NSString *))send {
    self = [self init];
    if (self) { _localURL = [url retain]; _sendVideo = [send copy]; }
    return self;
}

- (ExteriaMessage *)message {
    return _index >= 0 && _index < (NSInteger)_messages.count ? [_messages objectAtIndex:(NSUInteger)_index] : nil;
}

- (BOOL)isVideo { return _localURL || self.message.media.kind == EXTERIA_PREVIEW_VIDEO || self.message.media.kind == EXTERIA_PREVIEW_GIF || (_oneTime && self.message.media.kind == EXTERIA_PREVIEW_VIDEO_MESSAGE); }
- (BOOL)isSending { return _sendPhoto || _sendVideo; }

- (void)dealloc {
    [_weak clear];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_media cancelPathRequest:_request];
    [self releasePlayer];
    [_senderNames release]; [_chatTitle release];
    [_messages release]; [_media release]; [_weak release];
    [_localImage release]; [_localURL release]; [_loadedPath release];
    [_sendPhoto release]; [_sendVideo release]; [_cancelHandler release]; [_openedHandler release];
    _document.delegate = nil; [_document dismissMenuAnimated:NO]; [_document release];
    if (_sharePath) [[NSFileManager defaultManager] removeItemAtPath:_sharePath error:NULL];
    [_sharePath release];
    [_page release]; [_pageTransition release];
    [_zoom release]; [_image release]; [_video release]; [_top release]; [_bottom release];
    [_title release]; [_date release]; [_count release]; [_caption release]; [_captionInput release];
    [_play release]; [_playGlyph release]; [_mute release];
    [_more release]; [_headerEdit release]; [_send release]; [_forward release];
    [_time release]; [_seek release]; [_spinner release]; [_progress release]; [_retry release];
    [super dealloc];
}

- (UIButton *)button:(ExteriaSymbol)symbol action:(SEL)action host:(UIView *)host {
    UIButton *button = [[UIButton alloc] init];
    [button setImage:ExteriaSymbolImage(symbol, 23, [UIColor whiteColor]) forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:button];
    return button;
}

- (void)loadView {
    self.view = [[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds] autorelease];
    self.view.backgroundColor = [UIColor blackColor];
    _page = [[UIView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:_page];
    _zoom = [[UIScrollView alloc] init];
    _zoom.delegate = self;
    _zoom.minimumZoomScale = 1; _zoom.maximumZoomScale = 4;
    _zoom.bounces = NO;
    ExteriaScrollViewOwnsInsets(_zoom);
    _zoom.showsHorizontalScrollIndicator = NO; _zoom.showsVerticalScrollIndicator = NO;
    [_page addSubview:_zoom];
    _image = [[UIImageView alloc] init];
    _image.contentMode = UIViewContentModeScaleAspectFit;
    [_zoom addSubview:_image];
    _video = [[ExteriaMediaVideoView alloc] init];
    ((AVPlayerLayer *)_video.layer).videoGravity = AVLayerVideoGravityResizeAspect;
    [_page addSubview:_video];
    _top = [[UIView alloc] init]; _bottom = [[UIView alloc] init];
    _top.backgroundColor = [UIColor blackColor];
    _bottom.backgroundColor = [UIColor colorWithWhite:0 alpha:ExteriaThemeIsClassic() ? 0.7 : 0.62];
    if (!ExteriaThemeIsClassic()) _bottom.layer.cornerRadius = 12;
    [self.view addSubview:_top]; [self.view addSubview:_bottom];
    UIButton *close = [self button:ExteriaSymbolBack action:@selector(close) host:_top];
    close.frame = CGRectMake(0, 4, 48, 48);
    close.accessibilityLabel = NSLocalizedString(@"attach.cancel", nil);
    _close = close;
    [close release];
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.textColor = [UIColor whiteColor]; _title.textAlignment = ExteriaTextAlignmentLeft;
    _title.font = ExteriaFontBold(17); [_top addSubview:_title];
    _date = [[UILabel alloc] init]; _date.backgroundColor = [UIColor clearColor];
    ExteriaLabelFitToWidth(_date, 9);
    _date.textColor = [UIColor whiteColor]; _date.font = [UIFont systemFontOfSize:13];
    [_top addSubview:_date];
    _count = [[UILabel alloc] init]; _count.backgroundColor = [UIColor clearColor];
    _count.textColor = [UIColor whiteColor]; _count.font = [UIFont boldSystemFontOfSize:15];
    _count.textAlignment = UITextAlignmentCenter; [_top addSubview:_count];
    _headerEdit = [self button:ExteriaSymbolHeaderDraw action:@selector(edit) host:_top];
    _headerEdit.accessibilityLabel = NSLocalizedString(@"media.edit", nil);
    _forward = [self button:ExteriaSymbolShare action:@selector(forward) host:_top];
    _forward.accessibilityLabel = NSLocalizedString(@"media.share", nil);
    _more = [self button:ExteriaSymbolEllipsisVertical action:@selector(showMenu) host:_top];
    _more.accessibilityLabel = NSLocalizedString(@"media.actions", nil);
    _play = [self button:ExteriaSymbolPlay action:@selector(togglePlay) host:_bottom];
    /* the triangle and the bars are the glyph of the media button of the chat, which turns one into the other; the picture of a plain triangle stood to the left of the
       middle of its disc */
    [_play setImage:nil forState:UIControlStateNormal];
    _playGlyph = [[ExteriaMediaActionView alloc] init];
    [_play addSubview:_playGlyph];
    _mute = [self button:ExteriaSymbolSpeaker action:@selector(toggleMute) host:_bottom];
    _mute.accessibilityLabel = NSLocalizedString(@"media.mute", nil);
    _time = [[UILabel alloc] init]; _time.backgroundColor = [UIColor clearColor];
    ExteriaLabelFitToWidth(_time, 9);
    _time.textColor = [UIColor whiteColor]; _time.font = [UIFont systemFontOfSize:12];
    _time.textAlignment = UITextAlignmentCenter; [_bottom addSubview:_time];
    _seek = [[ExteriaSlider alloc] init];
    [(ExteriaSlider *)_seek setTrackColor:[UIColor whiteColor]];
    [_seek addTarget:self action:@selector(beginSeek) forControlEvents:UIControlEventTouchDown];
    [_seek addTarget:self action:@selector(seekChanged) forControlEvents:UIControlEventValueChanged];
    [_seek addTarget:self action:@selector(endSeek) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    _seek.accessibilityLabel = NSLocalizedString(@"media.seek", nil);
    [_bottom addSubview:_seek];
    _caption = [[ExteriaEmojiLabel alloc] init];
    _caption.textColor = [UIColor whiteColor]; _caption.font = ExteriaFontRegular(15);
    _caption.numberOfLines = 3; [_bottom addSubview:_caption];
    _captionInput = [[ExteriaCenteredHintField alloc] init];
    ((ExteriaCenteredHintField *)_captionInput).leftAligned = YES;
    _captionInput.textColor = [UIColor whiteColor]; _captionInput.font = [UIFont systemFontOfSize:16];
    _captionInput.placeholder = NSLocalizedString(@"media.caption", nil);
    _captionInput.delegate = self; _captionInput.returnKeyType = UIReturnKeyDone;
    _captionInput.accessibilityLabel = NSLocalizedString(@"media.caption", nil);
    [_bottom addSubview:_captionInput];
    _send = [self button:ExteriaSymbolSendArrow action:@selector(send) host:_bottom];
    _send.accessibilityLabel = NSLocalizedString(@"attach.send", nil);
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.hidesWhenStopped = YES; [self.view addSubview:_spinner];
    _progress = [[ExteriaProgressBar alloc] init];
    [self.view addSubview:_progress];
    _retry = [[UIButton alloc] init]; _retry.titleLabel.font = [UIFont systemFontOfSize:15];
    _retry.titleLabel.numberOfLines = 3; _retry.titleLabel.textAlignment = UITextAlignmentCenter;
    [_retry setTitle:NSLocalizedString(@"media.failed", nil) forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(retry) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_retry];
    UITapGestureRecognizer *doubleTap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)] autorelease];
    doubleTap.numberOfTapsRequired = 2; doubleTap.delegate = self; [self.view addGestureRecognizer:doubleTap];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease];
    tap.delegate = self; [tap requireGestureRecognizerToFail:doubleTap]; [self.view addGestureRecognizer:tap];
    for (NSNumber *direction in [NSArray arrayWithObjects:@(UISwipeGestureRecognizerDirectionDown), nil]) {
        UISwipeGestureRecognizer *swipe = [[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swiped:)] autorelease];
        swipe.direction = direction.unsignedIntegerValue; swipe.delegate = self; [self.view addGestureRecognizer:swipe];
    }
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(backgrounded:) name:UIApplicationWillResignActiveNotification object:nil];
    /* the value of MPMusicPlayerControllerVolumeDidChangeNotification, spelled out so this file does not need MediaPlayer */
    [center addObserver:self selector:@selector(volumeChanged:) name:@"MPMusicPlayerControllerVolumeDidChangeNotification" object:nil];
    [center addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
    UIPanGestureRecognizer *page = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(paged:)] autorelease];
    page.delegate = self;
    page.maximumNumberOfTouches = 1;
    [self.view addGestureRecognizer:page];
    for (UIGestureRecognizer *gesture in self.view.gestureRecognizers) {
        if ([gesture isKindOfClass:[UISwipeGestureRecognizer class]]) [gesture requireGestureRecognizerToFail:page];
    }
    [self loadCurrent];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _statusHidden = [UIApplication sharedApplication].statusBarHidden;
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _wantsPlay = NO; [_player pause]; [self tick];
    [[UIApplication sharedApplication] setStatusBarHidden:_statusHidden withAnimation:UIStatusBarAnimationNone];
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return YES; }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
#else
- (NSUInteger)supportedInterfaceOrientations
#endif
{ return UIInterfaceOrientationMaskAll; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat width = bounds.size.width, height = bounds.size.height;
    /* the picture runs under the notch and the home indicator; the bars and their buttons stand clear of them, in landscape too */
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat top = insets.top, left = insets.left, right = insets.right, inner = MAX(0, width - left - right);
    if (!CGSizeEqualToSize(_layoutSize, bounds.size)) {
        [self cancelPaging];
        _layoutSize = bounds.size;
        [_zoom setZoomScale:1 animated:NO];
    }
    _page.bounds = bounds;
    _page.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    _zoom.frame = bounds; _video.frame = bounds;
    if (_zoom.zoomScale <= 1.001) { _image.frame = _zoom.bounds; _zoom.contentSize = bounds.size; }
    CGFloat header = top + (self.isSending ? 56 : 96);
    _top.frame = CGRectMake(0, 0, width, header);
    _close.frame = CGRectMake(left, top + 4, 48, 48);
    _title.frame = CGRectMake(left + 56, top + (self.isSending ? 17 : 6), MAX(0, inner - 188), 24);
    _date.frame = CGRectMake(left + 56, top + 30, MAX(0, inner - 188), 20);
    _headerEdit.frame = CGRectMake(width - right - 132, top + 4, 44, 48);
    _forward.frame = CGRectMake(width - right - 88, top + 4, 44, 48);
    _more.frame = CGRectMake(width - right - 44, top + 4, 44, 48);
    _count.frame = CGRectMake(left + 48, top + 56, MAX(0, inner - 96), 40);
    CGFloat controls = self.isVideo ? 76 : 0;
    CGFloat caption = self.isSending ? 50 : (_caption.text.length ? 66 : 0);
    CGFloat bottom = controls + caption;
    /* the plate runs under the home indicator while its controls stay above it; with the keyboard up the keyboard covers the indicator */
    CGFloat pad = (bottom > 0 && _keyboardHeight == 0) ? insets.bottom : 0;
    _bottom.frame = CGRectMake(0, MAX(header, height - bottom - pad - _keyboardHeight), width, bottom + pad);
    _play.frame = CGRectMake(left + 2, 0, 48, 44); _mute.frame = CGRectMake(width - right - 50, 0, 48, 44);
    if (!ExteriaThemeIsClassic()) {
        _play.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
        _play.layer.cornerRadius = 20;
        _play.frame = CGRectMake(left + 6, 2, 40, 40);
    }
    _playGlyph.frame = _play.bounds;
    _seek.frame = CGRectMake(left + 54, 0, MAX(0, inner - 108), 44);
    _time.frame = CGRectMake(left + 54, 44, MAX(0, inner - 108), 24);
    _caption.frame = CGRectMake(left + 16, controls, MAX(0, inner - 32), caption);
    _captionInput.frame = CGRectMake(left + 16, controls, MAX(0, inner - 76), caption);
    _send.frame = CGRectMake(width - right - 54, controls, 50, caption);
    _spinner.center = CGPointMake(width / 2, height / 2);
    _progress.frame = CGRectMake(width / 2 - 80, height / 2 + 36, 160, 4);
    _retry.frame = CGRectMake(left + 24, height / 2 - 44, MAX(0, inner - 48), 88);
}

- (void)keyboard:(NSNotification *)note {
    CGRect frame = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    frame = [self.view convertRect:frame fromView:nil];
    _keyboardHeight = MAX(0, CGRectGetMaxY(self.view.bounds) - MAX(0, frame.origin.y));
    [self.view setNeedsLayout];
}
- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; return YES; }
- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    return range.location <= field.text.length && range.length <= field.text.length - range.location && field.text.length - range.length + string.length <= 1024;
}

- (void)releasePlayer {
    if (_timeObserver && _player) [_player removeTimeObserver:_timeObserver];
    [_timeObserver release]; _timeObserver = nil;
    if (_observingStatus) { [_playerItem removeObserver:self forKeyPath:@"status"]; _observingStatus = NO; }
    if (_playerItem) [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:_playerItem];
    [_player pause]; ((AVPlayerLayer *)_video.layer).player = nil;
    [_player release]; _player = nil; [_playerItem release]; _playerItem = nil;
    if (_playableURL) [[NSFileManager defaultManager] removeItemAtPath:_playableURL.path.stringByDeletingLastPathComponent error:NULL];
    [_playableURL release]; _playableURL = nil;
    _wantsPlay = NO; _scrubbing = NO; _muted = NO;
    [_mute setImage:ExteriaSymbolImage(ExteriaSymbolSpeaker, 23, [UIColor whiteColor]) forState:UIControlStateNormal];
}

- (void)loadCurrent {
    ++_generation;
    [_media cancelPathRequest:_request]; _request = 0;
    [self releasePlayer];
    [_loadedPath release]; _loadedPath = nil;
    [_zoom setZoomScale:1 animated:NO]; _zoom.maximumZoomScale = self.isVideo ? 1 : 4;
    _photoReady = NO;
    _image.image = nil; _retry.hidden = YES; _progress.hidden = YES; _progress.progress = 0;
    _more.enabled = _forward.enabled = _headerEdit.enabled = NO;
    _video.hidden = !self.isVideo;
    _play.hidden = _mute.hidden = _time.hidden = _seek.hidden = !self.isVideo;
    _seek.enabled = NO; _play.enabled = NO; _mute.enabled = NO;
    _headerEdit.hidden = self.isVideo;
    _date.hidden = _count.hidden = self.isSending;
    _caption.hidden = self.isSending;
    _forward.enabled = NO;
    _captionInput.hidden = _send.hidden = !self.isSending;
    _caption.text = self.message.text;
    NSString *name = [_senderNames objectForKey:[NSNumber numberWithLongLong:self.message.senderKey]];
    if (!name.length) name = self.message.outgoing ? NSLocalizedString(@"media.you", nil) : _chatTitle;
    if (self.isSending) {
        _title.entities = nil;
        _title.text = NSLocalizedString(@"media.preview", nil);
    } else {
        /* the sender's marks stand after the name, as in the chat; a negative key is a channel, which wears none */
        long long sender = self.message.senderKey;
        ExteriaShowNameWithBadges(_title, name.length ? name : NSLocalizedString(@"chat.someone", nil), sender > 0 ? sender : 0, nil, nil);
    }
    _date.text = ExteriaMediaTimeText(self.message.date);
    _count.text = [NSString stringWithFormat:NSLocalizedString(@"media.count", nil), (long)(_index + 1), (long)_messages.count];
    if (_oneTime) {
        /* nothing here can keep the picture: no menu, no share, no edit, and the line under the title says it goes */
        _more.hidden = _forward.hidden = _headerEdit.hidden = _count.hidden = YES;
        _title.entities = nil;
        _title.text = NSLocalizedString(_previewOnly ? @"viewonce.preview.title" : (self.isVideo ? @"viewonce.title.video" : @"viewonce.title.photo"), nil);
        _date.text = NSLocalizedString(_previewOnly ? @"viewonce.preview.hint" : @"viewonce.hint", nil);
        _date.hidden = NO;
    }
    [self.view setNeedsLayout];
    if (_localImage) { _image.image = _localImage; _more.enabled = _forward.enabled = _headerEdit.enabled = YES; return; }
    if (_localURL) { [self playURL:_localURL]; return; }
    /* a one-time file of ours that has not finished going up has no server copy to fetch yet */
    ExteriaOutgoing *pending = self.message.pendingSend;
    if (_previewOnly && pending && pending->path && !self.message.media.file) {
        NSURL *local = [NSURL fileURLWithPath:pending->path];
        if (self.isVideo) { [self playURL:local]; return; }
        UIImage *picture = ExteriaDecodeImageAtURL(local, EXTERIA_VIEWER_PHOTO_SIDE_MAX);
        if (!picture) { [self failed]; return; }
        _image.image = picture;
        _photoReady = YES;
        return;
    }
    ExteriaMedia *content = self.message.media;
    if (!content.file) { [self failed]; return; }
    [_spinner startAnimating];
    ExteriaWeakReference *weak = _weak;
    NSUInteger generation = _generation;
    if (!self.isVideo) {
        _image.image = [_media cachedImageForFile:content.file maxSide:640];
        [_media loadImageForFile:content.file maxSide:640 completion:^(UIImage *image) {
            ExteriaMediaViewer *viewer = weak.target;
            if (viewer && !viewer->_closed && viewer->_generation == generation && !viewer->_photoReady && image) viewer->_image.image = image;
        }];
        ExteriaRemoteFile *file = content.fullPhotoFile ? content.fullPhotoFile : content.file;
        long long size = content.fullPhotoFile ? content.fullPhotoSize : content.size;
        _request = [_media loadPathForFile:file size:size progress:^(float fraction) {
            ExteriaMediaViewer *me = weak.target;
            if (me && me->_generation == generation) me->_progress.progress = fraction;
        } completion:^(NSString *path) {
            ExteriaMediaViewer *me = weak.target;
            if (!me || me->_closed || me->_generation != generation) return;
            me->_request = 0;
            if (!path) { [me failed]; return; }
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                UIImage *image = [ExteriaDecodeImageAtURL([NSURL fileURLWithPath:path], EXTERIA_VIEWER_PHOTO_SIDE_MAX) retain];
                dispatch_async(dispatch_get_main_queue(), ^{
                    ExteriaMediaViewer *viewer = weak.target;
                    if (viewer && !viewer->_closed && viewer->_generation == generation) {
                        [viewer->_spinner stopAnimating];
                        if (image) { viewer->_photoReady = YES; viewer->_image.image = image; viewer->_more.enabled = viewer->_forward.enabled = viewer->_headerEdit.enabled = YES; [viewer noteOpened]; }
                        else [viewer failed];
                    }
                    [image release];
                });
                [pool drain];
            });
        }];
    } else {
        if (content.previewFile) [_media loadImageForFile:content.previewFile maxSide:640 completion:^(UIImage *image) {
            ExteriaMediaViewer *me = weak.target;
            if (me && !me->_closed && me->_generation == generation && !me->_player) me->_image.image = image;
        }];
        _progress.hidden = NO;
        _request = [_media loadPathForFile:content.file size:content.size progress:^(float fraction) {
            ExteriaMediaViewer *me = weak.target;
            if (me && me->_generation == generation) me->_progress.progress = fraction;
        } completion:^(NSString *path) {
            ExteriaMediaViewer *me = weak.target;
            if (!me || me->_closed || me->_generation != generation) return;
            me->_request = 0; me->_progress.hidden = YES;
            if (path) [me playPath:path]; else [me failed];
        }];
    }
}

- (void)retry {
    ExteriaMedia *content = self.message.media;
    [_media retryFile:content.file]; [_media retryFile:content.fullPhotoFile];
    [self loadCurrent];
}
- (void)failed {
    [self releasePlayer]; [_spinner stopAnimating]; _progress.hidden = YES; _retry.hidden = NO;
    _play.enabled = _seek.enabled = _more.enabled = _forward.enabled = _mute.enabled = _headerEdit.enabled = NO;
}

- (void)playPath:(NSString *)path {
    [_loadedPath release]; _loadedPath = [path copy];
    NSString *slot = [NSString stringWithFormat:@"viewer-%p", self];
    _playableURL = [ExteriaPlayableLink(path, @"mp4", slot) retain];
    if (!_playableURL) { [self failed]; return; }
    [self playURL:_playableURL];
}

- (void)playURL:(NSURL *)url {
    _playerItem = [[AVPlayerItem playerItemWithURL:url] retain];
    _player = [[AVPlayer playerWithPlayerItem:_playerItem] retain];
    ((AVPlayerLayer *)_video.layer).player = _player;
    _observingStatus = YES;
    [_playerItem addObserver:self forKeyPath:@"status" options:0 context:&ExteriaMediaPlayerStatusContext];
    [[ExteriaMusicPlayer sharedPlayer] pauseForMedia];
    if (!ExteriaAudioSessionBeginPlayback()) { [self failed]; return; }
    _wantsPlay = [UIApplication sharedApplication].applicationState == UIApplicationStateActive && !self.presentedViewController;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ended:) name:AVPlayerItemDidPlayToEndTimeNotification object:_playerItem];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:_playerItem];
    ExteriaWeakReference *weak = _weak;
    _timeObserver = [[_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 5) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        (void)time;
        [(ExteriaMediaViewer *)weak.target tick];
    }] retain];
    [_spinner startAnimating];
    if (_wantsPlay) [_player play];
    [self tick];
}

static NSString *ExteriaVideoTime(double seconds) {
    if (!isfinite(seconds) || seconds < 0) seconds = 0;
    NSInteger total = (NSInteger)MIN(seconds, 2147483647);
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &ExteriaMediaPlayerStatusContext) { [super observeValueForKeyPath:keyPath ofObject:object change:change context:context]; return; }
    ExteriaWeakReference *weak = _weak;
    dispatch_async(dispatch_get_main_queue(), ^{
        ExteriaMediaViewer *me = weak.target;
        if (me && me->_playerItem == object) [me tick];
    });
}
- (void)tick {
    if (!_playerItem || _closed) return;
    if (_playerItem.status == AVPlayerItemStatusFailed) { NSLog(@"exteria: video playback failed: %@", _playerItem.error); [self failed]; return; }
    if (_playerItem.status != AVPlayerItemStatusReadyToPlay) return;
    [_spinner stopAnimating]; _image.hidden = NO;
    [self noteOpened];
    _play.enabled = _mute.enabled = YES; _more.enabled = _forward.enabled = _headerEdit.enabled = YES;
    double duration = CMTimeGetSeconds(_playerItem.duration), position = CMTimeGetSeconds(_player.currentTime);
    _seek.enabled = isfinite(duration) && duration > 0;
    if (!isfinite(position) || position < 0) position = 0;
    if (!_scrubbing && _seek.enabled) _seek.value = (float)MAX(0, MIN(1, position / duration));
    _time.text = [NSString stringWithFormat:@"%@ / %@", ExteriaVideoTime(_scrubbing ? _seek.value * duration : position), ExteriaVideoTime(duration)];
    [_playGlyph setIcon:_wantsPlay ? ExteriaMediaIconPause : ExteriaMediaIconPlay animated:YES];
    _play.accessibilityLabel = NSLocalizedString(_wantsPlay ? @"media.pause" : @"media.play", nil);
}
- (void)playbackFailed:(NSNotification *)note { NSLog(@"exteria: video stopped: %@", note.userInfo); [self failed]; }
- (void)ended:(NSNotification *)note {
    (void)note;
    if (self.message.media.kind == EXTERIA_PREVIEW_GIF && !_closed && _wantsPlay) {
        [_player seekToTime:kCMTimeZero]; [_player play];
    } else { _wantsPlay = NO; [_player pause]; }
    [self tick];
}
- (void)togglePlay {
    if (!_player) return;
    [[ExteriaMusicPlayer sharedPlayer] pauseForMedia];
    _wantsPlay = !_wantsPlay;
    if (_wantsPlay) {
        if (!ExteriaAudioSessionBeginPlayback()) { _wantsPlay = NO; [self failed]; return; }
        double end = CMTimeGetSeconds(_playerItem.duration), now = CMTimeGetSeconds(_player.currentTime);
        if (isfinite(end) && now >= end - 0.1) [_player seekToTime:kCMTimeZero];
        [_player play];
    } else [_player pause];
    [self tick];
}
- (void)jump:(int)direction {
    double duration = CMTimeGetSeconds(_playerItem.duration), now = CMTimeGetSeconds(_player.currentTime);
    if (!isfinite(duration) || duration <= 0 || !isfinite(now)) return;
    double target = MAX(0, MIN(duration, now + direction * (double)ExteriaChatSeekSeconds()));
    [_player seekToTime:CMTimeMakeWithSeconds(target, 600)];
    [self tick];
}

/* a volume button raises the sound of a muted video, as the loudspeaker button of a player would */
- (void)volumeChanged:(NSNotification *)note {
    (void)note;
    if (_muted && self.isVideo && ExteriaChatFlagGet(ExteriaChatFlagUnmuteWithVolume)) [self toggleMute];
}

- (void)toggleMute {
    if (!_playerItem) return;
    _muted = !_muted;
    /* AVAudioMix supplies per-item volume on ios 5, before AVPlayer gained muted */
    NSMutableArray *parameters = [NSMutableArray array];
    for (AVAssetTrack *track in [_playerItem.asset tracksWithMediaType:AVMediaTypeAudio]) {
        AVMutableAudioMixInputParameters *input = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
        [input setVolume:_muted ? 0 : 1 atTime:kCMTimeZero]; [parameters addObject:input];
    }
    AVMutableAudioMix *mix = [AVMutableAudioMix audioMix]; mix.inputParameters = parameters;
    _playerItem.audioMix = mix;
    [_mute setImage:ExteriaSymbolImage(_muted ? ExteriaSymbolSpeakerSlash : ExteriaSymbolSpeaker, 23, [UIColor whiteColor]) forState:UIControlStateNormal];
}
- (void)beginSeek { _scrubbing = YES; _resumeAfterSeek = _wantsPlay; [_player pause]; }
- (void)seekChanged { [self tick]; }
- (void)endSeek {
    if (!_playerItem) return;
    double duration = CMTimeGetSeconds(_playerItem.duration);
    if (!_scrubbing || !isfinite(duration) || duration <= 0) return;
    _scrubbing = NO;
    [_player seekToTime:CMTimeMakeWithSeconds(_seek.value * duration, 600)];
    if (_resumeAfterSeek) [_player play];
}
- (void)backgrounded:(NSNotification *)note { (void)note; _wantsPlay = NO; [_player pause]; [self tick]; }

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scroll { return self.isVideo ? nil : _image; }
- (void)scrollViewDidZoom:(UIScrollView *)scroll {
    CGSize size = scroll.bounds.size;
    _image.center = CGPointMake(MAX(size.width, scroll.contentSize.width) / 2, MAX(size.height, scroll.contentSize.height) / 2);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    for (UIView *view = touch.view; view; view = view.superview) if (view == _top || view == _bottom || view == _retry) return NO;
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return _zoom.zoomScale <= 1.001 && ([gesture isKindOfClass:[UISwipeGestureRecognizer class]] || [other isKindOfClass:[UISwipeGestureRecognizer class]] || gesture.view == self.view || other.view == self.view);
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (_paging) return NO;
    if ([gesture isKindOfClass:[UIPanGestureRecognizer class]] && gesture.view == self.view) {
        CGPoint speed = [(UIPanGestureRecognizer *)gesture velocityInView:self.view];
        return _messages.count > 1 && _zoom.zoomScale <= 1.001 && !_captionInput.isFirstResponder && fabs(speed.x) > fabs(speed.y);
    }
    return ![gesture isKindOfClass:[UISwipeGestureRecognizer class]] || (_zoom.zoomScale <= 1.001 && !_captionInput.isFirstResponder);
}
/* a double tap on the outer thirds of a video jumps by the number of seconds the setting names, the middle third pauses or plays */
- (void)doubleTap:(UITapGestureRecognizer *)tap {
    if (self.isVideo) {
        CGFloat x = [tap locationInView:self.view].x, third = self.view.bounds.size.width / 3;
        if (_playerItem && _playerItem.status == AVPlayerItemStatusReadyToPlay && (x < third || x > 2 * third)) [self jump:x < third ? -1 : 1];
        else [self togglePlay];
        return;
    }
    if (_zoom.zoomScale > 1.001) [_zoom setZoomScale:1 animated:YES];
    else {
        CGPoint point = [tap locationInView:_image];
        CGFloat width = _zoom.bounds.size.width / 2.5, height = _zoom.bounds.size.height / 2.5;
        [_zoom zoomToRect:CGRectMake(point.x - width / 2, point.y - height / 2, width, height) animated:YES];
    }
}
- (void)toggleChrome { [self.view endEditing:YES]; _chromeHidden = !_chromeHidden; _top.hidden = _bottom.hidden = _chromeHidden; }
/* with "show next media on tap" a tap near the left or right edge, below the top bar */
- (void)tapped:(UITapGestureRecognizer *)tap {
    if (ExteriaChatNextMediaTap() && _messages.count > 1 && !_captionInput.isFirstResponder) {
        CGPoint point = [tap locationInView:self.view];
        CGFloat width = self.view.bounds.size.width, side = MIN(135.0, width / 8);
        if (point.y > CGRectGetMaxY(_top.frame) + 40) {
            if (point.x < side && _index > 0) { [self previous]; return; }
            if (point.x > width - side && _index + 1 < (NSInteger)_messages.count) { [self next]; return; }
        }
    }
    [self toggleChrome];
}
- (void)swiped:(UISwipeGestureRecognizer *)swipe {
    if (swipe.direction == UISwipeGestureRecognizerDirectionDown) [self close];
    else if (swipe.direction == UISwipeGestureRecognizerDirectionLeft) [self next];
    else [self previous];
}
- (void)cancelPaging {
    [_page.layer removeAllAnimations];
    _page.transform = CGAffineTransformIdentity;
    [_pageTransition removeFromSuperview];
    [_pageTransition release];
    _pageTransition = nil;
    _paging = NO;
}

- (void)pageToIndex:(NSInteger)index {
    if (_closed || _paging || index < 0 || index >= (NSInteger)_messages.count || index == _index) return;
    CGFloat direction = index > _index ? 1 : -1;
    UIImageView *old = [[UIImageView alloc] initWithImage:_image.image];
    old.contentMode = UIViewContentModeScaleAspectFit;
    old.frame = self.view.bounds;
    old.transform = _page.transform;
    [self.view insertSubview:old belowSubview:_top];
    _pageTransition = old;
    _paging = YES;
    _page.transform = CGAffineTransformIdentity;
    _index = index;
    [self loadCurrent];
    CGFloat width = self.view.bounds.size.width;
    _page.transform = CGAffineTransformMakeTranslation(direction * width, 0);
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        old.transform = CGAffineTransformMakeTranslation(-direction * width, 0);
        _page.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        (void)finished;
        [old removeFromSuperview];
        if (_pageTransition == old) {
            [_pageTransition release];
            _pageTransition = nil;
            _paging = NO;
        }
    }];
}

- (void)paged:(UIPanGestureRecognizer *)pan {
    if (_closed || _paging) return;
    CGFloat drag = [pan translationInView:self.view].x;
    BOOL available = drag < 0 ? _index + 1 < (NSInteger)_messages.count : _index > 0;
    if (pan.state == UIGestureRecognizerStateChanged) {
        _page.transform = CGAffineTransformMakeTranslation(available ? drag : drag * 0.25, 0);
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGFloat speed = [pan velocityInView:self.view].x;
        if (pan.state == UIGestureRecognizerStateEnded && available &&
            (fabs(drag) > self.view.bounds.size.width * 0.2 || (fabs(speed) > 500 && speed * drag > 0))) {
            [self pageToIndex:_index + (drag < 0 ? 1 : -1)];
        } else {
            _paging = YES;
            [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.2 animations:^{
                _page.transform = CGAffineTransformIdentity;
            } completion:^(BOOL finished) { (void)finished; _paging = NO; }];
        }
    }
}

- (void)previous { [self pageToIndex:_index - 1]; }
- (void)next { [self pageToIndex:_index + 1]; }
- (void)showMenu {
    if (!_more.enabled) return;
    ExteriaSymbol symbols[] = {ExteriaSymbolArrowDown};
    ExteriaWeakReference *weak = _weak;
    /* sharing has its own button in the bar, so the menu holds what the bar has no button for */
    ExteriaPopupMenu *menu = [[[ExteriaPopupMenu alloc] initWithTitles:[NSArray arrayWithObject:NSLocalizedString(@"media.save", nil)]
        symbols:symbols handler:^(NSUInteger index) {
            (void)index;
            ExteriaMediaViewer *viewer = weak.target;
            if (viewer && !viewer->_closed) [viewer save];
        }] autorelease];
    [menu showInView:self.view anchor:CGPointMake(CGRectGetMaxX(_more.frame) - 8, CGRectGetMaxY(_more.frame))];
}
- (void)forward {
    [self.view endEditing:YES];
    _wantsPlay = NO; [_player pause]; [self tick];
    NSMutableArray *items = [NSMutableArray array];
    if (self.isVideo && _loadedPath) {
        if (_sharePath) [[NSFileManager defaultManager] removeItemAtPath:_sharePath error:NULL];
        [_sharePath release];
        _sharePath = [[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"exteria-share-%08x.mp4", arc4random()]] copy];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] linkItemAtPath:_loadedPath toPath:_sharePath error:&error]) {
            NSLog(@"exteria: cannot stage video for sharing: %@", error); [self notice:NSLocalizedString(@"media.share.failed", nil)]; return;
        }
        [items addObject:[NSURL fileURLWithPath:_sharePath]];
    } else if (_image.image) [items addObject:_image.image];
    if (!items.count) return;
    Class activityClass = NSClassFromString(@"UIActivityViewController");
    if (activityClass) {
        id activity = [[activityClass alloc] initWithActivityItems:items applicationActivities:nil];
        if ([activity respondsToSelector:NSSelectorFromString(@"popoverPresentationController")]) {
            id popover = [activity performSelector:NSSelectorFromString(@"popoverPresentationController")];
            [popover setValue:_top forKey:@"sourceView"];
            [popover setValue:[NSValue valueWithCGRect:_forward.frame] forKey:@"sourceRect"];
        }
        [self presentViewController:activity animated:YES completion:nil]; [activity release];
    } else {
        if (!self.isVideo) {
            if (_sharePath) [[NSFileManager defaultManager] removeItemAtPath:_sharePath error:NULL];
            [_sharePath release];
            _sharePath = [[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"exteria-share-%08x.jpg", arc4random()]] copy];
            if (![UIImageJPEGRepresentation(_image.image, 0.9) writeToFile:_sharePath atomically:YES]) { [self notice:NSLocalizedString(@"media.share.failed", nil)]; return; }
        }
        _document.delegate = nil; [_document release];
        _document = [[UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:_sharePath]] retain];
        _document.delegate = self;
        if (![_document presentOpenInMenuFromRect:_forward.frame inView:_top animated:YES]) [self notice:NSLocalizedString(@"media.share.unavailable", nil)];
    }
}
/* a one-time file that was seen burns before the viewer goes; one that never loaded just leaves, and the message stays as it was */
- (void)close {
    if (!_oneTime || !_opened) { [self closeNow]; return; }
    if (_burning) return;
    _burning = YES;
    [self releasePlayer];
    ExteriaWeakReference *weak = _weak;
    [ExteriaBurnEffect burnRect:self.view.bounds inView:self.view duration:0.9 completion:^{ [(ExteriaMediaViewer *)weak.target closeNow]; }];
    [UIView animateWithDuration:0.8 delay:0.05 options:UIViewAnimationOptionCurveEaseIn animations:^{
        _page.alpha = 0;
        _page.transform = CGAffineTransformMakeScale(1.04, 1.04);
        _top.alpha = 0;
        _bottom.alpha = 0;
    } completion:nil];
}

- (void)closeNow {
    [self cancelPaging];
    if (_closed) return;
    _closed = YES; ++_generation;
    [_media cancelPathRequest:_request]; _request = 0;
    [self releasePlayer]; [self.view endEditing:YES];
    void (^cancel)(void) = [[_cancelHandler copy] autorelease];
    [self dismissViewControllerAnimated:YES completion:^{ if (cancel) cancel(); }];
}
- (void)edit {
    if (!_image.image || self.isVideo || (!self.isSending && !_photoReady)) return;
    ExteriaWeakReference *weak = _weak;
    ExteriaPhotoEditor *editor = [[[ExteriaPhotoEditor alloc] initWithImage:_image.image completion:^(UIImage *image) {
        ExteriaMediaViewer *me = weak.target;
        if (!me || me->_closed) return;
        if (me.isSending) { [me->_localImage release]; me->_localImage = [image retain]; }
        me->_image.image = image;
        [me->_zoom setZoomScale:1 animated:NO]; [me.view setNeedsLayout];
    }] autorelease];
    [self presentViewController:editor animated:YES completion:nil];
}
- (void)send {
    if (_closed) return;
    [self.view endEditing:YES];
    NSString *caption = [[_captionInput.text copy] autorelease];
    void (^photo)(UIImage *, NSString *) = [[_sendPhoto copy] autorelease];
    void (^video)(NSString *) = [[_sendVideo copy] autorelease];
    UIImage *image = [[_localImage retain] autorelease];
    _closed = YES; ++_generation; [self releasePlayer];
    [self dismissViewControllerAnimated:YES completion:^{
        if (photo) photo(image, caption ? caption : @"");
        else if (video) video(caption ? caption : @"");
    }];
}

- (void)notice:(NSString *)text {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:text delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show]; [alert release];
}
- (void)save {
    if (_saving) return;
    if (self.isVideo && _loadedPath) {
        /* a hard link pins the cached movie without copying it on the main thread */
        NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"exteria-save-%08x.mp4", arc4random()]];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] linkItemAtPath:_loadedPath toPath:temporary error:&error]) { NSLog(@"exteria: cannot stage video: %@", error); [self notice:NSLocalizedString(@"media.save.failed", nil)]; return; }
        if (!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(temporary)) {
            [[NSFileManager defaultManager] removeItemAtPath:temporary error:NULL];
            [self notice:NSLocalizedString(@"media.save.failed", nil)]; return;
        }
        _saving = YES; [self retain];
        UISaveVideoAtPathToSavedPhotosAlbum(temporary, self, @selector(video:didFinishSavingWithError:contextInfo:), NULL);
    } else if (_image.image) {
        _saving = YES; [self retain];
        UIImageWriteToSavedPhotosAlbum(_image.image, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
    }
}
- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)context {
    (void)image; (void)context; _saving = NO;
    if (error) NSLog(@"exteria: cannot save photo: %@", error);
    if (!_closed) [self notice:NSLocalizedString(error ? @"media.save.failed" : @"media.saved", nil)];
    [self release];
}
- (void)video:(NSString *)path didFinishSavingWithError:(NSError *)error contextInfo:(void *)context {
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    [self image:nil didFinishSavingWithError:error contextInfo:context];
}
@end
