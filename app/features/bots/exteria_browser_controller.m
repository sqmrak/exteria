#import "exteria_browser_controller.h"

#import <QuartzCore/QuartzCore.h>
#import "exteria_animation.h"
#import "exteria_dismiss_pan.h"
#import "exteria_platform.h"
#import "exteria_sheet.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_tunnel_protocol.h"
#import "exteria_weak_reference.h"

BOOL ExteriaIsWebURL(NSURL *url) {
    NSString *scheme = [url.scheme lowercaseString];
    return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) && url.host.length;
}

static BOOL ExteriaIsArticleURL(NSURL *url) {
    NSString *scheme = [url.scheme lowercaseString];
    NSString *host = [url.host lowercaseString];
    return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) &&
           ([host isEqualToString:@"telegra.ph"] || [host isEqualToString:@"www.telegra.ph"]);
}

@interface ExteriaBrowserController : UIViewController <UIWebViewDelegate, ExteriaDismissPanGuard> {
    NSURL *_url;
    /* the address of the page on screen, which the menu copies and a retry loads again */
    NSURL *_current;
    /* telegra.ph loads through the app's client; every other address goes to the web view as it is */
    BOOL _article;
    UIView *_dim;
    UIView *_card;
    UIView *_handle;
    UILabel *_pageTitle;
    UILabel *_hostLabel;
    UIButton *_more;
    UIWebView *_web;
    UIButton *_close;
    UILabel *_error;
    UIActivityIndicatorView *_spinner;
    UIButton *_retry;
    UIButton *_browser;
    BOOL _closing;
    ExteriaArticleLoad *_load;
    ExteriaWeakReference *_weak;
    NSUInteger _loadToken;
}
- (id)initWithURL:(NSURL *)url;
- (void)enter;
@end

void ExteriaPresentBrowser(NSURL *url, UIViewController *host) {
    if (!ExteriaIsWebURL(url) || !host) return;
    /* telegra.ph and its files load through the client of the app on every route: the tunnel when it is up (the site is blocked on the ordinary network), and a
       direct connection otherwise, which old systems cannot make with their own TLS */
    [ExteriaTunnelURLProtocol install];
    UIViewController *parent = host;
    while (parent.parentViewController) parent = parent.parentViewController;
    ExteriaBrowserController *browser = [[[ExteriaBrowserController alloc] initWithURL:url] autorelease];
    [parent addChildViewController:browser];
    browser.view.frame = parent.view.bounds;
    [parent.view addSubview:browser.view];
    [browser didMoveToParentViewController:parent];
    [browser enter];
}

