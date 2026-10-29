#import <UIKit/UIKit.h>

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

@end
