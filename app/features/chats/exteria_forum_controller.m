#import "exteria_forum_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_avatar_view.h"
#import "exteria_chat_controller.h"
#import "exteria_next_chat_hint.h"
#import "exteria_community_badge.h"
#import "exteria_custom_emoji_loader.h"
#import "exteria_dialog_cell.h"
#import "exteria_draft.h"
#import "exteria_emoji_label.h"
#import "exteria_geometry.h"
#import "exteria_platform.h"
#import "exteria_session_channels.h"
#import "exteria_plural.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_wave_background_view.h"
#import "exteria_weak_reference.h"

#define BAR_HEIGHT 48.0
#define RAIL_WIDTH 76.0
#define RAIL_ROW 76.0
#define RAIL_AVATAR 52.0
#define RAIL_BADGE 20.0
#define HEADER_AVATAR 36.0
/* a topic list that is older than this loads again when the screen comes back */
#define STALE_SECONDS 60.0

#pragma mark rail cell

@interface ExteriaForumRailCell : UITableViewCell {
    UIView *_mark;
    ExteriaAvatarView *_avatar;
    UILabel *_count;
    UIImageView *_forumBadge;
}
- (void)configureWithDialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars current:(BOOL)current;
@end

@implementation ExteriaForumRailCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    _mark = [[UIView alloc] init];
    _mark.backgroundColor = ExteriaColorAccent();
    _mark.layer.cornerRadius = 2;
    [self.contentView addSubview:_mark];
    _avatar = [[ExteriaAvatarView alloc] init];
    _avatar.circular = YES;
    [self.contentView addSubview:_avatar];
    _forumBadge = [[UIImageView alloc] initWithImage:ExteriaCommunityBadgeImage()];
    [self.contentView addSubview:_forumBadge];
    _count = [[UILabel alloc] init];
    _count.font = ExteriaFontBold(12);
    _count.textAlignment = ExteriaTextAlignmentCenter;
    _count.textColor = [UIColor whiteColor];
    _count.clipsToBounds = YES;
    [self.contentView addSubview:_count];
    return self;
}

- (void)dealloc {
    [_mark release];
    [_avatar release];
    [_count release];
    [_forumBadge release];
    [super dealloc];
}

- (void)configureWithDialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars current:(BOOL)current {
    BOOL symbol = dialog.saved || dialog.folder || dialog.replies;
    _avatar.seed = dialog.avatarSeed;
    _avatar.initials = dialog.initials;
    _avatar.deleted = dialog.deleted;
    _avatar.accent = symbol;
    _avatar.symbol = dialog.folder ? ExteriaSymbolArchive : (dialog.replies ? ExteriaSymbolReply : ExteriaSymbolBookmark);
    _avatar.showsSymbol = symbol;
    [_avatar setPhoto:symbol ? nil : dialog.photo cache:avatars];
    _mark.hidden = !current;
    _mark.backgroundColor = ExteriaColorAccent();
    BOOL unread = dialog.unreadCount > 0 && !dialog.folder;
    _count.hidden = !unread;
    _count.text = dialog.unreadCount > 999 ? @"999+" : [NSString stringWithFormat:@"%ld", (long)dialog.unreadCount];
    _count.backgroundColor = dialog.muted ? ExteriaColorMuted() : ExteriaColorAccent();
    /* the arrow on a forum's picture says it holds topics; a count of unread messages takes its place */
    _forumBadge.hidden = !dialog.forum || unread;
    self.accessibilityLabel = dialog.title;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width, height = self.contentView.bounds.size.height;
    CGRect avatar = CGRectMake((width - RAIL_AVATAR) / 2, (height - RAIL_AVATAR) / 2, RAIL_AVATAR, RAIL_AVATAR);
    _avatar.frame = avatar;
    _mark.frame = CGRectMake(-2, (height - 36) / 2, 6, 36);
    _forumBadge.frame = CGRectMake(CGRectGetMaxX(avatar) - RAIL_BADGE + 4, CGRectGetMaxY(avatar) - RAIL_BADGE + 4, RAIL_BADGE, RAIL_BADGE);
    CGSize fit = [_count sizeThatFits:CGSizeMake(60, RAIL_BADGE)];
    CGFloat badgeWidth = MAX(RAIL_BADGE, fit.width + 10);
    _count.frame = CGRectMake(CGRectGetMaxX(avatar) - badgeWidth + 6, CGRectGetMaxY(avatar) - RAIL_BADGE + 4, badgeWidth, RAIL_BADGE);
    _count.layer.cornerRadius = RAIL_BADGE / 2;
}

