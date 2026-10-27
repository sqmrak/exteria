#import <UIKit/UIKit.h>

/* the wallpaper picker in one row that scrolls sideways, as the wallpapers of Telegram are offered */
@interface ExteriaWallpaperGridView : UIView

/* runs on the main thread with the index of the gradient, as ExteriaWallpaperPreset takes it */
@property (nonatomic, copy) void (^chooseHandler)(NSUInteger index);
/* the tile of the photo library was tapped */
@property (nonatomic, copy) void (^galleryHandler)(void);
/* the tile of the standard wallpaper was tapped */
@property (nonatomic, copy) void (^standardHandler)(void);
/* where the last chosen tile is, in window coordinates, which is where a change of colors spreads from */
@property (nonatomic, readonly) CGPoint tapPoint;
/* the gradient with this index is the chosen one; NSNotFound marks none */
@property (nonatomic, assign) NSUInteger chosenIndex;
/* the wallpaper is the standard one, or a photo of the library; with neither flag and a chosenIndex the gradient is the chosen tile */
@property (nonatomic, assign) BOOL standardChosen;
@property (nonatomic, assign) BOOL photoChosen;

/* the height of the row */
+ (CGFloat)height;

@end
