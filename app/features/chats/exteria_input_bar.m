#import "exteria_input_bar.h"
#import "exteria_animation.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_chat_settings.h"
#import "exteria_classic_chrome.h"
#import "exteria_emoji_text_view.h"
#import "exteria_input_format.h"
#import "exteria_weak_reference.h"
#import "exteria_platform.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define MARGIN 8.0
/* on an ipad the one line bar is as tall as the tab bar beside it (49 points), so the tops of the two bars stand on one line */
#define MARGIN_PAD 6.5

static CGFloat ExteriaInputVerticalMargin(void) {
    return ExteriaIsPad() ? MARGIN_PAD : MARGIN;
}

/* the bar that has a button or a note in place of the field, as tall as the one line bar */
static CGFloat ExteriaInputIdleHeight(void) {
    return ExteriaIsPad() ? 49 : 48;
}
#define FIELD_MIN 36.0
#define FIELD_MAX 112.0
#define BUTTON 36.0
#define PANEL_BUTTON_WIDTH 36.0
/* how far the finger slides left before the recording counts as thrown away */
#define SLIDE_CANCEL 90.0
/* how far the finger rises before the recording locks and keeps going without the hold */
#define LOCK_DISTANCE 70.0
/* a hold that ends this soon after it began locks the recording instead of ending it; a swipe up is the only other way to lock, and a gesture tweak on the phone
   takes that swipe for itself */
#define QUICK_LOCK_SECONDS 0.5

static NSString *const ExteriaRecordModeKey = @"ExteriaRecordMode";

@interface ExteriaInputBar () {
    UIView *_field;
    ExteriaEmojiTextView *_text;
    UILabel *_placeholder;
    UIButton *_panelButton;
    UIButton *_attachButton;
    UIButton *_send;
    UILongPressGestureRecognizer *_hold;
    UIView *_recording;
    UIView *_dot;
    UILabel *_timer;
    UILabel *_slide;
    UIView *_lockView;
    UIImageView *_lockIcon;
    UIButton *_cancelLocked;
    BOOL _locked;
    UIButton *_onceChip;
    BOOL _oneTimeRecording;
    BOOL _lockedRecording;
    BOOL _raisedRecording;
    BOOL _sendShowsPlane;
    CGFloat _holdStartY;
    ExteriaRecordMode _mode;
    BOOL _holding;
    BOOL _slidAway;
    CFTimeInterval _holdBeganAt;
    CGFloat _holdStart;
    UIView *_hairline;
    UIToolbar *_toolbar;
    UILabel *_note;
    CGFloat _fieldHeight;
    BOOL _writable;
    NSString *_readOnlyNote;
    NSMutableArray *_custom;
    ExteriaInputFormat *_format;
    ExteriaWeakReference *_weak;
    UIButton *_botButton;
    UIButton *_menuPill;
    UIControl *_senderButton;
    ExteriaAvatarView *_senderAvatar;
    BOOL _senderVisible;
    UIButton *_actionButton;
    NSString *_placeholderText;
    NSString *_menuTitle;
    NSString *_actionTitle;
    BOOL _actionWithInput;
    ExteriaBotKeyboardState _botState;
}
@end

@implementation ExteriaInputBar

