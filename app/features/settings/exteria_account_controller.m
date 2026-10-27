#import "exteria_account_controller.h"

#import "exteria_accounts.h"
#import "exteria_alert.h"
#import "exteria_date_sheet.h"
#import "exteria_people_avatars.h"
#import "exteria_text_filter.h"
#import "exteria_channel_picker_controller.h"
#import "exteria_gift_screen.h"
#import "exteria_session_profile.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

/* the account page asks for the person and the full profile one after the other, and the privacy rule of the bio on its own */
@interface ExteriaAccountController () {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    ExteriaPerson *_person;
    ExteriaFullUser *_full;
    ExteriaPeopleAvatars *_faces;
    BOOL _working;
    void (^_changedHandler)(void);
    void (^_logoutHandler)(void);
}
@end

@implementation ExteriaAccountController

@synthesize changedHandler = _changedHandler;
@synthesize logoutHandler = _logoutHandler;

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"account.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_avatars release];
    [_media release];
    [_person release];
    [_full release];
    [_faces invalidate];
    [_faces release];
    [_changedHandler release];
    [_logoutHandler release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self load];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

#pragma mark loading

- (void)load {
    ExteriaWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        ExteriaAccountController *me = weak.target;
        if (!me) return;
        if (!items.count) {
            NSLog(@"exteria: the account page did not load the person: %@", errorName);
            return;
        }
        [me->_person release];
        me->_person = [[items objectAtIndex:0] retain];
        ExteriaAccountSetInfo(ExteriaAccountActive(), me->_person.name, me->_person.username, me->_person.userId);
        [me rebuild];
        [me loadFull];
    }];
}

- (void)loadFull {
    if (!_person) return;
    ExteriaWeakReference *weak = _weak;
    [_session loadFullUserOfDialog:[ExteriaDialog savedMessagesWithPerson:_person] completion:^(ExteriaFullUser *user, NSString *errorName) {
        ExteriaAccountController *me = weak.target;
        if (!me) return;
        if (!user) {
            NSLog(@"exteria: the account page did not load the profile: %@", errorName);
            return;
        }
        [me->_full release];
        me->_full = [user retain];
        [me rebuild];
    }];
}

#pragma mark editing

- (NSString *)firstName {
    NSRange space = [_person.name rangeOfString:@" "];
    return space.location == NSNotFound ? _person.name : [_person.name substringToIndex:space.location];
}

- (NSString *)lastName {
    NSRange space = [_person.name rangeOfString:@" "];
    return space.location == NSNotFound ? @"" : [_person.name substringFromIndex:space.location + 1];
}

static NSString *ExteriaAccountErrorText(NSString *errorName) {
    if ([errorName isEqualToString:@"FIRSTNAME_INVALID"]) return NSLocalizedString(@"profile.edit.noname", nil);
    if ([errorName isEqualToString:@"ABOUT_TOO_LONG"]) return NSLocalizedString(@"profile.edit.longabout", nil);
    return ExteriaGiftErrorText(errorName);
}

/* a nil part stays as it is on the server */
- (void)saveFirst:(NSString *)first last:(NSString *)last about:(NSString *)about {
    if (_working) return;
    _working = YES;
    ExteriaWeakReference *weak = _weak;
    [_session updateFirstName:first lastName:last about:about completion:^(ExteriaPerson *person, NSString *errorName) {
        ExteriaAccountController *me = weak.target;
        if (!me) return;
        me->_working = NO;
        if (errorName) {
            ExteriaGiftAlert(nil, ExteriaAccountErrorText(errorName));
            return;
        }
        if (person) {
            [me->_person release];
            me->_person = [person retain];
        }
        if (me->_changedHandler) me->_changedHandler();
        [me loadFull];
        [me rebuild];
    }];
}

- (void)editFirst {
    if (!_person) return;
    ExteriaWeakReference *weak = _weak;
    ExteriaPromptText(NSLocalizedString(@"profile.edit.first", nil), nil, [self firstName], NSLocalizedString(@"profile.edit.first", nil), ^(NSString *text) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!trimmed.length) {
            ExteriaGiftAlert(nil, NSLocalizedString(@"profile.edit.noname", nil));
            return;
        }
        [(ExteriaAccountController *)weak.target saveFirst:trimmed last:nil about:nil];
    });
}

- (void)editLast {
    if (!_person) return;
    ExteriaWeakReference *weak = _weak;
    ExteriaPromptText(NSLocalizedString(@"profile.edit.last", nil), nil, [self lastName], NSLocalizedString(@"profile.edit.last", nil), ^(NSString *text) {
        [(ExteriaAccountController *)weak.target saveFirst:nil last:[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] about:nil];
    });
}

- (void)editAbout {
    if (!_full) return;
    ExteriaWeakReference *weak = _weak;
    ExteriaPromptText(NSLocalizedString(@"profile.about", nil), NSLocalizedString(@"profile.edit.hint.about", nil), _full.about, NSLocalizedString(@"profile.about", nil), ^(NSString *text) {
        [(ExteriaAccountController *)weak.target saveFirst:nil last:nil about:text];
    });
}

