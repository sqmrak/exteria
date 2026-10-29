#import <Foundation/Foundation.h>

@interface ExteriaArticleLoad : NSObject {
    volatile int _cancelled;
}
- (void)startURL:(NSURL *)url completion:(void (^)(NSData *html, NSURL *url, NSString *error))completion;
- (void)cancel;
@end

/* ios 6 cannot complete telegra.ph TLS, and UIWebView cannot follow the app's tunnel route */
@interface ExteriaTunnelURLProtocol : NSURLProtocol
+ (void)install;
@end
