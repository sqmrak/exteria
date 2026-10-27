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
    [_weak clear];
    [_weak release];
    [_faces invalidate];
    [_faces release];
    [_session release];
    [_avatars release];
    [_all release];
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
    [_session loadDialogs:^(NSArray *items, NSString *errorName) {
        ExteriaDialogPickerController *me = weak.target;
        if (!me) return;
        if (!items) {
            [me->_status release];
            me->_status = [ExteriaGiftErrorText(errorName) copy];
            [me rebuild];
            return;
        }
        NSMutableArray *rows = [NSMutableArray array];
        ExteriaDialog *saved = nil;
        for (ExteriaDialog *dialog in items) {
            if (![me usable:dialog]) continue;
            if (me->_forwarding && dialog.saved) saved = dialog;
            else [rows addObject:dialog];
        }
        if (me->_forwarding) {
            if (!saved && me->_all.count && ((ExteriaDialog *)[me->_all objectAtIndex:0]).saved) saved = [me->_all objectAtIndex:0];
            if (saved) [rows insertObject:saved atIndex:0];
        }
        [me->_all release];
        me->_all = [rows retain];
        [me->_status release];
        me->_status = [(rows.count ? @"" : NSLocalizedString(@"chats.nothing", nil)) copy];
        [me rebuild];
    }];
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
    if (!query.length) return nil;
    NSMutableArray *matches = [NSMutableArray array];
    for (ExteriaDialog *dialog in _all) {
        if ([dialog.title rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) [matches addObject:dialog];
    }
    return [self sectionsForDialogs:matches footer:matches.count ? nil : NSLocalizedString(@"chats.nothing", nil)];
}

@end
