#import "exteria_privacy_controller.h"

#import "exteria_classic_devices_controller.h"
#import "exteria_contact_picker_controller.h"
#import "exteria_devices_controller.h"
#import "exteria_dialog_picker_controller.h"
#import "exteria_gift_screen.h"
#import "exteria_people_avatars.h"
#import "exteria_person.h"
#import "exteria_sheet.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_time.h"
#import "exteria_weak_reference.h"

/* the seconds of the default auto-delete the server offers: off, a day, a week, a month */
#define TTL_DAY 86400
#define TTL_WEEK 604800
#define TTL_MONTH 2678400

static const struct { exteria_privacy_key key; ExteriaSymbol symbol; ExteriaSettingsTone tone; NSString *title; NSString *who; } ExteriaPrivacyKeys[] = {
    {EXTERIA_PRIVACY_PHONE, ExteriaSymbolPhone, ExteriaSettingsToneBlue, @"privacy.phone", @"privacy.who.phone"},
    {EXTERIA_PRIVACY_LAST_SEEN, ExteriaSymbolClock, ExteriaSettingsToneGreen, @"privacy.lastseen", @"privacy.who.lastseen"},
    {EXTERIA_PRIVACY_PHOTO, ExteriaSymbolGallery, ExteriaSettingsToneOrange, @"privacy.photo", @"privacy.who.photo"},
    {EXTERIA_PRIVACY_FORWARDS, ExteriaSymbolForward, ExteriaSettingsToneCyan, @"privacy.forwards", @"privacy.who.forwards"},
    {EXTERIA_PRIVACY_CALLS, ExteriaSymbolCallback, ExteriaSettingsToneRed, @"privacy.calls", @"privacy.who.calls"},
    {EXTERIA_PRIVACY_VOICE, ExteriaSymbolMicrophone, ExteriaSettingsTonePurple, @"privacy.voice", @"privacy.who.voice"},
    {EXTERIA_PRIVACY_ABOUT, ExteriaSymbolInfo, ExteriaSettingsToneBlueDeep, @"privacy.about", @"privacy.who.about"},
    {EXTERIA_PRIVACY_BIRTHDAY, ExteriaSymbolCake, ExteriaSettingsToneOrangeBright, @"privacy.birthday", @"privacy.who.birthday"},
    {EXTERIA_PRIVACY_MUSIC, ExteriaSymbolMusic, ExteriaSettingsToneRed, @"privacy.music", @"privacy.who.music"},
    {EXTERIA_PRIVACY_INVITES, ExteriaSymbolGroupsMenu, ExteriaSettingsToneGreen, @"privacy.invites", @"privacy.who.invites"},
};
#define PRIVACY_KEY_ROWS (sizeof(ExteriaPrivacyKeys) / sizeof(ExteriaPrivacyKeys[0]))

/* the base of a rule in words, and what the exceptions add to it, the way the settings of the original client write it: "Contacts (+2, -1)" */
NSString *ExteriaPrivacyValue(ExteriaPrivacyRules *rules) {
    NSString *base;
    switch (rules.base) {
    case EXTERIA_PRIVACY_EVERYBODY: base = NSLocalizedString(@"privacy.everybody", nil); break;
    case EXTERIA_PRIVACY_CONTACTS: base = NSLocalizedString(@"privacy.contacts", nil); break;
    default: base = NSLocalizedString(@"privacy.nobody", nil); break;
    }
    NSUInteger allowed = [rules countAllowed:YES], never = [rules countAllowed:NO];
    /* what contradicts the base has no meaning, so it is not counted: an exception that adds a person to everybody changes nothing */
    BOOL showAllowed = allowed && rules.base != EXTERIA_PRIVACY_EVERYBODY;
    BOOL showNever = never && rules.base != EXTERIA_PRIVACY_NOBODY;
    if (showAllowed && showNever) return [NSString stringWithFormat:@"%@ (+%lu, -%lu)", base, (unsigned long)allowed, (unsigned long)never];
    if (showAllowed) return [NSString stringWithFormat:@"%@ (+%lu)", base, (unsigned long)allowed];
    if (showNever) return [NSString stringWithFormat:@"%@ (-%lu)", base, (unsigned long)never];
    return base;
}

