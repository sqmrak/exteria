#import "exteria_contact_edit_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_profile_photo_picker.h"
#import "exteria_row_icon.h"
#import "exteria_session_bots.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define FIELD_HEIGHT 52.0
#define ROW_HEIGHT 56.0
#define CAPTION_HEIGHT 30.0
#define GAP 16.0
#define NAME_LIMIT 64
#define NOTE_LIMIT 128

typedef enum { ExteriaContactPhotoSuggest, ExteriaContactPhotoSet, ExteriaContactPhotoReset } ExteriaContactPhotoRow;

@interface ExteriaContactEditController () <UITextFieldDelegate> {
    ExteriaPerson *_person;
    ExteriaFullUser *_full;
    ExteriaWeakReference *_weak;
    UIScrollView *_scroll;
    UIView *_nameCard;
    UILabel *_nameCaption;
    UITextField *_first;
    UITextField *_last;
    UIView *_nameLine;
    UIView *_noteCard;
    UILabel *_noteCaption;
    UITextField *_note;
    UILabel *_noteHint;
    UIView *_photoCard;
    UIControl *_photoRows[3];
    UIView *_photoLines[2];
    UILabel *_photoHint;
    UIActivityIndicatorView *_spinner;
    BOOL _working;
    BOOL _hasPersonalPhoto;
    CGFloat _keyboardOverlap;
    void (^_changedHandler)(void);
}
@end

@implementation ExteriaContactEditController

@synthesize changedHandler = _changedHandler;

- (id)initWithSession:(ExteriaSession *)session person:(ExteriaPerson *)person fullUser:(ExteriaFullUser *)full avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _person = [person retain];
    _full = [full retain];
    _hasPersonalPhoto = full.hasPersonalPhoto;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.screenTitle = NSLocalizedString(person.contact ? @"profile.contact.edit" : @"profile.contact.add", nil);
    ExteriaWeakReference *me = _weak;
    [self setActionTitle:NSLocalizedString(@"profile.edit.save", nil) handler:^{ [(ExteriaContactEditController *)me.target save]; }];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _first.delegate = nil;
    _last.delegate = nil;
    _note.delegate = nil;
    [_person release];
    [_full release];
    [_scroll release];
    [_nameCard release];
    [_nameCaption release];
    [_first release];
    [_last release];
    [_nameLine release];
    [_noteCard release];
    [_noteCaption release];
    [_note release];
    [_noteHint release];
    [_photoCard release];
    for (int i = 0; i < 3; ++i) [_photoRows[i] release];
    [_photoLines[0] release];
    [_photoLines[1] release];
    [_photoHint release];
    [_spinner release];
    [_changedHandler release];
    [super dealloc];
}

static UIView *ExteriaContactCard(void) {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = ExteriaColorCard();
    card.layer.cornerRadius = 14;
    return card;
}

static UIView *ExteriaContactLine(void) {
    UIView *line = [[UIView alloc] init];
    line.backgroundColor = ExteriaColorHairline();
    return line;
}

static UILabel *ExteriaContactLabel(UIColor *color, CGFloat size, BOOL bold) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = bold ? ExteriaFontSemibold(size) : ExteriaFontRegular(size);
    return label;
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text words:(BOOL)words {
    UITextField *field = [[UITextField alloc] init];
    field.delegate = self;
    field.font = ExteriaFontRegular(17);
    field.textColor = ExteriaColorTitle();
    field.placeholder = placeholder;
    field.text = text;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    /* a text field aligns its text to the top of a tall frame on ios 5 and 6 */
    field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    field.returnKeyType = UIReturnKeyDone;
    field.autocorrectionType = UITextAutocorrectionTypeDefault;
    field.autocapitalizationType = words ? UITextAutocapitalizationTypeWords : UITextAutocapitalizationTypeSentences;
    field.keyboardAppearance = ExteriaThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    return field;
}

