#import "exteria_symbol.h"

/* the bundled mask of a symbol, resources/icons/symbol_*, cut drawables by tools/make_assets.py */
static NSString *ExteriaSymbolMaskName(ExteriaSymbol symbol) {
    switch (symbol) {
    case ExteriaSymbolMagnifier: return @"symbol_magnifier";
    case ExteriaSymbolPlusCircle: return @"symbol_pluscircle";
    case ExteriaSymbolCompose: return @"symbol_compose";
    case ExteriaSymbolBookmark: return @"symbol_bookmark";
    case ExteriaSymbolPin: return @"symbol_pin";
    case ExteriaSymbolBellSlash: return @"symbol_bellslash";
    case ExteriaSymbolChats: return @"symbol_chats";
    case ExteriaSymbolPerson: return @"symbol_person";
    case ExteriaSymbolGear: return @"symbol_gear";
    case ExteriaSymbolArchive: return @"symbol_archive";
    case ExteriaSymbolChevronRight: return @"symbol_chevronright";
    case ExteriaSymbolCheck: return @"symbol_check";
    case ExteriaSymbolCheckDouble: return @"symbol_checkdouble";
    case ExteriaSymbolSmiley: return @"symbol_smiley";
    case ExteriaSymbolKeyboard: return @"symbol_keyboard";
    case ExteriaSymbolSendArrow: return @"symbol_sendarrow";
    case ExteriaSymbolClock: return @"symbol_clock";
    case ExteriaSymbolArrowDown: return @"symbol_arrowdown";
    case ExteriaSymbolPlay: return @"symbol_play";
    case ExteriaSymbolDocument: return @"symbol_document";
    case ExteriaSymbolSticker: return @"symbol_sticker";
    case ExteriaSymbolBackspace: return @"symbol_backspace";
    case ExteriaSymbolMicrophone: return @"symbol_microphone";
    case ExteriaSymbolVideoCamera: return @"symbol_videocamera";
    case ExteriaSymbolCameraFlip: return @"symbol_cameraflip";
    case ExteriaSymbolPaperclip: return @"symbol_paperclip";
    case ExteriaSymbolGallery: return @"symbol_gallery";
    case ExteriaSymbolMapPin: return @"symbol_mappin";
    case ExteriaSymbolLock: return @"symbol_lock";
    case ExteriaSymbolEllipsis: return @"symbol_ellipsis";
    case ExteriaSymbolSun: return @"symbol_sun";
    case ExteriaSymbolMoon: return @"symbol_moon";
    case ExteriaSymbolMegaphone: return @"symbol_megaphone";
    case ExteriaSymbolGift: return @"symbol_gift";
    case ExteriaSymbolHeart: return @"symbol_heart";
    case ExteriaSymbolHeartOutline: return @"symbol_heartoutline";
    case ExteriaSymbolStar: return @"symbol_star";
    case ExteriaSymbolClose: return @"symbol_close";
    case ExteriaSymbolTrashCan: return @"symbol_trashcan";
    case ExteriaSymbolTrashLid: return @"symbol_trashlid";
    case ExteriaSymbolTrash: return @"symbol_trashcan";
    case ExteriaSymbolPhone: return @"symbol_phone";
    case ExteriaSymbolAt: return @"symbol_at";
    case ExteriaSymbolCake: return @"symbol_cake";
    case ExteriaSymbolLogout: return @"symbol_logout";
    case ExteriaSymbolQr: return @"symbol_qr";
    case ExteriaSymbolLink: return @"symbol_link";
    case ExteriaSymbolMusic: return @"symbol_music";
    case ExteriaSymbolPause: return @"symbol_pause";
    case ExteriaSymbolNext: return @"symbol_next";
    case ExteriaSymbolPrevious: return @"symbol_previous";
    case ExteriaSymbolEyeSlash: return @"symbol_eyeslash";
    case ExteriaSymbolSpeaker: return @"symbol_speaker";
    case ExteriaSymbolSpeakerSlash: return @"symbol_speakerslash";
    case ExteriaSymbolEllipsisVertical: return @"symbol_ellipsisvertical";
    case ExteriaSymbolBell: return @"symbol_bell";
    case ExteriaSymbolEye: return @"symbol_eye";
    case ExteriaSymbolShare: return @"symbol_share";
    case ExteriaSymbolBellMuted: return @"symbol_bellmuted";
    case ExteriaSymbolPinnedList: return @"symbol_pinnedlist";
    case ExteriaSymbolBroom: return @"symbol_broom";
    case ExteriaSymbolBack: return @"symbol_back";
    case ExteriaSymbolExternalLink: return @"symbol_externallink";
    case ExteriaSymbolApps: return @"symbol_apps";
    case ExteriaSymbolCopy: return @"symbol_copy";
    case ExteriaSymbolStars: return @"symbol_stars";
    case ExteriaSymbolCrop: return @"symbol_crop";
    case ExteriaSymbolAdjust: return @"symbol_adjust";
    case ExteriaSymbolDraw: return @"symbol_draw";
    case ExteriaSymbolRotate: return @"symbol_rotate";
    case ExteriaSymbolMirror: return @"symbol_mirror";
    case ExteriaSymbolHeaderDraw: return @"symbol_headerdraw";
    case ExteriaSymbolMember: return @"symbol_member";
    case ExteriaSymbolReport: return @"symbol_report";
    case ExteriaSymbolReply: return @"symbol_reply";
    case ExteriaSymbolForward: return @"symbol_forward";
    case ExteriaSymbolUnpin: return @"symbol_unpin";
    case ExteriaSymbolInfo: return @"symbol_info";
    case ExteriaSymbolRepeat: return @"symbol_repeat";
    case ExteriaSymbolSettingsAccount: return @"symbol_settingsaccount";
    case ExteriaSymbolSettingsChat: return @"symbol_settingschat";
    case ExteriaSymbolSettingsStickers: return @"symbol_settingsstickers";
    case ExteriaSymbolSettingsPrivacy: return @"symbol_settingsprivacy";
    case ExteriaSymbolSettingsSounds: return @"symbol_settingssounds";
    case ExteriaSymbolSettingsData: return @"symbol_settingsdata";
    case ExteriaSymbolSettingsFolders: return @"symbol_settingsfolders";
    case ExteriaSymbolSettingsDevices: return @"symbol_settingsdevices";
    case ExteriaSymbolSettingsPower: return @"symbol_settingspower";
    case ExteriaSymbolSettingsLanguage: return @"symbol_settingslanguage";
    case ExteriaSymbolSettingsPremium: return @"symbol_settingspremium";
    case ExteriaSymbolSettingsStars: return @"symbol_settingsstars";
    case ExteriaSymbolSettingsBusiness: return @"symbol_settingsbusiness";
    case ExteriaSymbolSettingsGift: return @"symbol_settingsgift";
    case ExteriaSymbolSettingsAsk: return @"symbol_settingsask";
    case ExteriaSymbolSettingsFaq: return @"symbol_settingsfaq";
    case ExteriaSymbolSettingsFeatures: return @"symbol_settingsfeatures";
    case ExteriaSymbolSettingsPolicy: return @"symbol_settingspolicy";
    case ExteriaSymbolBlock: return @"symbol_block";
    case ExteriaSymbolQrMini: return @"symbol_qrmini";
    case ExteriaSymbolGlobe: return @"symbol_globe";
    case ExteriaSymbolTranslate: return @"symbol_translate";
    case ExteriaSymbolAppDevices: return @"symbol_appdevices";
    case ExteriaSymbolDeviceAndroid: return @"symbol_deviceandroid";
    case ExteriaSymbolDeviceAndroidTablet: return @"symbol_deviceandroidtablet";
    case ExteriaSymbolDeviceIphone: return @"symbol_deviceiphone";
    case ExteriaSymbolDeviceIpad: return @"symbol_deviceipad";
    case ExteriaSymbolDeviceWindows: return @"symbol_devicewindows";
    case ExteriaSymbolDeviceMac: return @"symbol_devicemac";
    case ExteriaSymbolDeviceDesktop: return @"symbol_devicedesktop";
    case ExteriaSymbolDeviceChrome: return @"symbol_devicechrome";
    case ExteriaSymbolDeviceEdge: return @"symbol_deviceedge";
    case ExteriaSymbolDeviceFirefox: return @"symbol_devicefirefox";
    case ExteriaSymbolDeviceOpera: return @"symbol_deviceopera";
    case ExteriaSymbolDeviceSafari: return @"symbol_devicesafari";
    case ExteriaSymbolDeviceWeb: return @"symbol_deviceweb";
    case ExteriaSymbolFileHQ: return @"symbol_filehq";
    case ExteriaSymbolSpoiler: return @"symbol_spoiler";
    case ExteriaSymbolQualitySD: return @"symbol_qualitysd";
    case ExteriaSymbolQualityHD: return @"symbol_qualityhd";
    case ExteriaSymbolCallback: return @"symbol_callback";
    case ExteriaSymbolVideoCallMenu: return @"symbol_videocall";
    case ExteriaSymbolBackground: return @"symbol_background";
    case ExteriaSymbolGroupsMenu: return @"symbol_groupsmenu";
    case ExteriaSymbolClearHistory: return @"symbol_clearhistory";
    case ExteriaSymbolHelp: return @"symbol_help";
    case ExteriaSymbolSettingsOld: return @"symbol_settingsold";
    case ExteriaSymbolFave: return @"symbol_fave";
    case ExteriaSymbolPinLine: return @"symbol_pinline";
    case ExteriaSymbolGhost: return @"symbol_ghost";
    }
    return nil;
}

