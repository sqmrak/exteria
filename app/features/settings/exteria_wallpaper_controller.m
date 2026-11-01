#import "exteria_wallpaper_controller.h"

#import "exteria_chat_preview_view.h"
#import "exteria_gift_screen.h"
#import "exteria_profile_photo_picker.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_tint_editor.h"
#import "exteria_tint_picker.h"
#import "exteria_wallpaper.h"
#import "exteria_wallpaper_grid_view.h"
#import "exteria_weak_reference.h"


@interface ExteriaWallpaperController () {
    ExteriaWeakReference *_weak;
    ExteriaChatPreviewView *_preview;
    ExteriaWallpaperGridView *_grid;
    UIControl<ExteriaTintControl> *_picker;
    /* the classic style makes every page again after a change of the color, and the new table starts at the top; the offset of the old one is brought back */
    CGFloat _restoreOffset;
    BOOL _restoresOffset;
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [_preview release];
    [_grid release];
    [_picker release];
    [super dealloc];
}

/* the settings table does not move for the keyboard of the hex field, which stands low on this page: the table gets room under it and brings the field up */
- (void)keyboardWillChange:(NSNotification *)note {
    NSValue *end = [note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey];
    if (![end isKindOfClass:[NSValue class]]) return;
    CGRect keyboard = [self.view convertRect:[end CGRectValue] fromView:nil];
    CGFloat covered = MAX(0, CGRectGetMaxY(self.table.frame) - keyboard.origin.y);
    UIEdgeInsets insets = self.table.contentInset;
    insets.bottom = covered;
    self.table.contentInset = insets;
    self.table.scrollIndicatorInsets = insets;
    if (covered > 0 && _picker.window) {
        [self.table scrollRectToVisible:[self.table convertRect:_picker.editingRect fromView:_picker] animated:YES];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillHideNotification object:nil];
    [self buildThemedViews];
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    ExteriaWallpaperController *again = [[[ExteriaWallpaperController alloc] init] autorelease];
    if ([self isViewLoaded]) {
        again->_restoreOffset = self.table.contentOffset.y;
        again->_restoresOffset = YES;
    }
    return again;
}

/* the offset is set once the new table has its size and its rows, clamped to what the page can scroll now */
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!_restoresOffset) return;
    UITableView *table = self.table;
    if (table.bounds.size.height <= 0 || table.contentSize.height <= 0) return;
    _restoresOffset = NO;
    CGFloat low = -table.contentInset.top;
    CGFloat high = MAX(low, table.contentSize.height - table.bounds.size.height + table.contentInset.bottom);
    table.contentOffset = CGPointMake(0, MIN(high, MAX(low, _restoreOffset)));
}

/* the preview and the tiles read their colors when they are made */
- (void)buildThemedViews {
    [_preview release];
    _preview = [[ExteriaChatPreviewView alloc] init];
    ExteriaWeakReference *previewWeak = _weak;
    _preview.heightHandler = ^{ [(ExteriaWallpaperController *)previewWeak.target updateRowHeights]; };
    [_picker release];
    /* the classic look keeps the square with metal discs; the modern one has the expressive editor */
    _picker = ExteriaThemeIsClassic() ? (UIControl<ExteriaTintControl> *)[[ExteriaTintPicker alloc] init] : (UIControl<ExteriaTintControl> *)[[ExteriaTintEditor alloc] init];
    [_picker addTarget:self action:@selector(tintCommitted:) forControlEvents:UIControlEventTouchUpInside];
    [_grid release];
    _grid = [[ExteriaWallpaperGridView alloc] init];
    ExteriaWeakReference *weak = _weak;
    _grid.galleryHandler = ^{ [(ExteriaWallpaperController *)weak.target pickPhoto]; };
    _grid.standardHandler = ^{
        ExteriaWallpaperController *me = weak.target;
        if (!me) return;
        ExteriaWallpaperSetting standard = ExteriaWallpaperStored();
        standard.kind = ExteriaWallpaperStandard;
        ExteriaWallpaperStore(standard);
        [me rebuild];
    };
    _grid.chooseHandler = ^(NSUInteger index) {
        ExteriaWallpaperSetting preset = ExteriaWallpaperPreset(index);
        ExteriaWallpaperStore(preset);
        [(ExteriaWallpaperController *)weak.target rebuild];
    };
}

- (void)tintCommitted:(UIControl<ExteriaTintControl> *)picker {
    ExteriaThemeStoreCustomTint(picker.hue, picker.saturation);
    CGPoint origin = [picker convertPoint:CGPointMake(CGRectGetMidX(picker.bounds), CGRectGetMidY(picker.bounds)) toView:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaThemeDidChangeNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:origin] forKey:ExteriaThemeOriginKey]];
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

    /* the purple of the app until a color is picked; the wallpaper does not give the app its color */
    float hue = 286, saturation = 0.6f;
    ExteriaThemeStoredCustomTint(&hue, &saturation);
    _picker.hue = hue;
    _picker.saturation = saturation;
    UIControl<ExteriaTintControl> *picker = _picker;
    ExteriaSettingsRow *tint = [ExteriaSettingsRow viewRowWithView:picker height:^CGFloat(CGFloat width) { (void)width; return picker.preferredHeight; }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.tint.header", nil) footer:nil rows:[NSArray arrayWithObject:tint]]];

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
        [me rebuild];
    } unavailable:^{
        ExteriaGiftAlert(nil, NSLocalizedString(@"attach.gallery.unavailable", nil));
    }];
}

@end
