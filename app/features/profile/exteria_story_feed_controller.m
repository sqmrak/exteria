#import "exteria_story_feed_controller.h"

#import "exteria_gift_grid_view.h"
#import "exteria_story_viewer_controller.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

@interface ExteriaStoryFeedController () <ExteriaGiftGridDelegate> {
    ExteriaProfileFeed *_feed;
    ExteriaDialog *_owner;
    ExteriaGiftGridView *_grid;
    UILabel *_status;
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaStoryFeedController

- (id)initWithSession:(ExteriaSession *)session kind:(ExteriaProfileFeedKind)kind owner:(ExteriaDialog *)owner avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _owner = [owner retain];
    _feed = [[ExteriaProfileFeed alloc] initWithSession:session kind:kind owner:owner];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.screenTitle = NSLocalizedString(kind == ExteriaFeedPinnedStories ? @"profile.tab.stories" : @"profile.tab.archive", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    _grid.delegate = nil;
    [_feed release];
    [_owner release];
    [_grid release];
    [_status release];
    [super dealloc];
}

- (void)buildBodyInView:(UIView *)root {
    _grid = [[ExteriaGiftGridView alloc] initWithMedia:self.media];
    _grid.delegate = self;
    [root addSubview:_grid];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = ExteriaColorSecondary();
    _status.textAlignment = ExteriaTextAlignmentCenter;
    _status.numberOfLines = 0;
    [root addSubview:_status];
}

- (void)layoutBody:(CGRect)body {
    _grid.frame = body;
    _status.frame = CGRectMake(body.origin.x + 24, CGRectGetMidY(body) - 40, body.size.width - 48, 80);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self showState];
    [self reload];
}

- (void)reload {
    ExteriaWeakReference *me = _weak;
    [_feed reload:^{ [(ExteriaStoryFeedController *)me.target changed]; }];
}

- (void)changed {
    [_grid setTiles:_feed.tiles];
    [self showState];
}

- (void)showState {
    NSString *text = @"";
    if (!_feed.loaded) text = _feed.errorName ? [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), _feed.errorName] : NSLocalizedString(@"profile.loading", nil);
    else if (!_feed.items.count) text = NSLocalizedString(_feed.kind == ExteriaFeedPinnedStories ? @"profile.stories.empty" : @"profile.archive.empty", nil);
    _status.text = text;
}

- (void)giftGridReachedEnd:(ExteriaGiftGridView *)grid {
    (void)grid;
    ExteriaWeakReference *me = _weak;
    [_feed loadMore:^{ [(ExteriaStoryFeedController *)me.target changed]; }];
}

- (void)giftGrid:(ExteriaGiftGridView *)grid didSelectIndex:(NSUInteger)index {
    (void)grid;
    if (index >= _feed.items.count) return;
    ExteriaStoryViewerController *viewer = [[[ExteriaStoryViewerController alloc] initWithSession:self.session owner:_owner stories:_feed.items index:index
                                                                                          avatars:self.avatars media:self.media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

@end