/* the mask filled with color; a bitmap on every system, so the glyphs look the same from ios 5 to the newest release */
static UIImage *ExteriaRenderSymbolImage(ExteriaSymbol symbol, CGFloat pointSize, UIColor *color) {
    NSString *name = ExteriaSymbolMaskName(symbol);
    UIImage *mask = name ? [UIImage imageNamed:name] : nil;
    if (!mask) {
        NSLog(@"exteria: symbol %d has no bitmap in the bundle", (int)symbol);
        return nil;
    }
    CGSize size = CGSizeMake(pointSize, pointSize);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    [color setFill];
    CGContextTranslateCTM(context, 0, size.height);
    CGContextScaleCTM(context, 1, -1);
    CGRect box = CGRectMake(0, 0, size.width, size.height);
    CGContextSaveGState(context);
    CGContextClipToMask(context, box, mask.CGImage);
    CGContextFillRect(context, box);
    CGContextRestoreGState(context);
    if (symbol == ExteriaSymbolTrash) {
        /* the lid mask shares the canvas of the can, so the pair is one trash can */
        UIImage *lid = [UIImage imageNamed:@"symbol_trashlid"];
        if (lid) {
            CGContextClipToMask(context, box, lid.CGImage);
            CGContextFillRect(context, box);
        }
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* rows ask for their marks on every configure and draw, and each ask rendered a new bitmap on the main thread */
UIImage *ExteriaSymbolImage(ExteriaSymbol symbol, CGFloat pointSize, UIColor *color) {
    static NSCache *cache;
    if (!cache) {
        cache = [[NSCache alloc] init];
        cache.countLimit = 128;
    }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        if ([color getWhite:&white alpha:&a]) r = g = b = white;
        else return ExteriaRenderSymbolImage(symbol, pointSize, color);
    }
    NSString *key = [NSString stringWithFormat:@"%d/%g/%g,%g,%g,%g", (int)symbol, (double)pointSize, (double)r, (double)g, (double)b, (double)a];
    UIImage *image = [[[cache objectForKey:key] retain] autorelease];
    if (!image) {
        image = ExteriaRenderSymbolImage(symbol, pointSize, color);
        if (image) [cache setObject:image forKey:key];
    }
    return image;
}

/* the bundled masks are square: msg_check is 16 units, msg_seen 25 */
#define CHECK_CANVAS 16.0
#define CHECK_DOUBLE_CANVAS 25.0

UIImage *ExteriaCheckImage(BOOL read, CGFloat pointSize, UIColor *color) {
    return ExteriaSymbolImage(read ? ExteriaSymbolCheckDouble : ExteriaSymbolCheck,
                              read ? pointSize * CHECK_DOUBLE_CANVAS / CHECK_CANVAS : pointSize, color);
}

UIImage *ExteriaStarsGlyph(CGFloat side) {
    return ExteriaSymbolImage(ExteriaSymbolStars, side, [UIColor colorWithRed:250.0 / 255 green:183.0 / 255 blue:26.0 / 255 alpha:1]);
}
