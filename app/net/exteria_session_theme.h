#import <Foundation/Foundation.h>

#import "exteria_message.h"
#import "exteria_session.h"

/* a cloud theme as the server describes it (account.getTheme in the ios format), the words of a t.me/addtheme link */
@interface ExteriaThemeLink : NSObject {
    NSString *_title;
    ExteriaMedia *_file;
    BOOL _hasColors;
    BOOL _dark;
    uint32_t _accent;
}
@property (nonatomic, readonly, copy) NSString *title;
/* the .tgios-theme file, nil for a theme that only carries accent colors */
@property (nonatomic, readonly, retain) ExteriaMedia *file;
/* a theme of colors says whether its base look is dark and what its accent is (0xRRGGBB); NO when it has none */
@property (nonatomic, readonly) BOOL hasColors;
@property (nonatomic, readonly) BOOL dark;
@property (nonatomic, readonly) uint32_t accent;
@end

@interface ExteriaSession (Theme)

/* the theme with this slug. the completion gets the theme, or nil with the error name of the server (THEME_SLUG_INVALID or THEME_FORMAT_INVALID for
   a slug it does not know), TIMEOUT, or MALFORMED for an answer that is not a theme; it runs on the main thread */
- (void)loadThemeOfSlug:(NSString *)slug completion:(void (^)(ExteriaThemeLink *theme, NSString *errorName))completion;

@end
