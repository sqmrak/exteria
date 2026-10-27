#import "exteria_article_controller.h"

#import <QuartzCore/QuartzCore.h>
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_tunnel_protocol.h"

BOOL ExteriaIsArticleURL(NSURL *url) {
    NSString *scheme = [url.scheme lowercaseString];
    NSString *host = [url.host lowercaseString];
    return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) &&
           ([host isEqualToString:@"telegra.ph"] || [host isEqualToString:@"www.telegra.ph"]);
}

@interface ExteriaArticleController : UIViewController <UIWebViewDelegate> {
    NSURL *_url;
    UIView *_dim;
    UIView *_card;
    UIWebView *_web;
    UIButton *_close;
    UILabel *_error;
    UIActivityIndicatorView *_spinner;
    UIButton *_retry;
    UIButton *_browser;
    BOOL _moving;
    BOOL _closing;
}
- (id)initWithURL:(NSURL *)url;
- (void)enter;
@end

void ExteriaPresentArticle(NSURL *url, UIViewController *host) {
    if (!ExteriaIsArticleURL(url) || !host) return;
    /* the page and its files load through the client of the app on every route: the tunnel when it is up (the site is blocked on the ordinary network), and a
       direct connection otherwise, which old systems cannot make with their own TLS */
    [ExteriaTunnelURLProtocol install];
    UIViewController *parent = host;
    while (parent.parentViewController) parent = parent.parentViewController;
    ExteriaArticleController *article = [[[ExteriaArticleController alloc] initWithURL:url] autorelease];
    [parent addChildViewController:article];
    article.view.frame = parent.view.bounds;
    [parent.view addSubview:article.view];
    [article didMoveToParentViewController:parent];
    [article enter];
}

@implementation ExteriaArticleController
- (id)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) _url = [url retain];
    return self;
}
- (void)dealloc {
    _web.delegate = nil;
    [_web stopLoading];
    [_url release];
    [_dim release];
    [_card release];
    [_web release];
    [_close release];
    [_error release];
    [_spinner release];
    [_retry release];
    [_browser release];
    [super dealloc];
}
- (void)loadView {
    UIView *root = [[[UIView alloc] init] autorelease];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    _dim = [[UIView alloc] init];
    _dim.backgroundColor = [UIColor blackColor];
    _dim.alpha = 0;
    [_dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)] autorelease]];
    [root addSubview:_dim];
    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.cornerRadius = 28;
    _card.clipsToBounds = YES;
    [root addSubview:_card];
    _close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_close setTitle:NSLocalizedString(@"shiro.close", nil) forState:UIControlStateNormal];
    [_close setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    _close.titleLabel.font = ExteriaFontMedium(14);
    [_close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:_close];
    _web = [[UIWebView alloc] init];
    _web.delegate = self;
    _web.scalesPageToFit = YES;
    /* article text disappears on a dark card, and an empty white page would hide the loading spinner */
    _web.opaque = YES;
    _web.backgroundColor = [UIColor whiteColor];
    _web.alpha = 0;
    [_card addSubview:_web];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:ExteriaThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [_card addSubview:_spinner];
    _retry = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _retry.titleLabel.font = ExteriaFontMedium(16);
    [_retry setTitle:NSLocalizedString(@"article.retry", nil) forState:UIControlStateNormal];
    [_retry setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(retry) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES;
    [_card addSubview:_retry];
    _browser = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _browser.titleLabel.font = ExteriaFontMedium(16);
    [_browser setTitle:NSLocalizedString(@"article.browser", nil) forState:UIControlStateNormal];
    [_browser setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_browser addTarget:self action:@selector(openInBrowser) forControlEvents:UIControlEventTouchUpInside];
    _browser.hidden = YES;
    [_card addSubview:_browser];
    _error = [[UILabel alloc] init];
    _error.backgroundColor = [UIColor clearColor];
    _error.textColor = ExteriaColorTitle();
    _error.font = ExteriaFontRegular(15);
    _error.textAlignment = ExteriaTextAlignmentCenter;
    _error.numberOfLines = 0;
    _error.hidden = YES;
    [_card addSubview:_error];
    [self load];
}
/* a page the network holds back says so after 25 seconds, instead of staying white for the minute the system waits */
- (void)load {
    _web.alpha = 0;
    _error.hidden = YES;
    _retry.hidden = YES;
    _browser.hidden = YES;
    [_spinner startAnimating];
    [_web loadRequest:[NSURLRequest requestWithURL:_url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:25]];
}
- (void)retry {
    [_web stopLoading];
    [self load];
}
- (void)openInBrowser {
    if (![[UIApplication sharedApplication] openURL:_url]) NSLog(@"exteria: the article %@ was not handed to the browser", _url);
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat width = ExteriaIsPad() ? MIN(size.width, 560) : size.width;
    CGFloat top = ExteriaIsPad() ? MAX(insets.top, 24) + 16 : MAX(insets.top, 0) + 28;
    _dim.frame = self.view.bounds;
    if (!_moving) _card.frame = CGRectMake(floor((size.width - width) / 2), top, width, size.height - top + 32);
    _close.frame = CGRectMake(16, 14, 90, 36);
    _web.frame = CGRectMake(0, 56, width, size.height - top - 56 - MAX(insets.bottom, 0));
    _error.frame = CGRectMake(24, _web.frame.origin.y + 24, width - 48, 120);
    _spinner.center = CGPointMake(width / 2, _web.frame.origin.y + 60);
    _retry.frame = CGRectMake(24, CGRectGetMaxY(_error.frame) + 4, width - 48, 44);
    _browser.frame = CGRectMake(24, CGRectGetMaxY(_retry.frame), width - 48, 44);
}
- (void)enter {
    [self.view layoutIfNeeded];
    CGRect rest = _card.frame;
    _moving = YES;
    _card.frame = CGRectOffset(rest, 0, self.view.bounds.size.height - rest.origin.y);
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _card.frame = rest;
        _dim.alpha = 0.45;
    } completion:^(BOOL finished) { (void)finished; _moving = NO; }];
}
- (void)close {
    if (_closing) return;
    _closing = YES;
    _moving = YES;
    [_web stopLoading];
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.3 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        _card.frame = CGRectOffset(_card.frame, 0, self.view.bounds.size.height - _card.frame.origin.y);
        _dim.alpha = 0;
    } completion:^(BOOL finished) {
        (void)finished;
        [self willMoveToParentViewController:nil];
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
    }];
}
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)type {
    (void)webView;
    (void)type;
    NSString *scheme = [request.URL.scheme lowercaseString];
    return [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"about"];
}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    (void)webView;
    if (_closing || ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled)) return;
    [_spinner stopAnimating];
    _error.text = [NSString stringWithFormat:@"%@\n%@", NSLocalizedString(@"article.failed", nil), [error localizedDescription]];
    _error.hidden = NO;
    _retry.hidden = NO;
    _browser.hidden = NO;
    NSLog(@"exteria: the article %@ did not load: %@ (%ld)", _url, error.domain, (long)error.code);
}
- (void)webViewDidFinishLoad:(UIWebView *)webView {
    (void)webView;
    [_spinner stopAnimating];
    _error.hidden = YES;
    /* how much text the page really holds, for the log: a page that loaded and shows nothing is told from one that holds nothing */
    NSString *length = [webView stringByEvaluatingJavaScriptFromString:@"document.body ? String(document.body.innerText.length) : '-1'"];
    NSLog(@"exteria: the article %@ loaded, %@ characters of text", _url, length);
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.2 animations:^{ _web.alpha = 1; }];
}
@end
