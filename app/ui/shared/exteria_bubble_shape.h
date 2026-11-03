#import <UIKit/UIKit.h>

/* the bubble of Telegram for iOS, from messageBubbleImage of ChatMessageBubbleImages.swift, as nogram (the ios6 branch of
   an0therlabs/nogram, Sources/NGOriginal.m) carries it over line for line: a stretchable picture of a box of 33 points
   with 6 more beside it for the tail, which is the lower ellipse filled out of the bottom corner and the upper one cut
   back out of it */

/* the room the tail takes beside the box */
#define EXTERIA_TELEGRAM_TAIL_ROOM 6.0

/* who stands next to the bubble in its run, as the neighbors of Telegram: none, one under it (the first of a run),
   one over it (the last, which has the tail) or both */
typedef enum {
    ExteriaTelegramNeighborsNone = 0,
    ExteriaTelegramNeighborsTop,
    ExteriaTelegramNeighborsBottom,
    ExteriaTelegramNeighborsBoth
} ExteriaTelegramNeighbors;

ExteriaTelegramNeighbors ExteriaTelegramNeighborsFor(BOOL joinsPrevious, BOOL joinsNext);
/* whether the bubble with these neighbours has the tail */
BOOL ExteriaTelegramNeighborsHaveTail(ExteriaTelegramNeighbors neighbors);

/* the stretchable picture; the same arguments give the same picture back from a cache */
UIImage *ExteriaTelegramBubbleImage(CGFloat maxCornerRadius, CGFloat minCornerRadius, BOOL incoming, UIColor *fillColor,
                                    ExteriaTelegramNeighbors neighbors);
/* where the picture is drawn for a box in body: it has a transparent margin of two points round it and the room of the
   tail on the side of the sender */
CGRect ExteriaTelegramBubbleImageFrame(CGRect body, BOOL incoming);
