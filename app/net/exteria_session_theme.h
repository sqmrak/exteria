#import <Foundation/Foundation.h>

#import "exteria_message.h"
#import "exteria_session.h"

/* a cloud theme as the server describes it (account.getTheme in the ios format), the words of a t.me/addtheme link */
@interface ExteriaThemeLink : NSObject {
    NSString *_title;
    ExteriaMedia *_file;
}
@property (nonatomic, readonly, copy) NSString *title;
/* the .tgios-theme file, nil for a theme that only carries accent colors, which this client cannot apply */
@property (nonatomic, readonly, retain) ExteriaMedia *file;
@end

@interface ExteriaSession (Theme)

/* the theme with this slug. the completion gets the theme, or nil with the error name of the server (THEME_SLUG_INVALID or THEME_FORMAT_INVALID for
   a slug it does not know), TIMEOUT, or MALFORMED for an answer that is not a theme; it runs on the main thread */
- (void)loadThemeOfSlug:(NSString *)slug completion:(void (^)(ExteriaThemeLink *theme, NSString *errorName))completion;

@end
