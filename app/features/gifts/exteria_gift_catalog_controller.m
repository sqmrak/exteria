#import "exteria_gift_catalog_controller.h"

#import "exteria_gift_compose_controller.h"
#import "exteria_gift_grid_view.h"
#import "exteria_gift_tiles.h"
#import "exteria_star_gift.h"
#import "exteria_theme.h"

@interface ExteriaGiftCatalogController () <ExteriaGiftGridDelegate> {
    ExteriaDialog *_dialog;
    ExteriaGiftGridView *_grid;
    UIActivityIndicatorView *_spinner;
    UILabel *_status;
    UIButton *_retry;
    UIImageView *_balance;
    NSArray *_gifts;
    BOOL _loading;
    void (^_sentHandler)(void);
}
@end

@implementation ExteriaGiftCatalogController

@synthesize sentHandler = _sentHandler;

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _dialog = [dialog retain];
    self.screenTitle = NSLocalizedString(@"gifts.catalog", nil);
    return self;
}

- (void)dealloc {
    _grid.delegate = nil;
    [_dialog release];
    [_grid release];
    [_spinner release];
    [_status release];
    [_retry release];
    [_balance release];
    [_gifts release];
    [_sentHandler release];
    [super dealloc];
}

- (void)buildBodyInView:(UIView *)root {
    _grid = [[ExteriaGiftGridView alloc] initWithMedia:self.media];
    _grid.delegate = self;
    [root addSubview:_grid];
    _balance = [[UIImageView alloc] init];
    _balance.contentMode = UIViewContentModeCenter;
    _balance.autoresizingMask = UIViewAutoresizingFlexibleWidth;
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
    [_retry addTarget:self action:@selector(load) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES;
    [root addSubview:_retry];
}

- (void)layoutBody:(CGRect)body {
    _grid.frame = body;
    _spinner.center = CGPointMake(CGRectGetMidX(body), CGRectGetMidY(body));
    _status.frame = CGRectMake(body.origin.x + 24, CGRectGetMidY(body) - 40, body.size.width - 48, 60);
    _retry.frame = CGRectMake(CGRectGetMidX(body) - 70, CGRectGetMidY(body) + 24, 140, 40);
    _balance.frame = CGRectMake(0, 0, body.size.width, 28);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self load];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadBalance];
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

- (void)load {
    if (_loading) return;
    _loading = YES;
    _retry.hidden = YES;
    _status.text = @"";
    if (!_gifts) [_spinner startAnimating];
    [self retain];
    [self.session loadGiftCatalog:^(NSArray *gifts, NSString *errorName) {
        [self autorelease];
        _loading = NO;
        [_spinner stopAnimating];
        if (!gifts) {
            if (_gifts) return;
            _status.text = [errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                  : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName ? errorName : @"?"];
            _retry.hidden = NO;
            return;
        }
        [_gifts release];
        _gifts = [gifts retain];
        _status.text = gifts.count ? @"" : NSLocalizedString(@"gifts.catalog.empty", nil);
        NSMutableArray *tiles = [NSMutableArray arrayWithCapacity:gifts.count];
        for (ExteriaStarGift *gift in gifts) [tiles addObject:ExteriaTileForCatalogGift(gift)];
        [_grid setTiles:tiles];
    }];
}

- (void)giftGrid:(ExteriaGiftGridView *)grid didSelectIndex:(NSUInteger)index {
    (void)grid;
    if (index >= _gifts.count) return;
    ExteriaStarGift *gift = [_gifts objectAtIndex:index];
    if (!gift.canBuy) {
        ExteriaGiftAlert(nil, NSLocalizedString(gift.auction ? @"gifts.auction" : @"gifts.soldout.notice", nil));
        return;
    }
    ExteriaGiftComposeController *compose = [[[ExteriaGiftComposeController alloc] initWithSession:self.session dialog:_dialog gift:gift
                                                                                           avatars:self.avatars media:self.media] autorelease];
    compose.sentHandler = ^{
        if (_sentHandler) _sentHandler();
        /* back to the screen that opened the catalog, past the form and the catalog */
        NSArray *stack = self.navigationController.viewControllers;
        NSUInteger at = [stack indexOfObject:self];
        if (at != NSNotFound && at > 0) [self.navigationController popToViewController:[stack objectAtIndex:at - 1] animated:YES];
    };
    [self.navigationController pushViewController:compose animated:YES];
}

@end
