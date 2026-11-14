#import "exteria_symbol.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_symbol_paths.h"

/* the bundled mask of a symbol, resources/icons/symbol_*, cut drawables by tools/make_assets.py */
static NSString *ExteriaSymbolMaskName(ExteriaSymbol symbol) {
    switch (symbol) {
    case ExteriaSymbolMagnifier: return @"symbol_magnifier";
    case ExteriaSymbolPlusCircle: return @"symbol_pluscircle";
    case ExteriaSymbolCompose: return @"symbol_compose";
    case ExteriaSymbolBookmark: return @"symbol_bookmark";
    case ExteriaSymbolPin: return @"symbol_pin";
    case ExteriaSymbolBellSlash: return @"symbol_bellslash";
    case ExteriaSymbolArchive: return @"symbol_archive";
    case ExteriaSymbolChevronRight: return @"symbol_chevronright";
    case ExteriaSymbolCheck: return @"symbol_check";
    case ExteriaSymbolCheckDouble: return @"symbol_checkdouble";
    case ExteriaSymbolKeyboard: return @"symbol_keyboard";
    case ExteriaSymbolSendArrow: return @"symbol_sendarrow";
    case ExteriaSymbolClock: return @"symbol_clock";
    case ExteriaSymbolArrowDown: return @"symbol_arrowdown";
    case ExteriaSymbolPlay: return @"symbol_play";
    case ExteriaSymbolDocument: return @"symbol_document";
    case ExteriaSymbolSticker: return @"symbol_sticker";
    case ExteriaSymbolBackspace: return @"symbol_backspace";
    case ExteriaSymbolMicrophone:
    case ExteriaSymbolMicrophoneSlash: return @"symbol_microphone";
    case ExteriaSymbolVideoCamera: return @"symbol_videocamera";
    case ExteriaSymbolCameraFlip: return @"symbol_cameraflip";
    case ExteriaSymbolPaperclip: return @"symbol_paperclip";
    case ExteriaSymbolGallery: return @"symbol_gallery";
    case ExteriaSymbolMapPin: return @"symbol_mappin";
    case ExteriaSymbolLock: return @"symbol_lock";
    /* one shape of the dots in the whole app: the vertical one, whatever name a screen asks for */
    case ExteriaSymbolEllipsis: return @"symbol_ellipsisvertical";
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
    case ExteriaSymbolFingerprint: return @"symbol_fingerprint";
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
    case ExteriaSymbolMessage: return @"symbol_message";
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
    case ExteriaSymbolPlayerPlay: return @"player_play";
    case ExteriaSymbolPlayerPause: return @"player_pause";
    case ExteriaSymbolPlayerPrevious: return @"player_previous";
    case ExteriaSymbolPlayerNext: return @"player_next";
    case ExteriaSymbolPlayerClose: return @"player_close";
    case ExteriaSymbolMaterialMic: return @"material_mic";
    case ExteriaSymbolMaterialVideocam: return @"material_videocam";
    case ExteriaSymbolHammer: return nil;
    case ExteriaSymbolCameraPlus: return nil;
    case ExteriaSymbolBlur: return nil;
    case ExteriaSymbolPipette: return nil;
    case ExteriaSymbolUndo: return nil;
    case ExteriaSymbolCross: return nil;
    case ExteriaSymbolChats: return nil;
    case ExteriaSymbolPerson: return nil;
    case ExteriaSymbolGear: return nil;
    case ExteriaSymbolSmiley: return nil;
    case ExteriaSymbolPhone: return nil;
    }
    return nil;
}

/* a claw hammer on a slant, in one color, drawn on a grid of 24 units as the bundled glyphs are cut: a handle with round ends, a head with soft corners, and a claw
   that curls from the head to the left */