static NSString *ExteriaHistoryTTLText(int32_t seconds) {
    if (seconds <= 0) return NSLocalizedString(@"privacy.ttl.off", nil);
    if (seconds == TTL_DAY) return NSLocalizedString(@"privacy.ttl.day", nil);
    if (seconds == TTL_WEEK) return NSLocalizedString(@"privacy.ttl.week", nil);
    if (seconds == TTL_MONTH) return NSLocalizedString(@"privacy.ttl.month", nil);
    return [NSString stringWithFormat:NSLocalizedString(@"privacy.ttl.days", nil), (int)(seconds / TTL_DAY)];
}

static NSString *ExteriaAccountTTLText(int32_t days) {
    if (days == 30) return NSLocalizedString(@"privacy.away.1", nil);
    if (days == 90) return NSLocalizedString(@"privacy.away.3", nil);
    if (days == 180) return NSLocalizedString(@"privacy.away.6", nil);
    if (days == 365) return NSLocalizedString(@"privacy.away.12", nil);
    /* the server keeps any period from 30 to 730 days, and other apps set ones such as 18 months */
    if (days >= 730) return [NSString stringWithFormat:NSLocalizedString(@"privacy.away.years", nil), 2];
    if (days >= 60) return [NSString stringWithFormat:NSLocalizedString(@"privacy.away.months", nil), (int)((days + 15) / 30)];
    return [NSString stringWithFormat:NSLocalizedString(@"privacy.ttl.days", nil), (int)days];
}

/* what to say of a failed call: a list too long for the screen has a line of its own, the rest the plain names of the server */
static void ExteriaPrivacyFail(NSString *errorName) {
    NSString *text = [errorName isEqualToString:@"PRIVACY_TOO_MANY"] ? NSLocalizedString(@"privacy.error.toomany", nil)
        : [errorName isEqualToString:@"PREMIUM_ACCOUNT_REQUIRED"] ? NSLocalizedString(@"privacy.error.premium", nil)
        : [NSString stringWithFormat:NSLocalizedString(@"privacy.error", nil), errorName];
    ExteriaGiftAlert(nil, text);
}

#pragma mark main screen

@interface ExteriaPrivacyController () {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    ExteriaPrivacyRules *_rules[EXTERIA_PRIVACY_KEY_COUNT];
    int32_t _blocked;
    BOOL _blockedKnown;
    int32_t _historyTTL;
    BOOL _historyKnown;
    int32_t _accountTTL;
    BOOL _accountKnown;
    BOOL _loaded;
}
@end

@implementation ExteriaPrivacyController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"privacy.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    for (int i = 0; i < EXTERIA_PRIVACY_KEY_COUNT; ++i) [_rules[i] release];
    [_session release];
    [_avatars release];
    [_media release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self loadAll];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaPrivacyController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
}

/* everything the rows show comes from the server, one call each, and the rows fill in as the answers come */
- (void)loadAll {
    ExteriaWeakReference *weak = _weak;
    for (size_t i = 0; i < PRIVACY_KEY_ROWS; ++i) {
        exteria_privacy_key key = ExteriaPrivacyKeys[i].key;
        [_session loadPrivacy:key completion:^(ExteriaPrivacyRules *rules, NSString *error) {
            ExteriaPrivacyController *me = weak.target;
            if (!me) return;
            if (!rules) {
                NSLog(@"exteria: privacy rule %d did not load: %@", (int)key, error);
                return;
            }
            [me->_rules[key] release];
            me->_rules[key] = [rules retain];
            [me rebuild];
        }];
    }
    [_session loadBlockedFrom:0 completion:^(NSArray *peers, int32_t total, NSString *error) {
        ExteriaPrivacyController *me = weak.target;
        if (!me) return;
        if (!peers) { NSLog(@"exteria: the blocked list did not load: %@", error); return; }
        me->_blocked = total;
        me->_blockedKnown = YES;
        [me rebuild];
    }];
    [_session loadHistoryTTL:^(int32_t seconds, NSString *error) {
        ExteriaPrivacyController *me = weak.target;
        if (!me) return;
        if (error) { NSLog(@"exteria: the auto-delete time did not load: %@", error); return; }
        me->_historyTTL = seconds;
        me->_historyKnown = YES;
        [me rebuild];
    }];
    [_session loadAccountTTL:^(int32_t days, NSString *error) {
        ExteriaPrivacyController *me = weak.target;
        if (!me) return;
        if (error) { NSLog(@"exteria: the account time did not load: %@", error); return; }
        me->_accountTTL = days;
        me->_accountKnown = YES;
        [me rebuild];
    }];
}