@synthesize delegate = _delegate;
@synthesize textView = _text;
@synthesize writable = _writable;
@synthesize readOnlyNote = _readOnlyNote;
@synthesize placeholderText = _placeholderText;
@synthesize senderAvatar = _senderAvatar;
@synthesize menuTitle = _menuTitle;
@synthesize botKeyboardState = _botState;
@synthesize actionTitle = _actionTitle;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    BOOL classic = ExteriaThemeIsClassic();
    self.backgroundColor = classic ? [UIColor clearColor] : ExteriaColorBar();
    if (classic) {
        /* the bar's surface is the system's own toolbar, whatever the system draws a toolbar as */
        _toolbar = [[UIToolbar alloc] init];
        ExteriaClassicStyleToolbar(_toolbar);
        _toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_toolbar];
    }
    _writable = YES;
    _fieldHeight = FIELD_MIN;
    _hairline = [[UIView alloc] init];
    _hairline.backgroundColor = ExteriaColorHairline();
    _hairline.hidden = classic;
    [self addSubview:_hairline];

    _field = [[UIView alloc] init];
    _field.backgroundColor = classic ? (ExteriaThemeIsDark() ? [UIColor colorWithWhite:0.23 alpha:1] : [UIColor whiteColor]) : ExteriaColorField();
    _field.layer.cornerRadius = FIELD_MIN / 2;
    if (classic) {
        /* the thin gray outline of the text box of the old messaging bars */
        _field.layer.borderWidth = 1;
        _field.layer.borderColor = (ExteriaThemeIsDark() ? [UIColor colorWithWhite:0.1 alpha:1] : [UIColor colorWithWhite:0.62 alpha:1]).CGColor;
    }
    [self addSubview:_field];

    _text = [[ExteriaEmojiTextView alloc] initWithFrame:CGRectZero];
    _text.emojiBackgroundColor = _field.backgroundColor;
    _text.backgroundColor = [UIColor clearColor];
    _text.font = ExteriaFontRegular(16);
    _text.textColor = ExteriaColorTitle();
    _text.delegate = self;
    _text.scrollsToTop = NO;
    _text.scrollEnabled = NO;
    _text.showsHorizontalScrollIndicator = NO;
    _text.keyboardAppearance = ExteriaThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    /* tintColor came with ios 7, and the ios 6.1 headers the build checks against do not know it */
    if ([_text respondsToSelector:@selector(setTintColor:)]) [_text setValue:ExteriaColorAccent() forKey:@"tintColor"];
    [_field addSubview:_text];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _format = [[ExteriaInputFormat alloc] initWithTextView:_text];
    ExteriaWeakReference *weak = _weak;
    _format.changed = ^{ ExteriaInputBar *bar = weak.target; [bar textViewDidChange:bar->_text]; };
    /* a translation lands as typing would: the runs after it move and the delegate hears of the change */
    _format.replace = ^(NSRange range, NSString *text) { [(ExteriaInputBar *)weak.target replaceRange:range withText:text]; };
    _text.formatHandler = ^{ [[(ExteriaInputBar *)weak.target formatter] presentMenu]; };

    _placeholder = [[UILabel alloc] init];
    _placeholder.backgroundColor = [UIColor clearColor];
    _placeholder.font = ExteriaFontRegular(16);
    _placeholder.textColor = ExteriaColorMuted();
    _placeholder.text = NSLocalizedString(@"chat.placeholder", nil);
    _placeholder.userInteractionEnabled = NO;
    [_field addSubview:_placeholder];

    _panelButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_panelButton addTarget:self action:@selector(panelTapped) forControlEvents:UIControlEventTouchUpInside];
    _panelButton.accessibilityLabel = NSLocalizedString(@"chat.panel", nil);
    [_field addSubview:_panelButton];

    _attachButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_attachButton addTarget:self action:@selector(attachTapped) forControlEvents:UIControlEventTouchUpInside];
    _attachButton.accessibilityLabel = NSLocalizedString(@"chat.attach", nil);
    [_field addSubview:_attachButton];

    _botButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_botButton addTarget:self action:@selector(botKeyboardTapped) forControlEvents:UIControlEventTouchUpInside];
    _botButton.accessibilityLabel = NSLocalizedString(@"bots.keyboard", nil);
    _botButton.hidden = YES;
    [_field addSubview:_botButton];

    /* the bot's menu stands outside the field, as a pill on the bar */
    _menuPill = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _menuPill.titleLabel.font = ExteriaFontSemibold(15);
    _menuPill.backgroundColor = ExteriaColorAccent();
    _menuPill.layer.cornerRadius = FIELD_MIN / 2;
    [_menuPill setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_menuPill addTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
    _menuPill.hidden = YES;
    [self addSubview:_menuPill];
    /* who the message is sent as, in a chat that lets the account choose: the picture of the identity, a tap offers the others */
    _senderButton = [[UIControl alloc] init];
    _senderButton.hidden = YES;
    _senderButton.accessibilityLabel = NSLocalizedString(@"chat.sendas", nil);
    [_senderButton addTarget:self action:@selector(senderTapped) forControlEvents:UIControlEventTouchUpInside];
    _senderAvatar = [[ExteriaAvatarView alloc] initWithFrame:CGRectMake(0, 0, FIELD_MIN, FIELD_MIN)];
    _senderAvatar.circular = YES;
    _senderAvatar.userInteractionEnabled = NO;
    [_senderButton addSubview:_senderAvatar];
    [self addSubview:_senderButton];

    _actionButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _actionButton.titleLabel.font = ExteriaFontSemibold(17);
    [_actionButton setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_actionButton addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
    _actionButton.hidden = YES;
    [self addSubview:_actionButton];

    _mode = (ExteriaRecordMode)[[NSUserDefaults standardUserDefaults] integerForKey:ExteriaRecordModeKey];
    if (_mode != ExteriaRecordRound) _mode = ExteriaRecordVoice;
    _send = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    /* the classic button is a bitmap of its own, see refreshControls */
    if (!classic) {
        _send.backgroundColor = ExteriaColorAccent();
        _send.layer.cornerRadius = BUTTON / 2;
    }
    [_send addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    /* the chip sits on the corner of the record button and is a control of its own, so a tap on it never starts the hold of the button */
    _onceChip = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _onceChip.titleLabel.font = ExteriaFontBold(12);
    [_onceChip setTitle:@"1" forState:UIControlStateNormal];
    _onceChip.layer.cornerRadius = 11;
    _onceChip.layer.borderWidth = 1.5;
    _onceChip.accessibilityLabel = NSLocalizedString(@"chat.record.once", nil);
    [_onceChip addTarget:self action:@selector(onceChipTapped) forControlEvents:UIControlEventTouchUpInside];
    [self refreshOnceChip];
    _hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)];
    _hold.minimumPressDuration = 0.25;
    /* the finger travels left to cancel, and a short move limit would end the hold before that */
    _hold.allowableMovement = 1000;
    [_send addGestureRecognizer:_hold];
    [self addSubview:_send];
    [self addSubview:_onceChip];

    _recording = [[UIView alloc] init];
    _recording.backgroundColor = _field.backgroundColor;
    _recording.layer.cornerRadius = FIELD_MIN / 2;
    _recording.hidden = YES;
    _dot = [[UIView alloc] init];
    _dot.backgroundColor = [UIColor colorWithRed:0.92 green:0.22 blue:0.22 alpha:1];
    _dot.layer.cornerRadius = 5;
    [_recording addSubview:_dot];
    _timer = [[UILabel alloc] init];
    _timer.backgroundColor = [UIColor clearColor];
    _timer.font = ExteriaFontMedium(16);
    _timer.textColor = ExteriaThemeIsClassic() && !ExteriaThemeIsDark() ? [UIColor blackColor] : ExteriaColorTitle();
    [_recording addSubview:_timer];
    _slide = [[UILabel alloc] init];
    _slide.backgroundColor = [UIColor clearColor];
    _slide.font = ExteriaFontRegular(15);
    _slide.textColor = ExteriaColorSecondary();
    _slide.textAlignment = ExteriaTextAlignmentRight;
    _slide.text = NSLocalizedString(@"chat.record.slide", nil);
    [_recording addSubview:_slide];
    _cancelLocked = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_cancelLocked setTitle:NSLocalizedString(@"attach.cancel", nil) forState:UIControlStateNormal];
    [_cancelLocked setTitleColor:[UIColor colorWithRed:0.92 green:0.22 blue:0.22 alpha:1] forState:UIControlStateNormal];
    _cancelLocked.titleLabel.font = ExteriaFontSemibold(16);
    _cancelLocked.hidden = YES;
    [_cancelLocked addTarget:self action:@selector(cancelLockedTapped) forControlEvents:UIControlEventTouchUpInside];
    [_recording addSubview:_cancelLocked];
    [self addSubview:_recording];

    /* the lock rises above the button while it is held; a finger that reaches it closes it */
    _lockView = [[UIView alloc] init];
    _lockView.backgroundColor = _field.backgroundColor;
    _lockView.layer.cornerRadius = 20;
    _lockView.layer.borderWidth = 1;
    _lockView.layer.borderColor = ExteriaColorHairline().CGColor;
    _lockView.alpha = 0;
    _lockView.hidden = YES;
    /* a second finger that taps the lock while the first one holds the button closes it; the view stands above the bar, so pointInside: lets the touch in */
    _lockView.userInteractionEnabled = YES;
    [_lockView addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(lockTapped)] autorelease]];
    _lockIcon = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolLock, 22, ExteriaColorSecondary())];
    _lockIcon.contentMode = UIViewContentModeCenter;
    _lockIcon.frame = CGRectMake(0, 6, 40, 30);
    [_lockView addSubview:_lockIcon];
    UIImageView *chevron = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolChevronRight, 16, ExteriaColorMuted())] autorelease];
    chevron.contentMode = UIViewContentModeCenter;
    chevron.frame = CGRectMake(0, 38, 40, 24);
    chevron.transform = CGAffineTransformMakeRotation((CGFloat)-M_PI_2);
    [_lockView addSubview:chevron];
    [self addSubview:_lockView];

    _note = [[UILabel alloc] init];
    _note.backgroundColor = [UIColor clearColor];
    _note.textColor = ExteriaColorSecondary();
    _note.textAlignment = ExteriaTextAlignmentCenter;
    _note.font = ExteriaFontRegular(15);
    _note.hidden = YES;
    [self addSubview:_note];
    [self refreshControls];
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateTextHeight) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(lockTapped) object:nil];
    [_weak clear];
    [_weak release];
    _text.formatHandler = nil;
    [_format release];
    [_custom release];
    _text.delegate = nil;
    [_field release];
    [_text release];
    [_placeholder release];
    [_panelButton release];
    [_attachButton release];
    [_botButton release];
    [_menuPill release];
    [_senderButton release];
    [_senderAvatar release];
    [_actionButton release];
    [_placeholderText release];
    [_menuTitle release];
    [_actionTitle release];
    [_send release];
    [_hold release];
    [_onceChip release];
    [_recording release];
    [_dot release];
    [_timer release];
    [_slide release];
    [_lockView release];
    [_lockIcon release];
    [_cancelLocked release];
    [_hairline release];
    [_toolbar release];
    [_note release];
    [_readOnlyNote release];
    [super dealloc];
}

