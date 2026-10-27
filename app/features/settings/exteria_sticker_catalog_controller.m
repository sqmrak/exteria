#import "exteria_sticker_catalog_controller.h"

#import "exteria_gift_screen.h"
#import "exteria_session_stickermanage.h"
#import "exteria_sheet.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define ARCHIVE_PAGE 100

@interface ExteriaStickerCatalogController () {
    ExteriaSession *_session;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    ExteriaStickerCatalogKind _kind;
    NSArray *_sets;
    BOOL _loaded;
    BOOL _busy;
    /* the cover of each set by id: the picture once the cache has it, and the ones already asked for */
    NSMutableDictionary *_covers;
    NSMutableSet *_asked;
}
@end

@implementation ExteriaStickerCatalogController

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media kind:(ExteriaStickerCatalogKind)kind {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _media = [media retain];
    _kind = kind;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _covers = [[NSMutableDictionary alloc] init];
    _asked = [[NSMutableSet alloc] init];
    NSString *keys[] = {@"stickers.featured", @"stickers.archived", @"stickers.emoji"};
    self.pageTitle = NSLocalizedString(keys[kind], nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_media release];
    [_sets release];
    [_covers release];
    [_asked release];
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
    return [[[ExteriaStickerCatalogController alloc] initWithSession:_session media:_media kind:_kind] autorelease];
}

- (void)load {
    ExteriaWeakReference *weak = _weak;
    void (^got)(NSArray *, NSString *) = ^(NSArray *sets, NSString *errorName) {
        ExteriaStickerCatalogController *me = weak.target;
        if (!me) return;
        if (!sets) NSLog(@"exteria: the sticker sets did not load: %@", errorName);
        [me->_sets release];
        me->_sets = [sets retain];
        me->_loaded = YES;
        [me rebuild];
    };
    switch (_kind) {
    case ExteriaStickerCatalogFeatured:
        [_session loadFeaturedStickerSets:got];
        break;
    case ExteriaStickerCatalogArchived:
        [_session loadArchivedStickerSetsLimit:ARCHIVE_PAGE completion:^(NSArray *sets, int32_t total, NSString *errorName) {
            (void)total;
            got(sets, errorName);
        }];
        break;
    case ExteriaStickerCatalogEmoji:
        [_session loadEmojiSets:got];
        break;
    }
}

/* the cover comes from the cache and takes the place of the symbol, and the page is built again */
- (UIImage *)coverOfSet:(ExteriaStickerSet *)set {
    NSNumber *key = [NSNumber numberWithLongLong:set.setId];
    UIImage *image = [_covers objectForKey:key];
    if (image || !_media || [_asked containsObject:key]) return image;
    ExteriaRemoteFile *file = set.coverFile;
    if (!file) return nil;
    [_asked addObject:key];
    ExteriaWeakReference *weak = _weak;
    [_media loadImageForFile:file maxSide:96 completion:^(UIImage *loaded) {
        ExteriaStickerCatalogController *me = weak.target;
        if (!me || !loaded) return;
        [me->_covers setObject:loaded forKey:key];
        [me rebuild];
    }];
    return nil;
}

- (void)finishWithError:(NSString *)errorName {
    _busy = NO;
    if (errorName) {
        ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
        return;
    }
    /* the server has the new lists, and the page shows what it says */
    [self load];
}

- (void)install:(ExteriaStickerSet *)set {
    if (_busy) return;
    _busy = YES;
    ExteriaWeakReference *weak = _weak;
    [_session installStickerSet:set completion:^(NSString *errorName) { [(ExteriaStickerCatalogController *)weak.target finishWithError:errorName]; }];
}

- (void)uninstall:(ExteriaStickerSet *)set {
    if (_busy) return;
    _busy = YES;
    ExteriaWeakReference *weak = _weak;
    [_session uninstallStickerSet:set completion:^(NSString *errorName) { [(ExteriaStickerCatalogController *)weak.target finishWithError:errorName]; }];
}

- (void)tapSet:(ExteriaStickerSet *)set {
    ExteriaWeakReference *weak = _weak;
    switch (_kind) {
    case ExteriaStickerCatalogFeatured:
        if (!set.row.installed) [self install:set];
        else ExteriaConfirmAction(self, [NSString stringWithFormat:NSLocalizedString(@"chatset.stickers.remove.confirm", nil), set.title], NSLocalizedString(@"chatset.stickers.remove", nil),
                                  ^{ [(ExteriaStickerCatalogController *)weak.target uninstall:set]; });
        break;
    case ExteriaStickerCatalogArchived:
        [ExteriaSheet presentInView:self.view title:set.title message:nil options:[NSArray arrayWithObject:NSLocalizedString(@"stickers.restore", nil)] destructive:nil
                        cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
            (void)index;
            [(ExteriaStickerCatalogController *)weak.target install:set];
        }];
        break;
    case ExteriaStickerCatalogEmoji:
        ExteriaConfirmAction(self, [NSString stringWithFormat:NSLocalizedString(@"chatset.stickers.remove.confirm", nil), set.title], NSLocalizedString(@"chatset.stickers.remove", nil),
                             ^{ [(ExteriaStickerCatalogController *)weak.target uninstall:set]; });
        break;
    }
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    for (ExteriaStickerSet *set in _sets) {
        NSString *count = [NSString stringWithFormat:NSLocalizedString(@"chatset.stickers.count", nil), (long)set.row.count];
        void (^tap)(void) = ^{ [(ExteriaStickerCatalogController *)weak.target tapSet:set]; };
        UIImage *cover = [self coverOfSet:set];
        ExteriaSettingsRow *row = cover ? [ExteriaSettingsRow rowWithTileImage:cover title:set.title subtitle:count tap:tap]
                                        : [ExteriaSettingsRow rowWithSymbol:_kind == ExteriaStickerCatalogEmoji ? ExteriaSymbolSmiley : ExteriaSymbolSticker tone:ExteriaSettingsToneOrangeDeep
                                                                      title:set.title subtitle:count value:nil tap:tap];
        /* a trending set the account has is ticked; the others add on a tap */
        if (_kind == ExteriaStickerCatalogFeatured && set.row.installed) row.trailingImage = ExteriaSymbolImage(ExteriaSymbolCheck, 22, ExteriaColorAccent());
        [rows addObject:row];
    }
    NSString *empty[] = {@"stickers.empty.featured", @"stickers.empty.archived", @"stickers.empty.emoji"};
    NSString *footer = !_loaded ? NSLocalizedString(@"chatset.stickers.loading", nil)
                     : (_sets ? (_sets.count ? NSLocalizedString(@"stickers.info.catalog", nil) : NSLocalizedString(empty[_kind], nil))
                              : NSLocalizedString(@"chatset.stickers.failed", nil));
    self.sections = [NSArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
    [self reloadSettings];
}

@end