- (void)open:(UIViewController *)page {
    [self.navigationController pushViewController:page animated:YES];
}

- (void)openRule:(exteria_privacy_key)key {
    ExteriaPrivacyRules *rules = _rules[key];
    /* the rule is asked for again if it did not come the first time, and the page opens when it is here */
    if (!rules) {
        ExteriaWeakReference *weak = _weak;
        [_session loadPrivacy:key completion:^(ExteriaPrivacyRules *loaded, NSString *error) {
            ExteriaPrivacyController *me = weak.target;
            if (!me) return;
            if (!loaded) { ExteriaPrivacyFail(error); return; }
            [me->_rules[key] release];
            me->_rules[key] = [loaded retain];
            [me rebuild];
            [me openRule:key];
        }];
        return;
    }
    ExteriaWeakReference *weak = _weak;
    ExteriaPrivacyRuleController *page = [[[ExteriaPrivacyRuleController alloc] initWithSession:_session rules:rules avatars:_avatars media:_media] autorelease];
    page.changedHandler = ^(ExteriaPrivacyRules *fresh) {
        ExteriaPrivacyController *me = weak.target;
        if (!me) return;
        [me->_rules[key] release];
        me->_rules[key] = [fresh retain];
        [me rebuild];
    };
    [self open:page];
}

