#import <UIKit/UIKit.h>

#import "exteria_message.h"

@class ExteriaSession, ExteriaTranslateJob, ExteriaWeakReference;

/* the styled runs of the text a person is typing, after the selection menu of the message field */
@interface ExteriaInputFormat : NSObject {
    UITextView *_view;
    NSMutableArray *_runs;
    ExteriaSession *_session;
    ExteriaTranslateJob *_job;
    UIView *_host;
    ExteriaWeakReference *_weak;
}

/* the session resolves @names for a mention and runs the translation; both are asked for only when the person picks them */
@property (nonatomic, assign) ExteriaSession *session;
/* the view the sheets and the date picker are shown over; the field itself sits in a bar that is too small for them */
@property (nonatomic, assign) UIView *host;
/* called after the runs changed in a way the text view did not report, so the owner can refresh what depends on the text */
@property (nonatomic, copy) void (^changed)(void);
/* called with a replacement for a range, as a translation arrives; the owner replaces it the way typing would */
@property (nonatomic, copy) void (^replace)(NSRange range, NSString *text);

- (id)initWithTextView:(UITextView *)view;
/* a run before an edit stays, one after it moves by the change in length, one the edit lies inside grows or shrinks with it, and one the edit
   cuts into loses what was cut */
- (void)shiftForRange:(NSRange)range replacementLength:(NSUInteger)length;
- (void)reset;
/* replaces the runs with these, such as the ones a draft kept; the ones the field cannot style (a link without an address, a name or a hashtag the server
   finds by itself) are left out. Offsets count the text now in the field */
- (void)restoreEntities:(NSArray *)entities;
/* the picker of what to do with the selection, as the one item the field adds to the system menu */
- (void)presentMenu;
/* the runs inside the first length characters after lead, offsets counted from lead */
- (NSArray *)entitiesAfterLead:(NSUInteger)lead length:(NSUInteger)length;
/* paints the runs on the text of the field */
- (void)refreshAppearance;

@end
