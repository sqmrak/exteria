#import <UIKit/UIKit.h>

@class ExteriaMedia;
@class ExteriaRichDocument;

/* an article laid out in a column: headings, paragraphs, lists, quotes, code, tables, dividers and pictures, top to bottom, in the coordinates of its own top left corner */
@interface ExteriaRichLayout : NSObject {
    NSMutableArray *_pieces;
    NSMutableArray *_media;
    NSMutableArray *_captions;
    NSMutableArray *_zooms;
    NSMutableArray *_details;
    CGSize _size;
    CGFloat _trailingLineWidth;
    BOOL _spoilersRevealed;
    UIColor *_placeholder;
}

/* toggled holds the indexes of the details blocks the reader opened or closed against how the author left them */
+ (ExteriaRichLayout *)layoutForDocument:(ExteriaRichDocument *)document width:(CGFloat)width textSize:(CGFloat)textSize color:(UIColor *)color
                               secondary:(UIColor *)secondary linkColor:(UIColor *)linkColor revealed:(BOOL)revealed toggled:(NSIndexSet *)toggled;

@property (nonatomic, readonly) CGSize size;
/* the width of the last line when the article ends in left aligned words at its foot, so the time can stand beside it; negative otherwise */
@property (nonatomic, readonly) CGFloat trailingLineWidth;
/* covered spoilers in the words, and the pictures marked as spoilers, show once this is set */
@property (nonatomic, assign) BOOL spoilersRevealed;

/* images holds the loaded pictures by media index (NSNumber to UIImage); a picture still loading is drawn as a plain box */
- (void)drawAtPoint:(CGPoint)origin images:(NSDictionary *)images;
/* the link under a point, ExteriaSpoilerTarget over a covered spoiler, nil over plain words */
- (NSString *)linkAtPoint:(CGPoint)point;

- (NSUInteger)mediaCount;
- (ExteriaMedia *)mediaAtIndex:(NSUInteger)index;
- (CGRect)frameOfMediaAtIndex:(NSUInteger)index;
/* NSNotFound when the point is over no picture */
- (NSUInteger)mediaIndexAtPoint:(CGPoint)point;
/* the words under a picture, empty without any */
- (NSString *)captionOfMediaAtIndex:(NSUInteger)index;
/* the zoom of a map, zero for a photo or a video */
- (int)zoomOfMediaAtIndex:(NSUInteger)index;
/* the block index of the details summary under a point, which a tap opens or closes; NSNotFound elsewhere */
- (NSUInteger)detailsAtPoint:(CGPoint)point;
@end
