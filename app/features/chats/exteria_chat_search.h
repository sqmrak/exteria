#import <UIKit/UIKit.h>

/* the search of a chat in the modern style: the bar that takes the place of the chat's header while the words are typed, and the strip over the
   keyboard that counts the matches and steps through them */

#define EXTERIA_CHAT_SEARCH_BAR_HEIGHT 44.0
#define EXTERIA_CHAT_SEARCH_NAV_HEIGHT 48.0

@interface ExteriaChatSearchBar : UIView <UITextFieldDelegate> {
    UITextField *_field;
    UIButton *_cancel;
    void (^_changeHandler)(NSString *text);
    void (^_cancelHandler)(void);
}
/* called with the text after every edit */
@property (nonatomic, copy) void (^changeHandler)(NSString *text);
@property (nonatomic, copy) void (^cancelHandler)(void);
@property (nonatomic, readonly) UITextField *field;
@end

@interface ExteriaChatSearchNav : UIView {
    UILabel *_count;
    UIButton *_older;
    UIButton *_newer;
    UIView *_line;
    void (^_olderHandler)(void);
    void (^_newerHandler)(void);
}
@property (nonatomic, copy) void (^olderHandler)(void);
@property (nonatomic, copy) void (^newerHandler)(void);
/* what the counter says: nothing typed yet, a search on its way, no match, or the place of the shown match among all of them */
- (void)showIdle;
- (void)showSearching;
- (void)showNone;
- (void)showPosition:(NSUInteger)position of:(NSUInteger)total;
@end
