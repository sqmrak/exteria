#import "exteria_now_playing.h"

#import <objc/message.h>

#import "exteria_audio_session.h"

static NSString *ExteriaMediaKey(const char *name) {
    return ExteriaAudioConstant(name);
}

/* one player owns the lock screen; keep its artwork across rate and position updates */
static UIImage *ExteriaNowPlayingCover;
static id ExteriaNowPlayingArtwork;

void ExteriaNowPlayingShow(NSString *title, NSString *performer, UIImage *cover, NSTimeInterval position, NSTimeInterval duration, float rate) {
    Class centerClass = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (!centerClass) return;
    id center = [centerClass performSelector:NSSelectorFromString(@"defaultCenter")];
    NSString *titleKey = ExteriaMediaKey("MPMediaItemPropertyTitle"), *artistKey = ExteriaMediaKey("MPMediaItemPropertyArtist");
    NSString *durationKey = ExteriaMediaKey("MPMediaItemPropertyPlaybackDuration"), *elapsedKey = ExteriaMediaKey("MPNowPlayingInfoPropertyElapsedPlaybackTime");
    NSString *rateKey = ExteriaMediaKey("MPNowPlayingInfoPropertyPlaybackRate"), *artKey = ExteriaMediaKey("MPMediaItemPropertyArtwork");
    if (!center || !titleKey) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (title) [info setObject:title forKey:titleKey];
    if (performer.length && artistKey) [info setObject:performer forKey:artistKey];
    if (duration > 0 && durationKey) [info setObject:[NSNumber numberWithDouble:duration] forKey:durationKey];
    if (elapsedKey) [info setObject:[NSNumber numberWithDouble:position] forKey:elapsedKey];
    if (rateKey) [info setObject:[NSNumber numberWithFloat:rate] forKey:rateKey];
    Class artworkClass = NSClassFromString(@"MPMediaItemArtwork");
    if (cover != ExteriaNowPlayingCover) {
        [ExteriaNowPlayingArtwork release];
        ExteriaNowPlayingArtwork = nil;
        UIImage *nextCover = [cover retain];
        [ExteriaNowPlayingCover release];
        ExteriaNowPlayingCover = nextCover;
        SEL initializer = NSSelectorFromString(@"initWithImage:");
        if (cover && artKey && [artworkClass instancesRespondToSelector:initializer])
            ExteriaNowPlayingArtwork = [[artworkClass alloc] performSelector:initializer withObject:cover];
    }
    if (ExteriaNowPlayingArtwork && artKey) [info setObject:ExteriaNowPlayingArtwork forKey:artKey];
    [center setValue:info forKey:@"nowPlayingInfo"];
}

void ExteriaNowPlayingClear(void) {
    [ExteriaNowPlayingArtwork release];
    ExteriaNowPlayingArtwork = nil;
    [ExteriaNowPlayingCover release];
    ExteriaNowPlayingCover = nil;
    Class centerClass = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (!centerClass) return;
    id center = [centerClass performSelector:NSSelectorFromString(@"defaultCenter")];
    [center setValue:nil forKey:@"nowPlayingInfo"];
}

/* before ios 7.1 an application is the one that plays for the lock screen and the tray of the multitasking bar only while a first responder takes the remote events: asking for them is
   not enough, and without a responder the system kept the Music app there, with its name and its icon, over the buttons of this one. a view of no size in the window is that responder.
   it never takes the focus from a text field, which would close the keyboard */
@interface ExteriaRemoteResponder : UIView
@end

@implementation ExteriaRemoteResponder
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    id<UIApplicationDelegate> delegate = [UIApplication sharedApplication].delegate;
    if ([delegate respondsToSelector:@selector(remoteControlReceivedWithEvent:)]) [(id)delegate remoteControlReceivedWithEvent:event];
}
@end

static ExteriaRemoteResponder *ExteriaRemoteResponderView;
static BOOL ExteriaKeyboardUp;
static BOOL ExteriaRemoteActive;

void ExteriaRemoteControlsClaim(void) {
    if (!ExteriaRemoteActive || NSClassFromString(@"MPRemoteCommandCenter") || ExteriaKeyboardUp) return;
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;
    if (!ExteriaRemoteResponderView) {
        ExteriaRemoteResponderView = [[ExteriaRemoteResponder alloc] initWithFrame:CGRectZero];
        /* a hidden view is refused as first responder on ios 6, so it stays visible and clear */
        ExteriaRemoteResponderView.alpha = 0;
        ExteriaRemoteResponderView.userInteractionEnabled = NO;
    }
    if (ExteriaRemoteResponderView.superview != window) [window addSubview:ExteriaRemoteResponderView];
    if (!ExteriaRemoteResponderView.isFirstResponder && ![ExteriaRemoteResponderView becomeFirstResponder]) NSLog(@"exteria: the remote events found no responder");
}

static void ExteriaWatchKeyboard(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserverForName:UIKeyboardDidShowNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { (void)note; ExteriaKeyboardUp = YES; }];
        [center addObserverForName:UIKeyboardDidHideNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            (void)note;
            ExteriaKeyboardUp = NO;
            /* the field that held the focus is gone, so the remote events have no responder again until it is taken back */
            ExteriaRemoteControlsClaim();
        }];
    });
}

static void ExteriaCommand(id center, NSString *name, id target, SEL action) {
    id command = [center valueForKey:name];
    if (!command || !action) return;
    /* the commands of next and previous song start switched off, and the buttons of the lock screen and the control center stay grey until they are on */
    [command setValue:[NSNumber numberWithBool:YES] forKey:@"enabled"];
    ((void (*)(id, SEL, id, SEL))objc_msgSend)(command, NSSelectorFromString(@"addTarget:action:"), target, action);
}

void ExteriaRemoteControlsStart(id target, SEL play, SEL pause, SEL toggle, SEL next, SEL previous) {
    Class commandClass = NSClassFromString(@"MPRemoteCommandCenter");
    if (commandClass) {
        id center = [commandClass performSelector:NSSelectorFromString(@"sharedCommandCenter")];
        /* targets are added once; adding the same one twice would run a command twice */
        ExteriaRemoteControlsStop(target);
        ExteriaCommand(center, @"playCommand", target, play);
        ExteriaCommand(center, @"pauseCommand", target, pause);
        ExteriaCommand(center, @"togglePlayPauseCommand", target, toggle);
        ExteriaCommand(center, @"nextTrackCommand", target, next);
        ExteriaCommand(center, @"previousTrackCommand", target, previous);
        return;
    }
    /* before ios 7.1 the buttons come as events to the first responder, and the application delegate at the end of its chain */
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    ExteriaRemoteActive = YES;
    ExteriaWatchKeyboard();
    ExteriaRemoteControlsClaim();
}

void ExteriaRemoteControlsStop(id target) {
    Class commandClass = NSClassFromString(@"MPRemoteCommandCenter");
    if (commandClass) {
        id center = [commandClass performSelector:NSSelectorFromString(@"sharedCommandCenter")];
        for (NSString *name in [NSArray arrayWithObjects:@"playCommand", @"pauseCommand", @"togglePlayPauseCommand", @"nextTrackCommand", @"previousTrackCommand", nil]) {
            id command = [center valueForKey:name];
            [command performSelector:NSSelectorFromString(@"removeTarget:") withObject:target];
        }
        return;
    }
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    ExteriaRemoteActive = NO;
    [ExteriaRemoteResponderView resignFirstResponder];
    [ExteriaRemoteResponderView removeFromSuperview];
}
