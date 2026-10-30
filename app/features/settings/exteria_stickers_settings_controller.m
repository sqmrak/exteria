#import "exteria_stickers_settings_controller.h"

#import "exteria_chat_settings.h"
#import "exteria_custom_emoji.h"
#import "exteria_gift_screen.h"
#import "exteria_session_stickermanage.h"
#import "exteria_sheet.h"
#import "exteria_quick_reaction_controller.h"
#import "exteria_sticker_catalog_controller.h"
#import "exteria_sticker_maker.h"
#import "exteria_symbol.h"
#import "exteria_weak_reference.h"
#include "exteria_reactions.h"

@interface ExteriaStickersSettingsController () {
    ExteriaSession *_session;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    NSArray *_sets;
    NSArray *_archived;
    NSArray *_emoji;
    NSArray *_featured;
    int32_t _archivedTotal;
    BOOL _loaded;
    BOOL _busy;
}
@end

@implementation ExteriaStickersSettingsController

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"chatset.stickers", nil);
    return self;
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaStickersSettingsController alloc] initWithSession:_session media:_media] autorelease];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaCustomEmojiDidLoadNotification object:nil];
    [_weak clear];
    [_weak release];
    [_session release];
    [_media release];
    [_sets release];
    [_archived release];
    [_emoji release];
    [_featured release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(quickReactionPictureLoaded:) name:ExteriaCustomEmojiDidLoadNotification object:nil];
    [self rebuild];
    [self load];
}

- (void)quickReactionPictureLoaded:(NSNotification *)notification {
    if ([notification.object longLongValue] == exteria_quick_reaction_document(ExteriaChatQuickReaction().UTF8String)) [self rebuild];
}

/* a page opened from here may have changed what is counted, so coming back asks again */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    ExteriaLoadQuickReactionPicture(_session, _media, nil);
    if (_loaded) { [self rebuild]; [self load]; }
}

- (void)load {
    ExteriaWeakReference *weak = _weak;
    [_session loadStickerSets:^(NSArray *sets, NSString *errorName) {
        ExteriaStickersSettingsController *me = weak.target;
        if (!me) return;
        if (!sets) NSLog(@"exteria: the sticker sets did not load: %@", errorName);
        [me->_sets release];
        me->_sets = [sets retain];
        me->_loaded = YES;
        [me rebuild];
    }];
    /* the counts of the rows above the list: how many the archive and the emoji sets hold, and whether the trending ones show */
    [_session loadArchivedStickerSetsLimit:1 completion:^(NSArray *sets, int32_t total, NSString *errorName) {
        ExteriaStickersSettingsController *me = weak.target;
        if (!me) return;
        if (!sets) NSLog(@"exteria: the archive did not load: %@", errorName);
        [me->_archived release];
        me->_archived = [sets retain];
        me->_archivedTotal = total;
        [me rebuild];
    }];
    [_session loadEmojiSets:^(NSArray *sets, NSString *errorName) {
        ExteriaStickersSettingsController *me = weak.target;
        if (!me) return;
        if (!sets) NSLog(@"exteria: the emoji sets did not load: %@", errorName);
        [me->_emoji release];
        me->_emoji = [sets retain];
        [me rebuild];
    }];
    [_session loadFeaturedStickerSets:^(NSArray *sets, NSString *errorName) {
        ExteriaStickersSettingsController *me = weak.target;
        if (!me) return;
        if (!sets) NSLog(@"exteria: the trending sets did not load: %@", errorName);
        [me->_featured release];
        me->_featured = [sets retain];
        [me rebuild];
    }];
}

