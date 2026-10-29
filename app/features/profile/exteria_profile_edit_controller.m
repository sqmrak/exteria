#import "exteria_profile_edit_controller.h"
#import "exteria_text_filter.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_channel_picker_controller.h"
#import "exteria_date_sheet.h"
#import "exteria_emoji_label.h"
#import "exteria_row_icon.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define NAME_HEIGHT 52.0
#define ROW_HEIGHT 64.0
#define CAPTION_HEIGHT 30.0
#define ABOUT_LIMIT 70
#define GAP 16.0

@interface ExteriaProfileNameField : UITextField {
    ExteriaEmojiLabel *_namePreview;
    UIColor *_nameColor;
}
- (void)setNameColor:(UIColor *)color;
- (void)refreshNamePreview;
@end

@implementation ExteriaProfileNameField

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _namePreview = [[ExteriaEmojiLabel alloc] initWithFrame:CGRectZero];
    _namePreview.dropsUndrawable = YES;
    [self addSubview:_namePreview];
    [self addTarget:self action:@selector(refreshNamePreview) forControlEvents:UIControlEventEditingDidBegin | UIControlEventEditingDidEnd | UIControlEventEditingChanged];
    return self;
}

- (void)dealloc {
    [_namePreview release];
    [_nameColor release];
    [super dealloc];
}

- (void)setNameColor:(UIColor *)color {
    if (color != _nameColor) {
        [_nameColor release];
        _nameColor = [color retain];
    }
    [self refreshNamePreview];
}

- (void)setText:(NSString *)text {
    [super setText:text];
    [self refreshNamePreview];
}

- (void)refreshNamePreview {
    if (!_namePreview || !_nameColor) return;
    BOOL preview = !self.editing && self.text.length > 0;
    _namePreview.text = self.text;
    _namePreview.font = self.font;
    _namePreview.textColor = _nameColor;
    _namePreview.hidden = !preview;
    self.textColor = preview ? [UIColor clearColor] : _nameColor;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _namePreview.frame = [self textRectForBounds:self.bounds];
    [self bringSubviewToFront:_namePreview];
}
@end

@interface ExteriaProfileEditController () <UITextFieldDelegate> {
    ExteriaPerson *_person;
    ExteriaFullUser *_full;
    ExteriaWeakReference *_weak;
    UIScrollView *_scroll;
    UIView *_nameCard;
    UILabel *_nameCaption;
    UITextField *_first;
    UITextField *_last;
    UIView *_nameLine;
    UIView *_aboutCard;
    UITextField *_about;
    UILabel *_counter;
    UILabel *_aboutNote;
    UIView *_infoCard;
    UILabel *_infoCaption;
    UIView *_phoneRow;
    UIView *_usernameRow;
    UITextField *_username;
    UIControl *_birthdayRow;
    UIView *_infoLines[2];
    UIControl *_channelRow;
    UIControl *_logoutRow;
    UIView *_channelCard;
    UIView *_logoutCard;
    UIActivityIndicatorView *_spinner;
    BOOL _working;
    CGFloat _keyboardOverlap;
    void (^_changedHandler)(void);
    void (^_logoutHandler)(void);
}
@end

@implementation ExteriaProfileEditController

@synthesize changedHandler = _changedHandler;
@synthesize logoutHandler = _logoutHandler;

- (id)initWithSession:(ExteriaSession *)session person:(ExteriaPerson *)person fullUser:(ExteriaFullUser *)full avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _person = [person retain];
    _full = [full retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.screenTitle = NSLocalizedString(@"profile.edit.title", nil);
    ExteriaWeakReference *me = _weak;
    [self setActionTitle:NSLocalizedString(@"profile.edit.save", nil) handler:^{ [(ExteriaProfileEditController *)me.target save]; }];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _first.delegate = nil;
    _last.delegate = nil;
    _about.delegate = nil;
    _username.delegate = nil;
    [_person release];
    [_full release];
    [_scroll release];
    [_nameCard release];
    [_nameCaption release];
    [_first release];
    [_last release];
    [_nameLine release];
    [_aboutCard release];
    [_about release];
    [_counter release];
    [_aboutNote release];
    [_infoCard release];
    [_infoCaption release];
    [_phoneRow release];
    [_usernameRow release];
    [_username release];
    [_birthdayRow release];
    [_infoLines[0] release];
    [_infoLines[1] release];
    [_channelRow release];
    [_logoutRow release];
    [_channelCard release];
    [_logoutCard release];
    [_spinner release];
    [_changedHandler release];
    [_logoutHandler release];
    [super dealloc];
}

