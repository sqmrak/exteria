#import <QuartzCore/QuartzCore.h>
#import "exteria_developers.h"
#import "exteria_classic_profile_controller.h"
#import "exteria_text_filter.h"

#import "exteria_avatar_view.h"
#import "exteria_classic_chrome.h"
#import "exteria_chat_settings.h"
#import "exteria_avatar_viewer.h"
#import "exteria_avatar_viewer.h"
#import "exteria_profile_hero_view.h"
#import "exteria_dialog.h"
#import "exteria_emoji_label.h"
#import "exteria_info_card_view.h"
#import "exteria_link_router.h"
#import "exteria_name_badge.h"
#import "exteria_chat_controller.h"
#import "exteria_gifts_controller.h"
#import "exteria_profile_qr_controller.h"
#import "exteria_profile_edit_controller.h"
#import "exteria_rating_view.h"
#import "exteria_profile_photo_picker.h"
#import "exteria_music_list_controller.h"
#import "exteria_music_player.h"
#import "exteria_settings_controller.h"
#import "exteria_symbol.h"
#import "exteria_session_profile.h"
#import "exteria_star_gift.h"
#import "exteria_story_feed_controller.h"
#import "exteria_person.h"
#import "exteria_platform.h"
#import "exteria_alert.h"
#import "exteria_theme.h"
#import "exteria_sheet.h"
#import "exteria_weak_reference.h"

#define AVATAR 84.0
#define HEADER_HEIGHT 150.0
#define BLOCK_MARGIN 10.0
#define BLOCK_GAP 8.0
#define ACTION_HEIGHT 62.0
#define MUSIC_HEIGHT 56.0
#define MUSIC_COVER 40.0

/* a lit plate with the symbol over its word, the three blocks under the name; the plate is drawn by the classic chrome so it follows the theme */
@interface ExteriaClassicProfileAction : UIControl {
    UIImageView *_plate;
    UIImageView *_icon;
    UILabel *_caption;
}
- (id)initWithSymbol:(ExteriaSymbol)symbol title:(NSString *)title;
@end

@implementation ExteriaClassicProfileAction

- (id)initWithSymbol:(ExteriaSymbol)symbol title:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _plate = [[UIImageView alloc] initWithImage:ExteriaClassicPlateImage()];
    _plate.userInteractionEnabled = NO;
    [self addSubview:_plate];
    _icon = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(symbol, 24, ExteriaColorAccent())];
    _icon.contentMode = UIViewContentModeCenter;
    [self addSubview:_icon];
    _caption = [[UILabel alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.textAlignment = ExteriaTextAlignmentCenter;
    _caption.font = [UIFont boldSystemFontOfSize:12];
    _caption.textColor = ExteriaThemeIsDark() ? ExteriaColorTitle() : [UIColor blackColor];
    _caption.adjustsFontSizeToFitWidth = YES;
    _caption.text = title;
    [self addSubview:_caption];
    self.accessibilityLabel = title;
    return self;
}

- (void)dealloc {
    [_plate release];
    [_icon release];
    [_caption release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _plate.frame = self.bounds;
    _icon.frame = CGRectMake(floor((size.width - 28) / 2), 8, 28, 28);
    _caption.frame = CGRectMake(4, 38, MAX(0, size.width - 8), 16);
}

/* the plate has no pressed picture of its own, so the whole block dims */
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1;
}

@end

/* the song the profile shows first, on the same plate: the cover, the title over the performer; a tap opens the list of the music */
@interface ExteriaClassicMusicPlate : UIControl {
    UIImageView *_plate;
    UIImageView *_cover;
    UIImageView *_note;
    ExteriaEmojiLabel *_title;
    ExteriaEmojiLabel *_performer;
    ExteriaMedia *_track;
    ExteriaMediaCache *_media;
}
@property (nonatomic, retain) ExteriaMedia *track;
@property (nonatomic, retain) ExteriaMediaCache *media;
@end

@implementation ExteriaClassicMusicPlate

@synthesize track = _track;
@synthesize media = _media;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    BOOL dark = ExteriaThemeIsDark();
    _plate = [[UIImageView alloc] initWithImage:ExteriaClassicPlateImage()];
    _plate.userInteractionEnabled = NO;
    [self addSubview:_plate];
    _cover = [[UIImageView alloc] init];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = 6;
    _cover.backgroundColor = [UIColor colorWithWhite:dark ? 1 : 0 alpha:0.12];
    _cover.userInteractionEnabled = NO;
    [self addSubview:_cover];
    _note = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolMusic, 22, ExteriaColorAccent())];
    _note.contentMode = UIViewContentModeCenter;
    _note.userInteractionEnabled = NO;
    [self addSubview:_note];
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.font = [UIFont boldSystemFontOfSize:16];
    _title.textColor = dark ? ExteriaColorTitle() : [UIColor blackColor];
    _title.dropsUndrawable = YES;
    _title.userInteractionEnabled = NO;
    [self addSubview:_title];
    _performer = [[ExteriaEmojiLabel alloc] init];
    _performer.font = [UIFont systemFontOfSize:13];
    _performer.textColor = dark ? ExteriaColorSecondary() : [UIColor grayColor];
    _performer.dropsUndrawable = YES;
    _performer.userInteractionEnabled = NO;
    [self addSubview:_performer];
    self.hidden = YES;
    return self;
}

