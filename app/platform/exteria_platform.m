#import "exteria_platform.h"

#import <dlfcn.h>

#include "exteria_column.h"

NSString *const ExteriaPadInterfaceKey = @"exteria.developer.padInterface";

NSString *const ExteriaPhoneInterfaceKey = @"exteria.developer.phoneInterface";

BOOL ExteriaIsPad(void) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:ExteriaPhoneInterfaceKey]) return NO;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:ExteriaPadInterfaceKey]) return YES;
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
}

CGFloat ExteriaScreenScale(void) {
    UIScreen *screen = [UIScreen mainScreen];
    return [screen respondsToSelector:@selector(scale)] ? screen.scale : 1.0;
}

/* these properties are absent from the armv7 sdk, so they are read through key value coding */
static CGFloat ExteriaGuideLength(UIViewController *controller, NSString *key) {
    if (![controller respondsToSelector:NSSelectorFromString(key)]) return 0;
    id guide = [controller valueForKey:key];
    return [[guide valueForKey:@"length"] doubleValue];
}

UIEdgeInsets ExteriaSafeInsets(UIView *view) {
    if (![view respondsToSelector:NSSelectorFromString(@"safeAreaInsets")]) return UIEdgeInsetsZero;
    return [[view valueForKey:@"safeAreaInsets"] UIEdgeInsetsValue];
}

void ExteriaScrollViewOwnsInsets(UIScrollView *scroll) {
    if (![scroll respondsToSelector:NSSelectorFromString(@"setContentInsetAdjustmentBehavior:")]) return;
    /* UIScrollViewContentInsetAdjustmentNever; the constant is absent from the armv7 sdk */
    [scroll setValue:[NSNumber numberWithInteger:2] forKey:@"contentInsetAdjustmentBehavior"];
}

void ExteriaTableUsesExactHeights(UITableView *table) {
    if (![table respondsToSelector:NSSelectorFromString(@"setEstimatedRowHeight:")]) return;
    [table setValue:[NSNumber numberWithDouble:0] forKey:@"estimatedRowHeight"];
    [table setValue:[NSNumber numberWithDouble:0] forKey:@"estimatedSectionHeaderHeight"];
    [table setValue:[NSNumber numberWithDouble:0] forKey:@"estimatedSectionFooterHeight"];
}

UIEdgeInsets ExteriaLayoutInsets(UIViewController *controller) {
    UIView *view = controller.view;
    if ([view respondsToSelector:NSSelectorFromString(@"safeAreaInsets")]) return ExteriaSafeInsets(view);
    CGFloat top = ExteriaGuideLength(controller, @"topLayoutGuide");
    UIWindow *window = view.window;
    if (window) {
        /* ios 5 has no guides, and ios 7 can pass the same status inset down nested containers */
        top = 0;
        if (![UIApplication sharedApplication].statusBarHidden) {
            CGRect status = [window convertRect:[UIApplication sharedApplication].statusBarFrame fromWindow:nil];
            CGRect overlap = CGRectIntersection(view.bounds, [view convertRect:status fromView:window]);
            if (!CGRectIsNull(overlap) && CGRectGetMinY(overlap) <= CGRectGetMinY(view.bounds)) top = overlap.size.height;
        }
        UINavigationController *navigation = controller.navigationController;
        if (navigation && !navigation.navigationBarHidden) {
            UINavigationBar *bar = navigation.navigationBar;
            CGRect overlap = CGRectIntersection(view.bounds, [view convertRect:bar.bounds fromView:bar]);
            if (!CGRectIsNull(overlap) && CGRectGetMinY(overlap) <= CGRectGetMinY(view.bounds) + top) {
                top = MAX(top, CGRectGetMaxY(overlap) - CGRectGetMinY(view.bounds));
            }
        }
    }
    return UIEdgeInsetsMake(top, 0, ExteriaGuideLength(controller, @"bottomLayoutGuide"), 0);
}

CGRect ExteriaContentColumn(CGSize size, UIEdgeInsets insets, CGFloat maxWidth) {
    exteria_column column;
    if (exteria_column_place(size.width, insets.left, insets.right, ExteriaIsPad() ? maxWidth : 0, &column) != EXTERIA_OK) {
        return CGRectMake(0, 0, size.width, size.height);
    }
    return CGRectMake((CGFloat)column.x, 0, (CGFloat)column.width, size.height);
}

BOOL ExteriaReduceMotionEnabled(void) {
    BOOL (*enabled)(void) = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "UIAccessibilityIsReduceMotionEnabled");
    return enabled ? enabled() : NO;
}

