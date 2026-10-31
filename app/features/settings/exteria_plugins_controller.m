#import "exteria_plugins_controller.h"
#import <QuartzCore/QuartzCore.h>
#import "exteria_alert.h"
#import "exteria_lottie_view.h"
#import "exteria_plugins.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"
#include "exteria_plugin.h"

#define PLUGINS_STICKER 130.0
#define PLUGINS_INSET 12.0

@interface ExteriaPluginsController () {
    ExteriaWeakReference *_weak;
    /* the animated folder is made once and moved into each header that is built */
    ExteriaLottieView *_sticker;
    CGFloat _headerWidth;
    /* no script found: the card under the folder tells where to put one, no row stands for it */
    BOOL _empty;
}
@end

@implementation ExteriaPluginsController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"plugins.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_sticker release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuildHeader];
}

/* the folder is loaded before the screen is on, so its first frame is drawn while the push still moves; the list is read
   again because the person comes back from the file app with new scripts */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_sticker setLoaded:YES];
    [self rebuild];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_sticker playOnce];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_sticker setPlaying:NO];
    [_sticker setLoaded:NO];
}

- (void)themeDidChange {
    [self rebuildHeader];
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaPluginsController alloc] init] autorelease];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    /* the card is laid out for the width of the table, so a turn of the phone builds it again */
    if (fabs(self.table.bounds.size.width - _headerWidth) > 0.5) [self rebuildHeader];
}

- (void)replaySticker {
    [_sticker rewind];
    [_sticker playOnce];
}

- (void)rebuildHeader {
    CGFloat width = self.table.bounds.size.width;
    if (width <= 0) return;
    _headerWidth = width;
    if (!_sticker) {
        _sticker = [[ExteriaLottieView alloc] initWithAnimationNamed:@"folders_hint"];
        [_sticker setLoaded:YES];
        _sticker.userInteractionEnabled = YES;
        [_sticker addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(replaySticker)] autorelease]];
    }
    CGFloat cardWidth = width - 2 * PLUGINS_INSET;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 100)] autorelease];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UILabel *text = [[[UILabel alloc] init] autorelease];
    text.backgroundColor = [UIColor clearColor];
    text.textColor = ExteriaColorSecondary();
    text.font = ExteriaFontRegular(15);
    text.textAlignment = ExteriaTextAlignmentCenter;
    text.numberOfLines = 0;
    text.text = _empty ? [NSString stringWithFormat:@"%@\n\n%@", NSLocalizedString(@"plugins.hint", nil), NSLocalizedString(@"plugins.empty", nil)]
                       : NSLocalizedString(@"plugins.hint", nil);
    CGSize fit = [text sizeThatFits:CGSizeMake(cardWidth - 40, 400)];
    _sticker.frame = CGRectMake((cardWidth - PLUGINS_STICKER) / 2, 12, PLUGINS_STICKER, PLUGINS_STICKER);
    text.frame = CGRectMake(20, CGRectGetMaxY(_sticker.frame) + 8, cardWidth - 40, ceil(fit.height));
    UIView *card = [[[UIView alloc] init] autorelease];
    card.backgroundColor = ExteriaColorCard();
    card.layer.cornerRadius = 22;
    card.frame = CGRectMake(PLUGINS_INSET, 12, cardWidth, CGRectGetMaxY(text.frame) + 16);
    [card addSubview:_sticker];
    [card addSubview:text];
    [header addSubview:card];
    header.frame = CGRectMake(0, 0, width, CGRectGetMaxY(card.frame) + 8);
    self.headerView = header;
}

#pragma mark scripts

static NSString *permission_names(unsigned permissions) {
    NSMutableArray *names = [NSMutableArray array];
    if (permissions & EXTERIA_PERM_MESSAGES_READ) [names addObject:NSLocalizedString(@"plugins.perm.read", nil)];
    if (permissions & EXTERIA_PERM_MESSAGES_MODIFY) [names addObject:NSLocalizedString(@"plugins.perm.modify", nil)];
    if (!names.count) return NSLocalizedString(@"plugins.perm.none", nil);
    return [names componentsJoinedByString:@", "];
}