- (void)dealloc {
    [_plate release];
    [_cover release];
    [_note release];
    [_title release];
    [_performer release];
    [_track release];
    [_media release];
    [super dealloc];
}

- (void)setTrack:(ExteriaMedia *)track {
    if (track == _track) return;
    [_track release];
    _track = [track retain];
    self.hidden = track == nil;
    _title.text = track ? ExteriaTrackTitle(track) : @"";
    _performer.text = track ? ExteriaTrackPerformer(track) : @"";
    _cover.image = nil;
    _note.hidden = NO;
    self.accessibilityLabel = track ? ExteriaTrackLine(track) : nil;
    [self setNeedsLayout];
    if (!track || !_media) return;
    ExteriaMedia *requested = track;
    [_media loadCoverForTrack:track maxSide:MUSIC_COVER * ExteriaScreenScale() completion:^(UIImage *image) {
        if (!image || requested != _track) return;
        _cover.image = image;
        _note.hidden = YES;
    }];
}

- (BOOL)hasContent { return _track != nil; }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _plate.frame = self.bounds;
    CGFloat inset = floor((size.height - MUSIC_COVER) / 2);
    _cover.frame = CGRectMake(inset, inset, MUSIC_COVER, MUSIC_COVER);
    _note.frame = _cover.frame;
    CGFloat left = CGRectGetMaxX(_cover.frame) + 10;
    CGFloat width = MAX(0, size.width - left - 12);
    BOOL hasPerformer = _performer.text.length > 0;
    _title.frame = CGRectMake(left, hasPerformer ? 9 : floor((size.height - 20) / 2), width, 20);
    _performer.frame = CGRectMake(left, 29, width, hasPerformer ? 18 : 0);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1;
}

@end

/* a row with a value over its caption; the value is the user's own text (a bio, a channel name), so it is drawn by
   the emoji label and not by the cell's textLabel, which shows the system's emoji font */
@interface ExteriaClassicInfoCell : UITableViewCell {
    ExteriaEmojiLabel *_value;
    ExteriaEmojiLabel *_caption;
    ExteriaWeakReference *_weak;
    BOOL _row;
}
- (void)setValue:(NSString *)value caption:(NSString *)caption;
/* the cell stands as a plain row of the list: the title in bold at the margin of the others, with custom emoji after the words */
- (void)setRowTitle:(NSString *)title entities:(NSArray *)entities;
- (ExteriaEmojiLabel *)valueLabel;
- (ExteriaWeakReference *)weakReference;
/* the height a row needs for the table width; it assumes the widest grouped margin, so a row never clips a line */
+ (CGFloat)heightForValue:(NSString *)value caption:(NSString *)caption tableWidth:(CGFloat)width hasImage:(BOOL)hasImage;
@end

#define INFO_PAD 15.0
#define INFO_MARGIN 20.0
#define INFO_VALUE_LINES 6

@implementation ExteriaClassicInfoCell

static UIFont *ExteriaClassicInfoValueFont(void) { return [UIFont systemFontOfSize:17]; }
static UIFont *ExteriaClassicInfoCaptionFont(void) { return [UIFont systemFontOfSize:13]; }

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    BOOL dark = ExteriaThemeIsDark();
    _value = [[ExteriaEmojiLabel alloc] init];
    _value.font = ExteriaClassicInfoValueFont();
    _value.textColor = dark ? ExteriaColorTitle() : [UIColor blackColor];
    _value.numberOfLines = INFO_VALUE_LINES;
    [self.contentView addSubview:_value];
    _caption = [[ExteriaEmojiLabel alloc] init];
    _caption.font = ExteriaClassicInfoCaptionFont();
    _caption.textColor = dark ? ExteriaColorSecondary() : [UIColor grayColor];
    [self.contentView addSubview:_caption];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_value release];
    [_caption release];
    [super dealloc];
}

- (void)setValue:(NSString *)value caption:(NSString *)caption {
    _value.text = value;
    BOOL bio = [caption isEqualToString:NSLocalizedString(@"profile.about", nil)];
    _value.entities = bio ? ExteriaInfoMentions(value) : nil;
    _value.linkColor = bio ? ExteriaColorAccent() : nil;
    _value.userInteractionEnabled = bio;
    if (bio && !_value.gestureRecognizers.count) {
        UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapBio:)] autorelease];
        [_value addGestureRecognizer:tap];
    }
    _caption.text = caption;
    [self setNeedsLayout];
}

