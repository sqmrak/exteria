#import <Foundation/Foundation.h>

#import "exteria_dialog.h"

/* a community as its screen shows it: the chats it groups, split by whether the account is in them */
@interface ExteriaCommunity : NSObject {
    NSString *_title;
    NSString *_about;
    BOOL _collapsed;
    NSArray *_joined;
    NSArray *_viewable;
}
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *about;
/* the list shows the community as one chat */
@property (nonatomic, assign) BOOL collapsed;
/* ExteriaDialog items of the chats the account is a member of, then of those it can only look at; both in the
   community's order */
@property (nonatomic, readonly, retain) NSArray *joined;
@property (nonatomic, readonly, retain) NSArray *viewable;
- (id)initWithTitle:(NSString *)title about:(NSString *)about collapsed:(BOOL)collapsed joined:(NSArray *)joined viewable:(NSArray *)viewable;
@end