- (UIControl *)photoRowWithSymbol:(ExteriaSymbol)symbol color:(UIColor *)color title:(NSString *)title action:(SEL)action {
    UIControl *row = [[UIControl alloc] init];
    [row addSubview:ExteriaRowIcon(symbol, color)];
    UILabel *label = ExteriaContactLabel(ExteriaColorTitle(), 17, NO);
    label.tag = 1;
    label.text = title;
    [row addSubview:label];
    [label release];
    [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return row;
}

/* the photo and the note belong to a contact: the server refuses both for a person who is not in the contacts */
- (BOOL)isContact {
    return _person.contact;
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
    _nameCard = ExteriaContactCard();
    [_scroll addSubview:_nameCard];
    _nameCaption = ExteriaContactLabel(ExteriaColorAccent(), 14, YES);
    _nameCaption.text = NSLocalizedString(@"contact.name.caption", nil);
    [_nameCard addSubview:_nameCaption];
    _first = [self fieldWithPlaceholder:NSLocalizedString(@"profile.edit.first", nil) text:first words:YES];
    [_nameCard addSubview:_first];
    _last = [self fieldWithPlaceholder:NSLocalizedString(@"profile.edit.last", nil) text:last words:YES];
    [_nameCard addSubview:_last];
    _nameLine = ExteriaContactLine();
    [_nameCard addSubview:_nameLine];

    if ([self isContact]) {
        _noteCard = ExteriaContactCard();
        [_scroll addSubview:_noteCard];
        _noteCaption = ExteriaContactLabel(ExteriaColorAccent(), 14, YES);
        _noteCaption.text = NSLocalizedString(@"contact.note.caption", nil);
        [_noteCard addSubview:_noteCaption];
        _note = [self fieldWithPlaceholder:NSLocalizedString(@"contact.note.placeholder", nil) text:_full.note words:NO];
        [_noteCard addSubview:_note];
        _noteHint = ExteriaContactLabel(ExteriaColorSecondary(), 13, NO);
        _noteHint.numberOfLines = 0;
        _noteHint.text = NSLocalizedString(@"contact.note.hint", nil);
        [_scroll addSubview:_noteHint];

        _photoCard = ExteriaContactCard();
        [_scroll addSubview:_photoCard];
        _photoRows[ExteriaContactPhotoSuggest] = [self photoRowWithSymbol:ExteriaSymbolCameraPlus color:[UIColor colorWithRed:0.24 green:0.58 blue:0.95 alpha:1]
                                                                    title:NSLocalizedString(@"contact.photo.suggest", nil) action:@selector(suggestPhoto)];
        _photoRows[ExteriaContactPhotoSet] = [self photoRowWithSymbol:ExteriaSymbolGallery color:[UIColor colorWithRed:0.30 green:0.76 blue:0.40 alpha:1]
                                                                title:NSLocalizedString(@"contact.photo.set", nil) action:@selector(setOwnPhoto)];
        _photoRows[ExteriaContactPhotoReset] = [self photoRowWithSymbol:ExteriaSymbolUndo color:[UIColor colorWithRed:0.96 green:0.62 blue:0.18 alpha:1]
                                                                  title:NSLocalizedString(@"contact.photo.reset", nil) action:@selector(resetPhoto)];
        for (int i = 0; i < 3; ++i) [_photoCard addSubview:_photoRows[i]];
        for (int i = 0; i < 2; ++i) {
            _photoLines[i] = ExteriaContactLine();
            [_photoCard addSubview:_photoLines[i]];
        }
        _photoHint = ExteriaContactLabel(ExteriaColorSecondary(), 13, NO);
        _photoHint.numberOfLines = 0;
        _photoHint.text = NSLocalizedString(@"contact.photo.hint", nil);
        [_scroll addSubview:_photoHint];
    }
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:ExteriaThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [_scroll addSubview:_spinner];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)layoutBody:(CGRect)body {
    _scroll.frame = body;
    CGFloat width = body.size.width;
    CGFloat inner = MIN(width - 32, 480);
    CGFloat x = (width - inner) / 2;
    CGFloat y = GAP;
    CGFloat hair = 1.0 / [UIScreen mainScreen].scale;
    _nameCard.frame = CGRectMake(x, y, inner, CAPTION_HEIGHT + 2 * FIELD_HEIGHT);
    _nameCaption.frame = CGRectMake(16, 8, inner - 32, 18);
    _first.frame = CGRectMake(16, CAPTION_HEIGHT, inner - 24, FIELD_HEIGHT);
    _nameLine.frame = CGRectMake(16, CAPTION_HEIGHT + FIELD_HEIGHT, inner - 16, hair);
    _last.frame = CGRectMake(16, CAPTION_HEIGHT + FIELD_HEIGHT, inner - 24, FIELD_HEIGHT);
    y += _nameCard.frame.size.height + GAP;
    if (_noteCard) {
        _noteCard.frame = CGRectMake(x, y, inner, CAPTION_HEIGHT + FIELD_HEIGHT);
        _noteCaption.frame = CGRectMake(16, 8, inner - 32, 18);
        _note.frame = CGRectMake(16, CAPTION_HEIGHT, inner - 24, FIELD_HEIGHT);
        y += _noteCard.frame.size.height + 6;
        CGSize hint = [_noteHint sizeThatFits:CGSizeMake(inner - 24, 100)];
        _noteHint.frame = CGRectMake(x + 12, y, inner - 24, hint.height);
        y += hint.height + GAP;
        _photoRows[ExteriaContactPhotoReset].hidden = !_hasPersonalPhoto;
        NSUInteger rows = _hasPersonalPhoto ? 3 : 2;
        _photoCard.frame = CGRectMake(x, y, inner, ROW_HEIGHT * (CGFloat)rows);
        for (NSUInteger i = 0; i < 3; ++i) {
            UIControl *row = _photoRows[i];
            row.frame = CGRectMake(0, ROW_HEIGHT * (CGFloat)i, inner, ROW_HEIGHT);
            UIView *icon = [row.subviews objectAtIndex:0];
            icon.frame = CGRectMake(16, (ROW_HEIGHT - icon.bounds.size.height) / 2, icon.bounds.size.width, icon.bounds.size.height);
            [row viewWithTag:1].frame = CGRectMake(16 + 32 + 14, 0, inner - 62 - 16, ROW_HEIGHT);
        }
        for (NSUInteger i = 0; i < 2; ++i) {
            _photoLines[i].hidden = i + 1 >= rows;
            _photoLines[i].frame = CGRectMake(62, ROW_HEIGHT * (CGFloat)(i + 1), inner - 62, hair);
        }
        y += _photoCard.frame.size.height + 6;
        CGSize photoHint = [_photoHint sizeThatFits:CGSizeMake(inner - 24, 120)];
        _photoHint.frame = CGRectMake(x + 12, y, inner - 24, photoHint.height);
        y += photoHint.height + GAP;
    }
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

#pragma mark fields

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *next = [field.text stringByReplacingCharactersInRange:range withString:string];
    return next.length <= (field == _note ? NOTE_LIMIT : NAME_LIMIT);
}

#pragma mark photo

- (void)setWorking:(BOOL)working {
    _working = working;
    _first.enabled = _last.enabled = _note.enabled = !working;
    if (working) [_spinner startAnimating];
    else [_spinner stopAnimating];
}

- (void)notifyChanged {
    if (_changedHandler) _changedHandler();
}

/* the picker hands over a square jpeg, which this screen deletes once the upload has ended */
- (void)pickPhotoThenSuggest:(BOOL)suggest {
    if (_working) return;
    [self.view endEditing:YES];
    ExteriaWeakReference *me = _weak;
    [ExteriaProfilePhotoPicker pickFrom:self picked:^(NSString *path) {
        ExteriaContactEditController *edit = me.target;
        if (!edit) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            return;
        }
        [edit setWorking:YES];
        [edit retain];
        [edit.session uploadContactPhotoAtPath:path ofPerson:edit->_person suggest:suggest completion:^(NSString *errorName) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            [edit autorelease];
            [edit setWorking:NO];
            if (errorName) {
                NSLog(@"exteria: the contact photo was not sent: %@", errorName);
                ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
                return;
            }
            if (suggest) {
                ExteriaGiftAlert(nil, NSLocalizedString(@"contact.photo.suggested", nil));
                return;
            }
            edit->_hasPersonalPhoto = YES;
            [edit.view setNeedsLayout];
            [edit notifyChanged];
        }];
    } unavailable:^{
        ExteriaGiftAlert(nil, NSLocalizedString(@"attach.failed", nil));
    }];
}

