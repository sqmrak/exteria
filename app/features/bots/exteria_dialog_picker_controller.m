#import "exteria_dialog_picker_controller.h"

#import "exteria_gift_screen.h"
#import "exteria_avatar_view.h"
#import "exteria_plural.h"
#import "exteria_time.h"
#import <QuartzCore/QuartzCore.h>
#import "exteria_people_avatars.h"
#import "exteria_person.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

@interface ExteriaDialogPickerController () {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaWeakReference *_weak;
    ExteriaPeopleAvatars *_faces;
    NSArray *_all;
    NSString *_status;
    NSMutableArray *_picked;
    UIButton *_done;
    BOOL (^_filter)(ExteriaDialog *dialog);
    void (^_pickHandler)(NSArray *dialogs);
    NSUInteger _limit;
    BOOL _forwarding;
    NSString *_remoteQuery;
    NSArray *_remoteResults;
    NSString *_remoteError;
    NSMutableSet *_pageCursors;
}
@end

@implementation ExteriaDialogPickerController

@synthesize filter = _filter;
@synthesize forwarding = _forwarding;
@synthesize limit = _limit;
@synthesize pickHandler = _pickHandler;

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    (void)media;
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _picked = [[NSMutableArray alloc] init];
    self.searchable = YES;
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchRemote) object:nil];
    [_weak clear];
    [_weak release];
    [_faces invalidate];
    [_faces release];
    [_session release];
    [_avatars release];
    [_all release];
    [_remoteQuery release];
    [_remoteResults release];
    [_remoteError release];
    [_pageCursors release];
    [_status release];
    [_picked release];
    [_done release];
    [_filter release];
    [_pickHandler release];
    [super dealloc];
}

- (NSString *)screenTitle {
    return self.pageTitle;
}

- (void)setScreenTitle:(NSString *)title {
    self.pageTitle = title;
}

- (NSUInteger)limit {
    return _limit ? _limit : 1;
}

/* a chat can be picked when it is a real chat the person can write in */
- (BOOL)usable:(ExteriaDialog *)dialog {
    if (dialog.folder || dialog.community || dialog.left || dialog.topicId) return NO;
    if (dialog.kind == EXTERIA_DIALOG_CHANNEL && !dialog.canPost) return NO;
    return _filter ? _filter(dialog) : YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (_forwarding) {
        long long account = [ExteriaSession accountIdInDirectory:_session.directory];
        ExteriaDialog *saved = account > 0 ? [ExteriaDialog savedMessagesOfUserId:account] : nil;
        if (saved && [self usable:saved]) _all = [[NSArray alloc] initWithObjects:saved, nil];
    }
    [self rebuild];
    [self refreshAction];
    ExteriaWeakReference *weak = _weak;
    if (!_forwarding) {
        [_session loadDialogs:^(NSArray *items, NSString *errorName) {
            ExteriaDialogPickerController *me = weak.target;
            if (!me) return;
            if (items) [me addDestinations:items];
            else { [me->_status release]; me->_status = [ExteriaGiftErrorText(errorName) copy]; [me rebuild]; }
        }];
    }
    if (_forwarding) {
        [self loadFolder:0 after:nil];
        [self loadFolder:1 after:nil];
        [_session loadContacts:^(NSArray *items, NSString *errorName) {
            ExteriaDialogPickerController *me = weak.target;
            if (!me) return;
            if (!items) { NSLog(@"exteria: forwarding contacts did not load: %@", errorName); return; }
            NSMutableArray *dialogs = [NSMutableArray array];
            for (ExteriaPerson *person in items) {
                ExteriaDialog *dialog = [ExteriaDialog dialogWithPerson:person];
                if (dialog) [dialogs addObject:dialog];
            }
            [me addDestinations:dialogs];
        }];
    }
}

