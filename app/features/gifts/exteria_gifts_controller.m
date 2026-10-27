#import "exteria_gifts_controller.h"

#import "exteria_gift_catalog_controller.h"
#import "exteria_gift_detail_controller.h"
#import "exteria_gift_folder_bar.h"
#import "exteria_gift_grid_view.h"
#import "exteria_gift_tiles.h"
#import "exteria_person.h"
#import "exteria_star_gift.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

@interface ExteriaGiftsController () <ExteriaGiftGridDelegate, ExteriaGiftFolderBarDelegate> {
    ExteriaGiftFolderBar *_folderBar;
    int32_t _folderId;
    ExteriaDialog *_dialog;
    BOOL _mine;
    ExteriaGiftGridView *_grid;
    UIActivityIndicatorView *_spinner;
    UILabel *_status;
    UIButton *_retry;
    UIImageView *_balance;
    NSMutableArray *_gifts;
    NSString *_nextOffset;
    BOOL _loading;
    BOOL _loaded;
    NSUInteger _generation;
    NSString *_ownerName;
    ExteriaStickerLibrary *_stickers;
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaGiftsController

@synthesize stickers = _stickers;

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog mine:(BOOL)mine avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _dialog = [dialog retain];
    _mine = mine;
    _gifts = [[NSMutableArray alloc] init];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.screenTitle = NSLocalizedString(@"gifts.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    _grid.delegate = nil;
    _folderBar.delegate = nil;
    [_folderBar release];
    [_dialog release];
    [_grid release];
    [_spinner release];
    [_status release];
    [_retry release];
    [_balance release];
    [_gifts release];
    [_nextOffset release];
    [_ownerName release];
    [_stickers release];
    [super dealloc];
}

- (void)buildBodyInView:(UIView *)root {
    _grid = [[ExteriaGiftGridView alloc] initWithMedia:self.media];
    _grid.avatars = self.avatars;
    _grid.delegate = self;
    [root addSubview:_grid];
    _folderBar = [[ExteriaGiftFolderBar alloc] initWithSession:self.session dialog:_dialog mine:_mine];
    _folderBar.delegate = self;
    [root addSubview:_folderBar];
    /* the saved messages dialog is titled by its own name, so the owner of a gift on it comes from the account */
    if (_dialog.saved) {
        [self retain];
        [self.session loadSelf:^(NSArray *people, NSString *errorName) {
            [self autorelease];
            if (people.count) _ownerName = [[(ExteriaPerson *)[people objectAtIndex:0] name] copy];
            else NSLog(@"exteria: own name for the gift owner not loaded: %@", errorName);
        }];
    }
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:ExteriaThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [root addSubview:_spinner];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = ExteriaColorSecondary();
    _status.textAlignment = ExteriaTextAlignmentCenter;
    _status.numberOfLines = 0;
    [root addSubview:_status];
    _retry = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_retry setTitle:NSLocalizedString(@"list.retry", nil) forState:UIControlStateNormal];
    [_retry setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(reloadFromStart) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES;
    [root addSubview:_retry];
    if (_mine) {
        _balance = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 320, 30)];
        _balance.contentMode = UIViewContentModeCenter;
        _balance.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    }
    /* a gift can go to a person, not to a bot, a group or the chat with oneself */
    if (!_mine && _dialog.kind == EXTERIA_DIALOG_USER && !_dialog.saved) {
        /* the screen owns this block, so it must not hold the screen */
        ExteriaWeakReference *me = [ExteriaWeakReference referenceTo:self];
        [self setActionTitle:NSLocalizedString(@"gifts.send", nil) handler:^{ [(ExteriaGiftsController *)me.target openCatalog]; }];
    }
}

- (void)layoutBody:(CGRect)body {
    CGFloat folders = [_folderBar height];
    _folderBar.frame = CGRectMake(body.origin.x, body.origin.y, body.size.width, folders);
    body.origin.y += folders;
    body.size.height -= folders;
    _grid.frame = body;
    _spinner.center = CGPointMake(CGRectGetMidX(body), CGRectGetMidY(body));
    _status.frame = CGRectMake(body.origin.x + 24, CGRectGetMidY(body) - 40, body.size.width - 48, 60);
    _retry.frame = CGRectMake(CGRectGetMidX(body) - 70, CGRectGetMidY(body) + 24, 140, 40);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [_folderBar reload];
    [self reloadFromStart];
    if (_mine) [self loadBalance];
}

