#import <Foundation/Foundation.h>

extern NSString *const ExteriaTunnelHTMLDidLoadNotification;

/* ios 6 cannot complete telegra.ph TLS, and UIWebView cannot follow the app's tunnel route */
@interface ExteriaTunnelURLProtocol : NSURLProtocol
+ (void)install;
@end