@end

#pragma mark controller

@interface ExteriaForumController () <UITableViewDataSource, UITableViewDelegate> {
    ExteriaSession *_session;
    ExteriaDialog *_forum;
    NSArray *_source;
    NSArray *_rail;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    ExteriaWeakReference *_weak;
    NSArray *_topics;
    NSMutableSet *_topicsSeen;
    NSDate *_loadedAt;
    BOOL _loading;
    BOOL _loaded;
    BOOL _stale;
    BOOL _entered;
    /* a late answer for a forum the person left must not fill the table of the one now shown */
    NSUInteger _generation;
    void (^_closeHandler)(void);
    void (^_archiveHandler)(void);

    ExteriaWaveBackgroundView *_backdrop;
    UIView *_header;
    UIView *_headerLine;
    UIButton *_back;
    ExteriaAvatarView *_headerAvatar;
    ExteriaEmojiLabel *_title;
    UILabel *_subtitle;
    UIView *_railPanel;
    UIView *_railLine;
    UITableView *_railTable;
    UITableView *_table;
    UILabel *_status;
    UIButton *_retry;
}
@end

@implementation ExteriaForumController

@synthesize closeHandler = _closeHandler;
@synthesize archiveHandler = _archiveHandler;

- (id)initWithSession:(ExteriaSession *)session forum:(ExteriaDialog *)forum dialogs:(NSArray *)dialogs avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _forum = [forum retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _topics = [[NSArray alloc] init];
    _source = [dialogs copy];
    _rail = [[NSArray alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(draftChanged:) name:ExteriaDraftDidChangeNotification object:session.drafts];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(forumSummariesChanged:) name:ExteriaForumSummariesDidChangeNotification object:session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dialogsChanged) name:ExteriaDialogsChangedNotification object:nil];
    return self;
}

- (BOOL)showsForum:(ExteriaDialog *)forum {
    return forum.peerKind == _forum.peerKind && forum.peerId == _forum.peerId;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    _railTable.delegate = nil;
    _railTable.dataSource = nil;
    _table.delegate = nil;
    _table.dataSource = nil;
    [_session release];
    [_forum release];
    [_source release];
    [_rail release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_topicsSeen release];
    [_topics release];
    [_loadedAt release];
    [_closeHandler release];
    [_archiveHandler release];
    [_backdrop release];
    [_header release];
    [_headerLine release];
    [_back release];
    [_headerAvatar release];
    [_title release];
    [_subtitle release];
    [_railPanel release];
    [_railLine release];
    [_railTable release];
    [_table release];
    [_status release];
    [_retry release];
    [super dealloc];
}

/* a community opens a screen of its own and is not a chat of the column; the archive
   button needs a handler that opens it */
- (void)buildRail {
    NSMutableArray *rail = [NSMutableArray array];
    for (ExteriaDialog *dialog in _source) {
        if (dialog.community || (dialog.folder && !_archiveHandler)) continue;
        [rail addObject:dialog];
    }
    [_rail release];
    _rail = [rail copy];
}

- (BOOL)hasRail {
    return _rail.count > 1;
}

#pragma mark view