- (void)tapBio:(UITapGestureRecognizer *)tap {
    NSString *link = [_value linkAtPoint:[tap locationInView:_value]];
    if (link.length) [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaOpenLinkNotification object:self
                                                                       userInfo:[NSDictionary dictionaryWithObject:link forKey:@"url"]];
}

- (ExteriaEmojiLabel *)valueLabel { return _value; }
- (ExteriaWeakReference *)weakReference { return _weak; }

- (void)setRowTitle:(NSString *)title entities:(NSArray *)entities {
    _row = YES;
    _value.font = [UIFont boldSystemFontOfSize:17];
    _value.numberOfLines = 1;
    [self setValue:title caption:nil];
    _value.entities = entities;
}

+ (CGFloat)heightForValue:(NSString *)value caption:(NSString *)caption tableWidth:(CGFloat)width hasImage:(BOOL)hasImage {
    CGFloat room = width - 2 * INFO_MARGIN - 2 * INFO_PAD - (hasImage ? 34 : 0);
    ExteriaEmojiLabel *probe = [[[ExteriaEmojiLabel alloc] init] autorelease];
    probe.font = ExteriaClassicInfoValueFont();
    probe.numberOfLines = INFO_VALUE_LINES;
    probe.text = value;
    CGFloat text = ceil([probe sizeThatFits:CGSizeMake(MAX(room, 1), CGFLOAT_MAX)].height);
    return MAX(44, text + (caption.length ? 17 : 0) + 18);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    /* a plain row of the list starts where its title does, 10 points into the cell */
    CGFloat left = _row ? 10 : INFO_PAD;
    if (self.imageView.image) left = CGRectGetMaxX(self.imageView.frame) + 10;
    CGFloat width = MAX(1, bounds.size.width - left - INFO_PAD);
    CGFloat captionHeight = _caption.text.length ? 17 : 0;
    CGSize fit = [_value sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    CGFloat valueHeight = ceil(fit.height);
    CGFloat top = floor((bounds.size.height - valueHeight - captionHeight) / 2);
    _value.frame = CGRectMake(left, top, width, valueHeight);
    _caption.frame = CGRectMake(left, top + valueHeight, width, captionHeight);
}

@end

@interface ExteriaClassicProfileController () {
    ExteriaSession *_session;
    ExteriaWeakReference *_weak;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickerLibrary;
    ExteriaPerson *_person;
    NSString *_about;
    ExteriaFullUser *_full;
    NSString *_starsText;
    NSArray *_infoRows;
    BOOL _uploading;
    ExteriaAvatarView *_avatar;
    ExteriaProfileHeroView *_hero;
    CGRect _heroCircle;
    BOOL _heroOpen;
    BOOL _heroMoving;
    BOOL _viewerWanted;
    ExteriaEmojiLabel *_name;
    UILabel *_detail;
    ExteriaRatingBadge *_ratingBadge;
    ExteriaClassicProfileAction *_photoAction;
    ExteriaClassicProfileAction *_editAction;
    ExteriaClassicProfileAction *_settingsAction;
    ExteriaClassicMusicPlate *_musicPlate;
    UIActivityIndicatorView *_spinner;
    BOOL _working;
    void (^_signOutHandler)(void (^)(NSString *));
}
@end

@implementation ExteriaClassicProfileController

@synthesize signOutHandler = _signOutHandler;
@synthesize media = _media;
@synthesize stickerLibrary = _stickerLibrary;

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _session = [session retain];
    _avatars = [avatars retain];
    self.title = NSLocalizedString(@"tab.profile", nil);
    return self;
}

/* the photo opened wide in the header of the list: the circle grows to the width of the screen and the rows move down, so it scrolls with the list */
- (void)openAvatars {
    if (_hero || !_person || _heroMoving) return;
    UITableView *table = self.tableView;
    UIView *header = table.tableHeaderView;
    ExteriaProfileHeroView *hero = [[[ExteriaProfileHeroView alloc] initWithSession:_session dialog:[ExteriaDialog savedMessagesWithPerson:_person] avatars:_avatars media:_media] autorelease];
    hero.name.text = _name.text;
    hero.name.entities = _name.entities;
    hero.status.text = _detail.text;
    /* the classic profile has no cards on the lower edge of the photo, so the words stand on it instead of high above it */
    hero.bottomRoom = 18;
    [hero setRatingLevel:_ratingBadge.hidden ? 0 : _ratingBadge.level target:self action:@selector(openRating)];
    _heroCircle = _avatar.frame;
    hero.frame = _heroCircle;
    hero.layer.cornerRadius = _heroCircle.size.width / 2;
    [hero beginMove];
    [header insertSubview:hero aboveSubview:_avatar];
    _hero = [hero retain];
    _heroOpen = YES;
    _heroMoving = YES;
    BOOL motion = !ExteriaReduceMotionEnabled();
    [hero animateCornerTo:0 duration:motion ? 0.38 : 0];
    [UIView animateWithDuration:motion ? 0.38 : 0 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        _name.alpha = 0;
        _detail.alpha = 0;
        /* the hero draws its own badge on its status line; the one of the header would stay over the wide photo, on top of the name */
        _ratingBadge.alpha = 0;
        [self layoutHeroHeader];
    } completion:^(BOOL finished) {
        (void)finished;
        _heroMoving = NO;
        _avatar.hidden = YES;
        [_hero finishOpen];
        if (_viewerWanted) {
            _viewerWanted = NO;
            [self openAvatarViewer];
        }
    }];
}

