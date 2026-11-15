#import <UIKit/UIKit.h>

#import "exteria_chat_settings.h"

@class ExteriaFilterBar;

@protocol ExteriaFilterBarDelegate <NSObject>
- (void)filterBar:(ExteriaFilterBar *)bar didSelectIndex:(NSInteger)index;
@end

/* a row of pill buttons that scrolls sideways, one selected, each with an optional unread count */
@interface ExteriaFilterBar : UIView {
    id<ExteriaFilterBarDelegate> _delegate;
    NSInteger _selectedIndex;
}

@property (nonatomic, assign) id<ExteriaFilterBarDelegate> delegate;
@property (nonatomic, assign) NSInteger selectedIndex;

- (id)initWithTitles:(NSArray *)titles;
- (void)setEntities:(NSArray *)entities forIndex:(NSInteger)index;
- (void)redrawTitles;
- (void)setCount:(NSInteger)count forIndex:(NSInteger)index;
/* the name of the icon of a tab (see ExteriaFolderIconName); a tab with none shows only its name whatever the style */
- (void)setIconName:(NSString *)name forIndex:(NSInteger)index;
/* what the tabs show; animated moves the tabs to their new widths and fades the name and the icon in or out, as exteraGram does when the setting changes */
@property (nonatomic, assign) ExteriaFolderTabStyle tabStyle;
- (void)setTabStyle:(ExteriaFolderTabStyle)style animated:(BOOL)animated;

@end
