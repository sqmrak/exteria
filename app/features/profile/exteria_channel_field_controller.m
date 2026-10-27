#import "exteria_channel_field_controller.h"
#import "exteria_channel_errors.h"

#import <QuartzCore/QuartzCore.h>

#include "exteria_channel.h"

#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define CARD_MARGIN 16.0
#define FIELD_HEIGHT 52.0
#define TITLE_LIMIT 128
#define ABOUT_LIMIT 255
#define RANK_LIMIT 16
#define CHECK_DELAY 0.5

@interface ExteriaChannelFieldController () {
    ExteriaChannelFieldKind _kind;
    NSString *_text;
    ExteriaDialog *_dialog;
    void (^_save)(NSString *text, void (^done)(NSString *errorName));
    ExteriaWeakReference *_weak;
    UIView *_card;
    UITextField *_field;
    UILabel *_counter;
    UILabel *_hint;
    UILabel *_status;
    BOOL _saving;
    /* a check that finishes after a newer one was asked for says nothing about the text now in the field */
    NSUInteger _checkToken;
}
@end

@implementation ExteriaChannelFieldController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media kind:(ExteriaChannelFieldKind)kind
                 text:(NSString *)text dialog:(ExteriaDialog *)dialog save:(void (^)(NSString *, void (^)(NSString *)))save {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _kind = kind;
    _text = [text copy];
    _dialog = [dialog retain];
    _save = [save copy];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    switch (kind) {
    case ExteriaChannelFieldTitle: self.screenTitle = NSLocalizedString(@"channel.field.title", nil); break;
    case ExteriaChannelFieldAbout: self.screenTitle = NSLocalizedString(@"channel.field.about", nil); break;
    case ExteriaChannelFieldUsername: self.screenTitle = NSLocalizedString(@"channel.field.link", nil); break;
    case ExteriaChannelFieldRank: self.screenTitle = NSLocalizedString(@"channel.rights.rank", nil); break;
    }
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_weak clear];
    [_weak release];
    _field.delegate = nil;
    [_text release];
    [_dialog release];
    [_save release];
    [_card release];
    [_field release];
    [_counter release];
    [_hint release];
    [_status release];
    [super dealloc];
}

- (NSInteger)limit {
    switch (_kind) {
    case ExteriaChannelFieldTitle: return TITLE_LIMIT;
    case ExteriaChannelFieldAbout: return ABOUT_LIMIT;
    case ExteriaChannelFieldUsername: return EXTERIA_CHANNEL_USERNAME_MAX - 1;
    case ExteriaChannelFieldRank: return RANK_LIMIT;
    }
    return 64;
}

- (NSString *)hintText {
    switch (_kind) {
    case ExteriaChannelFieldTitle: return nil;
    case ExteriaChannelFieldAbout: return NSLocalizedString(@"channel.about.hint", nil);
    case ExteriaChannelFieldUsername: return NSLocalizedString(@"channel.username.hint", nil);
    case ExteriaChannelFieldRank: return NSLocalizedString(@"channel.rank.hint", nil);
    }
    return nil;
}

- (void)buildBodyInView:(UIView *)root {
    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.cornerRadius = 14;
    [root addSubview:_card];
    _field = [[UITextField alloc] init];
    _field.delegate = self;
    _field.font = ExteriaFontRegular(17);
    _field.textColor = ExteriaColorTitle();
    _field.text = _text;
    _field.clearButtonMode = UITextFieldViewModeWhileEditing;
    /* a text field aligns its text to the top of a tall frame on ios 5 and 6 */
    _field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _field.returnKeyType = UIReturnKeyDone;
    BOOL name = _kind == ExteriaChannelFieldUsername;
    _field.autocorrectionType = name ? UITextAutocorrectionTypeNo : UITextAutocorrectionTypeDefault;
    _field.autocapitalizationType = name ? UITextAutocapitalizationTypeNone : UITextAutocapitalizationTypeSentences;
    _field.keyboardAppearance = ExteriaThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    if (name) _field.placeholder = @"username";
    [_card addSubview:_field];
    _counter = [[UILabel alloc] init];
    _counter.backgroundColor = [UIColor clearColor];
    _counter.textColor = ExteriaColorSecondary();
    _counter.font = ExteriaFontRegular(13);
    _counter.textAlignment = ExteriaTextAlignmentRight;
    [_card addSubview:_counter];
    _hint = [[UILabel alloc] init];
    _hint.backgroundColor = [UIColor clearColor];
    _hint.textColor = ExteriaColorSecondary();
    _hint.font = ExteriaFontRegular(13);
    _hint.numberOfLines = 0;
    _hint.text = [self hintText];
    [root addSubview:_hint];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.font = ExteriaFontSemibold(14);
    [root addSubview:_status];
    [self refreshCounter];
    ExteriaWeakReference *me = _weak;
    [self setActionTitle:NSLocalizedString(@"channel.save", nil) handler:^{ [(ExteriaChannelFieldController *)me.target commit]; }];
}