- (void)openCatalog:(ExteriaStickerCatalogKind)kind {
    [self.navigationController pushViewController:[[[ExteriaStickerCatalogController alloc] initWithSession:_session media:_media kind:kind] autorelease] animated:YES];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    ExteriaSettingsRow *featured = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolStars tone:ExteriaSettingsToneOrange title:NSLocalizedString(@"stickers.featured", nil) subtitle:nil
                                                               value:_featured.count ? [NSString stringWithFormat:@"%lu", (unsigned long)_featured.count] : nil
                                                                 tap:^{ [(ExteriaStickersSettingsController *)weak.target openCatalog:ExteriaStickerCatalogFeatured]; }];
    ExteriaSettingsRow *archived = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolArchive tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"stickers.archived", nil) subtitle:nil
                                                               value:[NSString stringWithFormat:@"%d", (int)_archivedTotal]
                                                                 tap:^{ [(ExteriaStickersSettingsController *)weak.target openCatalog:ExteriaStickerCatalogArchived]; }];
    ExteriaSettingsRow *emoji = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSmiley tone:ExteriaSettingsToneBlueDeep title:NSLocalizedString(@"stickers.emoji", nil) subtitle:nil
                                                            value:_emoji.count ? [NSString stringWithFormat:@"%lu", (unsigned long)_emoji.count] : nil
                                                              tap:^{ [(ExteriaStickersSettingsController *)weak.target openCatalog:ExteriaStickerCatalogEmoji]; }];
    NSMutableArray *catalog = [NSMutableArray arrayWithObject:featured];
    /* an archive with nothing in it is not offered */
    if (_archivedTotal > 0) [catalog addObject:archived];
    [catalog addObject:emoji];
    ExteriaSettingsRow *quick = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolHeart tone:ExteriaSettingsTonePurple title:NSLocalizedString(@"chatset.quickreaction", nil) subtitle:nil value:ExteriaChatQuickReactionDisplay() tap:^{
        ExteriaStickersSettingsController *me = weak.target;
        if (me) [me.navigationController pushViewController:[[[ExteriaQuickReactionController alloc] initWithSession:me->_session] autorelease] animated:YES];
    }];
    quick.valueIsEmoji = YES;
    quick.valueEmojiDocument = exteria_quick_reaction_document(ExteriaChatQuickReaction().UTF8String);
    [catalog addObject:quick];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:catalog]];
    ExteriaSettingsRow *large = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.largeemoji", nil) subtitle:NSLocalizedString(@"chatset.largeemoji.info", nil)
                                                                    on:ExteriaChatLargeEmoji() toggle:^(BOOL on) { ExteriaChatSetLargeEmoji(on); }];
    ExteriaSettingsRow *order = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.dynamicorder", nil) subtitle:nil
                                                                    on:ExteriaChatDynamicPackOrder() toggle:^(BOOL on) { ExteriaChatSetDynamicPackOrder(on); }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.stickers.settings", nil) footer:NSLocalizedString(@"chatset.dynamicorder.info", nil)
                                                             rows:[NSArray arrayWithObjects:large, order, nil]]];

    ExteriaSettingsRow *make = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolPlusCircle tone:ExteriaSettingsToneGreen title:NSLocalizedString(@"sticker.make.row", nil)
                                                        subtitle:NSLocalizedString(@"sticker.make.row.info", nil) value:nil tap:^{
        ExteriaStickersSettingsController *me = weak.target;
        if (!me) return;
        [ExteriaStickerMaker startWithSession:me->_session host:me done:^(NSString *shortName) {
            (void)shortName;
            [(ExteriaStickersSettingsController *)weak.target load];
        }];
    }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:make]]];

    NSMutableArray *rows = [NSMutableArray array];
    for (ExteriaStickerSet *set in _sets) {
        [rows addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSticker tone:ExteriaSettingsToneOrangeDeep title:set.title
                                                 subtitle:[NSString stringWithFormat:NSLocalizedString(@"chatset.stickers.count", nil), (long)set.row.count] value:nil tap:^{
            [(ExteriaStickersSettingsController *)weak.target showActionsOfSet:set];
        }]];
    }
    NSString *footer = !_loaded ? NSLocalizedString(@"chatset.stickers.loading", nil)
                     : (_sets ? (_sets.count ? NSLocalizedString(@"chatset.stickers.info", nil) : NSLocalizedString(@"chatset.stickers.none", nil))
                              : NSLocalizedString(@"chatset.stickers.failed", nil));
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.stickers.header", nil) footer:footer rows:rows]];
    self.sections = sections;
    [self reloadSettings];
}

- (void)showActionsOfSet:(ExteriaStickerSet *)set {
    if (_busy) return;
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *options = [NSMutableArray array];
    BOOL first = _sets.count && [_sets objectAtIndex:0] == set;
    if (!first) [options addObject:NSLocalizedString(@"chatset.stickers.first", nil)];
    [options addObject:NSLocalizedString(@"chatset.stickers.remove", nil)];
    ExteriaSettingsChoose(self, set.title, options, ^(NSUInteger index) {
        ExteriaStickersSettingsController *me = weak.target;
        if (!me) return;
        BOOL removes = index == options.count - 1;
        if (removes) {
            ExteriaConfirmAction(me, [NSString stringWithFormat:NSLocalizedString(@"chatset.stickers.remove.confirm", nil), set.title], NSLocalizedString(@"chatset.stickers.remove", nil), ^{
                [(ExteriaStickersSettingsController *)weak.target removeSet:set];
            });
        } else {
            [me moveSetToTop:set];
        }
    });
}

- (void)finishWithError:(NSString *)errorName {
    _busy = NO;
    if (errorName) {
        ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
        return;
    }
    /* the server has the new list, and the screen shows what it says */
    [self load];
}

- (void)moveSetToTop:(ExteriaStickerSet *)set {
    _busy = YES;
    ExteriaWeakReference *weak = _weak;
    [_session moveStickerSetToTop:set among:_sets completion:^(NSString *errorName) { [(ExteriaStickersSettingsController *)weak.target finishWithError:errorName]; }];
}

- (void)removeSet:(ExteriaStickerSet *)set {
    _busy = YES;
    ExteriaWeakReference *weak = _weak;
    [_session uninstallStickerSet:set completion:^(NSString *errorName) { [(ExteriaStickersSettingsController *)weak.target finishWithError:errorName]; }];
}

@end