/* the photos on the whole screen; the arrow of the viewer comes back to the wide photo, which stays open under it */
- (void)openAvatarViewer {
    if (!_hero || !_heroOpen || _heroMoving || self.presentedViewController) return;
    ExteriaAvatarViewer *viewer = [[[ExteriaAvatarViewer alloc] initWithSession:_session dialog:[ExteriaDialog savedMessagesWithPerson:_person] avatars:_avatars media:_media] autorelease];
    viewer.title = _person.name;
    viewer.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)closeHero {
    if (!_hero || !_heroOpen || _heroMoving) return;
    _heroMoving = YES;
    _heroOpen = NO;
    _avatar.hidden = NO;
    [_hero beginClose];
    BOOL motion = !ExteriaReduceMotionEnabled();
    [_hero animateCornerTo:_heroCircle.size.width / 2 duration:motion ? 0.38 : 0];
    [UIView animateWithDuration:motion ? 0.38 : 0 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        _name.alpha = 1;
        _detail.alpha = 1;
        _ratingBadge.alpha = 1;
        [self layoutHeroHeader];
    } completion:^(BOOL finished) {
        (void)finished;
        _heroMoving = NO;
        [_hero removeFromSuperview];
        [_hero release];
        _hero = nil;
    }];
}

/* the header is as tall as the wide photo while it is open and as it was before; the list under it slides with the change */
- (void)layoutHeroHeader {
    UITableView *table = self.tableView;
    UIView *header = table.tableHeaderView;
    CGFloat width = table.bounds.size.width;
    CGFloat wide = [ExteriaProfileHeroView heightForWidth:width screenHeight:self.view.bounds.size.height];
    if (_hero) _hero.frame = _heroOpen ? CGRectMake(0, 0, width, wide) : _heroCircle;
    CGRect frame = header.frame;
    frame.size.height = [self layoutBlocksBelow:_heroOpen ? wide : HEADER_HEIGHT width:width];
    header.frame = frame;
    [table beginUpdates];
    table.tableHeaderView = header;
    [table endUpdates];
}

/* the three blocks and the song stand under the photo, or under the wide photo while it is open; returns the height the header needs */
- (CGFloat)layoutBlocksBelow:(CGFloat)photoBottom width:(CGFloat)width {
    CGFloat y = photoBottom + BLOCK_GAP;
    CGFloat room = MAX(0, width - 2 * BLOCK_MARGIN - 2 * BLOCK_GAP);
    CGFloat slot = floor(room / 3);
    _photoAction.frame = CGRectMake(BLOCK_MARGIN, y, slot, ACTION_HEIGHT);
    _editAction.frame = CGRectMake(BLOCK_MARGIN + slot + BLOCK_GAP, y, slot, ACTION_HEIGHT);
    _settingsAction.frame = CGRectMake(BLOCK_MARGIN + 2 * (slot + BLOCK_GAP), y, room - 2 * slot, ACTION_HEIGHT);
    y += ACTION_HEIGHT;
    if (_musicPlate.hasContent) {
        y += BLOCK_GAP;
        _musicPlate.frame = CGRectMake(BLOCK_MARGIN, y, MAX(0, width - 2 * BLOCK_MARGIN), MUSIC_HEIGHT);
        y += MUSIC_HEIGHT;
    }
    return y + 6;
}

/* the header grows with the song that arrives after the full profile */
- (void)fitHeader {
    UITableView *table = self.tableView;
    UIView *header = table.tableHeaderView;
    if (!header || _heroMoving) return;
    CGFloat width = table.bounds.size.width;
    CGFloat photoBottom = _heroOpen ? [ExteriaProfileHeroView heightForWidth:width screenHeight:self.view.bounds.size.height] : HEADER_HEIGHT;
    CGFloat height = [self layoutBlocksBelow:photoBottom width:width];
    if (fabs(header.frame.size.height - height) < 0.5) return;
    CGRect frame = header.frame;
    frame.size.height = height;
    header.frame = frame;
    table.tableHeaderView = header;
}

