#import <UIKit/UIKit.h>

/* what a downloaded file turns out to be, from its first bytes */
typedef enum {
    ExteriaFileFormatUnknown,
    ExteriaFileFormatWebP,
    ExteriaFileFormatGzip,      /* a lottie sticker */
    ExteriaFileFormatMatroska,  /* a vp9 video sticker */
    ExteriaFileFormatMP4        /* the clip of a gif or a video whose only preview is a clip */
} ExteriaFileFormat;

ExteriaFileFormat ExteriaFileFormatOfData(NSData *data);

/* turns picture bytes into an image no larger than maxSide pixels on its longer side */
UIImage *ExteriaDecodeImage(NSData *data, CGFloat maxSide);

/* file-backed ImageIO thumbnails avoid decoding a camera original at its full size */
UIImage *ExteriaDecodeImageAtURL(NSURL *url, CGFloat maxSide);

/* fits the visible alpha bounds to the same square used by ordinary emoji */
UIImage *ExteriaFitEmojiImage(UIImage *image);

/* whether a picture is a round or free shape on an empty or white ground: three or more of its four corners are
   see-through or white */
BOOL ExteriaImageIsRound(UIImage *image);