@implementation ExteriaBrowserController
- (id)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _article = ExteriaIsArticleURL(url);
        NSString *address = url.absoluteString;
        _url = [(_article && [[url.scheme lowercaseString] isEqualToString:@"http"]) ? [NSURL URLWithString:[@"https:" stringByAppendingString:[address substringFromIndex:5]]] : url retain];
        _current = [_url retain];
        _weak = [[ExteriaWeakReference referenceTo:self] retain];
    }
    return self;
}
- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_weak clear];
    [_weak release];
    [_load cancel];
    [_load release];
    _web.delegate = nil;
    [_web stopLoading];
    [_url release];
    [_current release];
    [_dim release];
    [_card release];
    [_handle release];
    [_pageTitle release];
    [_hostLabel release];
    [_more release];
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
    /* the corners round the card's own color and nothing is clipped: a clipping mask over a web view is drawn off screen again on every frame of
       the slide, and the slide stuttered; the page starts below the corners */
    _card.layer.cornerRadius = 28;
    _card.clipsToBounds = NO;
    [root addSubview:_card];
    ExteriaAddDismissPan(_card, self, @selector(close));
    _handle = [[UIView alloc] init];
    _handle.backgroundColor = [ExteriaColorSecondary() colorWithAlphaComponent:0.4];
    _handle.layer.cornerRadius = 2;
    [_card addSubview:_handle];
    _close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_close setImage:ExteriaSymbolImage(ExteriaSymbolClose, 20, ExteriaColorAccent()) forState:UIControlStateNormal];
    _close.accessibilityLabel = NSLocalizedString(@"shiro.close", nil);
    [_close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:_close];
    _pageTitle = [[UILabel alloc] init];
    _pageTitle.backgroundColor = [UIColor clearColor];
    _pageTitle.textColor = ExteriaColorTitle();
    _pageTitle.font = ExteriaFontSemibold(15);
    _pageTitle.textAlignment = ExteriaTextAlignmentCenter;
    _pageTitle.text = NSLocalizedString(@"browser.untitled", nil);
    [_card addSubview:_pageTitle];
    _hostLabel = [[UILabel alloc] init];
    _hostLabel.backgroundColor = [UIColor clearColor];
    _hostLabel.textColor = ExteriaColorSecondary();
    _hostLabel.font = ExteriaFontRegular(12);
    _hostLabel.textAlignment = ExteriaTextAlignmentCenter;
    _hostLabel.text = _url.host;
    [_card addSubview:_hostLabel];
    _more = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_more setImage:ExteriaSymbolImage(ExteriaSymbolEllipsis, 22, ExteriaColorAccent()) forState:UIControlStateNormal];
    [_more addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:_more];
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
- (void)load {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadTimedOut) object:nil];
    [_load cancel];
    [_load release];
    _load = nil;
    NSUInteger token = ++_loadToken;
    _error.hidden = YES;
    _retry.hidden = YES;
    _browser.hidden = YES;
    [_spinner startAnimating];
    if (!_article) {
        _web.alpha = 1;
        [_web loadRequest:[NSURLRequest requestWithURL:_current cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30]];
        return;
    }
    /* a page the network holds back says so after 30 seconds, instead of staying white for the minute the system waits */
    _load = [[ExteriaArticleLoad alloc] init];
    _web.alpha = 0;
    [self performSelector:@selector(loadTimedOut) withObject:nil afterDelay:30];
    ExteriaWeakReference *weak = _weak;
    [_load startURL:_url completion:^(NSData *html, NSURL *address, NSString *error) {
        ExteriaBrowserController *browser = weak.target;
        if (!browser || browser->_closing || token != browser->_loadToken) return;
        if (!html) {
            NSLog(@"exteria: article %@ failed: %@", address, error);
            [browser showFailure:error];
            return;
        }
        [NSObject cancelPreviousPerformRequestsWithTarget:browser selector:@selector(loadTimedOut) object:nil];
        [browser->_spinner stopAnimating];
        browser->_web.alpha = 1;
        [browser->_web loadData:html MIMEType:@"text/html" textEncodingName:@"UTF-8" baseURL:address];
    }];
}
- (void)retry {
    [_web stopLoading];
    [self load];
}
- (void)showFailure:(NSString *)reason {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadTimedOut) object:nil];
    [_spinner stopAnimating];
    _web.alpha = 0;
    _error.text = [NSString stringWithFormat:@"%@\n%@", NSLocalizedString(@"article.failed", nil), reason ? reason : @""];
    _error.hidden = NO;
    _retry.hidden = NO;
    _browser.hidden = NO;
}
- (void)loadTimedOut {
    ++_loadToken;
    [_load cancel];
    [_web stopLoading];
    [self showFailure:NSLocalizedString(@"error.offline", nil)];
}
- (void)openInBrowser {
    if (![[UIApplication sharedApplication] openURL:_current]) NSLog(@"exteria: the page %@ was not handed to the browser", _current);
}
/* the options are the ones that apply now: a page with nothing behind it has no back */
- (void)showMenu {
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *actions = [NSMutableArray array];
    if (_web.canGoBack) { [titles addObject:NSLocalizedString(@"browser.back", nil)]; [actions addObject:NSStringFromSelector(@selector(goBack))]; }
    if (_web.canGoForward) { [titles addObject:NSLocalizedString(@"browser.forward", nil)]; [actions addObject:NSStringFromSelector(@selector(goForward))]; }
    [titles addObject:NSLocalizedString(@"browser.reload", nil)];
    [actions addObject:NSStringFromSelector(@selector(retry))];
    [titles addObject:NSLocalizedString(@"browser.copy", nil)];
    [actions addObject:NSStringFromSelector(@selector(copyAddress))];
    [titles addObject:NSLocalizedString(@"browser.safari", nil)];
    [actions addObject:NSStringFromSelector(@selector(openInBrowser))];
    ExteriaWeakReference *weak = _weak;
    [ExteriaSheet presentInView:self.view title:_current.host message:nil options:titles destructive:nil cancelTitle:NSLocalizedString(@"shiro.close", nil)
                        handler:^(NSUInteger index) {
        ExteriaBrowserController *browser = weak.target;
        if (!browser || browser->_closing || index >= actions.count) return;
        [browser performSelector:NSSelectorFromString([actions objectAtIndex:index])];
    }];
}
- (void)goBack { [_web goBack]; }
- (void)goForward { [_web goForward]; }
- (void)copyAddress {
    [UIPasteboard generalPasteboard].string = _current.absoluteString;
}
- (BOOL)exteriaCanDismissByPan {
    return !_closing;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat width = ExteriaIsPad() ? MIN(size.width, 560) : size.width;
    CGFloat top = ExteriaIsPad() ? MAX(insets.top, 24) + 16 : MAX(insets.top, 0) + 28;
    _dim.frame = self.view.bounds;
    /* the pull and the animations move the card by its transform, and the frame of a moved view is not where it rests: a layout pass during the slide out moved the card by the size of the move for a frame */
    ExteriaPlaceView(_card, CGRectMake(floor((size.width - width) / 2), top, width, size.height - top + 32));
    _handle.frame = CGRectMake(floor((width - 36) / 2), 6, 36, 4);
    _close.frame = CGRectMake(4, 12, 44, 40);
    _more.frame = CGRectMake(width - 60, 12, 44, 40);
    _pageTitle.frame = CGRectMake(110, 12, width - 220, 20);
    _hostLabel.frame = CGRectMake(110, 32, width - 220, 16);
    _web.frame = CGRectMake(0, 56, width, size.height - top - 56 - MAX(insets.bottom, 0));
    _error.frame = CGRectMake(24, _web.frame.origin.y + 24, width - 48, 120);
    _spinner.center = CGPointMake(width / 2, _web.frame.origin.y + 60);
    _retry.frame = CGRectMake(24, CGRectGetMaxY(_error.frame) + 4, width - 48, 44);
    _browser.frame = CGRectMake(24, CGRectGetMaxY(_retry.frame), width - 48, 44);
}
/* how far the card goes to stand just below the screen, counted from where it rests. the frame of a card that was pulled down by the finger already carries the pull, so
   the top is taken from its center, which a transform does not move: counting from the frame, a card that was pulled first stopped short by the length of the pull and was
   taken off the screen with a jump */