- (void)editUsername {
    if (!_person) return;
    ExteriaWeakReference *weak = _weak;
    ExteriaPromptText(NSLocalizedString(@"profile.username", nil), NSLocalizedString(@"profile.edit.hint", nil), _person.username, NSLocalizedString(@"profile.username", nil), ^(NSString *text) {
        ExteriaAccountController *me = weak.target;
        if (!me || me->_working) return;
        NSString *name = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([name hasPrefix:@"@"]) name = [name substringFromIndex:1];
        me->_working = YES;
        [me->_session updateUsername:name completion:^(ExteriaPerson *person, NSString *errorName) {
            ExteriaAccountController *again = weak.target;
            if (!again) return;
            again->_working = NO;
            if (errorName) {
                NSString *key = nil;
                if ([errorName isEqualToString:@"USERNAME_OCCUPIED"] || [errorName isEqualToString:@"USERNAME_PURCHASE_AVAILABLE"]) key = @"profile.edit.taken";
                else if ([errorName isEqualToString:@"USERNAME_INVALID"] || [errorName isEqualToString:@"USERNAME_NOT_MODIFIED"]) key = @"profile.edit.badusername";
                ExteriaGiftAlert(nil, key ? NSLocalizedString(key, nil) : ExteriaGiftErrorText(errorName));
                return;
            }
            if (person) {
                [again->_person release];
                again->_person = [person retain];
            }
            ExteriaAccountSetInfo(ExteriaAccountActive(), again->_person.name, again->_person.username, again->_person.userId);
            if (again->_changedHandler) again->_changedHandler();
            [again rebuild];
        }];
    });
}

- (void)chooseBirthday {
    if (!_full || _working) return;
    ExteriaDateSheet *sheet = [[[ExteriaDateSheet alloc] initWithDay:_full.birthdayDay month:_full.birthdayMonth year:_full.birthdayYear] autorelease];
    sheet.canRemove = _full.hasBirthday;
    ExteriaWeakReference *weak = _weak;
    sheet.doneHandler = ^(int32_t day, int32_t month, int32_t year) {
        ExteriaAccountController *me = weak.target;
        if (!me || me->_working) return;
        me->_working = YES;
        [me->_session setBirthdayDay:day month:month year:year completion:^(NSString *errorName) { [(ExteriaAccountController *)weak.target birthdayDone:errorName]; }];
    };
    sheet.removeHandler = ^{
        ExteriaAccountController *me = weak.target;
        if (!me || me->_working) return;
        me->_working = YES;
        [me->_session clearBirthday:^(NSString *errorName) { [(ExteriaAccountController *)weak.target birthdayDone:errorName]; }];
    };
    [sheet showInView:self.view];
}

- (void)birthdayDone:(NSString *)errorName {
    _working = NO;
    if (errorName) {
        ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
        return;
    }
    [self loadFull];
}

- (NSString *)birthdayText {
    if (!_full) return nil;
    if (!_full.hasBirthday) return NSLocalizedString(@"account.empty", nil);
    NSDateComponents *parts = [[[NSDateComponents alloc] init] autorelease];
    parts.day = _full.birthdayDay;
    parts.month = _full.birthdayMonth;
    parts.year = _full.birthdayYear > 0 ? _full.birthdayYear : 2000;
    NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:parts];
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    formatter.dateFormat = _full.birthdayYear > 0 ? @"d MMMM yyyy" : @"d MMMM";
    return date ? [formatter stringFromDate:date] : NSLocalizedString(@"account.empty", nil);
}

