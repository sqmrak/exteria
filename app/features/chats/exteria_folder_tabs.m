#import "exteria_folder_tabs.h"
#import "exteria_chat_settings.h"
#import "exteria_filter_bar.h"
#import "exteria_dialog_cell.h"
#import "exteria_custom_emoji.h"
#import "exteria_custom_emoji_loader.h"
#import "exteria_message.h"
#import "exteria_weak_reference.h"

@interface ExteriaFolderTabs () <ExteriaFilterBarDelegate, UIGestureRecognizerDelegate> {
    ExteriaSession *_session;
    ExteriaMediaCache *_media;
    NSSet *_emojiDocuments;
    ExteriaFilterBar *_bar;
    NSArray *_folders;
    int32_t _selectedId;
    NSInteger _shownIndex;
    NSInteger _slideDirection;
    void (^_changed)(void);
    NSArray *_pagingRecognizers;
}
@end

@implementation ExteriaFolderTabs
@synthesize slideDirection = _slideDirection;
- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media changed:(void (^)(void))changed {
    self = [super initWithFrame:CGRectZero];
    if (!self)
        return nil;
    _session = [session retain];
    _media = [media retain];
    _changed = [changed copy];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rebuild) name:ExteriaChatFoldersDidChangeNotification object:session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(emojiLoaded:) name:ExteriaCustomEmojiDidLoadNotification object:nil];
    [self rebuild];
    return self;
}
- (void)dealloc {
    for (UIGestureRecognizer *gesture in _pagingRecognizers) {
        gesture.delegate = nil;
        [gesture.view removeGestureRecognizer:gesture];
    }
    [_pagingRecognizers release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_session release];
    [_media release];
    [_emojiDocuments release];
    [_folders release];
    [_bar release];
    [_changed release];
    [super dealloc];
}
- (CGFloat)height {
    return _folders.count > 1 ? 48 : 0;
}
- (ExteriaChatFolder *)selectedFolder {
    for (ExteriaChatFolder *folder in _folders)
        if (folder.folderId == _selectedId)
            return folder;
    return nil;
}
- (void)refresh {
    [_session loadChatFoldersWithCompletion:^(NSArray *folders, NSString *errorName) {
        (void)folders;
        if (errorName)
            NSLog(@"exteria: chat folders did not refresh: %@", errorName);
    }];
}
- (void)rebuild {
    NSMutableArray *folders = [NSMutableArray arrayWithArray:_session.chatFolders];
    BOOL hasDefault = NO;
    for (ExteriaChatFolder *folder in folders)
        if (!folder.folderId)
            hasDefault = YES;
    if (!hasDefault) {
        ExteriaChatFolder *all = [[[ExteriaChatFolder alloc] init] autorelease];
        all.title = NSLocalizedString(@"folders.all", nil);
        [folders insertObject:all atIndex:0];
    }
    /* the person may hide the tab of all chats, as long as two folders are left to switch between */
    if (ExteriaChatFlagGet(ExteriaChatFlagHideAllChatsTab) && folders.count > 2) {
        for (NSInteger i = (NSInteger)folders.count - 1; i >= 0; --i)
            if (![(ExteriaChatFolder *)[folders objectAtIndex:(NSUInteger)i] folderId])
                [folders removeObjectAtIndex:(NSUInteger)i];
    }
    [_folders release];
    _folders = [folders copy];
    NSMutableArray *titles = [NSMutableArray array];
    NSInteger selected = 0;
    for (NSUInteger i = 0; i < _folders.count; ++i) {
        ExteriaChatFolder *folder = [_folders objectAtIndex:i];
        [titles addObject:folder.title];
        if (folder.folderId == _selectedId)
            selected = (NSInteger)i;
    }
    _selectedId = ((ExteriaChatFolder *)[_folders objectAtIndex:(NSUInteger)selected]).folderId;
    [_bar removeFromSuperview];
    [_bar release];
    _bar = [[ExteriaFilterBar alloc] initWithTitles:titles];
    NSMutableSet *documents = [NSMutableSet set];
    for (NSUInteger i = 0; i < _folders.count; ++i) {
        ExteriaChatFolder *folder = [_folders objectAtIndex:i];
        [_bar setEntities:folder.titleEntities forIndex:(NSInteger)i];
        for (ExteriaTextEntity *entity in folder.titleEntities)
            [documents addObject:[NSNumber numberWithLongLong:entity.documentId]];
    }
    [_emojiDocuments release];
    _emojiDocuments = [documents copy];
    if (_media && documents.count)
        [ExteriaCustomEmojiLoader loadDocuments:[documents allObjects] session:_session media:_media documents:nil picture:nil];
    _bar.delegate = self;
    _bar.selectedIndex = selected;
    _shownIndex = selected;
    /* folders that arrive or go replace the list where it is, with no slide */
    _slideDirection = 0;
    [self addSubview:_bar];
    self.hidden = self.height == 0;
    [self setNeedsLayout];
    if (_changed)
        _changed();
}
- (void)emojiLoaded:(NSNotification *)notification {
    if ([_emojiDocuments containsObject:notification.object]) [_bar redrawTitles];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _bar.frame = self.bounds;
}
- (void)filterBar:(ExteriaFilterBar *)bar didSelectIndex:(NSInteger)index {
    (void)bar;
    if (index < 0 || (NSUInteger)index >= _folders.count)
        return;
    _selectedId = ((ExteriaChatFolder *)[_folders objectAtIndex:(NSUInteger)index]).folderId;
    _slideDirection = index > _shownIndex ? 1 : (index < _shownIndex ? -1 : 0);
    _shownIndex = index;
    if (_changed)
        _changed();
}