- (void)loadBalance {
    [self retain];
    [self.session loadStarsBalance:^(long long stars, NSString *errorName) {
        [self autorelease];
        if (errorName) {
            NSLog(@"exteria: star balance not loaded: %@", errorName);
            return;
        }
        _balance.image = ExteriaStarsImage(NSLocalizedString(@"gifts.balance", nil), stars, ExteriaFontRegular(14), ExteriaColorSecondary());
        _grid.headerView = _balance;
    }];
}

- (void)openCatalog {
    ExteriaGiftCatalogController *catalog = [[[ExteriaGiftCatalogController alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars
                                                                                              media:self.media] autorelease];
    catalog.sentHandler = ^{ [self reloadFromStart]; };
    [self.navigationController pushViewController:catalog animated:YES];
}

#pragma mark loading

- (void)reloadFromStart {
    ++_generation;
    _loading = NO;
    [_nextOffset release];
    _nextOffset = nil;
    [self loadPage];
}

- (void)loadPage {
    if (_loading) return;
    _loading = YES;
    BOOL first = _nextOffset == nil;
    NSString *offset = _nextOffset;
    NSUInteger generation = _generation;
    _retry.hidden = YES;
    if (first && !_loaded) [_spinner startAnimating];
    [self retain];
    [self.session loadSavedGiftsOfDialog:_dialog folder:_folderId offset:offset completion:^(NSArray *gifts, NSInteger total, NSString *next, NSString *errorName) {
        [self autorelease];
        if (generation != _generation) return;
        _loading = NO;
        [_spinner stopAnimating];
        if (!gifts) {
            if (_loaded) {
                NSLog(@"exteria: more gifts not loaded: %@", errorName);
                return;
            }
            _status.text = ExteriaGiftErrorText(errorName);
            _retry.hidden = NO;
            return;
        }
        if (first) [_gifts removeAllObjects];
        [_gifts addObjectsFromArray:gifts];
        [_nextOffset release];
        _nextOffset = [next copy];
        _loaded = YES;
        _status.text = _gifts.count ? @"" : NSLocalizedString(_mine ? @"gifts.mine.empty" : @"gifts.empty", nil);
        [self showTiles];
    }];
}

- (void)showTiles {
    NSMutableArray *tiles = [NSMutableArray arrayWithCapacity:_gifts.count];
    for (ExteriaSavedGift *saved in _gifts) [tiles addObject:ExteriaTileForSavedGift(saved, _mine)];
    [_grid setTiles:tiles];
}

- (void)giftFolderBar:(ExteriaGiftFolderBar *)bar didSelectFolder:(ExteriaGiftFolder *)folder {
    _folderId = folder.folderId;
    [self reloadFromStart];
}

- (void)giftFolderBarDidChange:(ExteriaGiftFolderBar *)bar selectionChanged:(BOOL)selectionChanged {
    if (selectionChanged) {
        _folderId = bar.selectedFolder.folderId;
        [self reloadFromStart];
    }
    [self.view setNeedsLayout];
}

- (void)giftGridReachedEnd:(ExteriaGiftGridView *)grid {
    (void)grid;
    if (_nextOffset && !_loading) [self loadPage];
}

- (void)giftGrid:(ExteriaGiftGridView *)grid didSelectIndex:(NSUInteger)index {
    (void)grid;
    if (index >= _gifts.count) return;
    ExteriaGiftDetailController *detail = [[[ExteriaGiftDetailController alloc] initWithSession:self.session gift:[_gifts objectAtIndex:index] mine:_mine
                                                                                        avatars:self.avatars media:self.media] autorelease];
    detail.ownerName = _dialog.saved ? _ownerName : _dialog.title;
    detail.stickers = _stickers;
    if (_mine) detail.folderDialog = _dialog;
    ExteriaWeakReference *weak = _weak;
    detail.changedHandler = ^{
        ExteriaGiftsController *controller = weak.target;
        if (!controller) return;
        [controller reloadFromStart];
        [controller->_folderBar reload];
        if (controller->_mine) [controller loadBalance];
    };
    [detail showInViewController:self];
}

@end