- (void)setPanelShown:(BOOL)shown {
    _panelShown = shown;
    [self refreshControls];
}

- (BOOL)panelShown {
    return _panelShown;
}

- (void)setWritable:(BOOL)writable {
    _writable = writable;
    _recording.hidden = YES;
    [self applyVisibility];
}

/* the field and its buttons, the note of a chat that cannot be written in and the wide button each have their turn */
- (void)applyVisibility {
    BOOL action = _actionTitle.length > 0 && (!_actionWithInput || !_writable);
    _note.hidden = _writable || action;
    _field.hidden = !_writable || action;
    _send.hidden = !_writable || action;
    _menuPill.hidden = !_writable || action || !_menuTitle.length;
    _senderButton.hidden = !_writable || action || !_senderVisible;
    _actionButton.hidden = !_actionTitle.length;
    [self setNeedsLayout];
}

- (BOOL)actionWithInput { return _actionWithInput; }

- (void)setActionWithInput:(BOOL)value {
    if (_actionWithInput == value) return;
    _actionWithInput = value;
    [self applyVisibility];
    [_delegate inputBarDidChangeHeight:self];
}

- (void)setActionTitle:(NSString *)title {
    if (title == _actionTitle || [title isEqualToString:_actionTitle]) return;
    [_actionTitle release];
    _actionTitle = [title copy];
    [_actionButton setTitle:_actionTitle forState:UIControlStateNormal];
    [self applyVisibility];
    [_delegate inputBarDidChangeHeight:self];
}

- (void)setMenuTitle:(NSString *)title {
    if (title == _menuTitle || [title isEqualToString:_menuTitle]) return;
    [_menuTitle release];
    _menuTitle = [title copy];
    [_menuPill setTitle:_menuTitle forState:UIControlStateNormal];
    [self applyVisibility];
}

- (void)setPlaceholderText:(NSString *)text {
    if (text == _placeholderText || [text isEqualToString:_placeholderText]) return;
    [_placeholderText release];
    _placeholderText = [text copy];
    _placeholder.text = _placeholderText.length ? _placeholderText : NSLocalizedString(@"chat.placeholder", nil);
}

- (void)setBotKeyboardState:(ExteriaBotKeyboardState)state {
    _botState = state;
    _botButton.hidden = state == ExteriaBotKeyboardNone;
    [self refreshControls];
    [self setNeedsLayout];
}

- (BOOL)senderVisible {
    return _senderVisible;
}

- (void)setSenderVisible:(BOOL)visible {
    if (visible == _senderVisible) return;
    _senderVisible = visible;
    [self applyVisibility];
}

- (void)senderTapped {
    if ([_delegate respondsToSelector:@selector(inputBarDidTapSender:)]) [_delegate inputBarDidTapSender:self];
}

