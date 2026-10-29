#import <UIKit/UIKit.h>
#import "exteria_session_folders.h"
@class ExteriaMediaCache;

@interface ExteriaFolderTabs : UIView
- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media changed:(void (^)(void))changed;
@property(nonatomic, readonly) CGFloat height;
/* which way the last change of folder went: 1 to a folder further along the bar (a swipe to the left), -1 to one before it; the list slides the same way */
@property(nonatomic, readonly) NSInteger slideDirection;
@property(nonatomic, readonly) ExteriaChatFolder *selectedFolder;
- (void)refresh;
- (void)installPagingInView:(UIView *)view;
@property(nonatomic, readonly) NSArray *pagingRecognizers;
@end
