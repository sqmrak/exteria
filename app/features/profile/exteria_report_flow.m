#import "exteria_report_flow.h"

#import "exteria_gift_screen.h"
#import "exteria_sheet.h"
#import "exteria_theme.h"
#import "exteria_session_report.h"

/* the alert with a text field starts at ios 5, which is the lowest this app runs on */
enum { ExteriaAlertStylePlainTextInput = 2 };

@interface ExteriaReportFlow () <UIActionSheetDelegate> {
    ExteriaDialog *_dialog;
    ExteriaSession *_session;
    void (^_done)(void);
}
@end

@implementation ExteriaReportFlow

static NSString *const ExteriaReportReasonKeys[EXTERIA_REPORT_REASON_COUNT] = {
    @"report.reason.spam", @"report.reason.violence", @"report.reason.pornography", @"report.reason.childabuse",
    @"report.reason.copyright", @"report.reason.drugs", @"report.reason.personal", @"report.reason.other",
};

- (id)initWithDialog:(ExteriaDialog *)dialog session:(ExteriaSession *)session done:(void (^)(void))done {
    self = [super init];
    if (!self) return nil;
    _dialog = [dialog retain];
    _session = [session retain];
    _done = [done copy];
    return self;
}

- (void)dealloc {
    [_dialog release];
    [_session release];
    [_done release];
    [super dealloc];
}

+ (void)startForDialog:(ExteriaDialog *)dialog session:(ExteriaSession *)session host:(UIViewController *)host done:(void (^)(void))done {
    NSMutableArray *reasons = [NSMutableArray arrayWithCapacity:EXTERIA_REPORT_REASON_COUNT];
    for (int reason = 0; reason < EXTERIA_REPORT_REASON_COUNT; ++reason) [reasons addObject:NSLocalizedString(ExteriaReportReasonKeys[reason], nil)];
    if (!ExteriaThemeIsClassic() && host.view) {
        /* the modern style lists the reasons on a sheet; the flow exists once one is picked, so a cancel leaves nothing behind */
        [ExteriaSheet presentInView:host.view title:NSLocalizedString(@"report.title", nil) message:nil options:reasons destructive:nil
                        cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
            ExteriaReportFlow *flow = [[ExteriaReportFlow alloc] initWithDialog:dialog session:session done:done];
            [flow choseReason:(NSInteger)index];
        }];
        return;
    }
    ExteriaReportFlow *flow = [[ExteriaReportFlow alloc] initWithDialog:dialog session:session done:done];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"report.title", nil) delegate:flow cancelButtonTitle:nil
                                              destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSString *title in reasons) [sheet addButtonWithTitle:title];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:NSLocalizedString(@"picker.cancel", nil)];
    [sheet showInView:host.view];
    [sheet release];
    /* the sheet only borrows its delegate; the flow lives on until the last answer and releases itself there */
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index == sheet.cancelButtonIndex) {
        [self release];
        return;
    }
    [self choseReason:index];
}

/* a reason was picked from either list; "other" asks for a line first */
- (void)choseReason:(NSInteger)index {
    if (index < 0 || index >= EXTERIA_REPORT_REASON_COUNT) {
        [self release];
        return;
    }
    if (index != EXTERIA_REPORT_OTHER) {
        [self sendReason:(exteria_report_reason)index comment:nil];
        return;
    }
    [self askComment];
}

- (void)askComment {
    Class alertClass = NSClassFromString(@"UIAlertView");
    id alert = [[alertClass alloc] initWithTitle:NSLocalizedString(@"report.comment", nil) message:nil delegate:self
                               cancelButtonTitle:NSLocalizedString(@"picker.cancel", nil) otherButtonTitles:NSLocalizedString(@"report.send", nil), nil];
    [alert setAlertViewStyle:ExteriaAlertStylePlainTextInput];
    [alert show];
    [alert release];
}

/* the alert view has no protocol declared here, because UIAlertView is looked up by name */
- (void)alertView:(id)alert clickedButtonAtIndex:(NSInteger)index {
    NSString *comment = [[[alert textFieldAtIndex:0] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (index == [alert cancelButtonIndex]) {
        [self release];
        return;
    }
    /* the server rejects "other" with nothing to read, so an empty line asks again instead of sending */
    if (!comment.length) {
        [self askComment];
        return;
    }
    [self sendReason:EXTERIA_REPORT_OTHER comment:comment];
}

- (void)sendReason:(exteria_report_reason)reason comment:(NSString *)comment {
    [_session reportDialog:_dialog reason:reason comment:comment completion:^(NSString *errorName) {
        if (errorName) {
            NSLog(@"exteria: report of %lld was not taken: %@", _dialog.peerId, errorName);
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
        } else {
            ExteriaGiftAlert(nil, NSLocalizedString(@"report.sent", nil));
            if (_done) _done();
        }
        [self release];
    }];
}

@end