- (void)menuTapped {
    if ([_delegate respondsToSelector:@selector(inputBarDidTapMenu:)]) [_delegate inputBarDidTapMenu:self];
}

- (void)botKeyboardTapped {
    if ([_delegate respondsToSelector:@selector(inputBarDidTapBotKeyboard:)]) [_delegate inputBarDidTapBotKeyboard:self];
}

- (void)actionTapped {
    if ([_delegate respondsToSelector:@selector(inputBarDidTapAction:)]) [_delegate inputBarDidTapAction:self];
}


- (void)setReadOnlyNote:(NSString *)note {
    if (note == _readOnlyNote || [note isEqualToString:_readOnlyNote]) return;
    [_readOnlyNote release];
    _readOnlyNote = [note copy];
    _note.text = _readOnlyNote;
}

- (void)refreshControls {
    UIColor *glyph = ExteriaColorSecondary();
    [_panelButton setImage:ExteriaSymbolImage(_panelShown ? ExteriaSymbolKeyboard : ExteriaSymbolSmiley, 24, glyph) forState:UIControlStateNormal];
    [_attachButton setImage:ExteriaSymbolImage(ExteriaSymbolPaperclip, 24, glyph) forState:UIControlStateNormal];
    [_botButton setImage:_botState == ExteriaBotKeyboardOpen ? ExteriaSymbolImage(ExteriaSymbolKeyboard, 24, glyph) : ExteriaSymbolImage(ExteriaSymbolApps, 24, glyph) forState:UIControlStateNormal];
    BOOL empty = [[self trimmedText] length] == 0;
    _placeholder.hidden = _text.text.length > 0;
    /* the clip steps aside once there are words in the field, and the text takes its room */
    if (_attachButton.hidden != (_text.text.length > 0)) {
        _attachButton.hidden = _text.text.length > 0;
        [self setNeedsLayout];
    }
    _hold.enabled = empty && !_lockedRecording;
    _onceChip.hidden = !empty || _lockedRecording || _holding || !_writable;
    BOOL plane = !empty || _lockedRecording;
    ExteriaSymbol symbol = plane ? ExteriaSymbolSendArrow : (_mode == ExteriaRecordRound ? ExteriaSymbolVideoCamera : ExteriaSymbolMicrophone);
    if (ExteriaThemeIsClassic()) {
        [_send setImage:ExteriaClassicRoundButtonImage(symbol, BUTTON, NO) forState:UIControlStateNormal];
        [_send setImage:ExteriaClassicRoundButtonImage(symbol, BUTTON, YES) forState:UIControlStateHighlighted];
    } else {
        [_send setImage:ExteriaSymbolImage(symbol, !empty ? 18 : 20, [UIColor whiteColor]) forState:UIControlStateNormal];
    }
    /* the glyph pops in when the field gains its first character or loses its last, never during a recording whose gesture owns the button */
    if (plane != _sendShowsPlane) {
        _sendShowsPlane = plane;
        if (CGAffineTransformIsIdentity(_send.transform) && !_holding && !_lockedRecording && self.window) {
            /* the sampled spring runs the same on ios 5, where the system's springs are absent */
            ExteriaAnimateEnter(_send.imageView, CGAffineTransformMakeScale(0.2, 0.2), 0, EXTERIA_MOTION_SPRING);
        }
    }
    _send.accessibilityLabel = !empty ? NSLocalizedString(@"chat.send", nil)
        : NSLocalizedString(_mode == ExteriaRecordRound ? @"chat.record.round" : @"chat.record.voice", nil);
    /* setting the text view color again removes range styles */
    UIColor *ink = ExteriaThemeIsClassic() && !ExteriaThemeIsDark() ? [UIColor blackColor] : ExteriaColorTitle();
    if (![_text.textColor isEqual:ink]) {
        _text.textColor = ink;
        [_format refreshAppearance];
    }
}

/* keeps the custom emoji runs on the characters they were typed for; a run before the edit stays, one after it
   moves by the change in length, and one the edit touches is no longer a whole emoji, so it turns into plain text */
- (void)shiftCustomForRange:(NSRange)range replacementLength:(NSUInteger)length {
    if (!_custom.count) return;
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:_custom.count];
    for (ExteriaTextEntity *run in _custom) {
        NSRange at = run.range;
        if (NSMaxRange(at) <= range.location) {
            [kept addObject:run];
        } else if (at.location >= NSMaxRange(range)) {
            NSRange moved = NSMakeRange(at.location - range.length + length, at.length);
            ExteriaTextEntity *entity = [[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleCustomEmoji range:moved url:nil];
            entity.documentId = run.documentId;
            [kept addObject:entity];
            [entity release];
        }
    }
    [_custom setArray:kept];
}

- (BOOL)textView:(UITextView *)view shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)replacement {
    (void)view;
    /* with "Send by Enter" the return key sends the message, and on an empty field it does nothing rather than start the text with a blank line */
    if (ExteriaChatSendByEnter() && [replacement isEqualToString:@"\n"]) {
        if ([[self trimmedText] length]) [_delegate inputBarDidTapSend:self];
        return NO;
    }
    [self shiftCustomForRange:range replacementLength:replacement.length];
    [_format shiftForRange:range replacementLength:replacement.length];
    return YES;
}