static UIImage *ExteriaHammerImage(CGFloat side, UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    [color setFill];
    CGFloat unit = side / 24 * 0.72;
    CGContextTranslateCTM(context, side / 2, side / 2);
    CGContextScaleCTM(context, unit, unit);
    CGContextRotateCTM(context, (CGFloat)(M_PI / 4));
    CGContextTranslateCTM(context, -12, -12);
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(10.5, 7, 3, 16) cornerRadius:1.5] fill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(7.2, 2, 11, 6.4) cornerRadius:1.4] fill];
    UIBezierPath *claw = [UIBezierPath bezierPath];
    [claw moveToPoint:CGPointMake(8, 2.6)];
    [claw addCurveToPoint:CGPointMake(2, 5.8) controlPoint1:CGPointMake(5.6, 2.4) controlPoint2:CGPointMake(3.4, 3.6)];
    [claw addCurveToPoint:CGPointMake(3.6, 8.0) controlPoint1:CGPointMake(2.2, 6.8) controlPoint2:CGPointMake(2.8, 7.6)];
    [claw addCurveToPoint:CGPointMake(8, 6.9) controlPoint1:CGPointMake(4.6, 6.8) controlPoint2:CGPointMake(6, 6.4)];
    [claw closePath];
    [claw fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* a camera with the plus of "add" cut into its lower right corner, on a grid of 24 units */
static UIImage *ExteriaCameraPlusImage(CGFloat side, UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(context, side / 24, side / 24);
    [color setFill];
    UIBezierPath *camera = [UIBezierPath bezierPath];
    [camera appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(1.5, 6.2, 19, 14.3) cornerRadius:3.2]];
    [camera appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(7.2, 3, 7.4, 5) cornerRadius:1.6]];
    /* the lens is a hole: even odd fill */
    [camera appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(6.6, 9.6, 8.4, 8.4)]];
    camera.usesEvenOddFillRule = YES;
    [camera fill];
    /* the plus has a clear ring round it, cut out of the body, so it stands on its own */
    CGContextSaveGState(context);
    CGContextSetBlendMode(context, kCGBlendModeClear);
    CGContextFillEllipseInRect(context, CGRectMake(13.2, 12.2, 10.8, 10.8));
    CGContextRestoreGState(context);
    [color setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(17.6, 14.4, 1.9, 6.4) cornerRadius:0.95] fill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(15.35, 16.65, 6.4, 1.9) cornerRadius:0.95] fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* a drop on a grid of 24 units, with a small clear glint cut into its lower left so it reads as water and not as a pin */
