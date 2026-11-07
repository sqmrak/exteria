#import "exteria_channel_invite_edit_controller.h"

#import "exteria_channel_errors.h"
#import "exteria_channel_field_controller.h"
#import "exteria_gift_screen.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define HOUR 3600
#define DAY (24 * HOUR)

/* the terms the form offers, in seconds from the moment of choosing; zero is a link that does not end */
static const int32_t kExpirePresets[] = {0, HOUR, DAY, 7 * DAY, 30 * DAY};
static const int32_t kLimitPresets[] = {0, 1, 5, 10, 25, 50, 100};
#define EXPIRE_PRESET_COUNT (sizeof(kExpirePresets) / sizeof(kExpirePresets[0]))
#define LIMIT_PRESET_COUNT (sizeof(kLimitPresets) / sizeof(kLimitPresets[0]))

@interface ExteriaChannelInviteEditController () {
    ExteriaSession *_session;
    ExteriaFullChannel *_channel;
    ExteriaInvite *_invite;
    void (^_saved)(ExteriaInvite *saved);
    ExteriaWeakReference *_weak;
    NSString *_name;
    /* the end of the link as a unix time, zero for none; a preset is turned into one when it is picked */
    int32_t _expire;
    int32_t _limit;
    BOOL _approval;
    BOOL _saving;
    UIButton *_done;
}
@end

@implementation ExteriaChannelInviteEditController

- (id)initWithSession:(ExteriaSession *)session channel:(ExteriaFullChannel *)channel invite:(ExteriaInvite *)invite saved:(void (^)(ExteriaInvite *))saved {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _channel = [channel retain];
    _invite = [invite retain];
    _saved = [saved copy];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _name = [(invite ? invite.title : @"") copy];
    _expire = invite.expireDate;
    _limit = invite.usageLimit;
    _approval = invite.requestNeeded;
    self.pageTitle = NSLocalizedString(invite ? @"invite.edit.title" : @"invite.new.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_channel release];
    [_invite release];
    [_saved release];
    [_name release];
    [_done release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self refreshSaveButton];
}

#pragma mark content

static NSString *ExteriaExpireName(int32_t seconds) {
    switch (seconds) {
    case 0: return NSLocalizedString(@"invite.expire.never", nil);
    case HOUR: return NSLocalizedString(@"invite.expire.hour", nil);
    case DAY: return NSLocalizedString(@"invite.expire.day", nil);
    case 7 * DAY: return NSLocalizedString(@"invite.expire.week", nil);
    default: return NSLocalizedString(@"invite.expire.month", nil);
    }
}

static NSString *ExteriaInviteEditDate(int32_t date) {
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:date]];
}

/* the choice the term of the form stands at: the index of a preset, or the date the link already had */
- (NSString *)expireValue {
    if (_expire == 0) return ExteriaExpireName(0);
    return ExteriaInviteEditDate(_expire);
}

- (NSString *)limitValue {
    return _limit > 0 ? [NSString stringWithFormat:@"%d", (int)_limit] : NSLocalizedString(@"invite.limit.none", nil);
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"invite.title.hint", nil) rows:[NSArray arrayWithObject:
        [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolCompose tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"invite.field.title", nil) subtitle:nil
                                    value:_name.length ? _name : NSLocalizedString(@"invite.title.none", nil) tap:^{
            [(ExteriaChannelInviteEditController *)weak.target editName];
        }]]]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"invite.expire.hint", nil) rows:[NSArray arrayWithObject:
        [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolClock tone:ExteriaSettingsToneOrange title:NSLocalizedString(@"invite.expire", nil) subtitle:nil
                                    value:[self expireValue] tap:^{
            [(ExteriaChannelInviteEditController *)weak.target chooseExpire];
        }]]]];
    ExteriaSettingsRow *limit = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolMember tone:ExteriaSettingsToneBlueDeep title:NSLocalizedString(@"invite.limit.title", nil)
                                                         subtitle:nil value:[self limitValue] tap:^{
        [(ExteriaChannelInviteEditController *)weak.target chooseLimit];
    }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"invite.limit.hint", nil) rows:[NSArray arrayWithObject:limit]]];
    ExteriaSettingsRow *approval = [ExteriaSettingsRow switchRowWithSymbol:ExteriaSymbolCheck tone:ExteriaSettingsToneGreen title:NSLocalizedString(@"invite.approval.title", nil)
                                                                  subtitle:nil on:_approval toggle:^(BOOL on) {
        [(ExteriaChannelInviteEditController *)weak.target setApproval:on];
    }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"invite.approval.hint", nil) rows:[NSArray arrayWithObject:approval]]];
    self.sections = sections;
    [self reloadSettings];
}