- (void)suggestPhoto {
    [self pickPhotoThenSuggest:YES];
}

- (void)setOwnPhoto {
    [self pickPhotoThenSuggest:NO];
}

- (void)resetPhoto {
    if (_working) return;
    ExteriaWeakReference *me = _weak;
    ExteriaConfirm(nil, NSLocalizedString(@"contact.photo.reset.confirm", nil), NSLocalizedString(@"contact.photo.reset", nil), ^{
        ExteriaContactEditController *edit = me.target;
        if (!edit) return;
        [edit setWorking:YES];
        [edit retain];
        [edit.session resetContactPhotoOfPerson:edit->_person completion:^(NSString *errorName) {
            [edit autorelease];
            [edit setWorking:NO];
            if (errorName) {
                NSLog(@"exteria: the contact photo was not reset: %@", errorName);
                ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
                return;
            }
            edit->_hasPersonalPhoto = NO;
            [edit.view setNeedsLayout];
            [edit notifyChanged];
        }];
    });
}

#pragma mark saving

static NSString *ExteriaContactTrimmed(NSString *text) {
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/* the name goes first and the note after it: the note of a person that was not in the contacts yet needs the name's call to have made them one */
- (void)save {
    if (_working) return;
    [self.view endEditing:YES];
    NSString *first = ExteriaContactTrimmed(_first.text), *last = ExteriaContactTrimmed(_last.text);
    if (!first.length) {
        ExteriaGiftAlert(nil, NSLocalizedString(@"profile.edit.noname", nil));
        return;
    }
    NSRange space = [_person.name rangeOfString:@" "];
    NSString *oldFirst = space.location == NSNotFound ? _person.name : [_person.name substringToIndex:space.location];
    NSString *oldLast = space.location == NSNotFound ? @"" : [_person.name substringFromIndex:space.location + 1];
    BOOL nameChanged = ![first isEqualToString:oldFirst] || ![last isEqualToString:oldLast];
    NSString *note = _note ? ExteriaContactTrimmed(_note.text) : nil;
    BOOL noteChanged = note && ![note isEqualToString:_full.note ? _full.note : @""];
    if (!nameChanged && !noteChanged) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self setWorking:YES];
    [self retain];
    void (^finish)(NSString *) = [^(NSString *errorName) {
        [self autorelease];
        [self setWorking:NO];
        if (errorName) {
            NSLog(@"exteria: the contact was not saved: %@", errorName);
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        [self notifyChanged];
        [self.navigationController popViewControllerAnimated:YES];
    } copy];
    void (^saveNote)(void) = [^{
        if (!noteChanged) {
            finish(nil);
            return;
        }
        [self.session setContactNote:note ofPerson:_person completion:finish];
    } copy];
    if (nameChanged) {
        [self.session editContact:_person firstName:first lastName:last completion:^(NSString *errorName) {
            if (errorName) finish(errorName);
            else saveNote();
            [saveNote release];
            [finish release];
        }];
    } else {
        saveNote();
        [saveNote release];
        [finish release];
    }
}

@end