- (void)openBlocked {
    ExteriaWeakReference *weak = _weak;
    ExteriaBlockedController *page = [[[ExteriaBlockedController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    page.countHandler = ^(int32_t total) {
        ExteriaPrivacyController *me = weak.target;
        if (!me) return;
        me->_blocked = total;
        me->_blockedKnown = YES;
        [me rebuild];
    };
    [self open:page];
}

- (void)openDevices {
    [self open:ExteriaThemeIsClassic() ? (UIViewController *)[[[ExteriaClassicDevicesController alloc] initWithSession:_session media:_media] autorelease]
                                       : (UIViewController *)[[[ExteriaDevicesController alloc] initWithSession:_session media:_media] autorelease]];
}

- (void)chooseHistoryTTL {
    ExteriaWeakReference *weak = _weak;
    static const int32_t values[] = {0, TTL_DAY, TTL_WEEK, TTL_MONTH};
    NSArray *options = [NSArray arrayWithObjects:ExteriaHistoryTTLText(0), ExteriaHistoryTTLText(TTL_DAY), ExteriaHistoryTTLText(TTL_WEEK), ExteriaHistoryTTLText(TTL_MONTH), nil];
    ExteriaSettingsChoose(self, NSLocalizedString(@"privacy.autodelete", nil), options, ^(NSUInteger index) {
        ExteriaPrivacyController *me = weak.target;
        if (!me || index >= 4) return;
        int32_t seconds = values[index];
        int32_t before = me->_historyTTL;
        /* the row shows the choice at once, and goes back to what it was when the server refuses */
        me->_historyTTL = seconds;
        [me rebuild];
        [me->_session setHistoryTTL:seconds completion:^(NSString *error) {
            ExteriaPrivacyController *again = weak.target;
            if (!error) return;
            ExteriaPrivacyFail(error);
            if (!again) return;
            again->_historyTTL = before;
            [again rebuild];
        }];
    });
}

- (void)chooseAccountTTL {
    ExteriaWeakReference *weak = _weak;
    static const int32_t values[] = {30, 90, 180, 365};
    NSArray *options = [NSArray arrayWithObjects:ExteriaAccountTTLText(30), ExteriaAccountTTLText(90), ExteriaAccountTTLText(180), ExteriaAccountTTLText(365), nil];
    ExteriaSettingsChoose(self, NSLocalizedString(@"privacy.away", nil), options, ^(NSUInteger index) {
        ExteriaPrivacyController *me = weak.target;
        if (!me || index >= 4) return;
        int32_t days = values[index];
        int32_t before = me->_accountTTL;
        me->_accountTTL = days;
        [me rebuild];
        [me->_session setAccountTTL:days completion:^(NSString *error) {
            ExteriaPrivacyController *again = weak.target;
            if (!error) return;
            ExteriaPrivacyFail(error);
            if (!again) return;
            again->_accountTTL = before;
            [again rebuild];
        }];
    });
}

- (void)confirmResetContacts {
    ExteriaWeakReference *weak = _weak;
    ExteriaConfirmAction(self, NSLocalizedString(@"privacy.contacts.confirm", nil), NSLocalizedString(@"privacy.contacts.delete", nil), ^{
        ExteriaPrivacyController *me = weak.target;
        if (!me) return;
        [me->_session resetSavedContactsWithCompletion:^(NSString *error) {
            if (error) ExteriaPrivacyFail(error);
            else ExteriaGiftAlert(nil, NSLocalizedString(@"privacy.contacts.done", nil));
        }];
    });
}

- (void)choosePaymentsToClear {
    ExteriaWeakReference *weak = _weak;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"privacy.payments.cards", nil), NSLocalizedString(@"privacy.payments.shipping", nil),
                        NSLocalizedString(@"privacy.payments.all", nil), nil];
    ExteriaSettingsChoose(self, NSLocalizedString(@"privacy.payments", nil), options, ^(NSUInteger index) {
        ExteriaPrivacyController *me = weak.target;
        if (!me) return;
        BOOL cards = index == 0 || index == 2, shipping = index == 1 || index == 2;
        [me->_session clearPaymentsCredentials:cards info:shipping completion:^(NSString *error) {
            if (error) ExteriaPrivacyFail(error);
            else ExteriaGiftAlert(nil, NSLocalizedString(@"privacy.payments.done", nil));
        }];
    });
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];

    NSString *blocked = _blockedKnown ? (_blocked > 0 ? [NSString stringWithFormat:@"%d", (int)_blocked] : NSLocalizedString(@"privacy.blocked.none", nil)) : nil;
    ExteriaSettingsRow *blockedRow = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolBlock tone:ExteriaSettingsToneRed title:NSLocalizedString(@"privacy.blocked", nil)
                                                              subtitle:nil value:blocked tap:^{ [(ExteriaPrivacyController *)weak.target openBlocked]; }];
    ExteriaSettingsRow *autoDelete = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolClearHistory tone:ExteriaSettingsToneOrange title:NSLocalizedString(@"privacy.autodelete", nil)
                                                              subtitle:nil value:_historyKnown ? ExteriaHistoryTTLText(_historyTTL) : nil
                                                                   tap:^{ [(ExteriaPrivacyController *)weak.target chooseHistoryTTL]; }];
    ExteriaSettingsRow *sessions = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsDevices tone:ExteriaSettingsToneCyan title:NSLocalizedString(@"settings.devices", nil)
                                                            subtitle:nil value:nil tap:^{ [(ExteriaPrivacyController *)weak.target openDevices]; }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"privacy.security", nil) footer:NSLocalizedString(@"privacy.autodelete.info", nil)
                                                             rows:[NSArray arrayWithObjects:blockedRow, autoDelete, sessions, nil]]];

    NSMutableArray *rows = [NSMutableArray array];
    for (size_t i = 0; i < PRIVACY_KEY_ROWS; ++i) {
        exteria_privacy_key key = ExteriaPrivacyKeys[i].key;
        ExteriaPrivacyRules *rules = _rules[key];
        [rows addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaPrivacyKeys[i].symbol tone:ExteriaPrivacyKeys[i].tone title:NSLocalizedString(ExteriaPrivacyKeys[i].title, nil)
                                                 subtitle:nil value:rules ? ExteriaPrivacyValue(rules) : nil tap:^{ [(ExteriaPrivacyController *)weak.target openRule:key]; }]];
    }
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"privacy.header", nil) footer:nil rows:rows]];

    ExteriaSettingsRow *away = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolTrash tone:ExteriaSettingsToneRed title:NSLocalizedString(@"privacy.away", nil)
                                                        subtitle:nil value:_accountKnown ? ExteriaAccountTTLText(_accountTTL) : nil
                                                             tap:^{ [(ExteriaPrivacyController *)weak.target chooseAccountTTL]; }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"privacy.delete.header", nil) footer:NSLocalizedString(@"privacy.away.info", nil)
                                                             rows:[NSArray arrayWithObject:away]]];

    ExteriaSettingsRow *contacts = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolMember tone:ExteriaSettingsToneBlueDeep title:NSLocalizedString(@"privacy.contacts.delete", nil)
                                                            subtitle:nil value:nil tap:^{ [(ExteriaPrivacyController *)weak.target confirmResetContacts]; }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"privacy.contacts.header", nil) footer:NSLocalizedString(@"privacy.contacts.info", nil)
                                                             rows:[NSArray arrayWithObject:contacts]]];

    ExteriaSettingsRow *payments = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsBusiness tone:ExteriaSettingsTonePurple title:NSLocalizedString(@"privacy.payments", nil)
                                                            subtitle:nil value:nil tap:^{ [(ExteriaPrivacyController *)weak.target choosePaymentsToClear]; }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"privacy.payments.header", nil) footer:NSLocalizedString(@"privacy.payments.info", nil)
                                                             rows:[NSArray arrayWithObject:payments]]];
    self.sections = sections;
    [self reloadSettings];
}