- (CGFloat)cardTravel {
    return self.view.bounds.size.height - (_card.center.y - _card.bounds.size.height / 2);
}
/* the way in is the quint curve of the sheets of exteraless, 320 ms, and the way out is their EASE_OUT, 250 ms; the quint on the way out covered most of the distance in the first frames */
- (void)enter {
    [self.view layoutIfNeeded];
    _card.transform = CGAffineTransformMakeTranslation(0, [self cardTravel]);
    _dim.alpha = 0;
    ExteriaAnimateView(_card, CGAffineTransformIdentity, 1, ExteriaPopupCurve(YES), nil);
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 0.45, ExteriaPopupCurve(YES), nil);
}
- (void)close {
    if (_closing) return;
    _closing = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadTimedOut) object:nil];
    [_load cancel];
    [_web stopLoading];
    _web.delegate = nil;
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 0, ExteriaPopupCurve(NO), nil);
    ExteriaAnimateView(_card, CGAffineTransformMakeTranslation(0, [self cardTravel]), 1, ExteriaPopupCurve(NO), ^(BOOL finished) {
        (void)finished;
        [self willMoveToParentViewController:nil];
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
    });
}
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)type {
    (void)webView;
    NSString *scheme = [request.URL.scheme lowercaseString];
    /* UIWebView uses applewebdata for the HTML supplied by loadData on old systems */
    if (type != UIWebViewNavigationTypeLinkClicked && [scheme isEqualToString:@"applewebdata"]) return YES;
    if ([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]) {
        /* frames of a page carry the address of the page as the main document, so only a load of the page itself changes the address */
        if ([request.mainDocumentURL isEqual:request.URL]) {
                    [_current release];
            _current = [request.URL retain];
            _hostLabel.text = _current.host;
        }
        return YES;
    }
    if ([scheme isEqualToString:@"about"]) return YES;
    /* a tapped mail or phone address belongs to the system; anything else (javascript:, file:, an app scheme) stays inside the page */
    if (type == UIWebViewNavigationTypeLinkClicked && ([scheme isEqualToString:@"mailto"] || [scheme isEqualToString:@"tel"]) &&
        ![[UIApplication sharedApplication] openURL:request.URL])
        NSLog(@"exteria: the address %@ was not handed to the system", request.URL);
    return NO;
}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    (void)webView;
    if (_closing || ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled)) return;
    /* WebKit reports a load that a delegate refused or a newer load replaced as frame load interrupted */
    if ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102) return;
    [self showFailure:[error localizedDescription]];
    NSLog(@"exteria: the page %@ did not load: %@ (%ld)", _current, error.domain, (long)error.code);
}
- (void)webViewDidFinishLoad:(UIWebView *)webView {
    if (_closing) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadTimedOut) object:nil];
    [_spinner stopAnimating];
    _error.hidden = YES;
    NSString *title = [webView stringByEvaluatingJavaScriptFromString:@"document.title"];
    _pageTitle.text = title.length ? title : (_current.host ? _current.host : NSLocalizedString(@"browser.untitled", nil));
    if (_article) {
        /* the title can load while the article body is empty or hidden by the page */
        NSString *details = [webView stringByEvaluatingJavaScriptFromString:
            @"(function(){var e=document.getElementById('_tl_editor');if(!e)return 'no article';"
             "var s=window.getComputedStyle(e);return 'text='+((e.innerText||e.textContent||'').length)+"
             "' paragraphs='+e.getElementsByTagName('p').length+' display='+s.display+"
             "' visibility='+s.visibility+' height='+e.offsetHeight;})()"];
        NSLog(@"exteria: the article %@ loaded: %@", _url, details ? details : @"no page details");
    }
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.2 animations:^{ _web.alpha = 1; }];
}
@end
