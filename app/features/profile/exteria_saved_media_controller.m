#import "exteria_saved_media_controller.h"
#import "exteria_group_tabs_view.h"
#import "exteria_chat_controller.h"
#import "exteria_media_viewer.h"
#import "exteria_platform.h"
#import "exteria_user_profile_controller.h"
#import "exteria_music_list_controller.h"
#import "exteria_music_pill.h"
#import "exteria_session_profile.h"
#import "exteria_weak_reference.h"

@interface ExteriaSavedMediaController () <ExteriaGroupTabsDelegate> {
    ExteriaDialog *_dialog;
    UIScrollView *_scroll;
    ExteriaGroupTabsView *_tabs;
    ExteriaMusicPill *_music;
    ExteriaMedia *_savedTrack;
    NSUInteger _musicGeneration;
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaSavedMediaController
- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _dialog = [dialog retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.screenTitle = NSLocalizedString(@"chats.saved", nil);
    return self;
}
- (void)dealloc {
    [_weak clear];
    [_weak release];
    _music.contentHandler = nil;
    [_music release];
    [_savedTrack release];
    _tabs.delegate = nil;
    [_tabs release];
    [_scroll release];
    [_dialog release];
    [super dealloc];
}
- (void)buildBodyInView:(UIView *)root {
    _scroll = [[UIScrollView alloc] init];
    ExteriaScrollViewOwnsInsets(_scroll);
    [root addSubview:_scroll];
    _music = [[ExteriaMusicPill alloc] init];
    [_music addTarget:self action:@selector(openMusic) forControlEvents:UIControlEventTouchUpInside];
    ExteriaWeakReference *weak = _weak;
    _music.contentHandler = ^{ [[(ExteriaSavedMediaController *)weak.target view] setNeedsLayout]; };
    [_scroll addSubview:_music];
    _tabs = [[ExteriaGroupTabsView alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media forUser:YES];
    _tabs.delegate = self;
    [_scroll addSubview:_tabs];
}
- (void)layoutBody:(CGRect)body {
    _scroll.frame = body;
    CGFloat top = 0;
    if (_music.hasContent) {
        _music.frame = CGRectMake(14, 12, MAX(0, body.size.width - 28), [ExteriaMusicPill height]);
        top = CGRectGetMaxY(_music.frame) + 12;
    }
    CGFloat height = [_tabs heightForWidth:body.size.width];
    _tabs.frame = CGRectMake(0, top, body.size.width, height);
    _scroll.contentSize = CGSizeMake(body.size.width, top + height);
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    /* returning from our playlist refreshes the first song after it was removed */
    NSUInteger generation = ++_musicGeneration;
    ExteriaWeakReference *weak = _weak;
    [self.session loadFullUserOfDialog:_dialog completion:^(ExteriaFullUser *user, NSString *errorName) {
        ExteriaSavedMediaController *screen = weak.target;
        if (!screen || generation != screen->_musicGeneration) return;
        if (!user) {
            NSLog(@"exteria: saved messages profile music did not load: %@", errorName);
            return;
        }
        [screen->_savedTrack release];
        screen->_savedTrack = [user.music retain];
        screen->_music.savedTrack = user.music;
        [screen.view setNeedsLayout];
    }];
}
- (void)openMusic {
    ExteriaMusicListController *list = [[[ExteriaMusicListController alloc] initWithSession:self.session dialog:_dialog first:_savedTrack
                                                                                              avatars:self.avatars media:self.media] autorelease];
    [self.navigationController pushViewController:list animated:YES];
}
- (void)groupTabsDidResize:(ExteriaGroupTabsView *)tabs {
    (void)tabs;
    [self.view setNeedsLayout];
}
- (void)groupTabs:(ExteriaGroupTabsView *)tabs didOpenPerson:(ExteriaPerson *)person {
    (void)tabs;
    ExteriaUserProfileController *profile = [[[ExteriaUserProfileController alloc] initWithSession:self.session dialog:[ExteriaDialog dialogWithPerson:person] avatars:self.avatars media:self.media stickers:nil] autorelease];
    [self.navigationController pushViewController:profile animated:YES];
}
- (void)groupTabs:(ExteriaGroupTabsView *)tabs didOpenMessage:(ExteriaMessage *)message {
    (void)tabs;
    NSArray *stack = self.navigationController.viewControllers;
    for (UIViewController *screen in [stack reverseObjectEnumerator]) {
        if (![screen isKindOfClass:[ExteriaChatController class]]) continue;
        ExteriaChatController *chat = (ExteriaChatController *)screen;
        if (![chat showsDialog:_dialog]) continue;
        [self.navigationController popToViewController:chat animated:YES];
        [chat jumpToMessageId:message.messageId];
        return;
    }
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars
        media:self.media stickers:nil] autorelease];
    chat.startMessageId = message.messageId;
    [self.navigationController pushViewController:chat animated:YES];
}
- (void)groupTabs:(ExteriaGroupTabsView *)tabs didOpenMedia:(ExteriaMessage *)message among:(NSArray *)messages {
    (void)tabs;
    ExteriaMediaViewer *viewer = [[[ExteriaMediaViewer alloc] initWithMessages:messages selected:message media:self.media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}
@end
