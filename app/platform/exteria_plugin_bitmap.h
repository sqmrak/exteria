#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

#include "exteria_status.h"

/* the pictures a plugin works on: the app decodes, shrinks, copies and blurs them and python holds a handle, so the pixels of a photo never pass through
   python. main thread only. a handle is a positive number and stays valid until it is released */

#define EXTERIA_PLUGIN_BITMAP_SIDE_MAX 4096
#define EXTERIA_PLUGIN_BITMAP_LIVE_MAX 8

/* Library/Application Support/exteria-plugin-pictures: the pictures the person chose in the picker a plugin opened. unlike the caches folder the system does not empty
   it, and a plugin keeps the address of its picture between runs. made on demand */
NSString *ExteriaPluginPicksDirectory(void);

/* moves a file the picker wrote into that folder under a new name, and removes the oldest files of the folder beyond the four newest. the new path, or nil
   with *failure set */
NSString *ExteriaPluginPicksAdopt(NSString *path, NSString **failure);

/* decodes the picture at path, which has to be a regular file (not a link) of the folder above or of the plugin files folder (ExteriaPluginsCacheDirectory), where a
   plugin keeps what it downloads, at most side points on its long side. *reply gets handle, w and h */
exteria_status ExteriaPluginBitmapDecode(NSString *path, int side, NSDictionary **reply, NSString **failure);
/* a new picture of the given size from an existing one */
exteria_status ExteriaPluginBitmapScale(long long handle, int width, int height, NSDictionary **reply, NSString **failure);
/* the part of a picture that starts at x, y and is width by height; a rectangle that leaves the picture is refused */
exteria_status ExteriaPluginBitmapCrop(long long handle, int x, int y, int width, int height, NSDictionary **reply, NSString **failure);
/* writes the picture as a jpeg (quality 1 to 100) or a png to path, which has to be a new or existing regular file directly inside the plugin files folder */
exteria_status ExteriaPluginBitmapEncode(long long handle, BOOL png, int quality, NSString *path, NSString **failure);
exteria_status ExteriaPluginBitmapCopy(long long handle, NSDictionary **reply, NSString **failure);
/* blurs the picture in place with exteria_stack_blur_rgba */
exteria_status ExteriaPluginBitmapBlur(long long handle, int radius, NSString **failure);
/* an unknown handle is ignored: python reports the ones it dropped, and a handle may be reported after the app forgot it */
void ExteriaPluginBitmapRelease(long long handle);
/* the picture as an image the caller owns (release it), NULL for an unknown handle. the pixels are copied, so a later blur does not change a layer that shows it */
CGImageRef ExteriaPluginBitmapCreateImage(long long handle);
