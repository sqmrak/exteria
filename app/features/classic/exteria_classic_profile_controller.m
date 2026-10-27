#import "exteria_developers.h"
#import "exteria_classic_profile_controller.h"
#import "exteria_text_filter.h"

#import "exteria_avatar_view.h"
#import "exteria_classic_chrome.h"
#import "exteria_avatar_viewer.h"
#import "exteria_dialog.h"
#import "exteria_emoji_label.h"
#import "exteria_name_badge.h"
#import "exteria_chat_controller.h"
#import "exteria_gifts_controller.h"
#import "exteria_profile_qr_controller.h"
#import "exteria_profile_edit_controller.h"
#import "exteria_profile_photo_picker.h"
#import "exteria_symbol.h"
#import "exteria_session_profile.h"
#import "exteria_star_gift.h"
#import "exteria_story_feed_controller.h"
#import "exteria_person.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_sheet.h"
#import "exteria_weak_reference.h"

#define AVATAR 84.0
#define HEADER_HEIGHT 150.0

/* a row with a value over its caption; the value is the user's own text (a bio, a channel name), so it is drawn by
   the emoji label and not by the cell's textLabel, which shows the system's emoji font */
@interface ExteriaClassicInfoCell : UITableViewCell {
    ExteriaEmojiLabel *_value;
    ExteriaEmojiLabel *_caption;
    BOOL _row;
}
- (void)setValue:(NSString *)value caption:(NSString *)caption;
/* the cell stands as a plain row of the list: the title in bold at the margin of the others, with custom emoji after the words */
- (void)setRowTitle:(NSString *)title entities:(NSArray *)entities;
- (ExteriaEmojiLabel *)valueLabel;
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
    [_value release];
    [_caption release];
    [super dealloc];
}

- (void)setValue:(NSString *)value caption:(NSString *)caption {
    _value.text = value;
    _caption.text = caption;
    [self setNeedsLayout];
}

- (ExteriaEmojiLabel *)valueLabel { return _value; }

- (void)setRowTitle:(NSString *)title entities:(NSArray *)entities {
    _row = YES;
    _value.font = [UIFont boldSystemFontOfSize:17];
    _value.numberOfLines = 1;
    _value.entities = entities;
    [self setValue:title caption:nil];
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
    ExteriaEmojiLabel *_name;
    UILabel *_detail;
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
    _session = [session retain];
    _avatars = [avatars retain];
    self.title = NSLocalizedString(@"tab.profile", nil);
    return self;
}

- (void)openAvatars {
    if (!_person) return;
    ExteriaAvatarViewer *viewer = [[[ExteriaAvatarViewer alloc] initWithSession:_session dialog:[ExteriaDialog savedMessagesWithPerson:_person]
                                                                        avatars:_avatars media:_media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)dealloc {
    /* a tab nobody opened has no view, and asking for it here would load one while the controller is being freed */
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
    [_avatar release];
    [_name release];
    [_detail release];
    [_spinner release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
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
    table.tableHeaderView = header;
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [self loadProfile];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _avatar.frame = CGRectMake((self.tableView.bounds.size.width - AVATAR) / 2, 14, AVATAR, AVATAR);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

/* the name, the line under it, the photo and the rows, from the person that is held */
- (void)showPerson {
    NSArray *hammer = nil;
    /* the mark after the name is the one the lists and the chat show: the status the person chose, or the Premium star */
    long long badge = ExteriaBadgeDocument(_person.emojiStatus, _person.premium);
    _name.text = ExteriaNameWithBadges(_person.name, badge, ExteriaPersonIsDeveloper(_person), &hammer);
    _name.entities = hammer;
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    ExteriaLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:badge]], _session, _media, ^{
        ExteriaClassicProfileController *profile = weak.target;
        [profile->_name setNeedsDisplay];
    });
    NSMutableArray *parts = [NSMutableArray array];
    if (_person.phone.length) [parts addObject:ExteriaOwnPhoneText(_person.phone)];
    if (_person.username.length) [parts addObject:[@"@" stringByAppendingString:_person.username]];
    _detail.text = [parts componentsJoinedByString:@"  "];
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
        [_about release];
        _about = [user.about copy];
        [self rebuildInfo];
    }];
}

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