- (void)chooseChannel {
    if (!_full || _working) return;
    ExteriaChannelPickerController *picker = [[[ExteriaChannelPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"profile.channel", nil);
    picker.currentChannelId = _full.channel ? _full.channel.dialog.peerId : 0;
    ExteriaWeakReference *weak = _weak;
    ExteriaWeakReference *pickerRef = [ExteriaWeakReference referenceTo:picker];
    picker.pickHandler = ^(ExteriaDialog *channel) {
        ExteriaAccountController *me = weak.target;
        UIViewController *host = pickerRef.target;
        if (host) [host.navigationController popViewControllerAnimated:YES];
        if (me) [me saveChannel:channel];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)saveChannel:(ExteriaDialog *)channel {
    if (_working) return;
    _working = YES;
    ExteriaWeakReference *weak = _weak;
    [_session setPersonalChannel:channel completion:^(NSString *errorName) {
        ExteriaAccountController *me = weak.target;
        if (!me) return;
        me->_working = NO;
        if (errorName) {
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        if (me->_changedHandler) me->_changedHandler();
        [me loadFull];
    }];
}

#pragma mark rows

- (UIImage *)faceForAccount:(NSString *)name title:(NSString *)title active:(BOOL)active {
    if (!_faces) {
        ExteriaWeakReference *weak = _weak;
        _faces = [[ExteriaPeopleAvatars alloc] initWithCache:_avatars changed:^{ [(ExteriaAccountController *)weak.target rebuild]; }];
    }
    NSDictionary *info = ExteriaAccountInfo(name);
    long long user = active ? _person.userId : [[info objectForKey:@"user"] longLongValue];
    return [_faces imageForKey:[@"account:" stringByAppendingString:name] initials:ExteriaInitialsOfName(title) seed:(NSUInteger)(user % 1000003) deleted:NO
                         photo:active ? _person.photo : nil];
}

- (ExteriaSettingsRow *)rowOfAccount:(NSString *)name {
    BOOL active = [name isEqualToString:ExteriaAccountActive()];
    NSDictionary *info = ExteriaAccountInfo(name);
    NSString *title = active && _person ? _person.name : [info objectForKey:@"title"];
    NSString *username = active && _person ? _person.username : [info objectForKey:@"username"];
    if (!title.length) title = NSLocalizedString(@"account.title", nil);
    ExteriaSettingsRow *row = [ExteriaSettingsRow rowWithTileImage:[self faceForAccount:name title:title active:active] title:title
                                                          subtitle:username.length ? [@"@" stringByAppendingString:username] : nil tap:^{
        if (!active) [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaAccountSwitchNotification object:nil userInfo:[NSDictionary dictionaryWithObject:name forKey:@"name"]];
    }];
    if (active) row.trailingImage = ExteriaSymbolImage(ExteriaSymbolCheck, 22, ExteriaColorAccent());
    return row;
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    ExteriaSettingsRow *first = [ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"profile.edit.first", nil) value:_person ? [self firstName] : nil
                                                             tap:^{ [(ExteriaAccountController *)weak.target editFirst]; }];
    ExteriaSettingsRow *last = [ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"profile.edit.last", nil)
                                                          value:_person ? ([[self lastName] length] ? [self lastName] : NSLocalizedString(@"account.empty", nil)) : nil
                                                            tap:^{ [(ExteriaAccountController *)weak.target editLast]; }];
    NSString *about = _full ? (_full.about.length ? _full.about : NSLocalizedString(@"account.empty", nil)) : nil;
    ExteriaSettingsRow *bio = [ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"profile.about", nil) value:about
                                                           tap:^{ [(ExteriaAccountController *)weak.target editAbout]; }];
    ExteriaSettingsRow *phone = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolPhone tone:ExteriaSettingsToneGreen title:NSLocalizedString(@"profile.phone", nil) subtitle:nil
                                                            value:_person ? ExteriaOwnPhoneText(_person.phone) : nil
                                                              tap:^{ ExteriaGiftAlert(nil, NSLocalizedString(@"account.phone.info", nil)); }];
    ExteriaSettingsRow *username = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolAt tone:ExteriaSettingsToneOrange title:NSLocalizedString(@"profile.username", nil) subtitle:nil
                                                               value:_person ? (_person.username.length ? [@"@" stringByAppendingString:_person.username] : NSLocalizedString(@"account.empty", nil)) : nil
                                                                 tap:^{ [(ExteriaAccountController *)weak.target editUsername]; }];
    ExteriaSettingsRow *birthday = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolCake tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"profile.birthday", nil) subtitle:nil
                                                               value:[self birthdayText] tap:^{ [(ExteriaAccountController *)weak.target chooseBirthday]; }];
    ExteriaSettingsRow *channel = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolMegaphone tone:ExteriaSettingsToneOrange title:NSLocalizedString(@"profile.channel", nil)
                                                           subtitle:nil value:_full ? (_full.channel ? _full.channel.dialog.title : NSLocalizedString(@"profile.channel.add", nil)) : nil
                                                                tap:^{ [(ExteriaAccountController *)weak.target chooseChannel]; }];
    ExteriaSettingsRow *add = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolPlusCircle title:NSLocalizedString(@"account.add", nil) destructive:NO
                                                                  tap:^{ [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaAccountAddNotification object:nil]; }];
    NSMutableArray *accounts = [NSMutableArray arrayWithObject:add];
    for (NSString *name in ExteriaAccountNames()) [accounts addObject:[self rowOfAccount:name]];
    ExteriaSettingsRow *logout = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolLogout title:NSLocalizedString(@"profile.signout", nil) destructive:YES tap:^{
        ExteriaAccountController *me = weak.target;
        if (me && me->_logoutHandler) me->_logoutHandler();
    }];
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"profile.edit.yourname", nil) footer:NSLocalizedString(@"account.about.info", nil)
                                                             rows:[NSArray arrayWithObjects:first, last, bio, nil]]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"profile.edit.info", nil) footer:NSLocalizedString(@"profile.edit.hint", nil)
                                                             rows:[NSArray arrayWithObjects:phone, username, birthday, nil]]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"account.channel.info", nil) rows:[NSArray arrayWithObject:channel]]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"account.accounts", nil) footer:NSLocalizedString(@"account.accounts.info", nil) rows:accounts]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:logout]]];
    self.sections = sections;
    [self reloadSettings];
}

@end
