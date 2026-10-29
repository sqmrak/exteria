#import "exteria_folders_controller.h"
#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_gift_screen.h"
#import "exteria_lottie_view.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_sheet.h"
#import "exteria_weak_reference.h"

static BOOL same_peer(exteria_peer_ref a, exteria_peer_ref b) {
    return a.self || b.self ? a.self == b.self : a.kind == b.kind && a.id == b.id;
}
static BOOL has_peer(NSData *data, exteria_peer_ref peer) {
    const exteria_peer_ref *peers = data.bytes;
    for (NSUInteger i = 0; i < data.length / sizeof(peer); ++i)
        if (same_peer(peers[i], peer))
            return YES;
    return NO;
}
static NSData *toggle_peer(NSData *data, exteria_peer_ref peer, BOOL include) {
    NSMutableData *updated = [NSMutableData data];
    const exteria_peer_ref *peers = data.bytes;
    for (NSUInteger i = 0; i < data.length / sizeof(peer); ++i)
        if (!same_peer(peers[i], peer))
            [updated appendBytes:&peers[i] length:sizeof(peer)];
    if (include && updated.length / sizeof(peer) < EXTERIA_FOLDER_PEERS_MAX)
        [updated appendBytes:&peer length:sizeof(peer)];
    return updated;
}
static exteria_peer_ref dialog_peer(ExteriaDialog *dialog) {
    exteria_peer_ref peer;
    memset(&peer, 0, sizeof(peer));
    peer.kind = dialog.peerKind;
    peer.id = dialog.peerId;
    peer.access_hash = dialog.peerHash;
    peer.self = dialog.saved;
    return peer;
}

@interface ExteriaFolderPeersController : ExteriaSettingsPageController {
    ExteriaChatFolder *_folder;
    NSArray *_dialogs;
    NSInteger _kind;
    ExteriaWeakReference *_weak;
}
- (id)initWithFolder:(ExteriaChatFolder *)folder dialogs:(NSArray *)dialogs kind:(NSInteger)kind;
@end

@implementation ExteriaFolderPeersController
- (id)initWithFolder:(ExteriaChatFolder *)folder dialogs:(NSArray *)dialogs kind:(NSInteger)kind {
    self = [super init];
    if (self) {
        _folder = [folder retain];
        _dialogs = [dialogs copy];
        _kind = kind;
        _weak = [[ExteriaWeakReference referenceTo:self] retain];
        self.pageTitle = NSLocalizedString(kind == 0 ? @"folders.include" : (kind == 1 ? @"folders.exclude" : @"folders.pinned"), nil);
        self.searchable = YES;
    }
    return self;
}
- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_folder release];
    [_dialogs release];
    [super dealloc];
}
- (NSData *)selection {
    return _kind == 0 ? _folder.included : (_kind == 1 ? _folder.excluded : _folder.pinned);
}
- (void)toggle:(NSData *)packed {
    exteria_peer_ref peer;
    [packed getBytes:&peer length:sizeof(peer)];
    BOOL on = !has_peer([self selection], peer);
    if (on && [self selection].length / sizeof(peer) >= EXTERIA_FOLDER_PEERS_MAX) {
        ExteriaShowNotice(nil, NSLocalizedString(@"folders.limit", nil));
        return;
    }
    NSData *updated = toggle_peer([self selection], peer, on);
    if (_kind == 0) {
        _folder.included = updated;
        if (on)
            _folder.excluded = toggle_peer(_folder.excluded, peer, NO);
    } else if (_kind == 1) {
        _folder.excluded = updated;
        if (on) {
            _folder.included = toggle_peer(_folder.included, peer, NO);
            _folder.pinned = toggle_peer(_folder.pinned, peer, NO);
        }
    } else {
        _folder.pinned = updated;
        if (on)
            _folder.excluded = toggle_peer(_folder.excluded, peer, NO);
    }
    [self rebuild];
    [self reloadSearchResults];
}
- (NSArray *)sectionsMatching:(NSString *)query {
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableData *known = [NSMutableData data];
    ExteriaWeakReference *weak = _weak;
    for (ExteriaDialog *dialog in _dialogs) {
        if (dialog.folder || (_folder.shared && dialog.peerKind != 3))
            continue;
        exteria_peer_ref peer = dialog_peer(dialog);
        if (has_peer(known, peer))
            continue;
        [known appendBytes:&peer length:sizeof(peer)];
        if (query.length && [dialog.title rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound)
            continue;
        NSData *packed = [NSData dataWithBytes:&peer length:sizeof(peer)];
        [rows addObject:[ExteriaSettingsRow checkRowWithTitle:dialog.title
                                                     subtitle:nil
                                                      checked:has_peer([self selection], peer)
                                                          tap:^{
                                                              [(ExteriaFolderPeersController *)weak.target toggle:packed];
                                                          }]];
    }
    if (!query.length) {
        NSData *selection = [self selection];
        const exteria_peer_ref *peers = selection.bytes;
        for (NSUInteger i = 0; i < selection.length / sizeof(*peers); ++i) {
            if (has_peer(known, peers[i]))
                continue;
            NSData *packed = [NSData dataWithBytes:&peers[i] length:sizeof(*peers)];
            [rows addObject:[ExteriaSettingsRow checkRowWithTitle:NSLocalizedString(@"folders.unknown", nil)
                                                         subtitle:nil
                                                          checked:YES
                                                              tap:^{
                                                                  [(ExteriaFolderPeersController *)weak.target toggle:packed];
                                                              }]];
        }
    }
    return [NSArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:rows]];
}
- (NSArray *)sectionsForSearchQuery:(NSString *)query {
    return [self sectionsMatching:query];
}
- (void)rebuild {
    self.sections = [self sectionsMatching:@""];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}
