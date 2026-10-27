#import "exteria_accounts.h"

#import "exteria_session.h"

NSString *const ExteriaAccountSwitchNotification = @"ExteriaAccountSwitchNotification";
NSString *const ExteriaAccountAddNotification = @"ExteriaAccountAddNotification";

static NSString *const ExteriaAccountActiveKey = @"exteria.account.active";
static NSString *const ExteriaAccountInfoKey = @"exteria.account.info";
static NSString *const ExteriaAccountPrefix = @"account-";

NSString *ExteriaAccountsRoot(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *directory = [[roots objectAtIndex:0] stringByAppendingPathComponent:@"Exteria"];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"exteria: cannot create %@: %@", directory, error);
    }
    return directory;
}

NSString *ExteriaAccountDirectory(NSString *name) {
    return name.length ? [ExteriaAccountsRoot() stringByAppendingPathComponent:name] : ExteriaAccountsRoot();
}

NSArray *ExteriaAccountNames(void) {
    NSMutableArray *names = [NSMutableArray array];
    if ([ExteriaSession hasAccountInDirectory:ExteriaAccountsRoot()]) [names addObject:@""];
    NSArray *entries = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:ExteriaAccountsRoot() error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *entry in entries) {
        if (![entry hasPrefix:ExteriaAccountPrefix]) continue;
        if ([ExteriaSession hasAccountInDirectory:ExteriaAccountDirectory(entry)]) [names addObject:entry];
    }
    return names;
}

NSString *ExteriaAccountActive(void) {
    NSArray *names = ExteriaAccountNames();
    NSString *chosen = [[NSUserDefaults standardUserDefaults] stringForKey:ExteriaAccountActiveKey];
    if (chosen && [names containsObject:chosen]) return chosen;
    return names.count ? [names objectAtIndex:0] : @"";
}

void ExteriaAccountSetActive(NSString *name) {
    [[NSUserDefaults standardUserDefaults] setObject:name forKey:ExteriaAccountActiveKey];
}

NSString *ExteriaAccountMakeNew(void) {
    NSInteger number = 2;
    NSString *name;
    do {
        name = [ExteriaAccountPrefix stringByAppendingFormat:@"%ld", (long)number++];
    } while ([[NSFileManager defaultManager] fileExistsAtPath:ExteriaAccountDirectory(name)]);
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:ExteriaAccountDirectory(name) withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"exteria: cannot create the account directory %@: %@", name, error);
        return nil;
    }
    return name;
}

static NSDictionary *ExteriaAccountInfos(void) {
    NSDictionary *infos = [[NSUserDefaults standardUserDefaults] dictionaryForKey:ExteriaAccountInfoKey];
    return infos ? infos : [NSDictionary dictionary];
}

void ExteriaAccountRemove(NSString *name) {
    NSMutableDictionary *infos = [NSMutableDictionary dictionaryWithDictionary:ExteriaAccountInfos()];
    [infos removeObjectForKey:name];
    [[NSUserDefaults standardUserDefaults] setObject:infos forKey:ExteriaAccountInfoKey];
    if (!name.length) return;
    NSError *error = nil;
    if (![[NSFileManager defaultManager] removeItemAtPath:ExteriaAccountDirectory(name) error:&error]) NSLog(@"exteria: the account directory %@ stays: %@", name, error);
}

NSDictionary *ExteriaAccountInfo(NSString *name) {
    return [ExteriaAccountInfos() objectForKey:name];
}

void ExteriaAccountSetInfo(NSString *name, NSString *title, NSString *username, long long userId) {
    NSMutableDictionary *infos = [NSMutableDictionary dictionaryWithDictionary:ExteriaAccountInfos()];
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:title ? title : @"", @"title", username ? username : @"", @"username",
                          [NSNumber numberWithLongLong:userId], @"user", nil];
    [infos setObject:info forKey:name];
    [[NSUserDefaults standardUserDefaults] setObject:infos forKey:ExteriaAccountInfoKey];
}

NSString *ExteriaAccountNameOfUser(long long userId, NSString *except) {
    NSDictionary *infos = ExteriaAccountInfos();
    for (NSString *name in ExteriaAccountNames()) {
        if ([name isEqualToString:except]) continue;
        if ([[[infos objectForKey:name] objectForKey:@"user"] longLongValue] == userId) return name;
    }
    return nil;
}
