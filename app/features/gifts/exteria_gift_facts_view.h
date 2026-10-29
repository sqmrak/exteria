#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_photo.h"

/* the rounded table under a gift: a title on the left of each row, its value on the right, hairlines between the rows */
@interface ExteriaGiftFactsView : UIView

/* where the people's pictures come from */
@property (nonatomic, retain) ExteriaAvatarCache *avatars;

/* a plain value, with an optional pill after it such as the rarity "3%" */
- (void)addRow:(NSString *)title text:(NSString *)text pill:(NSString *)pill;
/* a person: their picture, or the spy when the name is hidden, then the name */
- (void)addRow:(NSString *)title name:(NSString *)name photo:(ExteriaPhoto *)photo seed:(NSUInteger)seed anonymous:(BOOL)anonymous;
/* the same, and a tap anywhere on the value side of the row runs the handler; nil keeps the row inert */
- (void)addRow:(NSString *)title name:(NSString *)name photo:(ExteriaPhoto *)photo seed:(NSUInteger)seed anonymous:(BOOL)anonymous
         onTap:(void (^)(void))handler;
/* the same with the marks after the name as entities (ExteriaNameWithBadges) */
- (void)addRow:(NSString *)title name:(NSString *)name entities:(NSArray *)entities photo:(ExteriaPhoto *)photo seed:(NSUInteger)seed
    anonymous:(BOOL)anonymous onTap:(void (^)(void))handler;
/* redraw the names after a picture of a status or a mark arrives */
- (void)redrawNames;
/* a price with the star picture */
- (void)addRow:(NSString *)title stars:(long long)stars;
/* a line across the whole row, such as the note that came with the gift */
- (void)addNote:(NSString *)text entities:(NSArray *)entities;
/* redraw the note after a custom emoji picture arrives */
- (void)redrawNote;

- (CGFloat)heightForWidth:(CGFloat)width;

@end