@end

@interface ExteriaFolderEditController : ExteriaSettingsPageController {
    ExteriaSession *_session;
    ExteriaChatFolder *_folder;
    NSArray *_dialogs;
    BOOL _saving;
    BOOL _loading;
    id<ExteriaFolderDialogRequest> _folderLoad;
    ExteriaWeakReference *_weak;
}
- (id)initWithSession:(ExteriaSession *)session folder:(ExteriaChatFolder *)folder;
@end

@implementation ExteriaFolderEditController
- (id)initWithSession:(ExteriaSession *)session folder:(ExteriaChatFolder *)folder {
    self = [super init];
    if (self) {
        _session = [session retain];
        _folder = [folder copy];
        _weak = [[ExteriaWeakReference referenceTo:self] retain];
        self.pageTitle = folder.title;
    }
    return self;
}
- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_folderLoad cancel];
    [_folderLoad release];
    [_session release];
    [_folder release];
    [_dialogs release];
    [super dealloc];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self loadChats];
}
- (void)loadChats {
    if (_loading)
        return;
    _loading = YES;
    [self rebuild];
    ExteriaChatFolder *all = [[[ExteriaChatFolder alloc] init] autorelease];
    all.folderId = 2;
    all.flags = 31;
    ExteriaWeakReference *weak = _weak;
    [_folderLoad release];
    _folderLoad = [[_session loadDialogsForChatFolder:all
                                           completion:^(NSArray *dialogs, NSString *errorName) {
                                               ExteriaFolderEditController *me = weak.target;
                                               if (!me)
                                                   return;
                                               me->_loading = NO;
                                               if (errorName)
                                                   ExteriaShowNotice(nil, ExteriaGiftErrorText(errorName));
                                               else {
                                                   [me->_dialogs release];
                                                   me->_dialogs = [dialogs retain];
                                               }
                                               [me rebuild];
                                           }] retain];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if ([self isViewLoaded])
        [self rebuild];
}
- (void)rename {
    if (_saving)
        return;
    ExteriaWeakReference *weak = _weak;
    ExteriaPromptText(NSLocalizedString(@"folders.name", nil), NSLocalizedString(@"folders.name.info", nil), _folder.title, nil, ^(NSString *text) {
        ExteriaFolderEditController *me = weak.target;
        NSString *name = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!me)
            return;
        if (!name.length || name.length > 12) {
            ExteriaShowNotice(nil, NSLocalizedString(@"folders.name.info", nil));
            return;
        }
        me->_folder.title = name;
        me.pageTitle = name;
        [me rebuild];
    });
}
- (void)pick:(NSInteger)kind {
    if (_saving)
        return;
    if (!_dialogs) {
        [self loadChats];
        return;
    }
    ExteriaFolderPeersController *page = [[[ExteriaFolderPeersController alloc] initWithFolder:_folder dialogs:_dialogs kind:kind] autorelease];
    [self.navigationController pushViewController:page animated:YES];
}
- (void)save {
    if (_saving)
        return;
    if (!_folder.title.length || _folder.title.length > 12 || (!(_folder.flags & 31u) && !_folder.included.length && !_folder.pinned.length)) {
        ExteriaShowNotice(nil, NSLocalizedString(@"folders.empty", nil));
        return;
    }
    _saving = YES;
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    [_session saveChatFolder:_folder
                  completion:^(NSString *errorName) {
                      ExteriaFolderEditController *me = weak.target;
                      if (!me)
                          return;
                      me->_saving = NO;
                      if (errorName) {
                          ExteriaShowNotice(nil, ExteriaGiftErrorText(errorName));
                          [me rebuild];
                      } else
                          [me goBack];
                  }];
}
- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[ExteriaSettingsSection
                            sectionWithHeader:nil
                                       footer:NSLocalizedString(@"folders.sync.info", nil)
                                         rows:[NSArray arrayWithObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"folders.name", nil)
                                                                                                  value:_folder.title
                                                                                                    tap:^{
                                                                                                        [(ExteriaFolderEditController *)weak.target rename];
                                                                                                    }]]]];
    NSMutableArray *rules = [NSMutableArray array];
    NSArray *keys = [NSArray arrayWithObjects:@"folders.contacts", @"folders.noncontacts", @"folders.groups", @"folders.channels", @"folders.bots",
                                              @"folders.muted", @"folders.read", @"folders.archived", nil];
    if (!_folder.shared)
        for (NSUInteger i = 0; i < keys.count; ++i) {
            uint32_t mask = 1u << i;
            ExteriaSettingsRow *row = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString([keys objectAtIndex:i], nil)
                                                                    subtitle:nil
                                                                          on:(_folder.flags & mask) != 0
                                                                      toggle:^(BOOL on) {
                                                                          ExteriaFolderEditController *me = weak.target;
                                                                          if (!me || me->_saving)
                                                                              return;
                                                                          me->_folder.flags = on ? me->_folder.flags | mask : me->_folder.flags & ~mask;
                                                                      }];
            row.disabled = _saving;
            [rules addObject:row];
        }
    if (rules.count)
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"folders.rules", nil) footer:nil rows:rules]];
    NSMutableArray *choices = [NSMutableArray array];
    for (NSInteger kind = 0; kind < 3; ++kind) {
        if (_folder.shared && kind == 1)
            continue;
        NSData *data = kind == 0 ? _folder.included : (kind == 1 ? _folder.excluded : _folder.pinned);
        NSString *key = kind == 0 ? @"folders.include" : (kind == 1 ? @"folders.exclude" : @"folders.pinned");
        [choices addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(key, nil)
                                                      value:[NSString stringWithFormat:@"%lu", (unsigned long)(data.length / sizeof(exteria_peer_ref))]
                                                        tap:^{
                                                            [(ExteriaFolderEditController *)weak.target pick:kind];
                                                        }]];
    }
    if (!_dialogs)
        [choices addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(_loading ? @"folders.loading" : @"folders.retry", nil)
                                                      value:nil
                                                        tap:^{
                                                            [(ExteriaFolderEditController *)weak.target loadChats];
                                                        }]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"folders.priority", nil) rows:choices]];
    [sections
        addObject:[ExteriaSettingsSection
                      sectionWithHeader:nil
                                 footer:nil
                                   rows:[NSArray arrayWithObject:[ExteriaSettingsRow
                                                                     actionRowWithSymbol:ExteriaSymbolCheck
                                                                                   title:NSLocalizedString(_saving ? @"folders.saving" : @"folders.save", nil)
                                                                             destructive:NO
                                                                                     tap:^{
                                                                                         [(ExteriaFolderEditController *)weak.target save];
                                                                                     }]]]];
    self.sections = sections;
}
@end