#pragma mark editing

- (void)editName {
    ExteriaWeakReference *weak = _weak;
    ExteriaChannelFieldController *field = [[[ExteriaChannelFieldController alloc] initWithSession:_session avatars:nil media:nil kind:ExteriaChannelFieldInviteTitle text:_name
                                                                                            dialog:_channel.dialog save:^(NSString *text, void (^done)(NSString *)) {
        ExteriaChannelInviteEditController *me = weak.target;
        if (me) {
            [me->_name release];
            me->_name = [text copy];
            [me rebuild];
        }
        done(nil);
    }] autorelease];
    [self.navigationController pushViewController:field animated:YES];
}

- (void)chooseExpire {
    NSMutableArray *options = [NSMutableArray array];
    for (size_t i = 0; i < EXPIRE_PRESET_COUNT; ++i) [options addObject:ExteriaExpireName(kExpirePresets[i])];
    ExteriaWeakReference *weak = _weak;
    ExteriaSettingsChoose(self, NSLocalizedString(@"invite.expire", nil), options, ^(NSUInteger index) {
        ExteriaChannelInviteEditController *me = weak.target;
        if (!me || index >= EXPIRE_PRESET_COUNT) return;
        int32_t seconds = kExpirePresets[index];
        me->_expire = seconds ? (int32_t)time(NULL) + seconds : 0;
        [me rebuild];
    });
}

- (void)chooseLimit {
    NSMutableArray *options = [NSMutableArray array];
    for (size_t i = 0; i < LIMIT_PRESET_COUNT; ++i) {
        [options addObject:kLimitPresets[i] ? [NSString stringWithFormat:@"%d", (int)kLimitPresets[i]] : NSLocalizedString(@"invite.limit.none", nil)];
    }
    ExteriaWeakReference *weak = _weak;
    ExteriaSettingsChoose(self, NSLocalizedString(@"invite.limit.title", nil), options, ^(NSUInteger index) {
        ExteriaChannelInviteEditController *me = weak.target;
        if (!me || index >= LIMIT_PRESET_COUNT) return;
        me->_limit = kLimitPresets[index];
        /* a join that waits for an admin counts no use of the link, so the server takes either the limit or the approval, not both */
        if (me->_limit > 0) me->_approval = NO;
        [me rebuild];
    });
}

- (void)setApproval:(BOOL)on {
    _approval = on;
    if (on) _limit = 0;
    [self rebuild];
}

#pragma mark saving

- (void)refreshSaveButton {
    if (ExteriaThemeIsClassic()) {
        self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"channel.save", nil) style:UIBarButtonItemStyleBordered
                                                                                  target:self action:@selector(save)] autorelease];
        return;
    }
    if (!_done) {
        _done = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _done.titleLabel.font = ExteriaFontSemibold(17);
        [_done setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
        [_done setTitle:NSLocalizedString(@"channel.save", nil) forState:UIControlStateNormal];
        [_done addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside];
        [_done sizeToFit];
        _done.frame = CGRectMake(0, 0, _done.frame.size.width + 24, 44);
    }
    self.barViews = [NSArray arrayWithObject:_done];
}

- (void)save {
    if (_saving) return;
    _saving = YES;
    _done.enabled = NO;
    ExteriaWeakReference *weak = _weak;
    [self retain];
    void (^finish)(ExteriaInvite *, NSString *) = ^(ExteriaInvite *saved, NSString *errorName) {
        [self autorelease];
        ExteriaChannelInviteEditController *me = weak.target;
        if (!me) return;
        me->_saving = NO;
        me->_done.enabled = YES;
        if (errorName) {
            ExteriaGiftAlert(nil, ExteriaChannelErrorText(errorName));
            return;
        }
        if (me->_saved) me->_saved(saved);
        [me.navigationController popViewControllerAnimated:YES];
    };
    if (_invite) {
        [_session editInvite:_invite inDialog:_channel.dialog expireDate:_expire usageLimit:_limit requestNeeded:_approval title:_name completion:finish];
    } else {
        [_session createInviteInDialog:_channel.dialog expireDate:_expire usageLimit:_limit requestNeeded:_approval title:_name completion:finish];
    }
}

@end