- (void)insertCustomEmoji:(long long)documentId alt:(NSString *)alt {
    if (!documentId || !alt.length) return;
    if (!_custom) _custom = [[NSMutableArray alloc] init];
    NSRange selection = _text.selectedRange;
    [_text insertText:alt];
    ExteriaTextEntity *entity = [[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleCustomEmoji range:NSMakeRange(selection.location, alt.length) url:nil];
    entity.documentId = documentId;
    [_custom addObject:entity];
    [entity release];
}

- (void)replaceRange:(NSRange)range withText:(NSString *)replacement {
    NSString *current = _text.text;
    if (!replacement || NSMaxRange(range) > current.length) return;
    [self shiftCustomForRange:range replacementLength:replacement.length];
    [_format shiftForRange:range replacementLength:replacement.length];
    _text.text = [current stringByReplacingCharactersInRange:range withString:replacement];
    _text.selectedRange = NSMakeRange(range.location + replacement.length, 0);
    [self textViewDidChange:_text];
}

- (void)insertEmoji:(NSString *)emoji {
    [_text insertText:emoji];
    [self textViewDidChange:_text];
}

- (void)deleteBackwardFromPicker {
    [_text deleteBackward];
    [self textViewDidChange:_text];
}

- (ExteriaInputFormat *)formatter {
    return _format;
}

- (ExteriaSession *)session {
    return _format.session;
}

- (void)setSession:(ExteriaSession *)session {
    _format.session = session;
}

- (UIView *)formatHost {
    return _format.host;
}

- (void)setFormatHost:(UIView *)host {
    _format.host = host;
}

- (NSArray *)sendEntities {
    NSString *raw = _text.text;
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSUInteger lead = 0, length = [self trimmedText].length;
    while (lead < raw.length && [space characterIsMember:[raw characterAtIndex:lead]]) ++lead;
    NSMutableArray *entities = [NSMutableArray arrayWithCapacity:_custom.count];
    for (ExteriaTextEntity *run in _custom) {
        NSRange at = run.range;
        if (at.location < lead || NSMaxRange(at) > lead + length) continue;
        ExteriaTextEntity *entity = [[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleCustomEmoji range:NSMakeRange(at.location - lead, at.length) url:nil];
        entity.documentId = run.documentId;
        [entities addObject:entity];
        [entity release];
    }
    [entities addObjectsFromArray:[_format entitiesAfterLead:lead length:length]];
    return entities;
}

- (NSString *)trimmedText {
    return [_text.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)clear {
    [_custom removeAllObjects];
    [_format reset];
    _text.text = @"";
    [self textViewDidChange:_text];
}

- (void)setText:(NSString *)text entities:(NSArray *)entities {
    [_custom removeAllObjects];
    [_format reset];
    _text.text = text ? text : @"";
    NSUInteger length = _text.text.length;
    NSMutableArray *styled = [NSMutableArray arrayWithCapacity:entities.count];
    for (ExteriaTextEntity *entity in entities) {
        if (NSMaxRange(entity.range) > length) continue;
        if (entity.style != ExteriaTextStyleCustomEmoji) {
            [styled addObject:entity];
        } else if (entity.documentId) {
            if (!_custom) _custom = [[NSMutableArray alloc] init];
            [_custom addObject:entity];
        }
    }
    [_format restoreEntities:styled];
    _text.selectedRange = NSMakeRange(length, 0);
    [self textViewDidChange:_text];
}

/* the height the text takes, with the field's own insets: ios 7 lays text out in a container, before that the view
   keeps it in its content size */
- (CGFloat)textHeight {
    CGFloat width = _text.bounds.size.width > 0 ? _text.bounds.size.width : 200;
    if ([_text respondsToSelector:@selector(textContainer)]) return ceil([_text sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
    return ceil(_text.contentSize.height);
}

- (CGFloat)preferredHeight {
    if (!_writable || (_actionTitle.length && !_actionWithInput)) return ExteriaInputIdleHeight();
    CGFloat height = MIN(FIELD_MAX, MAX(FIELD_MIN, [self textHeight] + 1));
    return height + 2 * ExteriaInputVerticalMargin() + (_actionTitle.length && _actionWithInput ? ExteriaInputIdleHeight() : 0);
}

- (void)textViewDidChange:(UITextView *)view {
    (void)view;
    [self refreshControls];
    /* after the controls, since setting the text color there would take the styles off again */
    [_format refreshAppearance];
    [_text refreshEmoji];
    if ([_delegate respondsToSelector:@selector(inputBarDidChangeText:)]) [_delegate inputBarDidChangeText:self];
    [self updateTextHeight];
}

- (void)updateTextHeight {
    CGFloat height = [self textHeight];
    CGFloat want = MIN(FIELD_MAX, MAX(FIELD_MIN, height + 1));
    _text.scrollEnabled = height > FIELD_MAX;
    if (want != _fieldHeight) {
        _fieldHeight = want;
        [_delegate inputBarDidChangeHeight:self];
    }
}

- (void)textViewDidChangeSelection:(UITextView *)view {
    (void)view;
    [_text refreshEmoji];
}

- (void)textViewDidBeginEditing:(UITextView *)view {
    (void)view;
    [_delegate inputBarDidBeginEditing:self];
}

- (void)refreshOnceChip {
    UIColor *accent = ExteriaColorAccent();
    _onceChip.backgroundColor = _oneTimeRecording ? accent : ExteriaColorField();
    _onceChip.layer.borderColor = (_oneTimeRecording ? accent : ExteriaColorSecondary()).CGColor;
    [_onceChip setTitleColor:_oneTimeRecording ? [UIColor whiteColor] : ExteriaColorSecondary() forState:UIControlStateNormal];
}

- (void)onceChipTapped {
    _oneTimeRecording = !_oneTimeRecording;
    [self refreshOnceChip];
    _onceChip.transform = CGAffineTransformMakeScale(0.7, 0.7);
    [UIView animateWithDuration:0.18 animations:^{ _onceChip.transform = CGAffineTransformIdentity; }];
}

- (BOOL)oneTimeRecording { return _oneTimeRecording; }

- (void)clearOneTimeRecording {
    if (!_oneTimeRecording) return;
    _oneTimeRecording = NO;
    [self refreshOnceChip];
}

- (void)attachTapped {
    [_delegate inputBarDidTapAttach:self];
}

- (void)panelTapped {
    [_delegate inputBarDidTapPanelButton:self];
}

- (void)sendTapped {
    if (_lockedRecording) {
        [self endLockedCancelled:NO];
        return;
    }
    if ([[self trimmedText] length]) {
        [_delegate inputBarDidTapSend:self];
        return;
    }
    /* an empty field turns the tap into a swap between the two kinds of recording */
    _mode = _mode == ExteriaRecordVoice ? ExteriaRecordRound : ExteriaRecordVoice;
    [[NSUserDefaults standardUserDefaults] setInteger:_mode forKey:ExteriaRecordModeKey];
    [UIView transitionWithView:_send duration:0.25 options:UIViewAnimationOptionTransitionFlipFromBottom
                    animations:^{ [self refreshControls]; } completion:nil];
}

- (void)setRecordingElapsed:(NSTimeInterval)elapsed {
    int tenths = (int)(elapsed * 10);
    _timer.text = [NSString stringWithFormat:@"%d:%02d,%d", tenths / 600, (tenths / 10) % 60, tenths % 10];
}

/* the field gives way to the timer strip, which slides in from the left, while the button swells past its size and settles */
- (void)showRecordingAnimated {
    _onceChip.hidden = YES;
    _recording.hidden = NO;
    _recording.alpha = 0;
    _recording.transform = CGAffineTransformMakeTranslation(-48, 0);
    CGRect button = _send.frame;
    _lockView.frame = CGRectMake(CGRectGetMidX(button) - 20, button.origin.y - 124, 40, 66);
    _lockView.transform = CGAffineTransformMakeTranslation(0, 24);
    _lockView.hidden = NO;
    _lockView.alpha = 0;
    [UIView animateWithDuration:0.2 delay:0.05 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _lockView.alpha = 1;
        _lockView.transform = CGAffineTransformIdentity;
    } completion:nil];
    _slide.transform = CGAffineTransformIdentity;
    _slide.alpha = 1;
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = [NSNumber numberWithFloat:1];
    pulse.toValue = [NSNumber numberWithFloat:0.2];
    pulse.duration = 0.6;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    [_dot.layer addAnimation:pulse forKey:@"pulse"];
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _recording.alpha = 1;
        _recording.transform = CGAffineTransformIdentity;
        _field.alpha = 0;
    } completion:^(BOOL finished) {
        (void)finished;
        if (_holding) _field.hidden = YES;
    }];
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _send.transform = CGAffineTransformMakeScale(1.75, 1.75);
    } completion:^(BOOL finished) {
        (void)finished;
        if (!_holding) return;
        [UIView animateWithDuration:0.1 animations:^{ _send.transform = CGAffineTransformMakeScale(1.5, 1.5); }];
    }];
}

