#import "exteria_cleaning.h"

#import "exteria_platform.h"
#import "exteria_theme_busy_view.h"

#define STEP_SECONDS 1.0
#define DONE_SECONDS 0.9

@interface ExteriaCleaningStep () {
@public
    NSString *name;
    void (^work)(void);
}
@end

@implementation ExteriaCleaningStep

+ (ExteriaCleaningStep *)stepNamed:(NSString *)name work:(void (^)(void))work {
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

static void ExteriaCleaningStepAt(NSArray *steps, NSUInteger index, void (^done)(void)) {
    if (index >= steps.count) {
        ExteriaCleaningView.text = NSLocalizedString(@"cache.cleaned", nil);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DONE_SECONDS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ExteriaCleaningFinish(done); });
        return;
    }
    ExteriaCleaningStep *step = [steps objectAtIndex:index];
    ExteriaCleaningView.text = [NSString stringWithFormat:NSLocalizedString(@"cache.cleaning", nil), step->name];
    if (step->work) step->work();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(STEP_SECONDS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ExteriaCleaningStepAt(steps, index + 1, done); });
}

void ExteriaRunCleaning(NSArray *steps, void (^done)(void)) {
    UIView *window = ExteriaOverlayHost();
    if (!window || ExteriaCleaningRunning) {
        for (ExteriaCleaningStep *step in steps) if (step->work) step->work();
        if (done) done();
        return;
    }
    ExteriaCleaningRunning = YES;
    if (!ExteriaCleaningView) ExteriaCleaningView = [[ExteriaThemeBusyView alloc] initWithFrame:window.bounds animation:@"clear_cache"];
    ExteriaCleaningView.frame = window.bounds;
    ExteriaCleaningView.alpha = ExteriaReduceMotionEnabled() ? 1 : 0;
    [window addSubview:ExteriaCleaningView];
    [ExteriaCleaningView startAnimating];
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.22 animations:^{ ExteriaCleaningView.alpha = 1; }];
    NSArray *kept = [steps copy];
    void (^finished)(void) = [done copy];
    ExteriaCleaningStepAt(kept, 0, ^{
        if (finished) finished();
        [finished release];
        [kept release];
    });
}