static UIView *ExteriaCard(void) {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = ExteriaColorCard();
    card.layer.cornerRadius = 14;
    return card;
}

static UIView *ExteriaLine(void) {
    UIView *line = [[UIView alloc] init];
    line.backgroundColor = ExteriaColorHairline();
    return line;
}

static UILabel *ExteriaEditLabel(UIColor *color, CGFloat size, BOOL bold) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = bold ? ExteriaFontSemibold(size) : ExteriaFontRegular(size);
    return label;
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text capitalized:(BOOL)capitalized name:(BOOL)name {
    UITextField *field = name ? [[ExteriaProfileNameField alloc] initWithFrame:CGRectZero] : [[UITextField alloc] init];
    field.delegate = self;
    field.font = ExteriaFontRegular(17);
    field.textColor = ExteriaColorTitle();
    if (name) [(ExteriaProfileNameField *)field setNameColor:ExteriaColorTitle()];
    field.placeholder = placeholder;
    field.text = text;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    // a text field aligns its text to the top of a tall frame on ios 5 and 6
    field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    field.returnKeyType = UIReturnKeyDone;
    field.autocorrectionType = capitalized ? UITextAutocorrectionTypeDefault : UITextAutocorrectionTypeNo;
    field.autocapitalizationType = capitalized ? UITextAutocapitalizationTypeWords : UITextAutocapitalizationTypeNone;
    field.keyboardAppearance = ExteriaThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    return field;
}

/* a row with an icon, a line and a smaller line under it; the labels are found by tag 1 and 2 */
- (UIControl *)rowWithIcon:(UIView *)icon title:(NSString *)title subtitle:(NSString *)subtitle {
    UIControl *row = [[[UIControl alloc] init] autorelease];
    [row addSubview:icon];
    UILabel *top = ExteriaEditLabel(ExteriaColorTitle(), 17, NO);
    top.tag = 1;
    top.text = title;
    [row addSubview:top];
    [top release];
    UILabel *bottom = ExteriaEditLabel(ExteriaColorSecondary(), 13, NO);
    bottom.tag = 2;
    bottom.text = subtitle;
    [row addSubview:bottom];
    [bottom release];
    return row;
}

- (NSString *)birthdayText {
    if (!_full.hasBirthday) return NSLocalizedString(@"profile.birthday.set", nil);
    NSDateComponents *parts = [[[NSDateComponents alloc] init] autorelease];
    parts.day = _full.birthdayDay;
    parts.month = _full.birthdayMonth;
    parts.year = _full.birthdayYear > 0 ? _full.birthdayYear : 2000;
    NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:parts];
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    formatter.dateFormat = _full.birthdayYear > 0 ? @"d MMMM yyyy" : @"d MMMM";
    return date ? [formatter stringFromDate:date] : NSLocalizedString(@"profile.birthday.set", nil);
}