/* a sent recording slides off to the left; a thrown away one drops its dot and fades where it is */
- (void)hideRecordingCancelled:(BOOL)cancelled {
    [_dot.layer removeAnimationForKey:@"pulse"];
    if (cancelled) {
        /* the can takes the dot's place at once, so no red shape is left shrinking behind it */
        _dot.hidden = YES;
        [self dropDotIntoTrash];
    }
    _field.hidden = !_writable;
    /* the field comes back once the can has shut: its smiley button sits where the can drops and showed through it before */
    if (cancelled) _field.alpha = 0;
    [UIView animateWithDuration:cancelled ? 0.25 : 0.18 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        if (!cancelled) _field.alpha = 1;
        _recording.alpha = 0;
        if (!cancelled) _recording.transform = CGAffineTransformMakeTranslation(-48, 0);
        _send.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        (void)finished;
        _dot.transform = CGAffineTransformIdentity;
        _dot.hidden = NO;
        if (!_holding) _recording.hidden = YES;
        _recording.transform = CGAffineTransformIdentity;
        [self refreshControls];
    }];
    _slide.textColor = ExteriaColorSecondary();
}

/* the red dot turns into a trash can whose lid opens and shuts, then the can fades; it lives in the bar itself, because the
   strip that held the dot is already fading out */
- (void)dropDotIntoTrash {
    CGFloat side = 26;
    UIColor *red = [UIColor colorWithRed:0.92 green:0.22 blue:0.22 alpha:1];
    CGPoint center = [_recording convertPoint:_dot.center toView:self];
    UIView *trash = [[[UIView alloc] initWithFrame:CGRectMake(center.x - side / 2, center.y - side / 2, side, side)] autorelease];
    trash.userInteractionEnabled = NO;
    UIImageView *can = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolTrashCan, side, red)] autorelease];
    UIImageView *lid = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolTrashLid, side, red)] autorelease];
    can.frame = trash.bounds;
    /* the lid turns about its left end, which is where the bar meets the can */
    lid.layer.anchorPoint = CGPointMake(0.16, 0.23);
    lid.frame = trash.bounds;
    [trash addSubview:can];
    [trash addSubview:lid];
    trash.alpha = 0;
    trash.transform = CGAffineTransformMakeScale(0.4, 0.4);
    [self addSubview:trash];
    [UIView animateWithDuration:0.14 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        trash.alpha = 1;
        trash.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        (void)finished;
        [UIView animateWithDuration:0.16 animations:^{ lid.transform = CGAffineTransformMakeRotation(-0.7); } completion:^(BOOL opened) {
            (void)opened;
            [UIView animateWithDuration:0.14 animations:^{ lid.transform = CGAffineTransformIdentity; } completion:^(BOOL shut) {
                (void)shut;
                [UIView animateWithDuration:0.2 delay:0.1 options:0 animations:^{
                    trash.alpha = 0;
                    if (!_holding) _field.alpha = 1;
                } completion:^(BOOL gone) {
                    (void)gone;
                    [trash removeFromSuperview];
                }];
            }];
        }];
    }];
}