static UIImage *ExteriaBlurImage(CGFloat side, UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(context, side / 24, side / 24);
    [color setFill];
    UIBezierPath *drop = [UIBezierPath bezierPath];
    [drop moveToPoint:CGPointMake(12, 2.2)];
    [drop addCurveToPoint:CGPointMake(18.8, 14) controlPoint1:CGPointMake(13.3, 6.2) controlPoint2:CGPointMake(18.8, 9.6)];
    [drop addCurveToPoint:CGPointMake(12, 21.4) controlPoint1:CGPointMake(18.8, 18) controlPoint2:CGPointMake(15.8, 21.4)];
    [drop addCurveToPoint:CGPointMake(5.2, 14) controlPoint1:CGPointMake(8.2, 21.4) controlPoint2:CGPointMake(5.2, 18)];
    [drop addCurveToPoint:CGPointMake(12, 2.2) controlPoint1:CGPointMake(5.2, 9.6) controlPoint2:CGPointMake(10.7, 6.2)];
    [drop closePath];
    [drop fill];
    CGContextSetBlendMode(context, kCGBlendModeClear);
    UIBezierPath *glint = [UIBezierPath bezierPath];
    [glint addArcWithCenter:CGPointMake(12, 14.4) radius:4.3 startAngle:(CGFloat)(M_PI * 0.62) endAngle:(CGFloat)(M_PI * 0.98) clockwise:YES];
    glint.lineWidth = 1.7;
    glint.lineCapStyle = kCGLineCapRound;
    [glint stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* a path in the notation of the vector drawables of the exteraless editor (absolute M, L, H, V, C and Z), on a square grid of the given size; the icons that came from there
   are kept as their own numbers instead of being redrawn by eye */
static UIBezierPath *ExteriaVectorPath(const char *d) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGPoint current = CGPointZero, start = CGPointZero;
    char command = 0;
    const char *p = d;
    while (*p) {
        while (*p == ' ' || *p == ',' || *p == '\n') ++p;
        if (!*p) break;
        if ((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z')) {
            command = *p++;
            if (command == 'Z' || command == 'z') { [path closePath]; current = start; command = 0; continue; }
        } else if (!command) break;
        double v[6];
        int need = command == 'C' ? 6 : (command == 'H' || command == 'V' ? 1 : 2);
        if (command != 'C' && command != 'M' && command != 'L' && command != 'H' && command != 'V') break;
        for (int i = 0; i < need; ++i) {
            char *end = NULL;
            v[i] = strtod(p, &end);
            if (end == p) return path;
            p = end;
            while (*p == ' ' || *p == ',') ++p;
        }
        if (command == 'M') { current = CGPointMake((CGFloat)v[0], (CGFloat)v[1]); start = current; [path moveToPoint:current]; command = 'L'; }
        else if (command == 'L') { current = CGPointMake((CGFloat)v[0], (CGFloat)v[1]); [path addLineToPoint:current]; }
        else if (command == 'H') { current.x = (CGFloat)v[0]; [path addLineToPoint:current]; }
        else if (command == 'V') { current.y = (CGFloat)v[0]; [path addLineToPoint:current]; }
        else {
            [path addCurveToPoint:CGPointMake((CGFloat)v[4], (CGFloat)v[5]) controlPoint1:CGPointMake((CGFloat)v[0], (CGFloat)v[1]) controlPoint2:CGPointMake((CGFloat)v[2], (CGFloat)v[3])];
            current = CGPointMake((CGFloat)v[4], (CGFloat)v[5]);
        }
    }
    return path;
}

/* filled when stroke is 0, otherwise a round stroke of that width in grid units */
static UIImage *ExteriaVectorImage(CGFloat side, UIColor *color, const char *d, CGFloat grid, CGFloat stroke) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextScaleCTM(UIGraphicsGetCurrentContext(), side / grid, side / grid);
    UIBezierPath *path = ExteriaVectorPath(d);
    if (stroke > 0) {
        path.lineWidth = stroke; path.lineCapStyle = kCGLineCapRound; path.lineJoinStyle = kCGLineJoinRound;
        [color setStroke]; [path stroke];
    } else {
        path.usesEvenOddFillRule = YES;
        [color setFill]; [path fill];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* the @3x bitmap of a mask (or the best one the bundle has) drawn into an alpha only bitmap of side x side pixels; NULL when the bundle has none, and the
   caller keeps the plain mask */
static CGImageRef ExteriaCreateScaledMask(NSString *name, size_t side) {
    if (side < 2 || side > 512) return NULL;
    UIImage *source = nil;
    for (NSString *suffix in [NSArray arrayWithObjects:@"@3x", @"@2x", @"", nil]) {
        NSString *path = [[NSBundle mainBundle] pathForResource:[name stringByAppendingString:suffix] ofType:@"png"];
        if (path) source = [UIImage imageWithContentsOfFile:path];
        if (source.CGImage) break;
    }
    if (!source.CGImage || CGImageGetWidth(source.CGImage) < side) return NULL;
    CGContextRef bitmap = CGBitmapContextCreate(NULL, side, side, 8, side, NULL, kCGImageAlphaOnly);
    if (!bitmap) return NULL;
    CGContextSetInterpolationQuality(bitmap, kCGInterpolationHigh);
    CGContextDrawImage(bitmap, CGRectMake(0, 0, side, side), source.CGImage);
    CGImageRef scaled = CGBitmapContextCreateImage(bitmap);
    CGContextRelease(bitmap);
    return scaled;
}

/* the mask filled with color; a bitmap on every system, so the glyphs look the same from ios 5 to the newest release */
static UIImage *ExteriaRenderSymbolImage(ExteriaSymbol symbol, CGFloat pointSize, UIColor *color) {
    if (symbol == ExteriaSymbolHammer) return ExteriaHammerImage(pointSize, color);
    if (symbol == ExteriaSymbolCameraPlus) return ExteriaCameraPlusImage(pointSize, color);
    if (symbol == ExteriaSymbolBlur) return ExteriaBlurImage(pointSize, color);
    if (symbol == ExteriaSymbolPipette) return ExteriaVectorImage(pointSize, color, "M11.793,7.207L11.293,6.707C10.902,6.317 10.902,5.683 11.293,5.293C11.683,4.902 12.317,4.902 12.707,5.293L13.707,6.293L16.439,3.561C17.025,2.975 17.975,2.975 18.561,3.561L20.439,5.439C21.025,6.025 21.025,6.975 20.439,7.561L17.707,10.293L18.707,11.293C19.098,11.683 19.098,12.317 18.707,12.707C18.317,13.098 17.683,13.098 17.293,12.707L16.793,12.207L8.879,20.121C8.316,20.684 7.553,21 6.757,21H4C3.448,21 3,20.552 3,20V17.243C3,16.447 3.316,15.684 3.879,15.121L5.06,16.302C4.81,16.552 4.67,16.89 4.67,17.243V19.33H6.757C7.11,19.33 7.448,19.19 7.698,18.941L15.612,11.026L12.974,8.388L5.06,16.302L3.879,15.121L11.793,7.207Z", 24, 0);
    if (symbol == ExteriaSymbolUndo) return ExteriaVectorImage(pointSize, color, "M34 58.5H41.5C50.6127 58.5 58 51.1127 58 42C58 32.8873 50.6127 25.5 41.5 25.5H16M29.5 39L16 25.5L29.5 12", 72, 5);
    if (symbol == ExteriaSymbolChats) return ExteriaVectorImage(pointSize, color, ExteriaPathChats, EXTERIA_PATH_CHATS_GRID, 0);
    if (symbol == ExteriaSymbolPerson) return ExteriaVectorImage(pointSize, color, ExteriaPathPerson, EXTERIA_PATH_PERSON_GRID, 0);
    if (symbol == ExteriaSymbolGear) return ExteriaVectorImage(pointSize, color, ExteriaPathGear, EXTERIA_PATH_GEAR_GRID, 0);
    if (symbol == ExteriaSymbolSmiley) return ExteriaVectorImage(pointSize, color, ExteriaPathSmiley, EXTERIA_PATH_SMILEY_GRID, 0);
    if (symbol == ExteriaSymbolPhone) return ExteriaVectorImage(pointSize, color, ExteriaPathPhone, EXTERIA_PATH_PHONE_GRID, 0);
    if (symbol == ExteriaSymbolCross) return ExteriaVectorImage(pointSize, color, "M19,6.41L17.59,5 12,10.59 6.41,5 5,6.41 10.59,12 5,17.59 6.41,19 12,13.41 17.59,19 19,17.59 13.41,12Z", 24, 0);
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
    /* the largest bitmap of the mask, brought to the exact pixels of the glyph with the best filter; the clip of a mask drawn at its own size and scaled by the
       context was soft, and the check marks, which are small and thin, showed it */
    CGImageRef sharp = symbol == ExteriaSymbolTrash ? NULL : ExteriaCreateScaledMask(name, (size_t)lround(pointSize * ExteriaScreenScale()));
    CGContextClipToMask(context, box, sharp ? sharp : mask.CGImage);
    if (sharp) CGImageRelease(sharp);
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
    if (symbol == ExteriaSymbolMicrophoneSlash) {
        /* VoIPToggleButton: a 3 unit gap cut 2 units above a 2 unit round line, both from just outside the top left of the glyph to just outside its bottom right.
           the numbers are fractions of the mask's own canvas, and the context is still flipped by the mask drawing above */
        CGFloat from[2] = {0.171, 0.160}, to[2] = {0.829, 0.840};
        CGFloat lift = 0.080, slash = 0.082, gap = 0.123;
        CGContextSetLineCap(context, kCGLineCapRound);
        CGContextSetBlendMode(context, kCGBlendModeClear);
        CGContextSetLineWidth(context, gap * size.width);
        CGContextMoveToPoint(context, from[0] * size.width, (1 - from[1] + lift) * size.height);
        CGContextAddLineToPoint(context, to[0] * size.width, (1 - to[1] + lift) * size.height);
        CGContextStrokePath(context);
        CGContextSetBlendMode(context, kCGBlendModeNormal);
        [color setStroke];
        CGContextSetLineWidth(context, slash * size.width);
        CGContextMoveToPoint(context, from[0] * size.width, (1 - from[1]) * size.height);
        CGContextAddLineToPoint(context, to[0] * size.width, (1 - to[1]) * size.height);
        CGContextStrokePath(context);
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

/* a Material glyph cut to the box its ink fills in the 24 unit canvas of the SVG, drawn so that the ink is width points wide: the masks keep their padding, which pushed
   a mark off the slot it is aligned in */
static UIImage *ExteriaInkImage(ExteriaSymbol symbol, CGRect ink, CGFloat width, UIColor *color) {
    CGFloat unit = width / ink.size.width;
    UIImage *full = ExteriaSymbolImage(symbol, 24 * unit, color);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, ink.size.height * unit), NO, 0);
    [full drawAtPoint:CGPointMake(-ink.origin.x * unit, -ink.origin.y * unit)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

ExteriaSymbol ExteriaSymbolCheckMark(void) { return ExteriaThemeIsClassic() ? ExteriaSymbolCheck : ExteriaSymbolMaterialCheck; }
ExteriaSymbol ExteriaSymbolCloseMark(void) { return ExteriaThemeIsClassic() ? ExteriaSymbolClose : ExteriaSymbolMaterialCloseOutlined; }

UIImage *ExteriaSendingImage(CGFloat pointSize, UIColor *color) {
    if (ExteriaThemeIsClassic()) return ExteriaSymbolImage(ExteriaSymbolClock, pointSize, color);
    return ExteriaInkImage(ExteriaSymbolMaterialSchedule, CGRectMake(2, 2, 20, 20), pointSize, color);
}

UIImage *ExteriaFailedImage(CGFloat pointSize, UIColor *color) {
    return ExteriaInkImage(ExteriaSymbolMaterialError, CGRectMake(2, 2, 20, 20), pointSize, color);
}

UIImage *ExteriaCheckImage(BOOL read, CGFloat pointSize, UIColor *color) {
    if (!ExteriaThemeIsClassic()) {
        /* the ink of the single check is 16.7 units wide and of the double one 22, so the pair keeps the proportion the slot of the old marks had */
        if (read) return ExteriaInkImage(ExteriaSymbolMaterialDoneAll, CGRectMake(1, 6, 22, 12), pointSize * CHECK_DOUBLE_CANVAS / CHECK_CANVAS, color);
        return ExteriaInkImage(ExteriaSymbolMaterialCheck, CGRectMake(3.6667, 6, 16.6667, 12), pointSize, color);
    }
    return ExteriaSymbolImage(read ? ExteriaSymbolCheckDouble : ExteriaSymbolCheck,
                              read ? pointSize * CHECK_DOUBLE_CANVAS / CHECK_CANVAS : pointSize, color);
}

UIImage *ExteriaStarsGlyph(CGFloat side) {
    return ExteriaSymbolImage(ExteriaSymbolStars, side, [UIColor colorWithRed:250.0 / 255 green:183.0 / 255 blue:26.0 / 255 alpha:1]);
}