- (void)buildBodyInView:(UIView *)root {
    _scroll = [[UIScrollView alloc] init];
    _scroll.alwaysBounceVertical = YES;
    [root addSubview:_scroll];

    NSString *first = _person.name, *last = @"";
    NSRange space = [_person.name rangeOfString:@" "];
    if (space.location != NSNotFound) {
        first = [_person.name substringToIndex:space.location];
        last = [_person.name substringFromIndex:space.location + 1];
    }
    _nameCard = ExteriaCard();
    [_scroll addSubview:_nameCard];
    _nameCaption = ExteriaEditLabel(ExteriaColorAccent(), 14, YES);
    _nameCaption.text = NSLocalizedString(@"profile.edit.yourname", nil);
    [_nameCard addSubview:_nameCaption];
    _first = [self fieldWithPlaceholder:NSLocalizedString(@"profile.edit.first", nil) text:first capitalized:YES name:YES];
    [_nameCard addSubview:_first];
    _last = [self fieldWithPlaceholder:NSLocalizedString(@"profile.edit.last", nil) text:last capitalized:YES name:YES];
    [_nameCard addSubview:_last];
    _nameLine = ExteriaLine();
    [_nameCard addSubview:_nameLine];

    _aboutCard = ExteriaCard();
    [_scroll addSubview:_aboutCard];
    _about = [self fieldWithPlaceholder:NSLocalizedString(@"profile.about", nil) text:_full.about capitalized:YES name:NO];
    [_aboutCard addSubview:_about];
    _counter = ExteriaEditLabel(ExteriaColorSecondary(), 15, NO);
    _counter.textAlignment = ExteriaTextAlignmentRight;
    [_aboutCard addSubview:_counter];
    [self refreshCounter];
    _aboutNote = ExteriaEditLabel(ExteriaColorSecondary(), 13, NO);
    _aboutNote.numberOfLines = 0;
    _aboutNote.text = NSLocalizedString(@"profile.edit.hint.about", nil);
    [_scroll addSubview:_aboutNote];

    _infoCard = ExteriaCard();
    [_scroll addSubview:_infoCard];
    _infoCaption = ExteriaEditLabel(ExteriaColorAccent(), 14, YES);
    _infoCaption.text = NSLocalizedString(@"profile.edit.info", nil);
    [_infoCard addSubview:_infoCaption];
    _phoneRow = [[self rowWithIcon:ExteriaRowIcon(ExteriaSymbolPhone, [UIColor colorWithRed:0.30 green:0.76 blue:0.40 alpha:1])
                             title:ExteriaOwnPhoneText(_person.phone) subtitle:NSLocalizedString(@"profile.phone", nil)] retain];
    [_infoCard addSubview:_phoneRow];
    _usernameRow = [[self rowWithIcon:ExteriaRowIcon(ExteriaSymbolAt, [UIColor colorWithRed:0.96 green:0.62 blue:0.18 alpha:1])
                                title:@"" subtitle:NSLocalizedString(@"profile.username", nil)] retain];
    [[_usernameRow viewWithTag:1] setHidden:YES];
    _username = [self fieldWithPlaceholder:NSLocalizedString(@"profile.username", nil) text:_person.username ? _person.username : @"" capitalized:NO name:NO];
    [_usernameRow addSubview:_username];
    [_infoCard addSubview:_usernameRow];
    _birthdayRow = [[self rowWithIcon:ExteriaRowIcon(ExteriaSymbolCake, [UIColor colorWithRed:0.24 green:0.58 blue:0.95 alpha:1])
                                title:[self birthdayText] subtitle:nil] retain];
    [_birthdayRow addTarget:self action:@selector(chooseBirthday) forControlEvents:UIControlEventTouchUpInside];
    [_infoCard addSubview:_birthdayRow];
    for (int i = 0; i < 2; ++i) {
        _infoLines[i] = ExteriaLine();
        [_infoCard addSubview:_infoLines[i]];
    }

    _channelCard = ExteriaCard();
    [_scroll addSubview:_channelCard];
    _channelRow = [[self rowWithIcon:ExteriaRowIcon(ExteriaSymbolMegaphone, [UIColor colorWithRed:0.96 green:0.62 blue:0.18 alpha:1])
                               title:NSLocalizedString(@"profile.channel", nil)
                            subtitle:_full.channel ? _full.channel.dialog.title : NSLocalizedString(@"profile.channel.add", nil)] retain];
    [_channelRow addTarget:self action:@selector(chooseChannel) forControlEvents:UIControlEventTouchUpInside];
    [_channelCard addSubview:_channelRow];

    _logoutCard = ExteriaCard();
    [_scroll addSubview:_logoutCard];
    _logoutRow = [[self rowWithIcon:ExteriaRowIcon(ExteriaSymbolLogout, ExteriaColorAccent()) title:NSLocalizedString(@"profile.signout", nil) subtitle:nil] retain];
    ((UILabel *)[_logoutRow viewWithTag:1]).textColor = ExteriaColorAccent();
    [_logoutRow addTarget:self action:@selector(logoutTapped) forControlEvents:UIControlEventTouchUpInside];
    [_logoutCard addSubview:_logoutRow];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:ExteriaThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [_scroll addSubview:_spinner];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
}

