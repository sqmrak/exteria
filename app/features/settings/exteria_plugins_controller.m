#import "exteria_plugins_controller.h"
#import <QuartzCore/QuartzCore.h>
#import "exteria_alert.h"
#import "exteria_senko_popup.h"
#import "exteria_classic_chrome.h"
#import "exteria_file_picker.h"
#import "exteria_plugin_settings_controller.h"
#import "exteria_platform.h"
#import "exteria_plugins.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define PLUGINS_STICKER 130.0
#define PLUGINS_INSET 12.0

@interface ExteriaPluginsController () {
    ExteriaWeakReference *_weak;
    /* the picture is made once and moved into each header that is built */
    UIImageView *_sticker;
    CGFloat _headerWidth;
    /* no script found: the card under the picture tells where to put one, no row stands for it */
    BOOL _empty;
    /* the files whose switch is on and whose plugin is still being started */
    NSMutableSet *_starting;
    ExteriaSenkoPopup *_failurePopup;
}
@end

@implementation ExteriaPluginsController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _starting = [[NSMutableSet alloc] init];
    self.pageTitle = NSLocalizedString(@"plugins.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_sticker release];
    [_starting release];
    [_failurePopup release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuildHeader];
}

/* the list is read again because the person comes back from the file app with new scripts */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
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

- (void)rebuildHeader {
    CGFloat width = self.table.bounds.size.width;
    if (width <= 0) return;
    _headerWidth = width;
    if (!_sticker) {
        _sticker = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"plugins_python.png"]];
        _sticker.contentMode = UIViewContentModeScaleAspectFit;
    }
    CGFloat cardWidth = width - 2 * PLUGINS_INSET;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 100)] autorelease];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UILabel *about = [[[UILabel alloc] init] autorelease];
    about.backgroundColor = [UIColor clearColor];
    about.textColor = ExteriaColorTitle();
    about.font = ExteriaFontMedium(15);
    about.textAlignment = ExteriaTextAlignmentCenter;
    about.numberOfLines = 0;
    about.text = NSLocalizedString(@"plugins.about", nil);
    CGSize aboutFit = [about sizeThatFits:CGSizeMake(cardWidth - 40, 400)];
    _sticker.frame = CGRectMake((cardWidth - PLUGINS_STICKER) / 2, 12, PLUGINS_STICKER, PLUGINS_STICKER);
    about.frame = CGRectMake(20, CGRectGetMaxY(_sticker.frame) + 8, cardWidth - 40, ceil(aboutFit.height));
    UILabel *text = [[[UILabel alloc] init] autorelease];
    text.backgroundColor = [UIColor clearColor];
    text.textColor = ExteriaColorSecondary();
    text.font = ExteriaFontRegular(15);
    text.textAlignment = ExteriaTextAlignmentCenter;
    text.numberOfLines = 0;
    text.text = _empty ? NSLocalizedString(@"plugins.empty", nil) : @"";
    CGSize fit = [text sizeThatFits:CGSizeMake(cardWidth - 40, 400)];
    /* the hint for an empty list stands under the description, and takes no room when the list has plugins */
    text.frame = CGRectMake(20, CGRectGetMaxY(about.frame) + (_empty ? 10 : 0), cardWidth - 40, _empty ? ceil(fit.height) : 0);
    UIView *card = [[[UIView alloc] init] autorelease];
    card.backgroundColor = ExteriaColorCard();
    card.layer.cornerRadius = 22;
    card.frame = CGRectMake(PLUGINS_INSET, 12, cardWidth, CGRectGetMaxY(text.frame) + 16);
    [card addSubview:_sticker];
    [card addSubview:about];
    [card addSubview:text];
    [header addSubview:card];
    header.frame = CGRectMake(0, 0, width, CGRectGetMaxY(card.frame) + 8);
    self.headerView = header;
}

#pragma mark scripts

/* the words for a permission key; a key the app has no words for shows as it is written, so nothing is hidden from the person */
static NSString *permission_names(NSArray *permissions) {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *key in permissions) {
        NSString *token = [@"plugins.perm." stringByAppendingString:key];
        NSString *text = NSLocalizedString(token, nil);
        [names addObject:[text isEqualToString:token] ? key : text];
    }
    if (!names.count) return NSLocalizedString(@"plugins.perm.none", nil);
    return [names componentsJoinedByString:@", "];
}