@end

#pragma mark one rule

@interface ExteriaPrivacyRuleController () {
    ExteriaSession *_session;
    ExteriaPrivacyRules *_rules;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    void (^_changedHandler)(ExteriaPrivacyRules *rules);
    BOOL _saving;
}
@end

/* the list of the people who are the exception, which edits the rules of the page that opened it */
@interface ExteriaPrivacyExceptionsController : ExteriaSettingsPageController {
    ExteriaSession *_session;
    ExteriaPrivacyRules *_rules;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    BOOL _allowed;
    BOOL _saving;
    ExteriaPeopleAvatars *_faces;
    void (^_changedHandler)(ExteriaPrivacyRules *rules);
}
- (id)initWithSession:(ExteriaSession *)session rules:(ExteriaPrivacyRules *)rules allowed:(BOOL)allowed avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;
@property (nonatomic, copy) void (^changedHandler)(ExteriaPrivacyRules *rules);
@end

@implementation ExteriaPrivacyRuleController

@synthesize changedHandler = _changedHandler;

- (id)initWithSession:(ExteriaSession *)session rules:(ExteriaPrivacyRules *)rules avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _rules = [rules retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    for (size_t i = 0; i < PRIVACY_KEY_ROWS; ++i) {
        if (ExteriaPrivacyKeys[i].key == rules.key) self.pageTitle = NSLocalizedString(ExteriaPrivacyKeys[i].title, nil);
    }
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_rules release];
    [_avatars release];
    [_media release];
    [_changedHandler release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

/* the page shows the rules as the server answered the last write, and a refused write brings back what the server holds */
- (void)adopt:(ExteriaPrivacyRules *)fresh {
    if (!fresh) return;
    [_rules release];
    _rules = [fresh retain];
    if (_changedHandler) _changedHandler(fresh);
}

- (void)choose:(exteria_privacy_base)base {
    if (_saving || _rules.base == base) return;
    _saving = YES;
    _rules.base = base;
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    exteria_privacy_key key = _rules.key;
    [_session savePrivacy:_rules completion:^(ExteriaPrivacyRules *fresh, NSString *error) {
        ExteriaPrivacyRuleController *me = weak.target;
        if (!me) return;
        me->_saving = NO;
        if (fresh) {
            [me adopt:fresh];
            [me rebuild];
            return;
        }
        ExteriaPrivacyFail(error);
        /* what the server holds is the truth, so the page asks for it again */
        [me->_session loadPrivacy:key completion:^(ExteriaPrivacyRules *held, NSString *loadError) {
            ExteriaPrivacyRuleController *again = weak.target;
            if (!again) return;
            if (held) [again adopt:held];
            else NSLog(@"exteria: the privacy rule did not load again: %@", loadError);
            [again rebuild];
        }];
    }];
}

- (void)openExceptions:(BOOL)allowed {
    ExteriaWeakReference *weak = _weak;
    ExteriaPrivacyExceptionsController *page = [[[ExteriaPrivacyExceptionsController alloc] initWithSession:_session rules:_rules allowed:allowed avatars:_avatars media:_media] autorelease];
    page.changedHandler = ^(ExteriaPrivacyRules *fresh) {
        ExteriaPrivacyRuleController *me = weak.target;
        if (!me) return;
        [me adopt:fresh];
        [me rebuild];
    };
    [self.navigationController pushViewController:page animated:YES];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSString *who = @"";
    for (size_t i = 0; i < PRIVACY_KEY_ROWS; ++i) {
        if (ExteriaPrivacyKeys[i].key == _rules.key) who = NSLocalizedString(ExteriaPrivacyKeys[i].who, nil);
    }
    exteria_privacy_base base = _rules.base;
    ExteriaSettingsRow *everybody = [ExteriaSettingsRow checkRowWithTitle:NSLocalizedString(@"privacy.everybody", nil) subtitle:nil checked:base == EXTERIA_PRIVACY_EVERYBODY
                                                                     tap:^{ [(ExteriaPrivacyRuleController *)weak.target choose:EXTERIA_PRIVACY_EVERYBODY]; }];
    ExteriaSettingsRow *contacts = [ExteriaSettingsRow checkRowWithTitle:NSLocalizedString(@"privacy.contacts", nil) subtitle:nil checked:base == EXTERIA_PRIVACY_CONTACTS
                                                                    tap:^{ [(ExteriaPrivacyRuleController *)weak.target choose:EXTERIA_PRIVACY_CONTACTS]; }];
    ExteriaSettingsRow *nobody = [ExteriaSettingsRow checkRowWithTitle:NSLocalizedString(@"privacy.nobody", nil) subtitle:nil checked:base == EXTERIA_PRIVACY_NOBODY
                                                                  tap:^{ [(ExteriaPrivacyRuleController *)weak.target choose:EXTERIA_PRIVACY_NOBODY]; }];
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:who footer:nil rows:[NSArray arrayWithObjects:everybody, contacts, nobody, nil]]];

    /* a person added to everybody or removed from nobody would change nothing, so the lists that would be empty of meaning are not offered */
    NSMutableArray *exceptions = [NSMutableArray array];
    if (base != EXTERIA_PRIVACY_EVERYBODY) {
        NSUInteger count = [_rules countAllowed:YES];
        [exceptions addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolPlusCircle tone:ExteriaSettingsToneGreen title:NSLocalizedString(@"privacy.always", nil) subtitle:nil
                                                          value:count ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : NSLocalizedString(@"privacy.add", nil)
                                                            tap:^{ [(ExteriaPrivacyRuleController *)weak.target openExceptions:YES]; }]];
    }
    if (base != EXTERIA_PRIVACY_NOBODY) {
        NSUInteger count = [_rules countAllowed:NO];
        [exceptions addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolBlock tone:ExteriaSettingsToneRed title:NSLocalizedString(@"privacy.never", nil) subtitle:nil
                                                          value:count ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : NSLocalizedString(@"privacy.add", nil)
                                                            tap:^{ [(ExteriaPrivacyRuleController *)weak.target openExceptions:NO]; }]];
    }
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"privacy.exceptions", nil) footer:NSLocalizedString(@"privacy.exceptions.info", nil) rows:exceptions]];
    self.sections = sections;
    [self reloadSettings];
}

