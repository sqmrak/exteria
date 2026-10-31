#import "exteria_imported_theme_preview_controller.h"

#import "exteria_alert.h"
#import "exteria_chat_preview_view.h"
#import "exteria_imported_theme.h"
#import "exteria_theme.h"

@interface ExteriaImportedThemePreviewController () {
    NSURL *_url;
    NSString *_themeName;
    BOOL _dark;
    ExteriaChatPreviewView *_preview;
}
@end

@implementation ExteriaImportedThemePreviewController

+ (void)openURL:(NSURL *)url fromController:(UIViewController *)controller {
    if (controller.presentedViewController) {
        ExteriaShowNotice(NSLocalizedString(@"theme.import.title", nil), NSLocalizedString(@"theme.import.busy", nil));
        return;
    }
    BOOL dark = NO;
    NSString *name = nil;
    NSString *error = ExteriaImportedThemeCheck(url, &dark, &name);
    if (error) { ExteriaShowNotice(NSLocalizedString(@"theme.import.title", nil), error); return; }
    ExteriaThemeApply(dark);
    error = ExteriaImportedThemeBeginPreview(url);
    if (error) { ExteriaThemeApplyStored(); ExteriaShowNotice(NSLocalizedString(@"theme.import.title", nil), error); return; }
    ExteriaImportedThemePreviewController *preview = [[[ExteriaImportedThemePreviewController alloc] initWithURL:url name:name dark:dark] autorelease];
    [controller presentViewController:preview animated:YES completion:nil];
}

- (id)initWithURL:(NSURL *)url name:(NSString *)name dark:(BOOL)dark {
    self = [super init];
    if (!self) return nil;
    _url = [url retain];
    _themeName = [name copy];
    _dark = dark;
    self.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    return self;
}

- (void)dealloc {
    [_url release];
    [_themeName release];
    [_preview release];
    [super dealloc];
}

- (void)loadView {
    UIView *view = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.backgroundColor = ExteriaColorScreen();
    self.view = view;
    UILabel *title = [[[UILabel alloc] init] autorelease];
    title.text = _themeName;
    title.textColor = ExteriaColorTitle();
    title.backgroundColor = [UIColor clearColor];
    title.font = ExteriaFontSemibold(20);
    title.textAlignment = ExteriaTextAlignmentCenter;
    title.adjustsFontSizeToFitWidth = YES;
    title.tag = 1;
    [view addSubview:title];
    UILabel *tone = [[[UILabel alloc] init] autorelease];
    tone.text = NSLocalizedString(_dark ? @"theme.import.preview.night" : @"theme.import.preview.day", nil);
    tone.textColor = ExteriaColorSecondary();
    tone.backgroundColor = [UIColor clearColor];
    tone.font = ExteriaFontRegular(13);
    tone.textAlignment = ExteriaTextAlignmentCenter;
    tone.numberOfLines = 2;
    tone.tag = 2;
    [view addSubview:tone];
    _preview = [[ExteriaChatPreviewView alloc] init];
    [view addSubview:_preview];
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [cancel setTitle:NSLocalizedString(@"notice.cancel", nil) forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    cancel.tag = 3;
    [view addSubview:cancel];
    UIButton *apply = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [apply setTitle:NSLocalizedString(@"theme.import.apply", nil) forState:UIControlStateNormal];
    [apply addTarget:self action:@selector(apply) forControlEvents:UIControlEventTouchUpInside];
    apply.tag = 4;
    [view addSubview:apply];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat width = MIN(bounds.size.width - 32, 440);
    CGFloat x = (bounds.size.width - width) / 2;
    CGFloat top = 36;
    [[self.view viewWithTag:1] setFrame:CGRectMake(x, top, width, 32)];
    [[self.view viewWithTag:2] setFrame:CGRectMake(x, top + 36, width, 42)];
    CGFloat bottom = MAX(top + 100, bounds.size.height - 64);
    CGFloat height = MIN([_preview heightForWidth:width], bottom - top - 108);
    _preview.frame = CGRectMake(x, top + 86, width, MAX(height, 0));
    [[self.view viewWithTag:3] setFrame:CGRectMake(x, bottom, width / 2, 44)];
    [[self.view viewWithTag:4] setFrame:CGRectMake(x + width / 2, bottom, width / 2, 44)];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:^{
        ExteriaThemeApplyStored();
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaThemeDidChangeNotification object:nil];
    }];
}

- (void)apply {
    NSString *error = ExteriaImportedThemeInstall(_url, _dark);
    if (error) { ExteriaShowNotice(NSLocalizedString(@"theme.import.title", nil), error); return; }
    ExteriaThemeStoreClassic(NO);
    ExteriaThemeStoreDark(_dark);
    [self dismissViewControllerAnimated:YES completion:^{
        ExteriaThemeApplyStored();
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaThemeDidChangeNotification object:nil];
    }];
}

@end
