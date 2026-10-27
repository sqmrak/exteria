#import "exteria_passcode_flow_controller.h"

#import "exteria_passcode_entry_view.h"
#import "exteria_passcode_store.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

@interface ExteriaPasscodeFlowController () {
    ExteriaPasscodeFlowMode _mode;
    void (^_completion)(BOOL done);
    ExteriaPasscodeEntryView *_entry;
    UIButton *_cancel;
    UIButton *_options;
    /* the first typing of a new code, until the second one confirms it */
    NSString *_first;
    exteria_passcode_type _chosen;
    BOOL _finished;
}
@end

@implementation ExteriaPasscodeFlowController

- (id)initWithMode:(ExteriaPasscodeFlowMode)mode completion:(void (^)(BOOL))completion {
    self = [super init];
    if (!self) return nil;
    _mode = mode;
    _completion = [completion copy];
    _chosen = mode == ExteriaPasscodeFlowVerify ? ExteriaPasscodeType() : EXTERIA_PASSCODE_PIN;
    return self;
}

- (void)dealloc {
    [_completion release];
    [_entry release];
    [_cancel release];
    [_options release];
    [_first release];
    [super dealloc];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = ExteriaColorScreen();
    self.view = root;
    _entry = [[ExteriaPasscodeEntryView alloc] initWithFrame:root.bounds];
    _entry.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _entry.type = _chosen;
    ExteriaPasscodeFlowController *flow = self;
    _entry.submit = ^(NSString *code) { [flow codeEntered:code]; };
    [root addSubview:_entry];
    _cancel = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_cancel setTitle:NSLocalizedString(@"passcode.cancel", nil) forState:UIControlStateNormal];
    [_cancel setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    _cancel.titleLabel.font = ExteriaFontRegular(17);
    _cancel.frame = CGRectMake(8, 22, 92, 44);
    _cancel.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    _cancel.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
    [_cancel addTarget:self action:@selector(cancelPressed) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_cancel];
    if (_mode == ExteriaPasscodeFlowSetup) {
        _options = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        [_options setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
        _options.titleLabel.font = ExteriaFontRegular(16);
        _options.frame = CGRectMake(self.view.bounds.size.width - 188, 22, 180, 44);
        _options.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        _options.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
        _options.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 8);
        [_options addTarget:self action:@selector(switchType) forControlEvents:UIControlEventTouchUpInside];
        [root addSubview:_options];
    }
    [self showStep];
}

/* the buttons sit right under the status bar (nothing in landscape on ios 7 and later), and the words start below them */
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat barTop = ExteriaStatusBarHeight();
    CGFloat width = self.view.bounds.size.width;
    _cancel.frame = CGRectMake(8, barTop, 92, 44);
    _options.frame = CGRectMake(width - 188, barTop, 180, 44);
    if (_entry.topInset != barTop + 44) {
        _entry.topInset = barTop + 44;
        [_entry setNeedsLayout];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_entry focus];
    if (_mode == ExteriaPasscodeFlowVerify) [_entry holdForSeconds:ExteriaPasscodeWaitRemaining()];
}

- (void)showStep {
    _entry.type = _chosen;
    _options.hidden = _first != nil;
    [_options setTitle:NSLocalizedString(_chosen == EXTERIA_PASSCODE_PIN ? @"passcode.to.password" : @"passcode.to.pin", nil) forState:UIControlStateNormal];
    if (_mode == ExteriaPasscodeFlowVerify) {
        _entry.title = NSLocalizedString(@"passcode.enter", nil);
        return;
    }
    _entry.title = NSLocalizedString(_first ? @"passcode.confirm" : @"passcode.new", nil);
    if (!_first) _entry.message = NSLocalizedString(_chosen == EXTERIA_PASSCODE_PIN ? @"passcode.new.pin.info" : @"passcode.new.password.info", nil);
}

- (void)switchType {
    _chosen = _chosen == EXTERIA_PASSCODE_PIN ? EXTERIA_PASSCODE_PASSWORD : EXTERIA_PASSCODE_PIN;
    [self showStep];
    [_entry focus];
}

- (void)cancelPressed {
    [self finish:NO];
}

- (void)finish:(BOOL)done {
    if (_finished) return;
    _finished = YES;
    [_entry resignFirstResponder];
    void (^completion)(BOOL) = [_completion retain];
    [self dismissViewControllerAnimated:YES completion:^{
        if (completion) completion(done);
        [completion release];
    }];
}

- (void)codeEntered:(NSString *)code {
    if (_mode == ExteriaPasscodeFlowVerify) {
        NSUInteger wait = 0;
        ExteriaPasscodeResult result = ExteriaPasscodeCheck(code, &wait);
        if (result == ExteriaPasscodeResultOK) {
            [self finish:YES];
            return;
        }
        [_entry rejectCode];
        _entry.message = result == ExteriaPasscodeResultWrong ? NSLocalizedString(@"passcode.wrong", nil) : nil;
        [_entry holdForSeconds:wait];
        return;
    }
    NSData *bytes = [code dataUsingEncoding:NSUTF8StringEncoding];
    if (!bytes || !exteria_passcode_valid(_chosen, bytes.bytes, bytes.length)) {
        [_entry rejectCode];
        _entry.message = NSLocalizedString(@"passcode.invalid", nil);
        return;
    }
    if (!_first) {
        _first = [code copy];
        [_entry reset];
        _entry.message = nil;
        [self showStep];
        [_entry focus];
        return;
    }
    if (![_first isEqualToString:code]) {
        [_first release];
        _first = nil;
        [self showStep];
        [_entry rejectCode];
        _entry.message = NSLocalizedString(@"passcode.mismatch", nil);
        return;
    }
    if (!ExteriaPasscodeSet(_chosen, code)) {
        [_first release];
        _first = nil;
        [self showStep];
        [_entry rejectCode];
        _entry.message = NSLocalizedString(@"passcode.failed", nil);
        return;
    }
    [self finish:YES];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

- (BOOL)shouldAutorotate {
    return YES;
}

/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations {
    return ExteriaOrientationMask();
}
#pragma clang diagnostic pop

@end
