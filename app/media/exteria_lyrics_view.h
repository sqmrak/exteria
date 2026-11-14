#import <UIKit/UIKit.h>

#import "exteria_lyrics.h"

/* the lyrics of the song that plays, a line to a label: the line that is being sung stands full size and bright and springs in when it takes over, the others are smaller and dim, and
   the list keeps the line near the upper third while it moves. a tap on a line of synced lyrics seeks to it. the screen under it paints the ground */
@interface ExteriaLyricsView : UIView
/* called with the second a tapped line starts at */
@property (nonatomic, copy) void (^onSeek)(NSTimeInterval seconds);
/* the skeuomorphic look: white lines on the dark ground the screen gives, the line that is being sung only brightens (no growing, no spring). set it before the lyrics are shown */
@property (nonatomic, assign) BOOL skeuomorphic;
/* a word instead of lyrics: loading, none, failed; nil leaves the lyrics */
- (void)showStatus:(NSString *)text;
- (void)showLyrics:(ExteriaLyrics *)lyrics;
/* the position of the song in seconds; the view also follows it by itself while it is on a screen */
- (void)updatePosition:(NSTimeInterval)seconds animated:(BOOL)animated;
@end