#define HINT_STICKER 130.0
#define HINT_INSET 12.0

@interface ExteriaFoldersController () {
    ExteriaSession *_session;
    ExteriaWeakReference *_weak;
    BOOL _busy;
    NSArray *_suggested;
    /* the animated sticker over the list is made once and moved into each header that is built */
    ExteriaLottieView *_sticker;
    CGFloat _headerWidth;
}
@end

@implementation ExteriaFoldersController
- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (self) {
        _session = [session retain];
        _weak = [[ExteriaWeakReference referenceTo:self] retain];
        self.pageTitle = NSLocalizedString(@"folders.title", nil);
    }
    return self;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [_session release];
    [_suggested release];
    [_sticker release];
    [super dealloc];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rebuild) name:ExteriaChatFoldersDidChangeNotification object:_session];
    [self rebuild];
    [self refresh];
}
/* the sticker is loaded before the screen is on, so its first frame is drawn while the push still moves and the card is not empty until the animation parses */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_sticker setLoaded:YES];
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
    return [[[ExteriaFoldersController alloc] initWithSession:_session] autorelease];
}

/* the animated sticker over a line that says what folders are for, in a card like the one of the devices screen */
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
    CGFloat cardWidth = width - 2 * HINT_INSET;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 100)] autorelease];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UILabel *text = [[[UILabel alloc] init] autorelease];
    text.backgroundColor = [UIColor clearColor];
    text.textColor = ExteriaColorSecondary();
    text.font = ExteriaFontRegular(15);
    text.textAlignment = ExteriaTextAlignmentCenter;
    text.numberOfLines = 0;
    text.text = NSLocalizedString(@"folders.hint", nil);
    CGSize fit = [text sizeThatFits:CGSizeMake(cardWidth - 40, 400)];
    _sticker.frame = CGRectMake((cardWidth - HINT_STICKER) / 2, 12, HINT_STICKER, HINT_STICKER);
    text.frame = CGRectMake(20, CGRectGetMaxY(_sticker.frame) + 8, cardWidth - 40, ceil(fit.height));
    UIView *card = [[[UIView alloc] init] autorelease];
    card.backgroundColor = ExteriaColorCard();
    card.layer.cornerRadius = 22;
    card.frame = CGRectMake(HINT_INSET, 12, cardWidth, CGRectGetMaxY(text.frame) + 16);
    [card addSubview:_sticker];
    [card addSubview:text];
    [header addSubview:card];
    header.frame = CGRectMake(0, 0, width, CGRectGetMaxY(card.frame) + 8);
    self.headerView = header;
}
- (void)replaySticker {
    [_sticker rewind];
    [_sticker playOnce];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    /* the card is laid out for the width of the table, so a turn of the phone builds it again */
    if (fabs(self.table.bounds.size.width - _headerWidth) > 0.5) [self rebuildHeader];
}
- (void)refresh {
    if (_busy)
        return;
    _busy = YES;
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    [_session loadChatFoldersWithCompletion:^(NSArray *folders, NSString *errorName) {
        (void)folders;
        ExteriaFoldersController *me = weak.target;
        if (!me)
            return;
        me->_busy = NO;
        if (errorName)
            ExteriaShowNotice(nil, ExteriaGiftErrorText(errorName));
        [me rebuild];
    }];
    [_session loadSuggestedChatFoldersWithCompletion:^(NSArray *items, NSString *errorName) {
        ExteriaFoldersController *me = weak.target;
        if (!me)
            return;
        if (!items)
            NSLog(@"exteria: the recommended folders did not load: %@", errorName);
        [me->_suggested release];
        me->_suggested = [items retain];
        [me rebuild];
    }];
}
/* the lowest id the account has not used, from 2: the first is the list of all chats */
- (int32_t)freeIdentifierAmong:(NSArray *)folders {
    int32_t identifier = 2;
    for (; identifier <= EXTERIA_FOLDERS_MAX + 2; ++identifier) {
        BOOL taken = NO;
        for (ExteriaChatFolder *existing in folders)
            if (existing.folderId == identifier)
                taken = YES;
        if (!taken)
            break;
    }
    return identifier;
}
- (void)create {
    if (_busy)
        return;
    _busy = YES;
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    [_session loadChatFoldersWithCompletion:^(NSArray *folders, NSString *errorName) {
        ExteriaFoldersController *me = weak.target;
        if (!me)
            return;
        me->_busy = NO;
        [me rebuild];
        if (errorName) {
            ExteriaShowNotice(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        ExteriaChatFolder *folder = [[[ExteriaChatFolder alloc] init] autorelease];
        folder.folderId = [me freeIdentifierAmong:folders];
        folder.title = NSLocalizedString(@"folders.new", nil);
        [me.navigationController pushViewController:[[[ExteriaFolderEditController alloc] initWithSession:me->_session folder:folder] autorelease]
                                           animated:YES];
    }];
}
/* a recommended folder is saved as it came, under an id the account does not use */
- (void)addSuggested:(ExteriaSuggestedFolder *)suggestion {
    if (_busy)
        return;
    _busy = YES;
    [self rebuild];
    ExteriaChatFolder *folder = [[suggestion.folder copy] autorelease];
    folder.folderId = [self freeIdentifierAmong:_session.chatFolders];
    ExteriaWeakReference *weak = _weak;
    [_session saveChatFolder:folder completion:^(NSString *errorName) { [(ExteriaFoldersController *)weak.target finish:errorName]; }];
}
- (void)finish:(NSString *)errorName {
    _busy = NO;
    if (errorName)
        ExteriaShowNotice(nil, ExteriaGiftErrorText(errorName));
    [self rebuild];
}
- (void)choose:(ExteriaChatFolder *)folder {
    if (_busy)
        return;
    ExteriaWeakReference *weak = _weak;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"folders.edit", nil), NSLocalizedString(@"folders.up", nil),
                                                 NSLocalizedString(@"folders.down", nil), NSLocalizedString(@"folders.delete", nil), nil];
    ExteriaSettingsChoose(self, folder.title, options, ^(NSUInteger choice) {
        ExteriaFoldersController *me = weak.target;
        if (!me || me->_busy)
            return;
        if (choice == 0) {
            [me.navigationController pushViewController:[[[ExteriaFolderEditController alloc] initWithSession:me->_session folder:folder] autorelease]
                                               animated:YES];
            return;
        }
        if (choice == 3) {
            ExteriaConfirmAction(me, NSLocalizedString(@"folders.delete.info", nil), NSLocalizedString(@"folders.delete", nil), ^{
                ExteriaFoldersController *page = weak.target;
                if (!page || page->_busy)
                    return;
                page->_busy = YES;
                [page rebuild];
                [page->_session deleteChatFolder:folder.folderId
                                      completion:^(NSString *errorName) {
                                          [(ExteriaFoldersController *)weak.target finish:errorName];
                                      }];
            });
            return;
        }
        NSMutableArray *ordered = [NSMutableArray arrayWithArray:me->_session.chatFolders];
        NSUInteger index = [ordered indexOfObject:folder];
        if (index == NSNotFound)
            return;
        NSInteger to = (NSInteger)index + (choice == 1 ? -1 : 1);
        if (to < 0 || (NSUInteger)to >= ordered.count)
            return;
        [ordered exchangeObjectAtIndex:index withObjectAtIndex:(NSUInteger)to];
        me->_busy = YES;
        [me rebuild];
        [me->_session orderChatFolders:ordered
                            completion:^(NSString *errorName) {
                                [(ExteriaFoldersController *)weak.target finish:errorName];
                            }];
    });
}