/* the failure of a plugin as a person can read it: what is missing or wrong, in a line. the traceback is behind a tap, and in the log */
static NSString *capture(NSString *text, NSString *pattern, NSUInteger group) {
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    NSTextCheckingResult *match = [expression firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    return match && match.numberOfRanges > group && [match rangeAtIndex:group].location != NSNotFound ? [text substringWithRange:[match rangeAtIndex:group]] : nil;
}

static NSString *friendly_fault(NSString *raw) {
    if (!raw.length) return NSLocalizedString(@"plugins.err.failed", nil);
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *lines = [trimmed componentsSeparatedByString:@"\n"];
    /* the line that names the exception: "Type: message", the last one in a traceback; the sdk's own reports start with it */
    NSString *last = [lines objectAtIndex:0];
    for (NSInteger i = (NSInteger)lines.count - 1; i >= 0; --i) {
        NSString *line = [lines objectAtIndex:(NSUInteger)i];
        if (capture(line, @"^([A-Za-z_][A-Za-z_.0-9]*(?:Error|Exception|Exit|Interrupt)):", 1)) { last = line; break; }
    }
    NSString *type = capture(last, @"^([A-Za-z_.]+?)(?::|$)", 1);
    NSString *message = capture(last, @"^[A-Za-z_.]+:\\s*(.*)$", 1);
    NSString *plugin_line = nil;
    NSRegularExpression *frame = [NSRegularExpression regularExpressionWithPattern:@"File \"[^\"]*\\.(?:plugin|py)\", line (\\d+)" options:0 error:NULL];
    for (NSTextCheckingResult *match in [frame matchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)]) {
        NSString *path = [trimmed substringWithRange:[match rangeAtIndex:0]];
        if ([path rangeOfString:@"/stdlib/"].location == NSNotFound && [path rangeOfString:@"/sdk/"].location == NSNotFound && [path rangeOfString:@"/shim/"].location == NSNotFound) {
            plugin_line = [trimmed substringWithRange:[match rangeAtIndex:1]];
        }
    }
    /* the sdk's reports end with "file.plugin:7: the line of code" instead of a frame */
    if (!plugin_line) plugin_line = capture(trimmed, @"[A-Za-z0-9_\\-]+\\.(?:plugin|py):(\\d+):", 1);
    NSString *where = plugin_line ? [NSString stringWithFormat:NSLocalizedString(@"plugins.fault.line", nil), plugin_line] : @"";
    NSString *module = capture(message, @"No module named '([^']+)'", 1);
    if (module) {
        BOOL android = [module hasPrefix:@"android"] || [module hasPrefix:@"androidx"] || [module hasPrefix:@"org.telegram"] || [module hasPrefix:@"java"] || [module hasPrefix:@"com."];
        return [NSString stringWithFormat:NSLocalizedString(android ? @"plugins.fault.module.android" : @"plugins.fault.module", nil), module];
    }
    if ([type hasSuffix:@"ClassNotFoundException"]) return [NSString stringWithFormat:NSLocalizedString(@"plugins.fault.class", nil), message];
    NSString *missing = capture(message, @"cannot import name '([^']+)' from '([^']+)'", 1);
    if (missing) return [NSString stringWithFormat:NSLocalizedString(@"plugins.fault.name", nil), capture(message, @"from '([^']+)'", 1), missing];
    if ([type isEqualToString:@"SyntaxError"] || [type isEqualToString:@"IndentationError"] || [type isEqualToString:@"TabError"]) {
        return plugin_line ? [NSString stringWithFormat:NSLocalizedString(@"plugins.fault.syntax.line", nil), plugin_line] : NSLocalizedString(@"plugins.fault.syntax", nil);
    }
    if ([type isEqualToString:@"TimeoutError"]) return NSLocalizedString(@"plugins.fault.time", nil);
    if ([type isEqualToString:@"PermissionError"]) {
        NSString *key = capture(message, @"missing the '([^']+)' permission", 1);
        if (key) return [NSString stringWithFormat:NSLocalizedString(@"plugins.fault.permission", nil), key];
        return [NSString stringWithFormat:NSLocalizedString(@"plugins.fault.notallowed", nil), message];
    }
    if ([type isEqualToString:@"FileNotFoundError"]) return [NSString stringWithFormat:NSLocalizedString(@"plugins.fault.file", nil), message];
    if ([type isEqualToString:@"NotImplementedError"]) return [NSString stringWithFormat:NSLocalizedString(@"plugins.fault.unsupported", nil), message];
    NSString *what = message.length ? [NSString stringWithFormat:@"%@: %@", type ? type : @"error", message] : (type ? type : last);
    if (what.length > 140) what = [[what substringToIndex:140] stringByAppendingString:@"…"];
    return [NSString stringWithFormat:NSLocalizedString(@"plugins.fault.generic", nil), what, where];
}