- (void)loadView {
    [self buildRail];
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = ExteriaColorScreen();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _backdrop = [[ExteriaWaveBackgroundView alloc] initWithFrame:root.bounds];
    _backdrop.plain = YES;
    _backdrop.animated = YES;
    [root addSubview:_backdrop];

    _table = [[UITableView alloc] initWithFrame:root.bounds style:UITableViewStylePlain];
    ExteriaScrollViewOwnsInsets(_table);
    ExteriaTableUsesExactHeights(_table);
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    [root addSubview:_table];

    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = ExteriaColorSecondary();
    _status.textAlignment = ExteriaTextAlignmentCenter;
    _status.numberOfLines = 0;
    [root addSubview:_status];
    _retry = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_retry setTitle:NSLocalizedString(@"list.retry", nil) forState:UIControlStateNormal];
    [_retry setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES;
    [root addSubview:_retry];

    _railPanel = [[UIView alloc] init];
    _railPanel.backgroundColor = [ExteriaColorBar() colorWithAlphaComponent:0.72f];
    _railPanel.hidden = ![self hasRail];
    [root addSubview:_railPanel];
    _railTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    ExteriaScrollViewOwnsInsets(_railTable);
    ExteriaTableUsesExactHeights(_railTable);
    _railTable.backgroundColor = [UIColor clearColor];
    _railTable.separatorStyle = UITableViewCellSeparatorStyleNone;
    _railTable.showsVerticalScrollIndicator = NO;
    _railTable.rowHeight = RAIL_ROW;
    _railTable.dataSource = self;
    _railTable.delegate = self;
    [_railPanel addSubview:_railTable];
    _railLine = [[UIView alloc] init];
    _railLine.backgroundColor = ExteriaColorHairline();
    [_railPanel addSubview:_railLine];

    _header = [[UIView alloc] init];
    _header.backgroundColor = ExteriaColorBar();
    [root addSubview:_header];
    _headerLine = [[UIView alloc] init];
    _headerLine.backgroundColor = ExteriaColorHairline();
    [_header addSubview:_headerLine];
    _back = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_back setImage:ExteriaSymbolImage(ExteriaSymbolBack, 22, ExteriaColorTitle()) forState:UIControlStateNormal];
    _back.accessibilityLabel = NSLocalizedString(@"phone.back", nil);
    [_back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:_back];
    _headerAvatar = [[ExteriaAvatarView alloc] init];
    _headerAvatar.circular = YES;
    [_header addSubview:_headerAvatar];
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.textColor = ExteriaColorTitle();
    _title.dropsUndrawable = YES;
    [_header addSubview:_title];
    _subtitle = [[UILabel alloc] init];
    _subtitle.backgroundColor = [UIColor clearColor];
    _subtitle.textColor = ExteriaColorSecondary();
    [_header addSubview:_subtitle];
    [self applyForumToHeader];
}

- (void)applyForumToHeader {
    _headerAvatar.seed = _forum.avatarSeed;
    _headerAvatar.initials = _forum.initials;
    [_headerAvatar setPhoto:_forum.photo cache:_avatars];
    _title.text = _forum.title;
    NSInteger members = _forum.participantsCount;
    _subtitle.text = members > 0 ? [NSString stringWithFormat:NSLocalizedString([@"chat.members." stringByAppendingString:ExteriaPluralForm(members)], nil), (long)members]
                                 : NSLocalizedString(@"chat.status.group", nil);
    [self.view setNeedsLayout];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reloadTopics];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    return ExteriaOrientationMask();
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_loaded && (_stale || (_loadedAt && -[_loadedAt timeIntervalSinceNow] > STALE_SECONDS))) [self reloadTopics];
    if (_entered || !animated || ExteriaReduceMotionEnabled()) {
        _entered = YES;
        return;
    }
    /* the column slides in from the edge it stands at and the topics follow it, over the same push that brings the screen */
    _entered = YES;
    [self.view layoutIfNeeded];
    ExteriaAnimateEnter(_railPanel, CGAffineTransformMakeTranslation(-RAIL_WIDTH, 0), 0, EXTERIA_MOTION_ENTER);
    ExteriaAnimateEnter(_table, CGAffineTransformMakeTranslation(28, 0), 0, EXTERIA_MOTION_ENTER);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (![self isMovingFromParentViewController]) return;
    if (_closeHandler) _closeHandler();
}

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat barBottom = insets.top + BAR_HEIGHT;
    CGFloat leftInset = insets.left, rightInset = insets.right;
    BOOL rail = [self hasRail];
    CGFloat railWidth = rail ? RAIL_WIDTH + leftInset : 0;
    _backdrop.frame = self.view.bounds;
    _header.frame = CGRectMake(0, 0, size.width, barBottom);
    _headerLine.frame = CGRectMake(0, barBottom - 1.0 / ExteriaScreenScale(), size.width, 1.0 / ExteriaScreenScale());
    _back.frame = CGRectMake(leftInset, insets.top, 52, BAR_HEIGHT);
    _headerAvatar.frame = CGRectMake(leftInset + 52, insets.top + (BAR_HEIGHT - HEADER_AVATAR) / 2, HEADER_AVATAR, HEADER_AVATAR);
    CGFloat textX = CGRectGetMaxX(_headerAvatar.frame) + 10;
    CGFloat textWidth = MAX(0, size.width - rightInset - 12 - textX);
    _title.font = ExteriaFontSemibold(17);
    _subtitle.font = ExteriaFontRegular(13);
    _title.frame = CGRectMake(textX, insets.top + 6, textWidth, 22);
    _subtitle.frame = CGRectMake(textX, insets.top + 27, textWidth, 16);
    _railPanel.frame = CGRectMake(0, barBottom, railWidth, size.height - barBottom);
    _railTable.frame = CGRectMake(leftInset, 0, RAIL_WIDTH, _railPanel.bounds.size.height);
    _railTable.contentInset = UIEdgeInsetsMake(6, 0, MAX(6, insets.bottom), 0);
    _railTable.scrollIndicatorInsets = _railTable.contentInset;
    _railLine.frame = CGRectMake(railWidth - 1.0 / ExteriaScreenScale(), 0, 1.0 / ExteriaScreenScale(), _railPanel.bounds.size.height);
    _table.frame = CGRectMake(railWidth, barBottom, size.width - railWidth - rightInset, size.height - barBottom);
    _table.contentInset = UIEdgeInsetsMake(0, 0, insets.bottom, 0);
    _table.scrollIndicatorInsets = _table.contentInset;
    CGFloat midY = barBottom + (size.height - barBottom - insets.bottom) / 2;
    CGFloat midX = railWidth + (size.width - railWidth - rightInset) / 2;
    _status.font = ExteriaFontRegular(16);
    CGSize fit = [_status sizeThatFits:CGSizeMake(MAX(0, size.width - railWidth - rightInset - 48), 200)];
    _status.frame = CGRectMake(midX - fit.width / 2, midY - fit.height / 2 - (_retry.hidden ? 0 : 22), fit.width, fit.height);
    _retry.titleLabel.font = ExteriaFontSemibold(17);
    _retry.frame = CGRectMake(midX - 70, CGRectGetMaxY(_status.frame) + 8, 140, 40);
}