@end

@implementation ExteriaPrivacyExceptionsController

@synthesize changedHandler = _changedHandler;

- (id)initWithSession:(ExteriaSession *)session rules:(ExteriaPrivacyRules *)rules allowed:(BOOL)allowed avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _rules = [rules retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _allowed = allowed;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(allowed ? @"privacy.always" : @"privacy.never", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_rules release];
    [_avatars release];
    [_media release];
    [_faces invalidate];
    [_faces release];
    [_changedHandler release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

/* writes the list as edited, and shows what the server answers; a refusal puts back what the server holds */
- (void)save {
    if (_saving) return;
    _saving = YES;
    ExteriaWeakReference *weak = _weak;
    exteria_privacy_key key = _rules.key;
    [_session savePrivacy:_rules completion:^(ExteriaPrivacyRules *fresh, NSString *error) {
        ExteriaPrivacyExceptionsController *me = weak.target;
        if (!me) return;
        me->_saving = NO;
        if (fresh) {
            [me->_rules release];
            me->_rules = [fresh retain];
            if (me->_changedHandler) me->_changedHandler(fresh);
            [me rebuild];
            return;
        }
        ExteriaPrivacyFail(error);
        [me->_session loadPrivacy:key completion:^(ExteriaPrivacyRules *held, NSString *loadError) {
            ExteriaPrivacyExceptionsController *again = weak.target;
            if (!again) return;
            if (held) {
                [again->_rules release];
                again->_rules = [held retain];
                if (again->_changedHandler) again->_changedHandler(held);
            } else {
                NSLog(@"exteria: the privacy rule did not load again: %@", loadError);
            }
            [again rebuild];
        }];
    }];
}

- (void)addPerson {
    if (_saving) return;
    ExteriaWeakReference *weak = _weak;
    ExteriaContactPickerController *picker = [[[ExteriaContactPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"privacy.exceptions.add", nil);
    ExteriaWeakReference *pickerRef = [ExteriaWeakReference referenceTo:picker];
    picker.pickHandler = ^(ExteriaDialog *dialog) {
        ExteriaPrivacyExceptionsController *me = weak.target;
        UIViewController *host = pickerRef.target;
        if (host) [host.navigationController popViewControllerAnimated:YES];
        if (!me) return;
        if (![me->_rules addUser:dialog.peerId hash:dialog.peerHash name:dialog.title photo:dialog.photo allowed:me->_allowed]) {
            ExteriaGiftAlert(nil, NSLocalizedString(@"privacy.exceptions.cannot", nil));
            return;
        }
        [me rebuild];
        [me save];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)addGroup {
    if (_saving) return;
    ExteriaWeakReference *weak = _weak;
    ExteriaDialogPickerController *picker = [[[ExteriaDialogPickerController alloc] init] autorelease];
    picker.filter = ^BOOL(ExteriaDialog *dialog) {
        return dialog.kind == EXTERIA_DIALOG_GROUP && !dialog.folder && !dialog.left;
    };
    picker.pickHandler = ^(NSArray *dialogs) {
        ExteriaPrivacyExceptionsController *me = weak.target;
        if (!me) return;
        for (ExteriaDialog *dialog in dialogs) {
            if (![me->_rules addChat:dialog.peerId title:dialog.title photo:dialog.photo allowed:me->_allowed]) {
                ExteriaGiftAlert(nil, NSLocalizedString(@"privacy.exceptions.cannot", nil));
                break;
            }
        }
        [me rebuild];
        [me save];
    };
    picker.limit = 20;
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)confirmRemove:(ExteriaPrivacyEntry *)entry {
    ExteriaWeakReference *weak = _weak;
    [ExteriaSheet presentInView:self.view title:entry.name message:nil options:[NSArray arrayWithObject:NSLocalizedString(@"privacy.exceptions.remove", nil)]
                    destructive:[NSIndexSet indexSetWithIndex:0] cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
        (void)index;
        ExteriaPrivacyExceptionsController *me = weak.target;
        if (!me || me->_saving) return;
        [me->_rules removeEntry:entry allowed:me->_allowed];
        [me rebuild];
        [me save];
    }];
}

- (UIImage *)faceForKey:(NSString *)key name:(NSString *)name seed:(NSUInteger)seed photo:(ExteriaPhoto *)photo {
    if (!_faces) {
        ExteriaWeakReference *weak = _weak;
        _faces = [[ExteriaPeopleAvatars alloc] initWithCache:_avatars changed:^{ [(ExteriaPrivacyExceptionsController *)weak.target rebuild]; }];
    }
    return [_faces imageForKey:key initials:ExteriaInitialsOfName(name) seed:seed deleted:NO photo:photo];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    ExteriaSettingsRow *add = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolPlusCircle title:NSLocalizedString(@"privacy.exceptions.add", nil) destructive:NO
                                                                  tap:^{ [(ExteriaPrivacyExceptionsController *)weak.target addPerson]; }];
    ExteriaSettingsRow *addGroup = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolPlusCircle title:NSLocalizedString(@"privacy.exceptions.addgroup", nil) destructive:NO
                                                                      tap:^{ [(ExteriaPrivacyExceptionsController *)weak.target addGroup]; }];
    NSMutableArray *rows = [NSMutableArray array];
    for (ExteriaPrivacyEntry *entry in [_rules entriesAllowed:_allowed]) {
        NSString *name = entry.name.length ? entry.name : NSLocalizedString(@"privacy.exceptions.unknown", nil);
        UIImage *face = [self faceForKey:[NSString stringWithFormat:@"%d:%lld", entry.chat, entry.identifier] name:entry.name seed:(NSUInteger)(entry.identifier % 1000003) photo:entry.photo];
        [rows addObject:[ExteriaSettingsRow rowWithTileImage:face title:name subtitle:entry.chat ? NSLocalizedString(@"privacy.exceptions.group", nil) : nil tap:^{
            [(ExteriaPrivacyExceptionsController *)weak.target confirmRemove:entry];
        }]];
    }
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObjects:add, addGroup, nil]]];
    if (rows.count) [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"privacy.exceptions.hint", nil) rows:rows]];
    self.sections = sections;
    [self reloadSettings];
}