- (void)openSettings {
    UITabBarController *tabs = self.tabBarController;
    NSArray *screens = tabs.viewControllers;
    for (NSUInteger i = 0; i < screens.count; ++i) {
        UINavigationController *navigation = [screens objectAtIndex:i];
        if (![navigation isKindOfClass:[UINavigationController class]] || !navigation.viewControllers.count) continue;
        if ([[navigation.viewControllers objectAtIndex:0] isKindOfClass:[ExteriaSettingsController class]]) {
            tabs.selectedIndex = i;
            return;
        }
    }
    /* a layout without a settings tab still has to reach them */
    ExteriaSettingsController *settings = [[[ExteriaSettingsController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    settings.signOutHandler = _signOutHandler;
    [self.navigationController pushViewController:settings animated:YES];
}

- (void)openMusic {
    ExteriaDialog *own = _person && _media ? [ExteriaDialog savedMessagesWithPerson:_person] : nil;
    if (!own) return;
    ExteriaMusicListController *list = [[[ExteriaMusicListController alloc] initWithSession:_session dialog:own first:_full.music avatars:_avatars media:_media] autorelease];
    [self.navigationController pushViewController:list animated:YES];
}

- (void)editProfile {
    if (!_person) return;
    ExteriaProfileEditController *edit = [[[ExteriaProfileEditController alloc] initWithSession:_session person:_person fullUser:_full avatars:_avatars media:_media] autorelease];
    ExteriaWeakReference *weak = _weak;
    edit.changedHandler = ^{ [(ExteriaClassicProfileController *)weak.target loadProfile]; };
    edit.logoutHandler = ^{ [(ExteriaClassicProfileController *)weak.target confirmSignOut]; };
    [self.navigationController pushViewController:edit animated:YES];
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    /* a tab nobody opened has no view, and asking for it here would load one while the controller is being freed */
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaChatSettingsDidChangeNotification object:nil];
    if ([self isViewLoaded]) {
        self.tableView.delegate = nil;
        self.tableView.dataSource = nil;
    }
    [_signOutHandler release];
    [_session release];
    [_avatars release];
    [_media release];
    [_stickerLibrary release];
    [_person release];
    [_about release];
    [_full release];
    [_starsText release];
    [_infoRows release];
    [_hero release];
    [_avatar release];
    [_name release];
    [_detail release];
    [_ratingBadge release];
    [_photoAction release];
    [_editAction release];
    [_settingsAction release];
    [_musicPlate release];
    [_spinner release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatSettingsChanged) name:ExteriaChatSettingsDidChangeNotification object:nil];
    UITableView *table = self.tableView;
    ExteriaClassicStyleTable(table);
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, table.bounds.size.width, HEADER_HEIGHT)] autorelease];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _avatar = [[ExteriaAvatarView alloc] initWithFrame:CGRectMake(0, 14, AVATAR, AVATAR)];
    _avatar.accent = YES;
    _avatar.userInteractionEnabled = YES;
    [_avatar addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openAvatars)] autorelease]];
    [header addSubview:_avatar];
    _name = [[ExteriaEmojiLabel alloc] initWithFrame:CGRectMake(16, 106, header.bounds.size.width - 32, 24)];
    _name.font = [UIFont boldSystemFontOfSize:20];
    _name.textAlignment = ExteriaTextAlignmentCenter;
    _name.textColor = ExteriaThemeIsDark() ? ExteriaColorTitle() : [UIColor blackColor];
    /* as every other name of the app is drawn: letters of a styled nick that the system font lacks are dropped, not shown as boxes */
    _name.dropsUndrawable = YES;
    _name.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:_name];
    _detail = [[UILabel alloc] initWithFrame:CGRectMake(16, 130, header.bounds.size.width - 32, 18)];
    _detail.backgroundColor = [UIColor clearColor];
    _detail.font = [UIFont systemFontOfSize:14];
    _detail.textAlignment = ExteriaTextAlignmentCenter;
    _detail.textColor = ExteriaThemeIsDark() ? ExteriaColorSecondary() : [UIColor grayColor];
    _detail.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:_detail];
    _ratingBadge = [[ExteriaRatingBadge alloc] initWithFrame:CGRectZero];
    _ratingBadge.hidden = YES;
    [_ratingBadge addTarget:self action:@selector(openRating) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:_ratingBadge];
    _photoAction = [[ExteriaClassicProfileAction alloc] initWithSymbol:ExteriaSymbolCameraPlus title:NSLocalizedString(@"profile.choosephoto", nil)];
    [_photoAction addTarget:self action:@selector(choosePhoto) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:_photoAction];
    _editAction = [[ExteriaClassicProfileAction alloc] initWithSymbol:ExteriaSymbolCompose title:NSLocalizedString(@"profile.edit", nil)];
    [_editAction addTarget:self action:@selector(editProfile) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:_editAction];
    _settingsAction = [[ExteriaClassicProfileAction alloc] initWithSymbol:ExteriaSymbolGear title:NSLocalizedString(@"tab.settings", nil)];
    [_settingsAction addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:_settingsAction];
    _musicPlate = [[ExteriaClassicMusicPlate alloc] init];
    _musicPlate.media = _media;
    [_musicPlate addTarget:self action:@selector(openMusic) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:_musicPlate];
    header.frame = CGRectMake(0, 0, table.bounds.size.width, [self layoutBlocksBelow:HEADER_HEIGHT width:table.bounds.size.width]);
    table.tableHeaderView = header;
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [self loadProfile];
}

