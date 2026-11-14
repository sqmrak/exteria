#import "exteria_plugin_tabs.h"

#import "exteria_symbol.h"

#define TAB_SLOTS 4
#define TITLE_MAX 64

NSString *const ExteriaPluginTabsNotification = @"ExteriaPluginTabs";

static NSMutableDictionary *g_changes;
static BOOL g_bar_up;

/* the icons of the client that plugins name, and the symbol the app draws for each */
static BOOL symbol_named(NSString *name, ExteriaSymbol *symbol) {
    if ([name isEqualToString:@"music"]) {
        *symbol = ExteriaSymbolMusic;
        return YES;
    }
    return NO;
}

NSDictionary *ExteriaPluginTabChange(NSInteger slot) {
    return [g_changes objectForKey:[NSNumber numberWithInteger:slot]];
}

void ExteriaPluginTabsSetBarUp(BOOL up) {
    g_bar_up = up;
}

void ExteriaPluginTabsReset(void) {
    if (!g_changes.count) return;
    [g_changes removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaPluginTabsNotification object:nil];
}

exteria_status ExteriaPluginTabsService(NSString *name, NSDictionary *request, NSDictionary **reply, NSString **failure) {
    if ([name isEqualToString:@"tabs.state"]) {
        *reply = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:g_bar_up] forKey:@"value"];
        return EXTERIA_OK;
    }
    if (![name isEqualToString:@"tabs.set"]) return EXTERIA_E_UNSUPPORTED;
    NSNumber *slot = [request objectForKey:@"slot"];
    id title = [request objectForKey:@"title"], icon = [request objectForKey:@"icon"];
    if (![slot isKindOfClass:[NSNumber class]] || [slot integerValue] < 0 || [slot integerValue] >= TAB_SLOTS) {
        if (failure) *failure = @"no such tab";
        return EXTERIA_E_ARG;
    }
    if (title != [NSNull null] && title && (![title isKindOfClass:[NSString class]] || [title lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > TITLE_MAX)) {
        if (failure) *failure = @"the title is not text or is too long";
        return EXTERIA_E_ARG;
    }
    ExteriaSymbol symbol = ExteriaSymbolChats;
    BOOL hasIcon = icon && icon != [NSNull null];
    if (hasIcon && (![icon isKindOfClass:[NSString class]] || !symbol_named(icon, &symbol))) {
        if (failure) *failure = [NSString stringWithFormat:@"the bar has no icon %@", icon];
        return EXTERIA_E_UNSUPPORTED;
    }
    NSMutableDictionary *change = [NSMutableDictionary dictionary];
    if ([title isKindOfClass:[NSString class]]) [change setObject:title forKey:@"title"];
    if (hasIcon) [change setObject:[NSNumber numberWithInt:symbol] forKey:@"symbol"];
    [change setObject:[NSNumber numberWithBool:[[request objectForKey:@"click"] boolValue]] forKey:@"click"];
    [change setObject:[NSNumber numberWithBool:[[request objectForKey:@"hold"] boolValue]] forKey:@"hold"];
    if (!g_changes) g_changes = [[NSMutableDictionary alloc] init];
    [g_changes setObject:change forKey:slot];
    *reply = [NSDictionary dictionary];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaPluginTabsNotification object:nil];
    return EXTERIA_OK;
}