/* positions a row's icon and lines; a row with no subtitle centers its one line */
static void ExteriaLayoutRow(UIView *row, CGFloat width, CGFloat height) {
    UIView *icon = [row.subviews objectAtIndex:0];
    icon.frame = CGRectMake(16, (height - icon.bounds.size.height) / 2, icon.bounds.size.width, icon.bounds.size.height);
    UILabel *top = (UILabel *)[row viewWithTag:1], *bottom = (UILabel *)[row viewWithTag:2];
    BOOL two = bottom.text.length > 0;
    CGFloat x = 16 + 32 + 14;
    top.frame = CGRectMake(x, two ? 10 : 0, width - x - 40, two ? 24 : height);
    bottom.frame = CGRectMake(x, 34, width - x - 16, 18);
}

- (void)layoutBody:(CGRect)body {
    _scroll.frame = body;
    CGFloat width = body.size.width;
    CGFloat inner = MIN(width - 32, 480);
    CGFloat x = (width - inner) / 2;
    CGFloat y = GAP;
    _nameCard.frame = CGRectMake(x, y, inner, CAPTION_HEIGHT + 2 * NAME_HEIGHT);
    _nameCaption.frame = CGRectMake(16, 8, inner - 32, 18);
    _first.frame = CGRectMake(16, CAPTION_HEIGHT, inner - 24, NAME_HEIGHT);
    _nameLine.frame = CGRectMake(16, CAPTION_HEIGHT + NAME_HEIGHT, inner - 16, 1.0 / [UIScreen mainScreen].scale);
    _last.frame = CGRectMake(16, CAPTION_HEIGHT + NAME_HEIGHT, inner - 24, NAME_HEIGHT);
    y += _nameCard.frame.size.height + GAP;
    _aboutCard.frame = CGRectMake(x, y, inner, NAME_HEIGHT);
    _about.frame = CGRectMake(16, 0, inner - 70, NAME_HEIGHT);
    _counter.frame = CGRectMake(inner - 62, 0, 48, NAME_HEIGHT);
    y += NAME_HEIGHT + 6;
    CGSize note = [_aboutNote sizeThatFits:CGSizeMake(inner - 24, 100)];
    _aboutNote.frame = CGRectMake(x + 12, y, inner - 24, note.height);
    y += note.height + GAP;
    CGFloat infoHeight = CAPTION_HEIGHT + 3 * ROW_HEIGHT - 8;
    _infoCard.frame = CGRectMake(x, y, inner, infoHeight);
    _infoCaption.frame = CGRectMake(16, 8, inner - 32, 18);
    CGFloat rowY = CAPTION_HEIGHT;
    _phoneRow.frame = CGRectMake(0, rowY, inner, ROW_HEIGHT);
    ExteriaLayoutRow(_phoneRow, inner, ROW_HEIGHT);
    rowY += ROW_HEIGHT;
    _usernameRow.frame = CGRectMake(0, rowY, inner, ROW_HEIGHT);
    ExteriaLayoutRow(_usernameRow, inner, ROW_HEIGHT);
    _username.frame = CGRectMake(62, 6, inner - 62 - 16, 28);
    rowY += ROW_HEIGHT;
    _birthdayRow.frame = CGRectMake(0, rowY, inner, ROW_HEIGHT - 8);
    ExteriaLayoutRow(_birthdayRow, inner, ROW_HEIGHT - 8);
    CGFloat hair = 1.0 / [UIScreen mainScreen].scale;
    _infoLines[0].frame = CGRectMake(62, CAPTION_HEIGHT + ROW_HEIGHT, inner - 62, hair);
    _infoLines[1].frame = CGRectMake(62, CAPTION_HEIGHT + 2 * ROW_HEIGHT, inner - 62, hair);
    y += infoHeight + GAP;
    _channelCard.frame = CGRectMake(x, y, inner, ROW_HEIGHT);
    _channelRow.frame = _channelCard.bounds;
    ExteriaLayoutRow(_channelRow, inner, ROW_HEIGHT);
    y += ROW_HEIGHT + GAP;
    _logoutCard.frame = CGRectMake(x, y, inner, 56);
    _logoutRow.frame = _logoutCard.bounds;
    ExteriaLayoutRow(_logoutRow, inner, 56);
    y += 56 + GAP;
    _spinner.center = CGPointMake(width / 2, y + 12);
    _scroll.contentSize = CGSizeMake(width, y + 40);
    _scroll.contentInset = UIEdgeInsetsMake(0, 0, _keyboardOverlap, 0);
}

