#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_message.h"

/* what one tile of the grid shows */
@interface ExteriaGiftTileInfo : NSObject {
    ExteriaMedia *_sticker;
    ExteriaRemoteFile *_pictureFile;
    NSString *_title;
    long long _starsAmount;
    NSString *_caption;
    NSString *_badge;
    BOOL _hasBackdrop;
    uint32_t _backdropCenter;
    uint32_t _backdropEdge;
    BOOL _dimmed;
    BOOL _card;
    BOOL _unique;
    BOOL _pinned;
    BOOL _hiddenMark;
    BOOL _anonymous;
    NSString *_ribbon;
    ExteriaMedia *_patternSticker;
    uint32_t _patternColor;
    ExteriaPhoto *_fromPhoto;
    NSUInteger _fromSeed;
    NSString *_fromInitials;
}
@property (nonatomic, retain) ExteriaMedia *sticker;
/* a picture to show instead of the sticker's own file, such as the thumbnail of a video */
@property (nonatomic, retain) ExteriaRemoteFile *pictureFile;
/* the line under the picture: a price or a name */
@property (nonatomic, copy) NSString *title;
/* a price in stars drawn under the picture with the star picture, instead of the title */
@property (nonatomic, assign) long long starsAmount;
/* a quieter line above the picture, such as how many are left */
@property (nonatomic, copy) NSString *caption;
/* a mark in the corner such as the pin */
@property (nonatomic, copy) NSString *badge;
@property (nonatomic, assign) BOOL hasBackdrop;
@property (nonatomic, assign) uint32_t backdropCenter;
@property (nonatomic, assign) uint32_t backdropEdge;
/* sold out */
@property (nonatomic, assign) BOOL dimmed;
/* a gift on a profile: a square card with the picture large and the marks in the corners, and no text under it */
@property (nonatomic, assign) BOOL card;
/* a unique gift keeps the pin at the left and shows its number on a ribbon in the right corner */
@property (nonatomic, assign) BOOL unique;
@property (nonatomic, assign) BOOL pinned;
/* the gift is hidden from the profile: a mark over the middle of the picture */
@property (nonatomic, assign) BOOL hiddenMark;
/* the sender kept their name back, so the left corner shows the spy instead of a picture */
@property (nonatomic, assign) BOOL anonymous;
@property (nonatomic, copy) NSString *ribbon;
@property (nonatomic, retain) ExteriaMedia *patternSticker;
@property (nonatomic, assign) uint32_t patternColor;
/* the sender of a regular gift, for the left corner */
@property (nonatomic, retain) ExteriaPhoto *fromPhoto;
@property (nonatomic, assign) NSUInteger fromSeed;
@property (nonatomic, copy) NSString *fromInitials;
@end

@class ExteriaGiftGridView;

@protocol ExteriaGiftGridDelegate <NSObject>
- (void)giftGrid:(ExteriaGiftGridView *)grid didSelectIndex:(NSUInteger)index;
@optional
/* the list scrolled; offset is how far past the top it is */
- (void)giftGrid:(ExteriaGiftGridView *)grid didScrollToOffset:(CGFloat)offset;
/* the last row came into view */
- (void)giftGridReachedEnd:(ExteriaGiftGridView *)grid;
@end

/* gift tiles in rows of two to four, on a scrolling list that keeps only the visible rows alive */
@interface ExteriaGiftGridView : UIView <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate> {
    id<ExteriaGiftGridDelegate> _delegate;
}

@property (nonatomic, assign) id<ExteriaGiftGridDelegate> delegate;
/* a view above the first row that scrolls with the tiles */
@property (nonatomic, retain) UIView *headerView;

- (id)initWithMedia:(ExteriaMediaCache *)media;
/* where the senders' pictures come from; set before the tiles */
@property (nonatomic, retain) ExteriaAvatarCache *avatars;
/* ExteriaGiftTileInfo items; the list keeps its place when more rows are added at the end */
- (void)setTiles:(NSArray *)tiles;
/* room below the last row, for what floats over the list */
@property (nonatomic, assign) CGFloat bottomInset;

@end
