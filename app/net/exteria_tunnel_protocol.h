#import <Foundation/Foundation.h>

/* ios 6 cannot complete telegra.ph TLS, and UIWebView cannot follow the app's tunnel route */
@interface ExteriaTunnelURLProtocol : NSURLProtocol
+ (void)install;
@end