/* the reason a file was refused, without the path of the plugins folder that the sdk puts in it */
static NSString *refusal_text(ExteriaPluginEntry *entry) {
    NSString *base;
    switch (entry.status) {
        case EXTERIA_E_MALFORMED: base = NSLocalizedString(@"plugins.err.script", nil); break;
        case EXTERIA_E_LIMIT: base = NSLocalizedString(@"plugins.err.limit", nil); break;
        case EXTERIA_E_TIMEOUT: base = NSLocalizedString(@"plugins.err.time", nil); break;
        case EXTERIA_E_IO: base = NSLocalizedString(@"plugins.err.unreadable", nil); break;
        default: base = NSLocalizedString(@"plugins.err.failed", nil); break;
    }
    if (!entry.error.length) return base;
    if ([entry.error rangeOfString:@"Traceback (most recent call last):"].location != NSNotFound)
        return [NSString stringWithFormat:@"%@\n%@", base, friendly_fault(entry.error)];
    NSString *reason = [entry.error stringByReplacingOccurrencesOfString:[ExteriaPluginsDirectory() stringByAppendingString:@"/"] withString:@""];
    if (reason.length > 160) reason = [[reason substringToIndex:160] stringByAppendingString:@"…"];
    return [NSString stringWithFormat:@"%@\n%@", base, reason];
}

/* the words of the popup for a plugin that did not load: what stops it as a whole, from exteria_diagnose.py. a name is shown as it is, up to three of them */
static NSString *failure_text(NSDictionary *why) {
    NSString *kind = [why objectForKey:@"kind"];
    NSArray *classes = [why objectForKey:@"classes"];
    if (![classes isKindOfClass:[NSArray class]]) classes = [NSArray array];
    NSArray *shown = classes.count > 3 ? [classes subarrayWithRange:NSMakeRange(0, 3)] : classes;
    NSString *names = [shown componentsJoinedByString:@", "];
    if ([kind isEqualToString:@"java"]) return [NSString stringWithFormat:NSLocalizedString(@"plugins.fail.java", nil), names];
    if ([kind isEqualToString:@"android"]) {
        long missing = [[why objectForKey:@"missing"] longValue];
        long total = [[why objectForKey:@"total"] longValue];
        if (missing >= 5) return [NSString stringWithFormat:NSLocalizedString(@"plugins.fail.android.many", nil), missing, total, names];
        return [NSString stringWithFormat:NSLocalizedString(@"plugins.fail.android", nil), names];
    }
    if ([kind isEqualToString:@"library"]) return [NSString stringWithFormat:NSLocalizedString(@"plugins.fail.library", nil), names];
    if ([kind isEqualToString:@"feature"]) return [NSString stringWithFormat:NSLocalizedString(@"plugins.fail.feature", nil), names];
    NSString *detail = [[why objectForKey:@"detail"] isKindOfClass:[NSString class]] ? [why objectForKey:@"detail"] : @"";
    detail = [detail stringByReplacingOccurrencesOfString:[ExteriaPluginsDirectory() stringByAppendingString:@"/"] withString:@""];
    if (detail.length > 200) detail = [[detail substringToIndex:200] stringByAppendingString:@"…"];
    return [NSString stringWithFormat:NSLocalizedString(@"plugins.fail.other", nil), detail];
}

