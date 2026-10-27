#import "exteria_classic_topics_controller.h"

#import "exteria_chat_controller.h"
#import "exteria_classic_chrome.h"
#import "exteria_classic_dialog_cell.h"
#import "exteria_custom_emoji_loader.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

@interface ExteriaClassicTopicsController () {
    ExteriaSession *_session;
    ExteriaDialog *_forum;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    ExteriaWeakReference *_weak;
    NSArray *_topics;
    UILabel *_status;
    BOOL _loading;
    BOOL _loaded;
    void (^_closeHandler)(void);
}
@end

@implementation ExteriaClassicTopicsController

@synthesize closeHandler = _closeHandler;

- (id)initWithSession:(ExteriaSession *)session forum:(ExteriaDialog *)forum avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers {
    self = [super initWithStyle:UITableViewStylePlain];
    if (!self) return nil;
    _session = [session retain];
    _forum = [forum retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _topics = [[NSArray alloc] init];
    NSString *heading = forum.saved ? NSLocalizedString(@"chat.saved.dialogs", nil) : forum.title;
    self.title = heading;
    /* the bar title is a user's own text, so the emoji in it come from the app's pictures */
    self.navigationItem.titleView = ExteriaClassicTitleView(heading, nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    if ([self isViewLoaded]) {
        self.tableView.delegate = nil;
        self.tableView.dataSource = nil;
    }
    [_session release];
    [_forum release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_topics release];
    [_status release];
    [_closeHandler release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UITableView *table = self.tableView;
    ExteriaClassicStyleTable(table);
    table.rowHeight = [ExteriaClassicDialogCell rowHeight];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = [UIColor grayColor];
    _status.textAlignment = ExteriaTextAlignmentCenter;
    _status.numberOfLines = 0;
    _status.font = [UIFont systemFontOfSize:16];
    _status.frame = table.backgroundView.bounds;
    _status.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [table.backgroundView addSubview:_status];
    [self reload];
}

- (void)reload {
    if (_loading) return;
    _loading = YES;
    [self retain];
    /* the favorites list the chats their messages came from, in the place of topics */
    void (^arrived)(NSArray *, NSString *) = ^(NSArray *items, NSString *errorName) {
        [self autorelease];
        _loading = NO;
        if (!items) {
            /* topics already on screen stay; only an empty screen shows the failure */
            if (!_loaded) {
                _status.text = [errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                       : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName ? errorName : @"?"];
            } else {
                NSLog(@"exteria: refresh of the topics failed: %@", errorName);
            }
            return;
        }
        _loaded = YES;
        [_topics release];
        _topics = [items copy];
        _status.text = _topics.count ? @"" : NSLocalizedString(_forum.saved ? @"chat.saved.empty" : @"topics.empty", nil);
        self.tableView.separatorStyle = _topics.count ? UITableViewCellSeparatorStyleSingleLine : UITableViewCellSeparatorStyleNone;
        [self.tableView reloadData];
        [self loadIcons];
    };
    if (_forum.saved) [_session loadSavedDialogs:arrived];
    else [_session loadTopicsOfDialog:_forum completion:arrived];
}

/* the rows draw the hash until the emoji picture is in memory, then they are configured again */
- (void)loadIcons {
    NSMutableArray *icons = [NSMutableArray array];
    for (ExteriaDialog *topic in _topics) {
        if (topic.topicIconEmoji) [icons addObject:[NSNumber numberWithLongLong:topic.topicIconEmoji]];
    }
    if (!icons.count) return;
    ExteriaWeakReference *weak = _weak;
    [ExteriaCustomEmojiLoader loadDocuments:icons session:_session media:_media documents:nil picture:^{
        ExteriaClassicTopicsController *topics = weak.target;
        if (topics) [topics.tableView reloadData];
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if ([self isMovingFromParentViewController] && _closeHandler) _closeHandler();
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_topics.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"topic";
    ExteriaClassicDialogCell *cell = (ExteriaClassicDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaClassicDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    [cell configureWithDialog:[_topics objectAtIndex:(NSUInteger)indexPath.row] avatars:_avatars];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ExteriaDialog *row = [_topics objectAtIndex:(NSUInteger)indexPath.row];
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:_session dialog:_forum.saved ? [_forum savedDialogFromSource:row] : row
                                                                          avatars:_avatars media:_media stickers:_stickers] autorelease];
    chat.hidesBottomBarWhenPushed = YES;
    /* reading changed the counts of the topics, so they load again once the person is back */
    chat.closeHandler = ^{ [self reload]; };
    [self.navigationController pushViewController:chat animated:YES];
}

@end