/* a long pull goes through the whole opening of the wide photo in one drag: the part that came while it opened is kept, or the photos would ask for a second pull */
- (BOOL)holdsPullWhileOpening:(CGFloat)pull {
    if (!_heroMoving) return NO;
    if (_heroOpen && pull > 130) _viewerWanted = YES;
    return YES;
}

/* the screen's own swipes: a pull down opens the photo wide, a longer one opens the photos, and scrolling up closes the wide photo */
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat pull = -(scrollView.contentOffset.y + scrollView.contentInset.top);
    if ([self holdsPullWhileOpening:pull]) return;
    if (!_hero) {
        if (pull > 60) [self openAvatars];
    } else if (_heroOpen) {
        /* the pull down goes on from the wide photo to the photos on the whole screen, and scrolling up takes it back to the circle */
        if (pull > 130) [self openAvatarViewer];
        else if (-pull > 90) [self closeHero];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    UIView *header = self.tableView.tableHeaderView;
    if (header && width > 0 && header.frame.size.width != width) {
        CGRect frame = header.frame;
        frame.size.width = width;
        header.frame = frame;
        self.tableView.tableHeaderView = header;
    }
    _avatar.frame = CGRectMake((width - AVATAR) / 2, 14, AVATAR, AVATAR);
    if (_hero && !_heroMoving) _hero.frame = _heroOpen ? CGRectMake(0, 0, width, [ExteriaProfileHeroView heightForWidth:width screenHeight:self.view.bounds.size.height]) : _avatar.frame;
    _name.frame = CGRectMake(16, 106, MAX(0, width - 32), 24);
    _detail.frame = CGRectMake(16, 130, MAX(0, width - 32), 18);
    CGFloat detailWidth = MIN(width - 70, ceil([_detail sizeThatFits:CGSizeMake(width - 70, 20)].width));
    _ratingBadge.frame = CGRectMake(floor((width - detailWidth) / 2) - 26, _detail.frame.origin.y, 22, 20);
    [self fitHeader];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

/* the name, the line under it, the photo and the rows, from the person that is held */
- (void)chatSettingsChanged {
    if (_person) [self showPerson];
}

- (void)showPerson {
    NSArray *hammer = nil;
    /* the mark after the name is the one the lists and the chat show: the status the person chose, or the Premium star */
    long long badge = ExteriaPersonBadgeDocument(_person);
    _name.text = ExteriaNameWithBadges(_person.name, badge, ExteriaPersonIsDeveloper(_person), &hammer);
    _name.entities = hammer;
    ExteriaWeakReference *weak = _weak;
    ExteriaLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:badge]], _session, _media, ^{
        ExteriaClassicProfileController *profile = weak.target;
        if (profile) [profile->_name setNeedsDisplay];
    });
    NSMutableArray *parts = [NSMutableArray array];
    if (_person.phone.length) [parts addObject:ExteriaOwnPhoneText(_person.phone)];
    if (_person.username.length) [parts addObject:[@"@" stringByAppendingString:_person.username]];
    _detail.text = _person.userId == EXTERIA_TELEGRAM_SERVICE_USER_ID ? NSLocalizedString(@"chat.status.telegram", nil) : [parts componentsJoinedByString:@"  "];
    _avatar.initials = _person.initials;
    _avatar.deleted = _person.deleted;
    _avatar.seed = (NSUInteger)(_person.userId % 1000003);
    [_avatar setPhoto:_person.photo cache:_avatars];
    [self rebuildInfo];
}

- (void)loadProfile {
    /* the profile of the last time draws at once, and the answer corrects it */
    if (!_person && [_session ownPerson]) {
        _person = [[_session ownPerson] retain];
        [_avatars pinPhoto:_person.photo];
        [self showPerson];
    }
    [self retain];
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        [self autorelease];
        if (!items) {
            NSLog(@"exteria: profile did not load: %@", errorName);
            return;
        }
        [_person release];
        _person = [[items objectAtIndex:0] retain];
        [self showPerson];
        [self loadFull];
    }];
    [self retain];
    [_session loadStarsBalance:^(long long stars, NSString *errorName) {
        [self autorelease];
        if (errorName) return;
        [_starsText release];
        _starsText = [ExteriaStarsText(stars) copy];
        [self rebuildInfo];
    }];
}