- (void)layoutBody:(CGRect)body {
    CGFloat width = MIN(body.size.width - 2 * CARD_MARGIN, 520);
    CGFloat x = body.origin.x + floor((body.size.width - width) / 2);
    CGFloat y = body.origin.y + 16;
    _card.frame = CGRectMake(x, y, width, FIELD_HEIGHT);
    _counter.frame = CGRectMake(width - 64, 0, 52, FIELD_HEIGHT);
    _field.frame = CGRectMake(14, 0, width - 14 - 64, FIELD_HEIGHT);
    y += FIELD_HEIGHT + 8;
    _status.frame = CGRectMake(x + 6, y, width - 12, 20);
    if (_kind == ExteriaChannelFieldUsername) y += 24;
    CGSize fit = [_hint sizeThatFits:CGSizeMake(width - 12, 400)];
    _hint.frame = CGRectMake(x + 6, y, width - 12, ceil(fit.height));
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_field becomeFirstResponder];
}

- (void)refreshCounter {
    _counter.text = [NSString stringWithFormat:@"%d", (int)([self limit] - (NSInteger)_field.text.length)];
}

#pragma mark checking

- (void)setStatus:(NSString *)text good:(BOOL)good {
    _status.text = text;
    _status.textColor = good ? ExteriaColorAccent() : ExteriaColorBadgeRed();
}

/* the server's verdict on the name in the field; the screen keeps asking only for a name the core would send */
- (void)checkName {
    NSString *name = _field.text;
    if (!name.length || [name isEqualToString:_text]) {
        _status.text = @"";
        return;
    }
    NSUInteger token = ++_checkToken;
    [self setStatus:NSLocalizedString(@"channel.username.checking", nil) good:YES];
    [self retain];
    [self.session checkUsername:name ofDialog:_dialog completion:^(NSString *errorName) {
        [self autorelease];
        if (token != _checkToken) return;
        if (!errorName) [self setStatus:NSLocalizedString(@"channel.username.free", nil) good:YES];
        else if ([errorName isEqualToString:@"USERNAME_OCCUPIED"] || [errorName isEqualToString:@"USERNAME_PURCHASE_AVAILABLE"]) [self setStatus:NSLocalizedString(@"channel.username.taken", nil) good:NO];
        else if ([errorName isEqualToString:@"USERNAME_INVALID"] || [errorName isEqualToString:@"NOT_MODIFIED"]) [self setStatus:NSLocalizedString(@"channel.username.invalid", nil) good:NO];
        else [self setStatus:ExteriaChannelErrorText(errorName) good:NO];
    }];
}

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *next = [field.text stringByReplacingCharactersInRange:range withString:string];
    if ((NSInteger)next.length > [self limit]) return NO;
    if (_kind == ExteriaChannelFieldUsername) {
        /* only what a name can hold goes in, so the field never holds one the core would refuse for a stray character */
        NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
        if ([[next stringByTrimmingCharactersInSet:allowed] length] != 0) return NO;
    }
    /* the counter is read from the field after the change lands */
    [self performSelector:@selector(textChanged) withObject:nil afterDelay:0];
    return YES;
}

- (void)textChanged {
    [self refreshCounter];
    if (_kind != ExteriaChannelFieldUsername) return;
    _checkToken++;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkName) object:nil];
    _status.text = @"";
    [self performSelector:@selector(checkName) withObject:nil afterDelay:CHECK_DELAY];
}

- (BOOL)textFieldShouldClear:(UITextField *)field {
    (void)field;
    [self performSelector:@selector(textChanged) withObject:nil afterDelay:0];
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    (void)field;
    [self commit];
    return NO;
}

#pragma mark saving

- (void)commit {
    if (_saving) return;
    NSString *text = [_field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    /* a channel keeps a title, and the server answers an empty one with an error the person could not read */
    if (_kind == ExteriaChannelFieldTitle && !text.length) {
        ExteriaGiftAlert(nil, NSLocalizedString(@"channel.title.empty", nil));
        return;
    }
    if ([text isEqualToString:_text]) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    _saving = YES;
    [_field resignFirstResponder];
    [self retain];
    _save(text, ^(NSString *errorName) {
        [self autorelease];
        _saving = NO;
        if (errorName) {
            ExteriaGiftAlert(nil, ExteriaChannelErrorText(errorName));
            return;
        }
        [self.navigationController popViewControllerAnimated:YES];
    });
}

@end
