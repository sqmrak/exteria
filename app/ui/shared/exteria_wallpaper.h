#import <UIKit/UIKit.h>

/* sets view up as the wallpaper of a chat for the day or the night: the picture of the modern style, or the linen
   tile of the classic one */
void ExteriaApplyChatWallpaper(UIImageView *view, BOOL dark);

/* the same for a view of a known size, such as a preview: the picked wallpaper is drawn at that size and not at the size of the screen */
void ExteriaApplyChatWallpaperSized(UIImageView *view, BOOL dark, CGSize size);
/* makes the picture of the chat wallpaper in the background, so the first chat that opens finds it ready */
void ExteriaWallpaperWarm(void);

/* the wallpaper the person picked in the chat settings, which both styles draw behind the chat in place of the
   standard picture (the classic one its linen) */
typedef enum {
    ExteriaWallpaperStandard = 0,
    ExteriaWallpaperColors,
    ExteriaWallpaperPhoto
} ExteriaWallpaperKind;

typedef struct {
    ExteriaWallpaperKind kind;
    /* the gradient, as 0xRRGGBB; equal colors are a plain color */
    uint32_t top, bottom;
    /* the direction of the gradient in degrees, 0 from the left edge to the right and 90 from the top to the bottom */
    int angle;
    /* the pattern over the colors, and how strong it is, 0 to 100 */
    int pattern;
    int intensity;
    /* the photo, blurred and dimmed by 0 to 100 percent */
    int blur;
    int dim;
} ExteriaWallpaperSetting;

/* posted on the main thread when the wallpaper changes */
extern NSString *const ExteriaWallpaperDidChangeNotification;

ExteriaWallpaperSetting ExteriaWallpaperStored(void);
void ExteriaWallpaperStore(ExteriaWallpaperSetting setting);
/* the photo is copied into the app's own folder and becomes the wallpaper, with no blur and no dimming; NO when the file cannot be read or kept */
BOOL ExteriaWallpaperUsePhotoAtPath(NSString *path);
/* the gradients the picker offers, as pairs of colors with their direction: the light ones in the day theme, the dark ones in the night theme */
NSUInteger ExteriaWallpaperPresetCount(void);
ExteriaWallpaperSetting ExteriaWallpaperPreset(NSUInteger index);
/* the picture of a setting at the size of the screen, for a small tile too (the preview sizes it down); nil for the standard wallpaper */
UIImage *ExteriaWallpaperImage(ExteriaWallpaperSetting setting, CGSize size);

/* the same for a style picked by the caller, for the screens that offer both whatever theme the app wears */
void ExteriaApplyWallpaperStyle(UIImageView *view, BOOL classic, BOOL dark);

#include "exteria_channel.h"

/* the background the admins gave a channel, at the size of the screen: its gradient with the pattern over it, or the picture of its file; nil when there is
   nothing to paint, or when the paper is a picture whose file has not come yet (file is that picture when it has) */
UIImage *ExteriaChannelWallpaperImage(const exteria_chat_wallpaper *paper, UIImage *file, CGSize size);

/* the finished background of a chat is kept on disk, so the next visit paints it at once instead of waiting for the full channel and, for a picture, decoding the file
   again. The signature says which paper it was made from (its colors, pattern and file), so a changed background is made anew and an equal one is not */
NSString *ExteriaChatWallpaperSignature(const exteria_chat_wallpaper *paper, NSString *fileKey);
/* the kept picture of the chat (peer kind and id) if it has the size; signature may be nil to take whatever is kept, and the one found is returned in found */
UIImage *ExteriaCachedChatWallpaper(int32_t peerKind, long long peerId, CGSize size, NSString *signature, NSString **found);
void ExteriaStoreChatWallpaper(int32_t peerKind, long long peerId, CGSize size, NSString *signature, UIImage *image);
/* the chat has no background of its own any more */
void ExteriaDropChatWallpaper(int32_t peerKind, long long peerId);