static NSString *hook_names(unsigned hooks) {
    NSMutableArray *names = [NSMutableArray array];
    if (hooks & EXTERIA_HOOK_MESSAGE) [names addObject:NSLocalizedString(@"plugins.hook.message", nil)];
    if (hooks & EXTERIA_HOOK_SEND) [names addObject:NSLocalizedString(@"plugins.hook.send", nil)];
    if (hooks & EXTERIA_HOOK_EVENT) [names addObject:NSLocalizedString(@"plugins.hook.event", nil)];
    return [names componentsJoinedByString:@", "];
}

static NSString *refusal_text(int status) {
    switch (status) {
        case EXTERIA_E_MALFORMED: return NSLocalizedString(@"plugins.err.script", nil);
        case EXTERIA_E_UNSUPPORTED: return NSLocalizedString(@"plugins.err.permission", nil);
        case EXTERIA_E_LIMIT: return NSLocalizedString(@"plugins.err.limit", nil);
        case EXTERIA_E_TIMEOUT: return NSLocalizedString(@"plugins.err.time", nil);
        case EXTERIA_E_NOMEM: return NSLocalizedString(@"plugins.err.memory", nil);
        case EXTERIA_E_IO: return NSLocalizedString(@"plugins.err.unreadable", nil);
        default: return NSLocalizedString(@"plugins.err.failed", nil);
    }
}

/* the switch asks first: a plugin that reads or edits messages gets that only when the person has seen the words for it */
- (void)turnOn:(ExteriaPluginEntry *)entry {
    NSString *message = [NSString stringWithFormat:@"%@\n\n%@", permission_names(entry.permissions), hook_names(entry.hooks)];
    ExteriaWeakReference *weak = _weak;
    NSString *file = entry.file;
    ExteriaConfirm(entry.name, message, NSLocalizedString(@"plugins.turnon", nil), ^{
        ExteriaPluginsSetEnabled(file, YES);
        [(ExteriaPluginsController *)weak.target rebuild];
    });
}

- (ExteriaSettingsRow *)rowForEntry:(ExteriaPluginEntry *)entry {
    if (entry.status != 0) {
        return [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolDocument tone:ExteriaSettingsToneGray title:entry.file subtitle:refusal_text(entry.status) value:nil tap:nil];
    }
    NSMutableArray *lines = [NSMutableArray array];
    if (entry.fault) [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"plugins.fault", nil), entry.fault]];
    else if (entry.changed) [lines addObject:NSLocalizedString(@"plugins.changed", nil)];
    [lines addObject:permission_names(entry.permissions)];
    ExteriaWeakReference *weak = _weak;
    return [ExteriaSettingsRow switchRowWithSymbol:ExteriaSymbolApps tone:ExteriaSettingsToneCyan title:entry.name subtitle:[lines componentsJoinedByString:@"\n"] on:entry.enabled
                                            toggle:^(BOOL on) {
        ExteriaPluginsController *me = weak.target;
        if (!me) return;
        if (!on) {
            ExteriaPluginsSetEnabled(entry.file, NO);
            [me rebuild];
            return;
        }
        /* the switch has moved already, the list is built again once the answer is in */
        [me turnOn:entry];
        [me rebuild];
    }];
}

- (void)rebuild {
    NSMutableArray *rows = [NSMutableArray array];
    for (ExteriaPluginEntry *entry in ExteriaPluginsList()) [rows addObject:[self rowForEntry:entry]];
    NSMutableArray *sections = [NSMutableArray array];
    if (rows.count) {
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"plugins.installed", nil)
                                                               footer:NSLocalizedString(@"plugins.footer", nil) rows:rows]];
    }
    self.sections = sections;
    if ((rows.count == 0) != _empty) {
        _empty = rows.count == 0;
        [self rebuildHeader];
    }
}

@end