- (void)keyboardChanged:(NSNotification *)note {
    CGRect frame = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    frame = [self.view convertRect:[self.view.window convertRect:frame fromWindow:nil] fromView:nil];
    BOOL showing = [note.name isEqualToString:UIKeyboardWillShowNotification];
    _keyboardOverlap = showing ? MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(frame)) : 0;
    [self.view setNeedsLayout];
}

- (void)refreshCounter {
    _counter.text = [NSString stringWithFormat:@"%d", (int)(ABOUT_LIMIT - (NSInteger)_about.text.length)];
}

#pragma mark fields

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *next = [field.text stringByReplacingCharactersInRange:range withString:string];
    if (field == _about) {
        BOOL fits = next.length <= ABOUT_LIMIT;
        if (fits) _counter.text = [NSString stringWithFormat:@"%d", (int)(ABOUT_LIMIT - (NSInteger)next.length)];
        return fits;
    }
    if (field == _username) {
        /* only what a username can hold goes in, so the field never holds a name the core would refuse for a stray character */
        NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
        return [[next stringByTrimmingCharactersInSet:allowed] length] == 0 && next.length <= 32;
    }
    return next.length <= 64;
}

#pragma mark rows

- (void)notifyChanged {
    if (_changedHandler) _changedHandler();
}

- (void)chooseBirthday {
    if (_working) return;
    [self.view endEditing:YES];
    ExteriaDateSheet *sheet = [[[ExteriaDateSheet alloc] initWithDay:_full.birthdayDay month:_full.birthdayMonth year:_full.birthdayYear] autorelease];
    sheet.canRemove = _full.hasBirthday;
    ExteriaWeakReference *me = _weak;
    sheet.doneHandler = ^(int32_t day, int32_t month, int32_t year) {
        [(ExteriaProfileEditController *)me.target saveBirthdayDay:day month:month year:year];
    };
    sheet.removeHandler = ^{ [(ExteriaProfileEditController *)me.target removeBirthday]; };
    [sheet showInView:self.view];
}

- (void)reloadFull:(void (^)(void))then {
    [self retain];
    [self.session loadFullUserOfDialog:[ExteriaDialog savedMessagesWithPerson:_person] completion:^(ExteriaFullUser *user, NSString *errorName) {
        [self autorelease];
        if (user) {
            [_full release];
            _full = [user retain];
        } else {
            NSLog(@"exteria: the profile did not reload: %@", errorName);
        }
        if (then) then();
    }];
}

- (void)refreshRows {
    ((UILabel *)[_birthdayRow viewWithTag:1]).text = [self birthdayText];
    ((UILabel *)[_channelRow viewWithTag:2]).text = _full.channel ? _full.channel.dialog.title : NSLocalizedString(@"profile.channel.add", nil);
    [self.view setNeedsLayout];
}