- (CGPoint)recordButtonCenterInView:(UIView *)view {
    CGPoint center = CGPointMake(CGRectGetMidX(_send.bounds), CGRectGetMidY(_send.bounds));
    return [_send convertPoint:center toView:view];
}

- (void)hideLockAnimated {
    [UIView animateWithDuration:0.15 animations:^{ _lockView.alpha = 0; } completion:^(BOOL finished) {
        (void)finished;
        _lockView.hidden = YES;
        _lockView.transform = CGAffineTransformIdentity;
        _lockIcon.image = ExteriaSymbolImage(ExteriaSymbolLock, 22, ExteriaColorSecondary());
    }];
}

/* the finger came up on the lock: the recording goes on by itself, the button becomes the send button and a cancel appears */
- (void)enterLockedRecording {
    _lockedRecording = YES;
    _locked = NO;
    _field.hidden = YES;
    _field.alpha = 0;
    [self hideLockAnimated];
    _slide.hidden = YES;
    _cancelLocked.hidden = NO;
    _cancelLocked.alpha = 0;
    [UIView animateWithDuration:0.18 animations:^{
        _cancelLocked.alpha = 1;
        _send.transform = CGAffineTransformIdentity;
    }];
    [self refreshControls];
    [self setNeedsLayout];
}

- (void)lockTapped {
    if (!_holding || _raisedRecording || _lockedRecording || _slidAway) return;
    _holding = NO;
    [self enterLockedRecording];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (!_lockView.hidden && _lockView.alpha > 0.01f && CGRectContainsPoint(_lockView.frame, point)) return YES;
    return [super pointInside:point withEvent:event];
}

- (void)endLockedCancelled:(BOOL)cancelled {
    if (!_lockedRecording) return;
    _lockedRecording = NO;
    _cancelLocked.hidden = YES;
    _slide.hidden = NO;
    [self refreshControls];
    [self hideRecordingCancelled:cancelled];
    [_delegate inputBar:self didFinishRecordingCancelled:cancelled];
}

- (void)cancelLockedTapped {
    [self endLockedCancelled:YES];
}

- (BOOL)beginRaisedRecording {
    if (_holding || _lockedRecording || _raisedRecording || !_hold.enabled || [[self trimmedText] length]) return NO;
    if (![_delegate inputBar:self didBeginRecording:ExteriaRecordVoice]) return NO;
    _raisedRecording = YES;
    _holding = YES;
    _slidAway = NO;
    _locked = NO;
    [self setRecordingElapsed:0];
    [self showRecordingAnimated];
    return YES;
}

- (void)endRaisedRecordingCancelled:(BOOL)cancelled {
    if (!_raisedRecording) return;
    _raisedRecording = NO;
    _holding = NO;
    [self hideLockAnimated];
    [self hideRecordingCancelled:cancelled];
    [_delegate inputBar:self didFinishRecordingCancelled:cancelled];
}