/* the bio, the birthday and the personal channel come with the full profile */
- (void)loadFull {
    if (!_person) return;
    [self retain];
    [_session loadFullUserOfDialog:[ExteriaDialog savedMessagesWithPerson:_person] completion:^(ExteriaFullUser *user, NSString *errorName) {
        [self autorelease];
        if (!user) {
            NSLog(@"exteria: full profile did not load: %@", errorName);
            return;
        }
        [_full release];
        _full = [user retain];
        _ratingBadge.hidden = !user.hasRating;
        _ratingBadge.level = user.rating.level;
        _ratingBadge.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"rating.level", nil), (int)user.rating.level];
        _musicPlate.media = _media;
        _musicPlate.track = user.music;
        [self.view setNeedsLayout];
        [_about release];
        _about = [user.about copy];
        [self rebuildInfo];
    }];
}

- (void)openRating { ExteriaShowRating(self.view.window, _full); }

/* the phone, the bio and the username, each only when there is one; a tap copies it */
- (void)rebuildInfo {
    NSMutableArray *rows = [NSMutableArray array];
    if (_person.phone.length) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.phone", nil), ExteriaOwnPhoneText(_person.phone), nil]];
    if (_about.length) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.about", nil), _about, nil]];
    if (_person.username.length) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.username", nil), [@"@" stringByAppendingString:_person.username], nil]];
    if (_full.hasBirthday) {
        NSDateComponents *parts = [[[NSDateComponents alloc] init] autorelease];
        parts.day = _full.birthdayDay;
        parts.month = _full.birthdayMonth;
        parts.year = _full.birthdayYear > 0 ? _full.birthdayYear : 2000;
        NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:parts];
        NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
        formatter.dateFormat = _full.birthdayYear > 0 ? @"d MMMM yyyy" : @"d MMMM";
        if (date) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.birthday", nil), [formatter stringFromDate:date], nil]];
    }
    [rows addObjectsFromArray:ExteriaIdentityRows(_person.userId, _person.photo)];
    if (_starsText.length) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.stars", nil), _starsText, nil]];
    [_infoRows release];
    _infoRows = [rows retain];
    [self.tableView reloadData];
}

/* sections: the phone and the bio, the stories and gifts, the way out; the photo, the profile and the settings are the blocks of the header */
enum { SectionInfo, SectionLists, SectionSignOut, SectionCount };

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return SectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
    case SectionInfo: return (NSInteger)_infoRows.count;
    case SectionLists: return 5 + (_full.channel ? 1 : 0);
    default: return 1;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL channelRow = indexPath.section == SectionLists && indexPath.row == 5;
    NSString *identifier = indexPath.section == SectionInfo ? @"info" : (indexPath.section == SectionSignOut ? @"signout" : (channelRow ? @"channel" : @"row"));
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        Class cellClass = (indexPath.section == SectionInfo || channelRow) ? [ExteriaClassicInfoCell class] : [UITableViewCell class];
        cell = [[[cellClass alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
        ExteriaClassicStyleCell(cell);
        if (indexPath.section == SectionSignOut) {
            cell.textLabel.textAlignment = ExteriaTextAlignmentCenter;
            cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
        } else if (indexPath.section != SectionInfo) {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    cell.accessoryView = nil;
    switch (indexPath.section) {
    case SectionInfo: {
        NSArray *row = [_infoRows objectAtIndex:(NSUInteger)indexPath.row];
        [(ExteriaClassicInfoCell *)cell setValue:[row objectAtIndex:1] caption:[row objectAtIndex:0]];
        cell.imageView.image = [[row objectAtIndex:0] isEqualToString:NSLocalizedString(@"profile.stars", nil)] ? ExteriaStarsGlyph(24) : nil;
        break;
    }
    case SectionLists: {
        NSString *keys[4] = {@"profile.tab.stories", @"profile.tab.archive", @"gifts.title", @"profile.qr"};
        if (indexPath.row < 4) cell.textLabel.text = NSLocalizedString(keys[indexPath.row], nil);
        else if (indexPath.row == 4) cell.textLabel.text = NSLocalizedString(@"music.title", nil);
        else {
            ExteriaDialog *channel = _full.channel.dialog;
            NSArray *entities = nil;
            NSString *title = ExteriaNameWithBadge([NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"profile.channel", nil), channel.title],
                                                   ExteriaBadgeDocument(channel.emojiStatus, channel.premium), &entities);
            ExteriaClassicInfoCell *info = (ExteriaClassicInfoCell *)cell;
            [info setRowTitle:title entities:entities];
            if (channel.emojiStatus) {
                ExteriaWeakReference *weak = [info weakReference];
                ExteriaLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:channel.emojiStatus]], _session, _media, ^{
                    [[(ExteriaClassicInfoCell *)weak.target valueLabel] setNeedsDisplay];
                });
            }
        }
        break;
    }
    default:
        cell.textLabel.text = NSLocalizedString(@"profile.signout", nil);
        cell.textLabel.textColor = _working ? [UIColor grayColor] : ExteriaColorAccent();
        cell.accessoryView = _working ? _spinner : nil;
        if (_working) [_spinner startAnimating];
        break;
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != SectionInfo) return tableView.rowHeight;
    NSArray *row = [_infoRows objectAtIndex:(NSUInteger)indexPath.row];
    BOOL stars = [[row objectAtIndex:0] isEqualToString:NSLocalizedString(@"profile.stars", nil)];
    return [ExteriaClassicInfoCell heightForValue:[row objectAtIndex:1] caption:[row objectAtIndex:0] tableWidth:tableView.bounds.size.width hasImage:stars];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UINavigationController *navigation = self.navigationController;
    ExteriaDialog *own = _person && _media ? [ExteriaDialog savedMessagesWithPerson:_person] : nil;
    switch (indexPath.section) {
    case SectionInfo: {
        NSArray *row = [_infoRows objectAtIndex:(NSUInteger)indexPath.row];
        [UIPasteboard generalPasteboard].string = [row objectAtIndex:1];
        break;
    }
    case SectionLists:
        if (!own) break;
        if (indexPath.row == 3) {
            [navigation pushViewController:[[[ExteriaProfileQrController alloc] initWithSession:_session person:_person avatars:_avatars media:_media] autorelease] animated:YES];
        } else if (indexPath.row == 4) {
            ExteriaMusicListController *list = [[[ExteriaMusicListController alloc] initWithSession:_session dialog:own first:_full.music avatars:_avatars media:_media] autorelease];
            [navigation pushViewController:list animated:YES];
        } else if (indexPath.row == 5) {
            [navigation pushViewController:[[[ExteriaChatController alloc] initWithSession:_session dialog:_full.channel.dialog avatars:_avatars media:_media
                                                                                  stickers:_stickerLibrary] autorelease] animated:YES];
        } else if (indexPath.row == 2) {
            ExteriaGiftsController *gifts = [[[ExteriaGiftsController alloc] initWithSession:_session dialog:own mine:YES avatars:_avatars media:_media] autorelease];
            gifts.stickers = _stickerLibrary;
            [navigation pushViewController:gifts animated:YES];
        } else {
            ExteriaProfileFeedKind kind = indexPath.row == 0 ? ExteriaFeedPinnedStories : ExteriaFeedArchivedStories;
            [navigation pushViewController:[[[ExteriaStoryFeedController alloc] initWithSession:_session kind:kind owner:own avatars:_avatars media:_media] autorelease] animated:YES];
        }
        break;
    default:
        if (_working) return;
        [self confirmSignOut];
        break;
    }
}