- (void)loadFolder:(int32_t)folder after:(ExteriaDialog *)cursor {
    if (cursor) {
        if (!_pageCursors) _pageCursors = [[NSMutableSet alloc] init];
        NSString *key = [NSString stringWithFormat:@"%d:%d:%lld:%d", (int)folder, cursor.peerKind, cursor.peerId, cursor.topMessage];
        if ([_pageCursors containsObject:key]) {
            [_status release]; _status = [ExteriaGiftErrorText(@"DIALOG_PAGINATION_FAILED") copy];
            [self rebuild];
            return;
        }
        [_pageCursors addObject:key];
    }
    ExteriaWeakReference *weak = _weak;
    [_session loadDialogPageInFolder:folder after:cursor completion:^(NSArray *items, ExteriaDialog *next, NSString *errorName) {
        ExteriaDialogPickerController *me = weak.target;
        if (!me) return;
        if (items) [me addDestinations:items];
        if (errorName) {
            NSLog(@"exteria: forwarding folder %d did not load: %@", (int)folder, errorName);
            [me->_status release]; me->_status = [ExteriaGiftErrorText(errorName) copy];
            [me rebuild];
        } else if (next) [me loadFolder:folder after:next];
    }];
}

- (void)addDestinations:(NSArray *)items {
    NSMutableArray *rows = [NSMutableArray arrayWithArray:_all ? _all : [NSArray array]];
    for (ExteriaDialog *candidate in items) {
        if (![self usable:candidate]) continue;
        BOOL found = NO;
        for (ExteriaDialog *row in rows) if (row.peerKind == candidate.peerKind && row.peerId == candidate.peerId) { found = YES; break; }
        if (!found) [rows addObject:candidate];
    }
    [_all release]; _all = [rows copy];
    if (_all.count) { [_status release]; _status = nil; }
    [self rebuild];
    if (self.searching) [self reloadSearchResults];
}

