#import <Foundation/Foundation.h>

/* the result of one HTTP call: the body of the answer, the status line's code and, for a call that did not reach
   an answer */
typedef void (^ExteriaHttpCompletion)(NSData *body, NSInteger status, NSString *failure);

/* a bounded HTTP call for the services of the app that are not Telegram; the answer is cut off at limit bytes, the
   whole call at timeout seconds, and a redirect is followed only within the same host over https, so a key in a
   header never travels to another host */
@interface ExteriaHttpCall : NSObject

+ (ExteriaHttpCall *)startRequest:(NSURLRequest *)request limit:(NSUInteger)limit timeout:(NSTimeInterval)timeout completion:(ExteriaHttpCompletion)completion;
/* the same, for a page that sends the browser to a sibling host of its own site (www.bing.com to cn.bing.com);
   only for a call that carries no key */
+ (ExteriaHttpCall *)startRequest:(NSURLRequest *)request limit:(NSUInteger)limit timeout:(NSTimeInterval)timeout sameSite:(BOOL)sameSite completion:(ExteriaHttpCompletion)completion;
/* what the last answer said, readable in the completion */
@property (nonatomic, readonly) NSURL *responseURL;
@property (nonatomic, readonly) NSDictionary *responseHeaders;
/* no completion runs after this */
- (void)cancel;

@end

/* the text of a URL or form component with every reserved character escaped, as a query value or a form field wants it */
NSString *ExteriaURLEscape(NSString *text);
