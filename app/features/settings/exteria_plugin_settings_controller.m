#import "exteria_plugin_settings_controller.h"

#include <math.h>
#import "exteria_alert.h"
#import "exteria_plugins.h"
#import "exteria_symbol.h"
#import "exteria_weak_reference.h"

@implementation ExteriaPluginSettingsController

- (id)initWithPluginId:(NSString *)pluginId title:(NSString *)title items:(NSArray *)items {
    self = [super init];
    if (!self) return nil;
    _pluginId = [pluginId copy];
    _items = [items retain];
    _root = items == nil;
    self.pageTitle = title;
    return self;
}

- (void)dealloc {
    [_pluginId release];
    [_items release];
    [super dealloc];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

/* a value the plugin keeps as a string, a number or a bool, shown as text */
static NSString *shown(id value) {
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return nil;
}

static NSString *string_of(NSDictionary *item, NSString *key) {
    id value = [item objectForKey:key];
    return [value isKindOfClass:[NSString class]] && [value length] ? value : nil;
}

- (void)reloadItems {
    if (!_root) return;
    [_items release];
    _items = [ExteriaPluginsSettingsItems(_pluginId) retain];
}

- (void)click:(NSDictionary *)item {
    NSString *callback = string_of(item, @"callback_id");
    NSArray *sub = [item objectForKey:@"sub_page"];
    if (callback) {
        ExteriaPluginsSettingClick(_pluginId, callback);
        if (_root) [self rebuild];
    }
    if ([sub isKindOfClass:[NSArray class]] && sub.count) {
        ExteriaPluginSettingsController *page = [[[ExteriaPluginSettingsController alloc] initWithPluginId:_pluginId title:string_of(item, @"text") items:sub] autorelease];
        [self.navigationController pushViewController:page animated:YES];
    }
}

- (ExteriaSettingsRow *)rowForItem:(NSDictionary *)item {
    NSString *type = string_of(item, @"type");
    NSString *text = string_of(item, @"text");
    NSString *subtext = string_of(item, @"subtext");
    NSString *key = string_of(item, @"key");
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    if ([type isEqualToString:@"text"]) {
        void (^tap)(void) = ^{ [(ExteriaPluginSettingsController *)weak.target click:item]; };
        if ([[item objectForKey:@"red"] boolValue]) return [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolApps title:text destructive:YES tap:tap];
        if ([[item objectForKey:@"accent"] boolValue]) return [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolApps title:text destructive:NO tap:tap];
        return [ExteriaSettingsRow rowWithTitle:text subtitle:subtext value:nil tap:tap];
    }
    if ([type isEqualToString:@"switch"] && key) {
        return [ExteriaSettingsRow switchRowWithTitle:text subtitle:subtext on:[[item objectForKey:@"value"] boolValue] toggle:^(BOOL on) {
            ExteriaPluginSettingsController *me = weak.target;
            if (!me) return;
            ExteriaPluginsSettingChanged(me->_pluginId, key, [NSNumber numberWithBool:on]);
            [me click:item];
        }];
    }
    if ([type isEqualToString:@"selector"] && key) {
        NSArray *choices = [item objectForKey:@"items"];
        NSInteger index = [[item objectForKey:@"value"] integerValue];
        NSString *current = (index >= 0 && (NSUInteger)index < choices.count) ? shown([choices objectAtIndex:(NSUInteger)index]) : nil;
        return [ExteriaSettingsRow rowWithTitle:text subtitle:subtext value:current tap:^{
            ExteriaPluginSettingsController *host = weak.target;
            if (!host) return;
            ExteriaSettingsChoose(host, text, choices, ^(NSUInteger picked) {
                ExteriaPluginSettingsController *me = weak.target;
                if (!me) return;
                ExteriaPluginsSettingChanged(me->_pluginId, key, [NSNumber numberWithUnsignedInteger:picked]);
                [me rebuild];
            });
        }];
    }
    if ([type isEqualToString:@"input"] && key) {
        NSString *current = shown([item objectForKey:@"value"]);
        return [ExteriaSettingsRow rowWithTitle:text subtitle:subtext value:current tap:^{
            ExteriaPromptText(text, subtext, current, nil, ^(NSString *entered) {
                ExteriaPluginSettingsController *me = weak.target;
                if (!me) return;
                ExteriaPluginsSettingChanged(me->_pluginId, key, entered);
                [me rebuild];
            });
        }];
    }
    if ([type isEqualToString:@"slider"] && key) {
        NSString *format = [[item objectForKey:@"integral"] boolValue] ? @"%.0f" : @"%.1f";
        return [ExteriaSettingsRow sliderRowWithTitle:text ? text : key format:format value:(float)[[item objectForKey:@"value"] doubleValue]
                                              minimum:(float)[[item objectForKey:@"min"] doubleValue] maximum:(float)[[item objectForKey:@"max"] doubleValue]
                                               change:^(float value) {
            ExteriaPluginSettingsController *me = weak.target;
            if (!me) return;
            float step = (float)[[item objectForKey:@"step"] doubleValue];
            if (step > 0) value = roundf(value / step) * step;
            ExteriaPluginsSettingChanged(me->_pluginId, key, [[item objectForKey:@"integral"] boolValue] ? (id)[NSNumber numberWithLong:lroundf(value)] : (id)[NSNumber numberWithFloat:value]);
        }];
    }
    if ([type isEqualToString:@"edittext"] && key) {
        NSString *current = shown([item objectForKey:@"value"]);
        NSString *hint = string_of(item, @"hint");
        return [ExteriaSettingsRow rowWithTitle:hint ? hint : key subtitle:nil value:current tap:^{
            ExteriaPluginSettingsController *me = weak.target;
            if (!me) return;
            ExteriaPromptText(hint ? hint : key, nil, current, hint, ^(NSString *entered) {
                ExteriaPluginSettingsController *again = weak.target;
                if (!again) return;
                ExteriaPluginsSettingChanged(again->_pluginId, key, entered);
                [again rebuild];
            });
        }];
    }
    /* a view drawn by the plugin has no counterpart yet: the row says so */
    return [ExteriaSettingsRow rowWithTitle:text ? text : (key ? key : type) subtitle:NSLocalizedString(@"plugins.settings.unsupported", nil) value:nil tap:nil];
}

- (void)rebuild {
    [self reloadItems];
    NSMutableArray *sections = [NSMutableArray array];
    NSString *header = nil;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *item in _items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *type = string_of(item, @"type");
        if ([type isEqualToString:@"header"]) {
            if (rows.count) [sections addObject:[ExteriaSettingsSection sectionWithHeader:header footer:nil rows:rows]];
            rows = [NSMutableArray array];
            header = string_of(item, @"text");
        } else if ([type isEqualToString:@"divider"]) {
            /* a divider ends a group; its text, if it has one, is the note under it */
            if (rows.count || string_of(item, @"text")) [sections addObject:[ExteriaSettingsSection sectionWithHeader:header footer:string_of(item, @"text") rows:rows]];
            rows = [NSMutableArray array];
            header = nil;
        } else {
            [rows addObject:[self rowForItem:item]];
        }
    }
    if (rows.count) [sections addObject:[ExteriaSettingsSection sectionWithHeader:header footer:nil rows:rows]];
    self.sections = sections;
}

@end
