#import "exteria_cleaning.h"

#import "exteria_platform.h"
#import "exteria_theme_busy_view.h"

#define STEP_SECONDS 1.0
#define DONE_SECONDS 0.9

@interface ExteriaCleaningStep () {
@public
    NSString *name;
    void (^work)(void (^finished)(BOOL));
}
@end

@implementation ExteriaCleaningStep

+ (ExteriaCleaningStep *)stepNamed:(NSString *)name work:(void (^)(void))work {
    ExteriaCleaningStep *step = [[[ExteriaCleaningStep alloc] init] autorelease];
    step->name = [name copy];
    step->work = [^(void (^finished)(BOOL)) { if (work) work(); finished(YES); } copy];
    return step;
}

+ (ExteriaCleaningStep *)stepNamed:(NSString *)name asyncWork:(void (^)(void (^)(BOOL)))work {
    ExteriaCleaningStep *step = [[[ExteriaCleaningStep alloc] init] autorelease];
    step->name = [name copy];
    step->work = [work copy];
    return step;
}

- (void)dealloc {
    [name release];
    [work release];
    [super dealloc];
}

@end

/* the view is kept for the next cleaning, with its animation parsed */
static ExteriaThemeBusyView *ExteriaCleaningView;
static BOOL ExteriaCleaningRunning;

static void ExteriaCleaningFinish(void (^done)(void)) {
    ExteriaThemeBusyView *view = ExteriaCleaningView;
    BOOL still = ExteriaReduceMotionEnabled();
    [UIView animateWithDuration:still ? 0 : 0.3 animations:^{ view.alpha = 0; } completion:^(BOOL finished) {
        (void)finished;
        [view stopAnimating];
        [view removeFromSuperview];
        ExteriaCleaningRunning = NO;
        if (done) done();
    }];
}

static void ExteriaCleaningStepAt(NSArray *steps, NSUInteger index, BOOL success, void (^done)(void)) {
    if (index >= steps.count) {
        ExteriaCleaningView.text = NSLocalizedString(success ? @"cache.cleaned" : @"cache.clean.failed", nil);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DONE_SECONDS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ExteriaCleaningFinish(done); });
        return;
    }
    ExteriaCleaningStep *step = [steps objectAtIndex:index];
    ExteriaCleaningView.text = [NSString stringWithFormat:NSLocalizedString(@"cache.cleaning", nil), step->name];
    void (^next)(BOOL) = ^(BOOL ok) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(STEP_SECONDS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ExteriaCleaningStepAt(steps, index + 1, success && ok, done); });
    };
    if (step->work) step->work(next);
    else next(NO);
}

void ExteriaRunCleaning(NSArray *steps, void (^done)(void)) {
    UIView *window = ExteriaOverlayHost();
    if (ExteriaCleaningRunning) return;
    ExteriaCleaningRunning = YES;
    if (window) {
        if (!ExteriaCleaningView) ExteriaCleaningView = [[ExteriaThemeBusyView alloc] initWithFrame:window.bounds animation:@"clear_cache"];
        ExteriaCleaningView.frame = window.bounds;
        ExteriaCleaningView.alpha = ExteriaReduceMotionEnabled() ? 1 : 0;
        [window addSubview:ExteriaCleaningView];
        [ExteriaCleaningView startAnimating];
        [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.22 animations:^{ ExteriaCleaningView.alpha = 1; }];
    }
    NSArray *kept = [steps copy];
    void (^finished)(void) = [done copy];
    ExteriaCleaningStepAt(kept, 0, YES, ^{
        if (finished) finished();
        [finished release];
        [kept release];
    });
}
