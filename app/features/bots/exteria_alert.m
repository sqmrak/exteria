#import "exteria_platform.h"
#import "exteria_alert.h"

#import <UIKit/UIKit.h>

/* holds the alert and its block until the alert is gone; UIAlertView keeps its delegate unretained */
@interface ExteriaAlertTarget : NSObject <UIAlertViewDelegate, UIActionSheetDelegate> {
@public
    ExteriaAlertHandler handler;
    void (^sheetHandler)(NSInteger index);
    NSInteger cancelIndex;
    BOOL secure;
    BOOL plainInput;
    BOOL done;
    NSInteger choiceCount;
}
@end

@implementation ExteriaAlertTarget

- (void)dealloc {
    [handler release];
    [sheetHandler release];
    [super dealloc];
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
    if (done) return;
    done = YES;
    NSString *text = (secure || plainInput) ? [alert textFieldAtIndex:0].text : nil;
    if (handler) handler(index, text);
}

- (void)alertViewCancel:(UIAlertView *)alert {
    (void)alert;
    if (done) return;
    done = YES;
    if (handler) handler(cancelIndex, nil);
}

- (void)alertView:(UIAlertView *)alert didDismissWithButtonIndex:(NSInteger)index {
    (void)alert;
    (void)index;
    [self autorelease];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    (void)sheet;
    if (done) return;
    done = YES;
    /* the cancel button is the last one, and the choices before it are what the caller counts */
    if (index >= 0 && index < choiceCount && sheetHandler) sheetHandler(index);
}

- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index {
    (void)sheet;
    (void)index;
    [self autorelease];
}

@end

/* style: 0 none, 1 secure field, 2 plain field with initial and placeholder */
static void ExteriaPresentAlert(NSString *title, NSString *message, NSArray *buttons, NSInteger cancelIndex, int style, NSString *initial, NSString *placeholder,
                                ExteriaAlertHandler handler) {
    Class alertClass = NSClassFromString(@"UIAlertView");
    ExteriaAlertTarget *target = [[ExteriaAlertTarget alloc] init];
    target->handler = [handler copy];
    target->cancelIndex = cancelIndex;
    target->secure = style == 1;
    target->plainInput = style == 2;
    id alert = [[alertClass alloc] initWithTitle:title message:message delegate:target cancelButtonTitle:nil otherButtonTitles:nil];
    for (NSString *button in buttons) [alert addButtonWithTitle:button];
    if (cancelIndex >= 0 && cancelIndex < (NSInteger)buttons.count) [alert setCancelButtonIndex:cancelIndex];
    if (style == 1) [alert setAlertViewStyle:UIAlertViewStyleSecureTextInput];
    if (style == 2) {
        [alert setAlertViewStyle:UIAlertViewStylePlainTextInput];
        UITextField *field = [alert textFieldAtIndex:0];
        field.text = initial;
        field.placeholder = placeholder;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }
    [alert show];
    [alert release];
}

void ExteriaShowAlert(NSString *title, NSString *message, NSArray *buttons, NSInteger cancelIndex, BOOL secure, ExteriaAlertHandler handler) {
    ExteriaPresentAlert(title, message, buttons, cancelIndex, secure ? 1 : 0, nil, nil, handler);
}

void ExteriaPromptText(NSString *title, NSString *message, NSString *initial, NSString *placeholder, void (^handler)(NSString *text)) {
    void (^done)(NSString *) = [handler copy];
    ExteriaPresentAlert(title, message, [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"tr.ok", nil), nil], 0, 2, initial, placeholder,
                        ^(NSInteger index, NSString *text) {
        if (index == 1 && done) done(text ? text : @"");
        [done release];
    });
}

void ExteriaPromptTextOrCancel(NSString *title, NSString *message, NSString *initial, NSString *placeholder, void (^handler)(NSString *text), void (^cancelled)(void)) {
    void (^done)(NSString *) = [handler copy];
    void (^turnedDown)(void) = [cancelled copy];
    ExteriaPresentAlert(title, message, [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"tr.ok", nil), nil], 0, 2, initial, placeholder,
                        ^(NSInteger index, NSString *text) {
        if (index == 1) {
            if (done) done(text ? text : @"");
        } else if (turnedDown) {
            turnedDown();
        }
        [done release];
        [turnedDown release];
    });
}

void ExteriaShowNotice(NSString *title, NSString *message) {
    ExteriaShowAlert(title, message, [NSArray arrayWithObject:NSLocalizedString(@"notice.ok", nil)], 0, NO, nil);
}

void ExteriaConfirm(NSString *title, NSString *message, NSString *confirmTitle, void (^handler)(void)) {
    void (^action)(void) = [handler copy];
    ExteriaShowAlert(title, message, [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), confirmTitle, nil], 0, NO,
                     ^(NSInteger index, NSString *text) {
        (void)text;
        if (index == 1 && action) action();
        [action release];
    });
}

void ExteriaChoose(NSString *title, NSArray *choices, NSInteger destructiveIndex, void (^handler)(NSInteger index)) {
    Class sheetClass = NSClassFromString(@"UIActionSheet");
    ExteriaAlertTarget *target = [[ExteriaAlertTarget alloc] init];
    target->sheetHandler = [handler copy];
    target->choiceCount = (NSInteger)choices.count;
    id sheet = [[sheetClass alloc] initWithTitle:title delegate:target cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSString *choice in choices) [sheet addButtonWithTitle:choice];
    [sheet addButtonWithTitle:NSLocalizedString(@"picker.cancel", nil)];
    [sheet setCancelButtonIndex:(NSInteger)choices.count];
    if (destructiveIndex >= 0 && destructiveIndex < (NSInteger)choices.count) [sheet setDestructiveButtonIndex:destructiveIndex];
    /* the view of the top controller turns with the screen and stays above a screen presented over the root */
    [sheet showInView:ExteriaOverlayHost()];
    [sheet release];
}