@end

#pragma mark blocked

@interface ExteriaBlockedController () {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    NSArray *_peers;
    int32_t _total;
    BOOL _loaded;
    BOOL _working;
    ExteriaPeopleAvatars *_faces;
    void (^_countHandler)(int32_t total);
}
@end

@implementation ExteriaBlockedController

@synthesize countHandler = _countHandler;

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"privacy.blocked", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_avatars release];
    [_media release];
    [_peers release];
    [_faces invalidate];
    [_faces release];
    [_countHandler release];
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

- (void)load {
    ExteriaWeakReference *weak = _weak;
    [_session loadBlockedFrom:0 completion:^(NSArray *peers, int32_t total, NSString *error) {
        ExteriaBlockedController *me = weak.target;
        if (!me) return;
        if (!peers) {
            ExteriaPrivacyFail(error);
            return;
        }
        [me->_peers release];
        me->_peers = [peers retain];
        me->_total = total;
        me->_loaded = YES;
        if (me->_countHandler) me->_countHandler(total);
        [me rebuild];
    }];
}

- (void)blockPerson {
    if (_working) return;
    ExteriaWeakReference *weak = _weak;
    ExteriaContactPickerController *picker = [[[ExteriaContactPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"privacy.blocked.block", nil);
    ExteriaWeakReference *pickerRef = [ExteriaWeakReference referenceTo:picker];
    picker.pickHandler = ^(ExteriaDialog *dialog) {
        ExteriaBlockedController *me = weak.target;
        UIViewController *host = pickerRef.target;
        if (host) [host.navigationController popViewControllerAnimated:YES];
        if (!me) return;
        me->_working = YES;
        [me->_session setBlocked:YES kind:dialog.peerKind identifier:dialog.peerId hash:dialog.peerHash completion:^(NSString *error) {
            ExteriaBlockedController *again = weak.target;
            if (!again) return;
            again->_working = NO;
            if (error) ExteriaPrivacyFail(error);
            else [again load];
        }];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)confirmUnblock:(ExteriaBlockedPeer *)peer {
    ExteriaWeakReference *weak = _weak;
    [ExteriaSheet presentInView:self.view title:peer.name message:nil options:[NSArray arrayWithObject:NSLocalizedString(@"privacy.blocked.unblock", nil)]
                    destructive:nil cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
        (void)index;
        ExteriaBlockedController *me = weak.target;
        if (!me || me->_working) return;
        me->_working = YES;
        [me->_session setBlocked:NO kind:peer.kind identifier:peer.identifier hash:peer.accessHash completion:^(NSString *error) {
            ExteriaBlockedController *again = weak.target;
            if (!again) return;
            again->_working = NO;
            if (error) ExteriaPrivacyFail(error);
            else [again load];
        }];
    }];
}

- (UIImage *)faceForKey:(NSString *)key name:(NSString *)name seed:(NSUInteger)seed photo:(ExteriaPhoto *)photo {
    if (!_faces) {
        ExteriaWeakReference *weak = _weak;
        _faces = [[ExteriaPeopleAvatars alloc] initWithCache:_avatars changed:^{ [(ExteriaBlockedController *)weak.target rebuild]; }];
    }
    return [_faces imageForKey:key initials:ExteriaInitialsOfName(name) seed:seed deleted:NO photo:photo];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    ExteriaSettingsRow *add = [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolBlock title:NSLocalizedString(@"privacy.blocked.block", nil) destructive:YES
                                                                  tap:^{ [(ExteriaBlockedController *)weak.target blockPerson]; }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:add]]];
    NSMutableArray *rows = [NSMutableArray array];
    for (ExteriaBlockedPeer *peer in _peers) {
        NSString *date = peer.date > 0 ? [NSString stringWithFormat:NSLocalizedString(@"privacy.blocked.since", nil), ExteriaListTimeText(peer.date)] : nil;
        UIImage *face = [self faceForKey:[NSString stringWithFormat:@"%d:%lld", peer.kind, peer.identifier] name:peer.name seed:(NSUInteger)(peer.identifier % 1000003) photo:peer.photo];
        [rows addObject:[ExteriaSettingsRow rowWithTileImage:face title:peer.name.length ? peer.name : NSLocalizedString(@"privacy.exceptions.unknown", nil) subtitle:date tap:^{
            [(ExteriaBlockedController *)weak.target confirmUnblock:peer];
        }]];
    }
    NSString *footer = !_loaded ? nil : (rows.count ? NSLocalizedString(@"privacy.blocked.hint", nil) : NSLocalizedString(@"privacy.blocked.empty", nil));
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
    self.sections = sections;
    [self reloadSettings];
}

@end
