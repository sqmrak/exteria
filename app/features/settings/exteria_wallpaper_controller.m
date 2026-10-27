#import "exteria_wallpaper_controller.h"

#import "exteria_chat_preview_view.h"
#import "exteria_gift_screen.h"
#import "exteria_profile_photo_picker.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_wallpaper.h"
#import "exteria_wallpaper_grid_view.h"
#import "exteria_weak_reference.h"

@interface ExteriaWallpaperController () {
    ExteriaWeakReference *_weak;
    ExteriaChatPreviewView *_preview;
    ExteriaWallpaperGridView *_grid;
}
@end

@implementation ExteriaWallpaperController


- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"chatset.wallpaper", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_preview release];
    [_grid release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildThemedViews];
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    ExteriaWallpaperController *again = [[[ExteriaWallpaperController alloc] init] autorelease];
    return again;
}

/* the preview and the tiles read their colors when they are made */
- (void)buildThemedViews {
    [_preview release];
    _preview = [[ExteriaChatPreviewView alloc] init];
    ExteriaWeakReference *previewWeak = _weak;
    _preview.heightHandler = ^{ [(ExteriaWallpaperController *)previewWeak.target updateRowHeights]; };
    [_grid release];
    _grid = [[ExteriaWallpaperGridView alloc] init];
    ExteriaWeakReference *weak = _weak;
    ExteriaWeakReference *shown = [ExteriaWeakReference referenceTo:_grid];
    _grid.galleryHandler = ^{ [(ExteriaWallpaperController *)weak.target pickPhoto]; };
    _grid.standardHandler = ^{
        ExteriaWallpaperController *me = weak.target;
        if (!me) return;
        ExteriaWallpaperSetting standard = ExteriaWallpaperStored();
        standard.kind = ExteriaWallpaperStandard;
        ExteriaWallpaperStore(standard);
        ExteriaWallpaperRetintTheme(((ExteriaWallpaperGridView *)shown.target).tapPoint);
        [me rebuild];
    };
    _grid.chooseHandler = ^(NSUInteger index) {
        ExteriaWallpaperSetting preset = ExteriaWallpaperPreset(index);
        ExteriaWallpaperStore(preset);
        /* the wallpaper gives the whole client its hue, which spreads from the tile */
        ExteriaWallpaperRetintTheme(((ExteriaWallpaperGridView *)shown.target).tapPoint);
        [(ExteriaWallpaperController *)weak.target rebuild];
    };
}

- (void)themeDidChange {
    [self buildThemedViews];
    [self rebuild];
}

/* the index of the gradient the stored wallpaper is, NSNotFound when it is none of them (a photo, or the standard wallpaper) */
static NSUInteger ExteriaChosenPreset(void) {
    ExteriaWallpaperSetting stored = ExteriaWallpaperStored();
    if (stored.kind != ExteriaWallpaperColors) return NSNotFound;
    for (NSUInteger i = 0; i < ExteriaWallpaperPresetCount(); ++i) {
        ExteriaWallpaperSetting preset = ExteriaWallpaperPreset(i);
        if (preset.top == stored.top && preset.bottom == stored.bottom && preset.angle == stored.angle) return i;
    }
    return NSNotFound;
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    ExteriaWallpaperSetting setting = ExteriaWallpaperStored();
    NSMutableArray *sections = [NSMutableArray array];

    ExteriaChatPreviewView *preview = _preview;
    ExteriaSettingsRow *picture = [ExteriaSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { return [preview heightForWidth:width]; }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:picture]]];

    ExteriaWallpaperGridView *grid = _grid;
    grid.chosenIndex = ExteriaChosenPreset();
    grid.photoChosen = setting.kind == ExteriaWallpaperPhoto;
    grid.standardChosen = setting.kind == ExteriaWallpaperStandard;
    ExteriaSettingsRow *tiles = [ExteriaSettingsRow viewRowWithView:grid height:^CGFloat(CGFloat width) { (void)width; return [ExteriaWallpaperGridView height]; }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.wallpaper.colors", nil) footer:nil rows:[NSArray arrayWithObject:tiles]]];

    if (setting.kind == ExteriaWallpaperColors) {
        NSMutableArray *options = [NSMutableArray array];
        [options addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.wallpaper.pattern", nil) subtitle:nil on:setting.pattern != 0 toggle:^(BOOL on) {
            ExteriaWallpaperSetting next = ExteriaWallpaperStored();
            next.pattern = on ? 1 : 0;
            ExteriaWallpaperStore(next);
            [(ExteriaWallpaperController *)weak.target rebuild];
        }]];
        if (setting.pattern) {
            [options addObject:[ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.wallpaper.intensity", nil) format:@"%.0f%%" value:(float)setting.intensity
                                                              minimum:0 maximum:100 change:^(float value) {
                ExteriaWallpaperSetting next = ExteriaWallpaperStored();
                int intensity = (int)(value + 0.5f);
                if (intensity == next.intensity) return;
                next.intensity = intensity;
                ExteriaWallpaperStore(next);
            }]];
        }
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:options]];
    } else if (setting.kind == ExteriaWallpaperPhoto) {
        NSMutableArray *options = [NSMutableArray array];
        [options addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.wallpaper.blur", nil) subtitle:nil on:setting.blur != 0 toggle:^(BOOL on) {
            ExteriaWallpaperSetting next = ExteriaWallpaperStored();
            next.blur = on ? 1 : 0;
            ExteriaWallpaperStore(next);
        }]];
        [options addObject:[ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.wallpaper.dim", nil) format:@"%.0f%%" value:(float)setting.dim
                                                          minimum:0 maximum:100 change:^(float value) {
            ExteriaWallpaperSetting next = ExteriaWallpaperStored();
            int dim = (int)(value + 0.5f);
            if (dim == next.dim) return;
            next.dim = dim;
            ExteriaWallpaperStore(next);
        }]];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:options]];
    }
    self.sections = sections;
    [self reloadSettings];
}

- (void)pickPhoto {
    ExteriaWeakReference *weak = _weak;
    [ExteriaProfilePhotoPicker pickWholeFrom:self picked:^(NSString *path) {
        ExteriaWallpaperController *me = weak.target;
        BOOL used = path && ExteriaWallpaperUsePhotoAtPath(path);
        if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        if (!used) {
            NSLog(@"exteria: the wallpaper photo could not be prepared");
            ExteriaGiftAlert(nil, NSLocalizedString(@"chatset.wallpaper.failed", nil));
            return;
        }
        ExteriaWallpaperRetintTheme(CGPointMake(CGRectGetMidX([[UIScreen mainScreen] bounds]), CGRectGetMidY([[UIScreen mainScreen] bounds])));
        [me rebuild];
    } unavailable:^{
        ExteriaGiftAlert(nil, NSLocalizedString(@"attach.gallery.unavailable", nil));
    }];
}

@end