/* the list is made again with a short cross fade, so a plugin that starts or stops changes in front of the person and not in a jump */
- (void)crossfade {
    [UIView transitionWithView:self.table duration:0.22 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                    animations:^{ [self rebuild]; } completion:nil];
}

/* the switch has moved already and its own animation runs; the plugin is started after it, in two steps so that the line "Starting" is on screen
   before the main thread is held by the import */
- (void)startPlugin:(NSString *)file {
    [_starting addObject:file];
    ExteriaWeakReference *weak = _weak;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ExteriaPluginsController *me = weak.target;
        if (!me) return;
        [me crossfade];
        dispatch_async(dispatch_get_main_queue(), ^{
            ExteriaPluginsController *again = weak.target;
            if (!again) return;
            ExteriaPluginsSetEnabled(file, YES);
            [again->_starting removeObject:file];
            [again crossfade];
            [again explainFailureOf:file];
        });
    });
}

/* a plugin that did not start says why in a window with the picture over the words, so the reason is not left to the grey line of the list */
- (void)explainFailureOf:(NSString *)file {
    ExteriaPluginEntry *failed = nil;
    for (ExteriaPluginEntry *entry in ExteriaPluginsList()) if ([entry.file isEqualToString:file]) failed = entry;
    if (!failed || failed.enabled || !failed.failure || _failurePopup.isShown) return;
    [_failurePopup release];
    _failurePopup = [[ExteriaSenkoPopup alloc] init];
    _failurePopup.pictureName = @"plugin_fail.png";
    _failurePopup.pictureHeight = 150;
    _failurePopup.titleText = [NSString stringWithFormat:NSLocalizedString(@"plugins.fail.title", nil), failed.name.length ? failed.name : failed.file];
    _failurePopup.messageText = failure_text(failed.failure);
    _failurePopup.buttonTitle = NSLocalizedString(@"notice.ok", nil);
    ExteriaWeakReference *weak = _weak;
    _failurePopup.dismissHandler = ^{
        ExteriaPluginsController *me = weak.target;
        if (!me) return;
        [me->_failurePopup release];
        me->_failurePopup = nil;
    };
    [_failurePopup showInView:ExteriaOverlayHost()];
}

- (void)stopPlugin:(NSString *)file {
    ExteriaPluginsSetEnabled(file, NO);
    ExteriaWeakReference *weak = _weak;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [(ExteriaPluginsController *)weak.target crossfade];
    });
}

- (ExteriaSettingsRow *)rowForEntry:(ExteriaPluginEntry *)entry {
    if (entry.status != 0) {
        NSString *report = entry.error;
        NSString *title = entry.file;
        return [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolDocument tone:ExteriaSettingsToneGray title:title subtitle:refusal_text(entry) value:nil tap:report.length ? ^{
            ExteriaShowAlert(title, report, [NSArray arrayWithObjects:NSLocalizedString(@"notice.ok", nil), NSLocalizedString(@"devices.copy", nil), nil], 0, NO,
                             ^(NSInteger index, NSString *text) {
                (void)text;
                if (index == 1) [UIPasteboard generalPasteboard].string = report;
            });
        } : nil];
    }
    BOOL starting = [_starting containsObject:entry.file];
    NSMutableArray *lines = [NSMutableArray array];
    if (starting) [lines addObject:NSLocalizedString(@"plugins.starting", nil)];
    else if (entry.fault) [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"plugins.fault", nil), friendly_fault(entry.fault)]];
    else if (entry.changed) [lines addObject:NSLocalizedString(@"plugins.changed", nil)];
    [lines addObject:permission_names(entry.permissions)];
    if (entry.enabled && entry.hasSettings) [lines addObject:NSLocalizedString(@"plugins.settings.hint", nil)];
    ExteriaWeakReference *weak = _weak;
    NSString *file = entry.file;
    ExteriaSettingsRow *row = [ExteriaSettingsRow switchRowWithSymbol:ExteriaSymbolApps tone:ExteriaSettingsToneCyan title:entry.name subtitle:[lines componentsJoinedByString:@"\n"] on:entry.enabled || starting
                                            toggle:^(BOOL on) {
        ExteriaPluginsController *me = weak.target;
        if (!me) return;
        if (on) [me startPlugin:file];
        else [me stopPlugin:file];
    }];
    /* a plugin that failed shows what went wrong in a line; a tap gives the whole report */
    if (entry.fault && !entry.enabled && !starting) {
        NSString *report = entry.fault;
        NSString *title = entry.name;
        row.tap = ^{ ExteriaShowNotice(title, report); };
    }
    /* a tap on the row of a running plugin opens the settings it built */
    if (entry.enabled && entry.hasSettings) {
        NSString *pluginId = entry.pluginId;
        NSString *title = entry.name;
        row.tap = ^{
            ExteriaPluginsController *me = weak.target;
            if (!me) return;
            [me.navigationController pushViewController:[[[ExteriaPluginSettingsController alloc] initWithPluginId:pluginId title:title items:nil] autorelease] animated:YES];
        };
    }
    return row;
}

