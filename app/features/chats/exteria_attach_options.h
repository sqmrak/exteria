#import <Foundation/Foundation.h>

/* the most photos and videos one selection holds; they go out as albums of ten */
#define ATTACH_SELECTION_MAX 30

/* what the person asked for in the gallery sheet besides the pictures themselves: the words to send with them and
   the choices of its menu */
@interface ExteriaAttachOptions : NSObject {
@public
    NSString *caption;
    /* the original file goes out as a document, not as a recompressed photo */
    BOOL asFiles;
    /* photos and videos are shown blurred until they are tapped */
    BOOL spoiler;
    /* one photo or video that the other side can open once; an album has no such mode, so the sheet drops it for a selection of several */
    BOOL viewOnce;
    /* a smaller picture and a lighter video than the usual */
    BOOL standard;
    /* one picture is opened in the editor first, as a tap on it asks for, and the sheet's words and choices are not used */
    BOOL preview;
}
@end
