#import "exteria_message_report_flow.h"

#import "exteria_gift_screen.h"
#import "exteria_session_report.h"
#import "exteria_sheet.h"
#import "exteria_theme.h"

/* the alert with a text field starts at ios 5, which is the lowest this app runs on */
enum { ExteriaAlertStylePlainTextInput = 2 };

@interface ExteriaMessageReportFlow () <UIActionSheetDelegate> {
    NSArray *_ids;
    ExteriaDialog *_dialog;
    ExteriaSession *_session;
    UIViewController *_host;
    ExteriaMessageReportStep *_step;
}
@end

@implementation ExteriaMessageReportFlow

- (id)initWithIds:(NSArray *)ids dialog:(ExteriaDialog *)dialog session:(ExteriaSession *)session host:(UIViewController *)host {
    self = [super init];
    if (!self) return nil;
    _ids = [ids copy];
    _dialog = [dialog retain];
    _session = [session retain];
    _host = [host retain];
    return self;
}

- (void)dealloc {
    [_ids release];
    [_dialog release];
    [_session release];
    [_host release];
    [_step release];
    [super dealloc];
}

+ (void)startForMessageIds:(NSArray *)ids dialog:(ExteriaDialog *)dialog session:(ExteriaSession *)session host:(UIViewController *)host {
    if (!ids.count) return;
    /* the flow releases itself where the dialogue ends */
    ExteriaMessageReportFlow *flow = [[ExteriaMessageReportFlow alloc] initWithIds:ids dialog:dialog session:session host:host];
    [flow sendToken:nil comment:nil];
}

- (void)sendToken:(NSData *)token comment:(NSString *)comment {
    [_session reportMessageIds:_ids ofDialog:_dialog token:token comment:comment completion:^(ExteriaMessageReportStep *step, NSString *errorName) {
        if (!step) {
            NSLog(@"exteria: report of messages in %lld was not taken: %@", _dialog.peerId, errorName);
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            [self release];
            return;
        }
        [self show:step];
    }];
}

- (void)show:(ExteriaMessageReportStep *)step {
    [_step release];
    _step = [step retain];
    switch (step.kind) {
    case ExteriaMessageReportDone:
        ExteriaGiftAlert(nil, NSLocalizedString(@"report.sent", nil));
        [self release];
        return;
    case ExteriaMessageReportComment:
        [self askComment];
        return;
    case ExteriaMessageReportChoose:
        break;
    }
    if (!ExteriaThemeIsClassic() && _host.view) {
        [ExteriaSheet presentInView:_host.view title:step.title message:nil options:step.options destructive:nil
                        cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
            [self choose:(NSInteger)index];
        }];
        return;
    }
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:step.title delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSString *option in step.options) [sheet addButtonWithTitle:option];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:NSLocalizedString(@"picker.cancel", nil)];
    [sheet showInView:_host.view];
    [sheet release];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    [self choose:index == sheet.cancelButtonIndex ? -1 : index];
}

/* a negative index is a cancel, which ends the flow with nothing sent */
- (void)choose:(NSInteger)index {
    if (index < 0 || (NSUInteger)index >= _step.tokens.count) {
        [self release];
        return;
    }
    [self sendToken:[_step.tokens objectAtIndex:(NSUInteger)index] comment:nil];
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
    if (index == [alert cancelButtonIndex]) {
        [self release];
        return;
    }
    NSString *comment = [[[alert textFieldAtIndex:0] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    /* a comment the server insists on is asked for again when it is empty; one it only allows may stay empty */
    if (!comment.length && !_step.commentOptional) {
        [self askComment];
        return;
    }
    [self sendToken:_step.token comment:comment];
}

@end