/* sections: the photo and the profile, the phone and the bio, the stories and gifts, the way out */
enum { SectionActions, SectionInfo, SectionLists, SectionSignOut, SectionCount };

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return SectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
    case SectionActions: return 2;
    case SectionInfo: return (NSInteger)_infoRows.count;
    case SectionLists: return 4 + (_full.channel ? 1 : 0);
    default: return 1;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL channelRow = indexPath.section == SectionLists && indexPath.row == 4;
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
    case SectionActions:
        cell.textLabel.text = NSLocalizedString(indexPath.row == 0 ? @"profile.photo" : @"profile.edit", nil);
        break;
    case SectionInfo: {
        NSArray *row = [_infoRows objectAtIndex:(NSUInteger)indexPath.row];
        [(ExteriaClassicInfoCell *)cell setValue:[row objectAtIndex:1] caption:[row objectAtIndex:0]];
        cell.imageView.image = [[row objectAtIndex:0] isEqualToString:NSLocalizedString(@"profile.stars", nil)] ? ExteriaStarsGlyph(24) : nil;
        break;
    }
    case SectionLists: {
        NSString *keys[4] = {@"profile.tab.stories", @"profile.tab.archive", @"gifts.title", @"profile.qr"};
        if (indexPath.row < 4) cell.textLabel.text = NSLocalizedString(keys[indexPath.row], nil);
        else {
            ExteriaDialog *channel = _full.channel.dialog;
            NSArray *entities = nil;
            NSString *title = ExteriaNameWithBadge([NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"profile.channel", nil), channel.title],
                                                   ExteriaBadgeDocument(channel.emojiStatus, channel.premium), &entities);
            ExteriaClassicInfoCell *info = (ExteriaClassicInfoCell *)cell;
            [info setRowTitle:title entities:entities];
            if (channel.emojiStatus) {
                ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:info];
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
    case SectionActions:
        if (indexPath.row == 0) {
            [self choosePhoto];
        } else if (_person) {
            ExteriaProfileEditController *edit = [[[ExteriaProfileEditController alloc] initWithSession:_session person:_person fullUser:_full
                                                                                                avatars:_avatars media:_media] autorelease];
            edit.changedHandler = ^{ [self loadProfile]; };
            edit.logoutHandler = ^{ [self confirmSignOut]; };
            [navigation pushViewController:edit animated:YES];
        }
        break;
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
    /* a cancelled picker calls nothing back, so the screen is not held for it */
    ExteriaWeakReference *me = [ExteriaWeakReference referenceTo:self];
    [ExteriaProfilePhotoPicker pickFrom:self picked:^(NSString *path) {
        ExteriaClassicProfileController *profile = me.target;
        if (!path) return;
        if (!profile) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            return;
        }
        [profile uploadPhotoAtPath:path];
    } unavailable:^{
        Class alertClass = NSClassFromString(@"UIAlertView");
        id alert = [[alertClass alloc] initWithTitle:nil message:NSLocalizedString(@"attach.gallery.unavailable", nil) delegate:nil
                                   cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
        [alert show];
        [alert release];
    }];
}

- (void)uploadPhotoAtPath:(NSString *)path {
    _uploading = YES;
    [self retain];
    [_session uploadProfilePhotoAtPath:path completion:^(NSString *errorName) {
        [self autorelease];
        _uploading = NO;
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        if (errorName) {
            NSLog(@"exteria: profile photo not set: %@", errorName);
            return;
        }
        [self loadProfile];
    }];
}

/* the question is the system alert in the middle of the screen: an action sheet on an ipad is a popover with nothing to point at, and it appeared in the middle of the chat beside the list */
- (void)confirmSignOut {
    if (_working || !_signOutHandler) return;
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
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
