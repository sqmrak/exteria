#import <Foundation/Foundation.h>

#import "exteria_session.h"

@interface ExteriaSession (Translate)

/* the translation Telegram does itself (messages.translateText), the service of the translator that needs no key
   and no other host. text goes as it is, with any markup the caller put in it */
- (void)translateText:(NSString *)text to:(NSString *)language completion:(void (^)(NSString *translated, NSString *errorName))completion;

@end
