#import "exteria_topics_controller.h"

#import "exteria_chat_controller.h"
#import "exteria_custom_emoji_loader.h"
#import "exteria_dialog_cell.h"
#import "exteria_draft.h"
#import "exteria_weak_reference.h"

@interface ExteriaTopicsController () {
    ExteriaDialog *_forum;
    NSArray *_topics;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    ExteriaWeakReference *_weak;
    void (^_closeHandler)(void);
}
@end

@implementation ExteriaTopicsController

@synthesize closeHandler = _closeHandler;

- (id)initWithSession:(ExteriaSession *)session forum:(ExteriaDialog *)forum avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers {
    self = [super initWithSession:session];
    if (!self) return nil;
    _forum = [forum retain];
    _topics = [[NSArray alloc] init];
    _media = [media retain];
    _stickers = [stickers retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.avatars = avatars;
    self.heading = forum.saved ? NSLocalizedString(@"chat.saved.dialogs", nil) : forum.title;
    self.showsBack = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(draftChanged:) name:ExteriaDraftDidChangeNotification object:session.drafts];
    return self;
}

/* the drafts of the topics show in their rows; the order is the server's and a draft in a topic does not move it here */
- (void)draftChanged:(NSNotification *)note {
    if (!self.isViewLoaded) return;
    NSMutableArray *affected = [NSMutableArray array];
    for (NSIndexPath *path in [self.table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row < _topics.count && ExteriaDraftChangeConcerns(note, [_topics objectAtIndex:(NSUInteger)path.row])) [affected addObject:path];
    }
    if (affected.count) [self.table reloadRowsAtIndexPaths:affected withRowAnimation:UITableViewRowAnimationNone];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaDraftDidChangeNotification object:nil];
    [_weak clear];
    [_weak release];
    [_forum release];
    [_topics release];
    [_media release];
    [_stickers release];
    [_closeHandler release];
    [super dealloc];
}

- (void)loadItemsWithCompletion:(ExteriaListCompletion)completion {
    /* the favorites list the chats their messages came from, in the place of topics */
    if (_forum.saved) [self.session loadSavedDialogs:completion];
    else [self.session loadTopicsOfDialog:_forum completion:completion];
}

- (void)didReceiveItems:(NSArray *)items {
    [_topics release];
    _topics = [items copy];
    NSMutableArray *icons = [NSMutableArray array];
    for (ExteriaDialog *topic in _topics) {
        if (topic.topicIconEmoji) [icons addObject:[NSNumber numberWithLongLong:topic.topicIconEmoji]];
    }
    if (!icons.count) return;
    /* the rows draw the hash until the emoji picture is in memory, then the rows on screen are configured again */
    ExteriaWeakReference *weak = _weak;
    [ExteriaCustomEmojiLoader loadDocuments:icons session:self.session media:_media documents:nil picture:^{
        ExteriaTopicsController *topics = weak.target;
        if (topics) [topics.table reloadData];
    }];
}

- (NSInteger)itemCount {
    return (NSInteger)_topics.count;
}

- (NSString *)emptyText {
    return NSLocalizedString(_forum.saved ? @"chat.saved.empty" : @"topics.empty", nil);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return [ExteriaDialogCell rowHeight];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"topic";
    ExteriaDialogCell *cell = (ExteriaDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    ExteriaDialog *topic = [_topics objectAtIndex:(NSUInteger)indexPath.row];
    [cell configureWithDialog:topic avatars:self.avatars action:ExteriaDialogActionNone];
    [cell showDraft:ExteriaVisibleDraft(self.session.drafts, topic)];
    [cell layoutIfNeeded];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ExteriaDialog *topic = [_topics objectAtIndex:(NSUInteger)indexPath.row];
    if (_forum.saved) topic = [_forum savedDialogFromSource:topic];
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:self.session dialog:topic avatars:self.avatars
                                                                           media:_media stickers:_stickers] autorelease];
    /* reading changed the counts of the topics, so they load again once the person is back */
    chat.closeHandler = ^{ [self reloadDiscardingRunning]; };
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if ([self isMovingFromParentViewController] && _closeHandler) _closeHandler();
}

@end