/* what a folder holds, in the words: the kinds of chat it takes and how many chats are named, or that it is empty */
static NSString *ExteriaFolderSummary(ExteriaChatFolder *folder) {
    if (folder.shared)
        return NSLocalizedString(@"folders.shared", nil);
    static NSString *const keys[] = {@"folders.contacts", @"folders.noncontacts", @"folders.groups", @"folders.channels", @"folders.bots"};
    NSMutableArray *parts = [NSMutableArray array];
    for (NSUInteger i = 0; i < 5; ++i)
        if (folder.flags & (1u << i))
            [parts addObject:NSLocalizedString(keys[i], nil)];
    NSUInteger named = folder.included.length / sizeof(exteria_peer_ref);
    if (named)
        [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"folders.chats.count", nil), (unsigned long)named]];
    return parts.count ? [parts componentsJoinedByString:@", "] : NSLocalizedString(@"folders.nochats", nil);
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    if (!self.headerView) [self rebuildHeader];
    NSMutableArray *sections = [NSMutableArray array];
    NSArray *folders = _session.chatFolders;
    NSMutableArray *mine = [NSMutableArray array];
    for (ExteriaChatFolder *folder in folders)
        if (folder.folderId)
            [mine addObject:folder];
    /* the recommended folders show while the account has room, and the ones it already made are not offered again */
    if (_suggested.count && mine.count < 10) {
        NSMutableArray *offers = [NSMutableArray array];
        for (ExteriaSuggestedFolder *suggestion in _suggested) {
            BOOL have = NO;
            for (ExteriaChatFolder *folder in mine)
                if ([folder.title isEqualToString:suggestion.folder.title])
                    have = YES;
            if (have)
                continue;
            [offers addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsFolders
                                                           tone:ExteriaSettingsToneGreen
                                                          title:suggestion.folder.title
                                                       subtitle:suggestion.info.length ? suggestion.info : nil
                                                          value:NSLocalizedString(@"folders.add", nil)
                                                            tap:^{
                                                                [(ExteriaFoldersController *)weak.target addSuggested:suggestion];
                                                            }]];
        }
        if (offers.count)
            [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"folders.recommended", nil) footer:nil rows:offers]];
    }
    NSMutableArray *rows = [NSMutableArray array];
    for (ExteriaChatFolder *folder in mine) {
        [rows addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsFolders
                                                     tone:ExteriaSettingsToneBlue
                                                    title:folder.title
                                                 subtitle:ExteriaFolderSummary(folder)
                                                    value:nil
                                                      tap:^{
                                                          [(ExteriaFoldersController *)weak.target choose:folder];
                                                      }]];
    }
    if (mine.count < EXTERIA_FOLDERS_MAX)
        [rows addObject:[ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolPlusCircle
                                                          title:NSLocalizedString(@"folders.create", nil)
                                                    destructive:NO
                                                            tap:^{
                                                                [(ExteriaFoldersController *)weak.target create];
                                                            }]];
    NSString *footer = _busy ? NSLocalizedString(@"folders.loading", nil) : NSLocalizedString(@"folders.sync.info", nil);
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:mine.count ? NSLocalizedString(@"folders.list", nil) : nil footer:footer rows:rows]];
    self.sections = sections;
    [self reloadSettings];
}
@end