- (void)choosePhoto {
    if (_uploading) return;
    ExteriaWeakReference *me = _weak;
    [ExteriaProfilePhotoPicker pickWithSheetIn:ExteriaOverlayHost() picked:^(NSString *path, BOOL video) {
        ExteriaClassicProfileController *profile = me.target;
        if (!profile) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            return;
        }
        [profile uploadPhotoAtPath:path video:video];
    } failed:^{
        ExteriaShowNotice(nil, NSLocalizedString(@"attach.failed", nil));
    }];
}

- (void)uploadPhotoAtPath:(NSString *)path video:(BOOL)video {
    _uploading = YES;
    [self retain];
    void (^finished)(NSString *) = ^(NSString *errorName) {
        [self autorelease];
        _uploading = NO;
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        if (errorName) {
            NSLog(@"exteria: profile %@ not set: %@", video ? @"video" : @"photo", errorName);
            return;
        }
        [self loadProfile];
    };
    if (video) [_session uploadProfileVideoAtPath:path completion:finished];
    else [_session uploadProfilePhotoAtPath:path completion:finished];
}

/* the question is the system alert in the middle of the screen: an action sheet on an ipad is a popover with nothing to point at, and it appeared in the middle of the chat beside the list */
- (void)confirmSignOut {
    if (_working || !_signOutHandler) return;
    ExteriaWeakReference *weak = _weak;
    ExteriaConfirmAction(self, NSLocalizedString(@"profile.signout.confirm", nil), NSLocalizedString(@"profile.signout", nil),
                         ^{ [(ExteriaClassicProfileController *)weak.target signOutNow]; });
}

- (void)signOutNow {
    if (!_signOutHandler) return;
    _working = YES;
    [self.tableView reloadData];
    [self retain];
    _signOutHandler(^(NSString *errorName) {
        [self autorelease];
        _working = NO;
        [self.tableView reloadData];
        if (!errorName) return;
        Class alertClass = NSClassFromString(@"UIAlertView");
        id failure = [[alertClass alloc] initWithTitle:nil
                                               message:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                       : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]
                                              delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
        [failure show];
        [failure release];
    });
}

@end