NSString *ExteriaReduceMotionChangedNotification(void) {
    NSString **name = (NSString **)dlsym(RTLD_DEFAULT, "UIAccessibilityReduceMotionStatusDidChangeNotification");
    return name ? *name : nil;
}

BOOL ExteriaAllowsOrientation(UIInterfaceOrientation orientation) {
    return ExteriaIsPad() || orientation != UIInterfaceOrientationPortraitUpsideDown;
}

NSUInteger ExteriaOrientationMask(void) {
    return ExteriaIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}


static BOOL ExteriaDefaultsPending;

static void ExteriaDefaultsSaveNow(void) {
    ExteriaDefaultsPending = NO;
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"exteria: the user defaults were not saved");
}

void ExteriaDefaultsSaveSoon(void) {
    static BOOL watching;
    if (!watching) {
        watching = YES;
        void (^flush)(NSNotification *) = ^(NSNotification *note) {
            (void)note;
            if (ExteriaDefaultsPending) ExteriaDefaultsSaveNow();
        };
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:flush];
        [center addObserverForName:UIApplicationWillTerminateNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:flush];
    }
    if (ExteriaDefaultsPending) return;
    ExteriaDefaultsPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (ExteriaDefaultsPending) ExteriaDefaultsSaveNow();
    });
}

UIView *ExteriaOverlayHost(void) {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top.view ? top.view : window;
}

CGFloat ExteriaStatusBarHeight(void) {
    CGRect frame = [UIApplication sharedApplication].statusBarFrame;
    return [UIApplication sharedApplication].statusBarHidden ? 0 : MIN(frame.size.width, frame.size.height);
}


/* ---- the status bar of the screens that cover the whole display ----
   each of them used to remember the state it found and put that back, so a screen that opened over another that had hidden the bar restored "hidden" for
   good, and the story camera never gave the bar back. the owners are counted instead: the bar is hidden while any owner is on screen, and shown when the
   last one lets go. an owner calls Show from dealloc too, so one that left without its disappear call cannot hold the bar */
static NSMutableSet *ExteriaStatusOwners(void) {
    static NSMutableSet *owners;
    if (!owners) owners = [[NSMutableSet alloc] init];
    return owners;
}

static void ExteriaStatusBarApply(BOOL hidden, UIStatusBarAnimation animation) {
    UIApplication *application = [UIApplication sharedApplication];
    if ([application respondsToSelector:@selector(setStatusBarHidden:withAnimation:)] && application.statusBarHidden != hidden)
        [application setStatusBarHidden:hidden withAnimation:animation];
}

void ExteriaStatusBarHide(id owner, UIStatusBarAnimation animation) {
    if (!owner) return;
    [ExteriaStatusOwners() addObject:[NSValue valueWithNonretainedObject:owner]];
    ExteriaStatusBarApply(YES, animation);
}

void ExteriaStatusBarShow(id owner, UIStatusBarAnimation animation) {
    if (!owner) return;
    NSMutableSet *owners = ExteriaStatusOwners();
    [owners removeObject:[NSValue valueWithNonretainedObject:owner]];
    if (!owners.count) ExteriaStatusBarApply(NO, animation);
}

void ExteriaStatusBarSettle(void) {
    NSMutableSet *owners = ExteriaStatusOwners();
    for (NSValue *held in [[owners copy] autorelease]) {
        id owner = [held nonretainedObjectValue];
        /* an owner whose screen is gone from the window no longer needs the bar hidden */
        BOOL shown = [owner isKindOfClass:[UIViewController class]] && [(UIViewController *)owner isViewLoaded] && [(UIViewController *)owner view].window;
        if (!shown) [owners removeObject:held];
    }
    if (!owners.count) ExteriaStatusBarApply(NO, UIStatusBarAnimationNone);
}


/* ---- the black under a viewer ----
   a viewer that lets its picture go translucent while it is pulled away shows whatever is under it, which for a screen over the whole display is the color of
   the window, light in the light themes. the window is black while a viewer is up, and the color comes back when the last one is gone */
static NSUInteger ExteriaBlackHolders;
static UIColor *ExteriaBlackSaved;

void ExteriaWindowBlackHold(void) {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;
    if (ExteriaBlackHolders++ == 0) {
        ExteriaBlackSaved = [window.backgroundColor retain];
        window.backgroundColor = [UIColor blackColor];
    }
}

void ExteriaWindowBlackRelease(void) {
    if (!ExteriaBlackHolders) return;
    if (--ExteriaBlackHolders == 0) {
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (window && ExteriaBlackSaved) window.backgroundColor = ExteriaBlackSaved;
        [ExteriaBlackSaved release];
        ExteriaBlackSaved = nil;
    }
}