/* the same browser as the one that picks a file to send, asking for scripts: only folders and plugin files show, and the one that is tapped is copied into the plugins folder */
- (void)importPlugin {
    ExteriaWeakReference *weak = _weak;
    ExteriaFilePicker *picker = [[[ExteriaFilePicker alloc] initWithDirectory:nil handler:^(NSString *path) {
        ExteriaPluginsController *me = weak.target;
        if (!me) return;
        NSString *installed = nil;
        NSString *failure = ExteriaPluginsImport(path, nil, &installed);
        if (failure) ExteriaShowNotice(NSLocalizedString(@"plugins.import.title", nil), failure);
        else ExteriaShowNotice(NSLocalizedString(@"plugins.import.title", nil), [NSString stringWithFormat:NSLocalizedString(@"plugins.import.done", nil), installed]);
        [me rebuild];
    } cancel:nil] autorelease];
    picker.extensions = [NSArray arrayWithObjects:@"plugin", @"py", nil];
    picker.rootTitle = NSLocalizedString(@"plugins.import.pick", nil);
    picker.searchPlaceholder = NSLocalizedString(@"plugins.import.search", nil);
    picker.emptyText = NSLocalizedString(@"plugins.import.empty", nil);
    picker.fileSymbol = ExteriaSymbolDocument;
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:picker] autorelease];
    if (ExteriaThemeIsClassic()) ExteriaClassicStyleNavigationBar(navigation.navigationBar);
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)rebuild {
    NSMutableArray *rows = [NSMutableArray array];
    for (ExteriaPluginEntry *entry in ExteriaPluginsList()) [rows addObject:[self rowForEntry:entry]];
    ExteriaWeakReference *weak = _weak;
    ExteriaSettingsRow *import = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolDocument tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"plugins.import.title", nil)
                                                          subtitle:nil value:nil tap:^{
        [(ExteriaPluginsController *)weak.target importPlugin];
    }];
    NSMutableArray *sections = [NSMutableArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:import]]];
    if (rows.count) {
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"plugins.installed", nil)
                                                               footer:NSLocalizedString(@"plugins.footer", nil) rows:rows]];
    }
    NSMutableArray *actionRows = [NSMutableArray array];
    for (NSDictionary *action in ExteriaPluginsActions()) {
        NSString *pluginId = [action objectForKey:@"pluginId"];
        NSString *itemId = [action objectForKey:@"item"];
        [actionRows addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolApps tone:ExteriaSettingsToneGreen title:[action objectForKey:@"text"]
                                                       subtitle:[action objectForKey:@"plugin"] value:nil tap:^{
            ExteriaPluginsRunAction(pluginId, itemId);
        }]];
    }
    if (actionRows.count) [sections insertObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"plugins.actions", nil) footer:nil rows:actionRows] atIndex:1];
    self.sections = sections;
    if ((rows.count == 0) != _empty) {
        _empty = rows.count == 0;
        [self rebuildHeader];
    }
}

@end