- (void)saveBirthdayDay:(int32_t)day month:(int32_t)month year:(int32_t)year {
    [self setWorking:YES];
    [self retain];
    [self.session setBirthdayDay:day month:month year:year completion:^(NSString *errorName) {
        [self autorelease];
        if (errorName) {
            [self setWorking:NO];
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        [self reloadFull:^{
            [self setWorking:NO];
            [self refreshRows];
            [self notifyChanged];
        }];
    }];
}

- (void)removeBirthday {
    [self setWorking:YES];
    [self retain];
    [self.session clearBirthday:^(NSString *errorName) {
        [self autorelease];
        if (errorName) {
            [self setWorking:NO];
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        [self reloadFull:^{
            [self setWorking:NO];
            [self refreshRows];
            [self notifyChanged];
        }];
    }];
}

- (void)chooseChannel {
    if (_working) return;
    [self.view endEditing:YES];
    ExteriaChannelPickerController *picker = [[[ExteriaChannelPickerController alloc] initWithSession:self.session avatars:self.avatars media:self.media] autorelease];
    picker.screenTitle = NSLocalizedString(@"profile.channel", nil);
    picker.currentChannelId = _full.channel ? _full.channel.dialog.peerId : 0;
    ExteriaWeakReference *me = _weak;
    ExteriaWeakReference *pickerRef = [ExteriaWeakReference referenceTo:picker];
    picker.pickHandler = ^(ExteriaDialog *channel) {
        ExteriaProfileEditController *edit = me.target;
        UIViewController *host = pickerRef.target;
        if (!edit || !host) return;
        [host.navigationController popViewControllerAnimated:YES];
        [edit savePersonalChannel:channel];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)savePersonalChannel:(ExteriaDialog *)channel {
    [self setWorking:YES];
    [self retain];
    [self.session setPersonalChannel:channel completion:^(NSString *errorName) {
        [self autorelease];
        if (errorName) {
            [self setWorking:NO];
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        [self reloadFull:^{
            [self setWorking:NO];
            [self refreshRows];
            [self notifyChanged];
        }];
    }];
}

- (void)logoutTapped {
    if (_logoutHandler) _logoutHandler();
}

#pragma mark saving

- (void)setWorking:(BOOL)working {
    _working = working;
    _first.enabled = _last.enabled = _about.enabled = _username.enabled = !working;
    if (working) [_spinner startAnimating];
    else [_spinner stopAnimating];
}

static NSString *ExteriaTrimmed(NSString *text) {
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)save {
    if (_working) return;
    [self.view endEditing:YES];
    NSString *first = ExteriaTrimmed(_first.text), *last = ExteriaTrimmed(_last.text), *about = ExteriaTrimmed(_about.text);
    NSString *username = _username.text;
    if (!first.length) {
        ExteriaGiftAlert(nil, NSLocalizedString(@"profile.edit.noname", nil));
        return;
    }
    NSRange space = [_person.name rangeOfString:@" "];
    NSString *oldFirst = space.location == NSNotFound ? _person.name : [_person.name substringToIndex:space.location];
    NSString *oldLast = space.location == NSNotFound ? @"" : [_person.name substringFromIndex:space.location + 1];
    BOOL nameChanged = ![first isEqualToString:oldFirst] || ![last isEqualToString:oldLast];
    BOOL aboutChanged = ![about isEqualToString:_full.about ? _full.about : @""];
    BOOL usernameChanged = ![username isEqualToString:_person.username ? _person.username : @""];
    if (usernameChanged && username.length && (username.length < 5 || [username rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location == 0 ||
                                               [username hasSuffix:@"_"])) {
        ExteriaGiftAlert(nil, NSLocalizedString(@"profile.edit.badusername", nil));
        return;
    }
    if (!nameChanged && !aboutChanged && !usernameChanged) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self setWorking:YES];
    [self retain];
    void (^finish)(NSString *) = ^(NSString *errorName) {
        [self autorelease];
        [self setWorking:NO];
        if (errorName) {
            [self showSaveError:errorName];
            return;
        }
        [self notifyChanged];
        [self.navigationController popViewControllerAnimated:YES];
    };
    void (^finishCopy)(NSString *) = [finish copy];
    void (^afterProfile)(ExteriaPerson *, NSString *) = ^(ExteriaPerson *person, NSString *errorName) {
        (void)person;
        if (errorName || !usernameChanged) {
            finishCopy(errorName);
            [finishCopy release];
            return;
        }
        [self.session updateUsername:username completion:^(ExteriaPerson *named, NSString *usernameError) {
            (void)named;
            finishCopy(usernameError);
            [finishCopy release];
        }];
    };
    if (!nameChanged && !aboutChanged) {
        afterProfile(nil, nil);
        return;
    }
    [self.session updateFirstName:nameChanged ? first : nil lastName:nameChanged ? last : nil about:aboutChanged ? about : nil completion:afterProfile];
}

- (void)showSaveError:(NSString *)errorName {
    NSString *key = nil;
    if ([errorName isEqualToString:@"USERNAME_OCCUPIED"] || [errorName isEqualToString:@"USERNAME_PURCHASE_AVAILABLE"]) key = @"profile.edit.taken";
    else if ([errorName isEqualToString:@"USERNAME_INVALID"] || [errorName isEqualToString:@"USERNAME_NOT_MODIFIED"]) key = @"profile.edit.badusername";
    else if ([errorName isEqualToString:@"FIRSTNAME_INVALID"]) key = @"profile.edit.noname";
    else if ([errorName isEqualToString:@"ABOUT_TOO_LONG"]) key = @"profile.edit.longabout";
    ExteriaGiftAlert(nil, key ? NSLocalizedString(key, nil) : ExteriaGiftErrorText(errorName));
}

@end
