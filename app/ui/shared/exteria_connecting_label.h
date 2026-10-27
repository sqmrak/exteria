#import <UIKit/UIKit.h>

/* the title while the link to the server is not up: "Connecting" with one to three dots */
NSString *ExteriaConnectingText(NSUInteger dots);
/* the title while the link works and the list is being loaded: "Updating" with one to three dots */
NSString *ExteriaUpdatingText(NSUInteger dots);

/* a label whose dots fill in one by one while connecting is set; the text stays as wide as the full title and left
   aligned, so the dots do not shift the line */
@interface ExteriaConnectingLabel : UILabel

@property (nonatomic, assign) BOOL connecting;
/* set with connecting: the words are those of the list being updated over a working link, not of the link coming up */
@property (nonatomic, assign) BOOL updating;

@end