#pragma mark topics

- (void)retryTapped {
    [self reloadTopics];
}

- (void)reloadTopics {
    if (_loading) return;
    _loading = YES;
    _stale = NO;
    NSUInteger generation = _generation;
    ExteriaWeakReference *weak = _weak;
    [_session loadTopicsOfDialog:_forum completion:^(NSArray *items, NSString *errorName) {
        ExteriaForumController *screen = weak.target;
        if (!screen || generation != screen->_generation) {
            /* the forum on screen changed meanwhile, and its own load was held back by this one */
            if (screen) {
                screen->_loading = NO;
                [screen reloadTopics];
            }
            return;
        }
        [screen receiveTopics:items error:errorName];
    }];
}

- (void)receiveTopics:(NSArray *)items error:(NSString *)errorName {
    _loading = NO;
    if (!items) {
        /* topics already on screen stay; only an empty screen shows the failure */
        if (!_loaded) {
            _status.text = [errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                   : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName ? errorName : @"?"];
            _retry.hidden = NO;
            [self.view setNeedsLayout];
        } else {
            NSLog(@"exteria: refresh of the topics failed: %@", errorName);
        }
        return;
    }
    _loaded = YES;
    [_loadedAt release];
    _loadedAt = [[NSDate date] retain];
    [_topics release];
    _topics = [items copy];
    _retry.hidden = YES;
    _status.text = _topics.count ? @"" : NSLocalizedString(@"topics.empty", nil);
    [_table reloadData];
    [self.view setNeedsLayout];
    [self loadIcons];
}

/* the rows draw the hash until the emoji picture is in memory, then the table draws them again */
- (void)loadIcons {
    NSMutableArray *icons = [NSMutableArray array];
    for (ExteriaDialog *topic in _topics) {
        if (topic.topicIconEmoji) [icons addObject:[NSNumber numberWithLongLong:topic.topicIconEmoji]];
    }
    if (!icons.count) return;
    ExteriaWeakReference *weak = _weak;
    [ExteriaCustomEmojiLoader loadDocuments:icons session:_session media:_media documents:nil picture:^{
        ExteriaForumController *screen = weak.target;
        if (screen) [screen->_table reloadData];
    }];
}

/* the list changed under the screen; the topics are read again when it is next on screen, or now when it is */
- (void)dialogsChanged {
    _stale = YES;
    if (self.isViewLoaded && self.view.window && self.navigationController.topViewController == self) [self reloadTopics];
}

- (void)forumSummariesChanged:(NSNotification *)note {
    if (!self.isViewLoaded) return;
    [_session applyForumSummariesToDialogs:_rail];
    [_railTable reloadData];
}