- (NSArray *)pagingRecognizers { return _pagingRecognizers; }

- (void)installPagingInView:(UIView *)view {
    if (!_pagingRecognizers) {
        NSMutableArray *gestures = [NSMutableArray array];
        for (NSNumber *direction in [NSArray arrayWithObjects:[NSNumber numberWithUnsignedInteger:UISwipeGestureRecognizerDirectionLeft],
                                                             [NSNumber numberWithUnsignedInteger:UISwipeGestureRecognizerDirectionRight], nil]) {
            UISwipeGestureRecognizer *gesture = [[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(pageSwiped:)] autorelease];
            gesture.direction = direction.unsignedIntegerValue;
            gesture.delegate = self;
            [gestures addObject:gesture];
        }
        _pagingRecognizers = [gestures copy];
    }
    for (UIGestureRecognizer *gesture in _pagingRecognizers) [view addGestureRecognizer:gesture];
}

- (NSInteger)pageAfterSwipe:(UISwipeGestureRecognizer *)gesture {
    return _bar.selectedIndex + (gesture.direction == UISwipeGestureRecognizerDirectionLeft ? 1 : -1);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    UIView *hit = [gesture.view hitTest:[gesture locationInView:gesture.view] withEvent:nil];
    for (UIView *view = hit; view && view != gesture.view; view = view.superview) {
        if ([view isKindOfClass:[ExteriaDialogCell class]] && [(ExteriaDialogCell *)view swipeOpen]) return NO;
        if ([view isKindOfClass:[UITableViewCell class]] &&
            ((UISwipeGestureRecognizer *)gesture).direction == UISwipeGestureRecognizerDirectionLeft &&
            ExteriaChatSwipeStored() != ExteriaChatSwipeFolders) return NO;
    }
    NSInteger index = [self pageAfterSwipe:(UISwipeGestureRecognizer *)gesture];
    return _folders.count > 1 && index >= 0 && (NSUInteger)index < _folders.count;
}

- (void)pageSwiped:(UISwipeGestureRecognizer *)gesture {
    NSInteger index = [self pageAfterSwipe:gesture];
    if (index < 0 || (NSUInteger)index >= _folders.count) return;
    _bar.selectedIndex = index;
    [self filterBar:_bar didSelectIndex:index];
}
@end