- (void)themeDidChange {
    [self rebuild];
    [self refreshAction];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

#pragma mark picking

- (BOOL)pickedDialog:(ExteriaDialog *)dialog {
    for (ExteriaDialog *one in _picked) if (one.peerKind == dialog.peerKind && one.peerId == dialog.peerId) return YES;
    return NO;
}

/* the action of the bar appears with the first tick and says how many there are */
- (void)refreshAction {
    if (self.limit <= 1) return;
    NSString *title = _picked.count ? [NSString stringWithFormat:@"%@ (%lu)", NSLocalizedString(@"bots.pick.done", nil), (unsigned long)_picked.count] : nil;
    if (ExteriaThemeIsClassic()) {
        self.navigationItem.rightBarButtonItem = title ? [[[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:self action:@selector(finish)] autorelease] : nil;
        return;
    }
    if (!title) {
        self.barViews = [NSArray array];
        return;
    }
    if (!_done) {
        _done = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _done.titleLabel.font = ExteriaFontSemibold(17);
        [_done setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
        [_done addTarget:self action:@selector(finish) forControlEvents:UIControlEventTouchUpInside];
    }
    [_done setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_done setTitle:title forState:UIControlStateNormal];
    [_done sizeToFit];
    _done.frame = CGRectMake(0, 0, _done.frame.size.width + 24, 44);
    self.barViews = [NSArray arrayWithObject:_done];
}

- (void)finish {
    if (!_picked.count) return;
    void (^handler)(NSArray *) = [_pickHandler retain];
    NSArray *chosen = [[_picked copy] autorelease];
    [self.navigationController popViewControllerAnimated:YES];
    if (handler) handler(chosen);
    [handler release];
}

- (void)choose:(ExteriaDialog *)dialog {
    if (self.limit <= 1) {
        void (^handler)(NSArray *) = [_pickHandler retain];
        [self.navigationController popViewControllerAnimated:YES];
        if (handler) handler([NSArray arrayWithObject:dialog]);
        [handler release];
        return;
    }
    if ([self pickedDialog:dialog]) {
        for (ExteriaDialog *one in [[_picked copy] autorelease]) if (one.peerKind == dialog.peerKind && one.peerId == dialog.peerId) [_picked removeObject:one];
    } else if (_picked.count < self.limit) {
        [_picked addObject:dialog];
    }
    if (self.searching) [self reloadSearchResults];
    else [self rebuild];
    [self refreshAction];
}

#pragma mark rows

static UIImage *ExteriaSavedPickerImage(void) {
    ExteriaAvatarView *avatar = [[[ExteriaAvatarView alloc] initWithFrame:CGRectMake(0, 0, 48, 48)] autorelease];
    avatar.circular = YES; avatar.accent = YES; avatar.showsSymbol = YES; avatar.symbol = ExteriaSymbolBookmark;
    UIGraphicsBeginImageContextWithOptions(avatar.bounds.size, NO, 0);
    [avatar.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (NSString *)subtitleOfDialog:(ExteriaDialog *)dialog {
    if (!_forwarding) return nil;
    if (dialog.saved) return NSLocalizedString(@"forward.saved.hint", nil);
    if (dialog.kind == EXTERIA_DIALOG_USER) return ExteriaLastSeenText(dialog.presence, dialog.seen);
    if (dialog.kind == EXTERIA_DIALOG_BOT) return NSLocalizedString(@"seen.bot", nil);
    if (dialog.participantsCount > 0) {
        NSString *base = dialog.kind == EXTERIA_DIALOG_CHANNEL ? @"chat.subscribers" : @"chat.members";
        NSString *key = [NSString stringWithFormat:@"%@.%@", base, ExteriaPluralForm(dialog.participantsCount)];
        return [NSString stringWithFormat:NSLocalizedString(key, nil), (long)dialog.participantsCount];
    }
    return nil;
}

- (ExteriaSettingsRow *)rowOfDialog:(ExteriaDialog *)dialog {
    ExteriaWeakReference *weak = _weak;
    if (!_faces) {
        _faces = [[ExteriaPeopleAvatars alloc] initWithCache:_avatars changed:^{
            ExteriaDialogPickerController *me = weak.target;
            if (me.searching) [me reloadSearchResults];
            else [me rebuild];
        }];
    }
    UIImage *face = _forwarding && dialog.saved ? ExteriaSavedPickerImage() : [_faces imageForKey:[NSString stringWithFormat:@"%d:%lld", dialog.peerKind, dialog.peerId] initials:dialog.initials seed:dialog.avatarSeed deleted:dialog.deleted photo:dialog.photo];
    ExteriaSettingsRow *row = [ExteriaSettingsRow rowWithTileImage:face title:dialog.title subtitle:[self subtitleOfDialog:dialog] tap:^{ [(ExteriaDialogPickerController *)weak.target choose:dialog]; }];
    if ([self pickedDialog:dialog]) row.trailingImage = ExteriaSymbolImage(ExteriaSymbolCheck, 22, ExteriaColorAccent());
    return row;
}

- (NSArray *)sectionsForDialogs:(NSArray *)dialogs footer:(NSString *)footer {
    NSMutableArray *rows = [NSMutableArray array];
    for (ExteriaDialog *dialog in dialogs) [rows addObject:[self rowOfDialog:dialog]];
    return [NSArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
}

- (void)rebuild {
    self.sections = [self sectionsForDialogs:_all footer:_status];
    [self reloadSettings];
}

- (NSArray *)sectionsForSearchQuery:(NSString *)query {
    if (!query.length) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchRemote) object:nil];
        [_remoteQuery release]; _remoteQuery = nil;
        [_remoteResults release]; _remoteResults = nil;
        [_remoteError release]; _remoteError = nil;
        return nil;
    }
    if (_forwarding && ![_remoteQuery isEqualToString:query]) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchRemote) object:nil];
        [_remoteQuery release]; _remoteQuery = [query copy];
        [_remoteResults release]; _remoteResults = nil;
        [_remoteError release]; _remoteError = nil;
        [self performSelector:@selector(searchRemote) withObject:nil afterDelay:0.3];
    }
    NSMutableArray *matches = [NSMutableArray array];
    for (ExteriaDialog *dialog in _all) {
        if ([dialog.title rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) [matches addObject:dialog];
    }
    for (ExteriaDialog *candidate in _remoteResults) {
        if (![self usable:candidate]) continue;
        BOOL found = NO;
        for (ExteriaDialog *row in matches) if (row.peerKind == candidate.peerKind && row.peerId == candidate.peerId) { found = YES; break; }
        if (!found) [matches addObject:candidate];
    }
    return [self sectionsForDialogs:matches footer:matches.count ? nil : (_remoteError ? ExteriaGiftErrorText(_remoteError) : NSLocalizedString(@"chats.nothing", nil))];
}

- (void)searchRemote {
    NSString *query = [[_remoteQuery copy] autorelease];
    if (!query.length) return;
    ExteriaWeakReference *weak = _weak;
    [_session searchPeers:query completion:^(NSArray *items, NSString *errorName) {
        ExteriaDialogPickerController *me = weak.target;
        if (!me || !me.searching || ![me->_remoteQuery isEqualToString:query]) return;
        [me->_remoteResults release]; me->_remoteResults = [items copy];
        [me->_remoteError release]; me->_remoteError = [errorName copy];
        [me reloadSearchResults];
    }];
}

@end