- (void)draftChanged:(NSNotification *)note {
    if (!self.isViewLoaded) return;
    NSMutableArray *affected = [NSMutableArray array];
    for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row < _topics.count && ExteriaDraftChangeConcerns(note, [_topics objectAtIndex:(NSUInteger)path.row])) [affected addObject:path];
    }
    if (affected.count) [_table reloadRowsAtIndexPaths:affected withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark switching forums

- (BOOL)isCurrent:(ExteriaDialog *)dialog {
    return dialog.peerKind == _forum.peerKind && dialog.peerId == _forum.peerId;
}

/* another forum of the column: the header changes name and picture with a short cross fade, and the topics of the new forum slide in over the old ones */
- (void)showForum:(ExteriaDialog *)forum {
    [_forum release];
    _forum = [forum retain];
    ++_generation;
    _loading = NO;
    _loaded = NO;
    _stale = NO;
    [_topics release];
    _topics = [[NSArray alloc] init];
    _status.text = @"";
    _retry.hidden = YES;
    BOOL animated = !ExteriaReduceMotionEnabled();
    void (^change)(void) = ^{
        [self applyForumToHeader];
        [_table reloadData];
        [_table setContentOffset:CGPointMake(0, -_table.contentInset.top) animated:NO];
    };
    if (animated) {
        [UIView transitionWithView:_header duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve animations:change completion:NULL];
        ExteriaAnimateEnter(_table, CGAffineTransformMakeTranslation(24, 0), 0, EXTERIA_MOTION_ENTER);
    } else {
        change();
    }
    for (ExteriaForumRailCell *cell in [_railTable visibleCells]) {
        NSIndexPath *path = [_railTable indexPathForCell:cell];
        if (path) [cell configureWithDialog:[_rail objectAtIndex:(NSUInteger)path.row] avatars:_avatars current:[self isCurrent:[_rail objectAtIndex:(NSUInteger)path.row]]];
    }
    [self reloadTopics];
}

#pragma mark tables

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)(tableView == _railTable ? _rail.count : _topics.count);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return tableView == _railTable ? RAIL_ROW : [ExteriaDialogCell rowHeight];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == _railTable) {
        static NSString *railIdentifier = @"rail";
        ExteriaForumRailCell *cell = (ExteriaForumRailCell *)[tableView dequeueReusableCellWithIdentifier:railIdentifier];
        if (!cell) cell = [[[ExteriaForumRailCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:railIdentifier] autorelease];
        ExteriaDialog *dialog = [_rail objectAtIndex:(NSUInteger)indexPath.row];
        [cell configureWithDialog:dialog avatars:_avatars current:[self isCurrent:dialog]];
        return cell;
    }
    static NSString *identifier = @"topic";
    ExteriaDialogCell *cell = (ExteriaDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    cell.media = _media;
    ExteriaDialog *topic = [_topics objectAtIndex:(NSUInteger)indexPath.row];
    [cell configureWithDialog:topic avatars:_avatars action:ExteriaDialogActionNone];
    [cell showDraft:ExteriaVisibleDraft(_session.drafts, topic)];
    [cell layoutIfNeeded];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (tableView == _railTable) {
        [self selectRailDialog:[_rail objectAtIndex:(NSUInteger)indexPath.row]];
        return;
    }
    ExteriaDialog *topic = [_topics objectAtIndex:(NSUInteger)indexPath.row];
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:_session dialog:topic avatars:_avatars media:_media stickers:_stickers] autorelease];
    ExteriaWeakReference *weak = _weak;
    /* a topic goes on to the next one with unread messages when the list is pulled past its end, as a channel goes on to the next channel; the topics gone through are forgotten
       when another one is opened from the list */
    [_topicsSeen release];
    _topicsSeen = [[NSMutableSet alloc] init];
    chat.nextChatProvider = ^ExteriaDialog *(ExteriaDialog *current) { return [ExteriaNextChatHint nextUnreadTopicIn:_topics after:current seen:_topicsSeen]; };
    /* reading changed the counts of the topics, so they load again once the person is back */
    chat.closeHandler = ^{
        ExteriaForumController *screen = weak.target;
        if (!screen) return;
        screen->_loading = NO;
        [screen reloadTopics];
    };
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)selectRailDialog:(ExteriaDialog *)dialog {
    if (dialog.folder) {
        if (_archiveHandler) _archiveHandler();
        return;
    }
    if ([self isCurrent:dialog]) {
        [_table setContentOffset:CGPointMake(0, -_table.contentInset.top) animated:YES];
        return;
    }
    if (dialog.forum) {
        [self showForum:dialog];
        return;
    }
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    [self.navigationController pushViewController:chat animated:YES];
}

@end