- (void)releaseHold {
    if (_raisedRecording) {
        /* the recorder ended by itself, so the message goes the way a cancelled hold does and is not sent twice */
        [self endRaisedRecordingCancelled:YES];
        return;
    }
    if (_lockedRecording) {
        /* the recorder ended by itself; the locked recording is closed without sending twice */
        [self endLockedCancelled:YES];
        return;
    }
    /* a recognizer switched off in mid gesture reports the cancelled state and then rests */
    _hold.enabled = NO;
    _hold.enabled = YES;
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    CGFloat x = [hold locationInView:self].x;
    switch (hold.state) {
    case UIGestureRecognizerStateBegan:
        if (![_delegate inputBar:self didBeginRecording:_mode]) {
            /* a recognizer that is switched off and on again drops the touch that began it */
            hold.enabled = NO;
            hold.enabled = YES;
            return;
        }
        _holding = YES;
        _slidAway = NO;
        _locked = NO;
        _holdStart = x;
        _holdBeganAt = CACurrentMediaTime();
        _holdStartY = [hold locationInView:self].y;
        [self setRecordingElapsed:0];
        [self showRecordingAnimated];
        /* a hold that lasts as long as the person chose in the chat settings, without a slide, locks the recording by itself: they mean to go on, and the swipe up it would
           take is the one a gesture tweak steals */
        NSInteger autoLock = ExteriaChatRecordLockSeconds();
        if (autoLock > 0) [self performSelector:@selector(lockTapped) withObject:nil afterDelay:(NSTimeInterval)autoLock];
        break;
    case UIGestureRecognizerStateChanged: {
        if (!_holding) return;
        CGFloat dx = MIN(0, x - _holdStart);
        CGFloat rise = MAX(0, _holdStartY - [hold locationInView:self].y);
        _slidAway = dx < -SLIDE_CANCEL;
        if (!_slidAway && !_locked) {
            _lockView.transform = CGAffineTransformMakeTranslation(0, -MIN(1, rise / LOCK_DISTANCE) * 14);
            if (rise > LOCK_DISTANCE) {
                _locked = YES;
                _lockIcon.image = ExteriaSymbolImage(ExteriaSymbolLock, 22, ExteriaColorAccent());
                [UIView animateWithDuration:0.1 animations:^{ _lockView.transform = CGAffineTransformMakeScale(1.15, 1.15); }
                                 completion:^(BOOL finished) { (void)finished; [UIView animateWithDuration:0.1 animations:^{ _lockView.transform = CGAffineTransformIdentity; }]; }];
            }
        }
        /* the hint follows the finger and fades as it nears the cancel line */
        _slide.transform = CGAffineTransformMakeTranslation(dx * 0.6, 0);
        _slide.alpha = _slidAway ? 1 : MAX(0.25, 1 + dx / (SLIDE_CANCEL * 1.4));
        _slide.textColor = _slidAway ? [UIColor colorWithRed:0.92 green:0.22 blue:0.22 alpha:1] : ExteriaColorSecondary();
        break;
    }
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed: {
        if (!_holding) return;
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(lockTapped) object:nil];
        _holding = NO;
        BOOL quick = CACurrentMediaTime() - _holdBeganAt < QUICK_LOCK_SECONDS;
        if ((_locked || quick) && !_slidAway && hold.state == UIGestureRecognizerStateEnded) {
            [self enterLockedRecording];
            break;
        }
        _locked = NO;
        BOOL cancelled = _slidAway || hold.state != UIGestureRecognizerStateEnded;
        [self hideLockAnimated];
        [self hideRecordingCancelled:cancelled];
        [_delegate inputBar:self didFinishRecordingCancelled:cancelled];
        break;
    }
    default:
        break;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _toolbar.frame = self.bounds;
    _hairline.frame = CGRectMake(0, 0, size.width, 1.0 / ExteriaScreenScale());
    if (_actionTitle.length && (!_actionWithInput || !_writable)) {
        _actionButton.frame = CGRectMake(MARGIN, 0, size.width - 2 * MARGIN, ExteriaInputIdleHeight());
        return;
    }
    if (!_writable) {
        _note.frame = CGRectMake(MARGIN, 0, size.width - 2 * MARGIN, ExteriaInputIdleHeight());
        return;
    }
    if (_actionTitle.length && _actionWithInput) _actionButton.frame = CGRectMake(MARGIN, _fieldHeight + 2 * ExteriaInputVerticalMargin(), size.width - 2 * MARGIN, ExteriaInputIdleHeight());
    CGFloat sendWidth = BUTTON;
    CGFloat sendHeight = BUTTON;
    /* a scaled button keeps its frame, so a transform in flight is set aside while the frame is set */
    CGAffineTransform held = _send.transform;
    _send.transform = CGAffineTransformIdentity;
    _send.frame = CGRectMake(size.width - MARGIN - sendWidth, ExteriaInputVerticalMargin() + _fieldHeight - sendHeight, sendWidth, sendHeight);
    _send.transform = held;
    _onceChip.frame = CGRectMake(CGRectGetMaxX(_send.frame) - 12, CGRectGetMinY(_send.frame) - 10, 22, 22);
    CGFloat pillWidth = _menuPill.hidden ? 0 : ceil([_menuTitle sizeWithFont:_menuPill.titleLabel.font].width) + 28;
    CGFloat senderRoom = _senderButton.hidden ? 0 : FIELD_MIN + MARGIN;
    CGFloat menuRoom = (pillWidth ? pillWidth + MARGIN : 0) + senderRoom;
    CGFloat fieldWidth = size.width - 3 * MARGIN - sendWidth - menuRoom;
    _senderButton.frame = CGRectMake(MARGIN, ExteriaInputVerticalMargin() + _fieldHeight - FIELD_MIN, FIELD_MIN, FIELD_MIN);
    _menuPill.frame = CGRectMake(MARGIN + senderRoom, ExteriaInputVerticalMargin() + _fieldHeight - FIELD_MIN, pillWidth, FIELD_MIN);
    _field.frame = CGRectMake(MARGIN + menuRoom, ExteriaInputVerticalMargin(), fieldWidth, _fieldHeight);
    _recording.frame = _field.frame;
    _recording.layer.cornerRadius = _field.layer.cornerRadius;
    _dot.frame = CGRectMake(14, (_fieldHeight - 10) / 2, 10, 10);
    _timer.frame = CGRectMake(32, 0, 80, _fieldHeight);
    _slide.frame = CGRectMake(112, 0, fieldWidth - 112 - BUTTON, _fieldHeight);
    _cancelLocked.frame = CGRectMake(fieldWidth - 100 - 40, 0, 100, _fieldHeight);
    _field.layer.cornerRadius = MIN(_fieldHeight / 2, FIELD_MIN / 2);
    /* the smiley stands at the left edge of the field and the clip at the right, with the text between them */
    _panelButton.frame = CGRectMake(2, _fieldHeight - FIELD_MIN, PANEL_BUTTON_WIDTH, FIELD_MIN);
    _attachButton.frame = CGRectMake(fieldWidth - PANEL_BUTTON_WIDTH - 2, _fieldHeight - FIELD_MIN, PANEL_BUTTON_WIDTH, FIELD_MIN);
    /* a bot's keyboard button stands between the text and the clip */
    CGFloat botRoom = _botButton.hidden ? 0 : PANEL_BUTTON_WIDTH;
    CGFloat attachRoom = _attachButton.hidden ? 0 : PANEL_BUTTON_WIDTH;
    _botButton.frame = CGRectMake(fieldWidth - PANEL_BUTTON_WIDTH - attachRoom - 2, _fieldHeight - FIELD_MIN, PANEL_BUTTON_WIDTH, FIELD_MIN);
    CGFloat oldTextWidth = _text.bounds.size.width;
    _text.frame = CGRectMake(PANEL_BUTTON_WIDTH + 2, 0, fieldWidth - PANEL_BUTTON_WIDTH - attachRoom - 4 - botRoom, _fieldHeight);
    if (_text.bounds.size.width > 0 && oldTextWidth != _text.bounds.size.width) {
        /* a restored draft can be measured before the text view has its real width */
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateTextHeight) object:nil];
        [self performSelector:@selector(updateTextHeight) withObject:nil afterDelay:0];
    }
    _placeholder.frame = CGRectMake(_text.frame.origin.x + 8, (FIELD_MIN - 20) / 2 + (_fieldHeight - FIELD_MIN), fieldWidth - 2 * PANEL_BUTTON_WIDTH - 20 - botRoom, 20);
    /* ios 7 puts five points of padding in front of the first character, earlier systems eight */
    if ([_text respondsToSelector:@selector(textContainer)]) _placeholder.frame = CGRectOffset(_placeholder.frame, -3, 0);
}

@end
