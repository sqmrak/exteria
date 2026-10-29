#import "exteria_slider.h"
#import "exteria_music_list_controller.h"
#import "exteria_music_card.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_emoji_label.h"
#import "exteria_music_player.h"
#import "exteria_platform.h"
#import "exteria_remote_file.h"
#import "exteria_session_profile.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define ROW_HEIGHT 62.0
#define ICON_SIDE 44.0
#define PANEL_HEIGHT 128.0
#define LOAD_AHEAD 6

static NSString *ExteriaClock(NSTimeInterval seconds) {
    NSInteger total = seconds > 0 ? (NSInteger)seconds : 0;
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

/* a song of the list: a square that shows the note, or play, pause and the load while the song is the current one, over its
   title and performer, with the length at the right */
@interface ExteriaSongCell : UITableViewCell {
    UIImageView *_cover;
    NSString *_coverKey;
    UIImageView *_icon;
    ExteriaEmojiLabel *_title;
    ExteriaEmojiLabel *_performer;
    UILabel *_length;
    UIActivityIndicatorView *_spinner;
}
- (void)configureWithTrack:(ExteriaMedia *)track state:(ExteriaMusicState)state current:(BOOL)current media:(ExteriaMediaCache *)media;
@end

@implementation ExteriaSongCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    UIView *selected = [[[UIView alloc] init] autorelease];
    selected.backgroundColor = ExteriaColorField();
    self.selectedBackgroundView = selected;
    _cover = [[UIImageView alloc] init];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = 10;
    [self.contentView addSubview:_cover];
    _icon = [[UIImageView alloc] init];
    _icon.contentMode = UIViewContentModeCenter;
    _icon.layer.cornerRadius = 10;
    [self.contentView addSubview:_icon];
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.font = ExteriaFontSemibold(16);
    _title.textColor = ExteriaColorTitle();
    [self.contentView addSubview:_title];
    _performer = [[ExteriaEmojiLabel alloc] init];
    _performer.backgroundColor = [UIColor clearColor];
    _performer.font = ExteriaFontRegular(14);
    _performer.textColor = ExteriaColorSecondary();
    [self.contentView addSubview:_performer];
    _length = [[UILabel alloc] init];
    _length.backgroundColor = [UIColor clearColor];
    _length.font = ExteriaFontRegular(13);
    _length.textColor = ExteriaColorSecondary();
    _length.textAlignment = ExteriaTextAlignmentRight;
    [self.contentView addSubview:_length];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.hidesWhenStopped = YES;
    [self.contentView addSubview:_spinner];
    return self;
}

- (void)dealloc {
    [_cover release];
    [_coverKey release];
    [_icon release];
    [_title release];
    [_performer release];
    [_length release];
    [_spinner release];
    [super dealloc];
}

- (void)configureWithTrack:(ExteriaMedia *)track state:(ExteriaMusicState)state current:(BOOL)current media:(ExteriaMediaCache *)media {
    _title.text = ExteriaTrackTitle(track);
    _title.textColor = current ? ExteriaColorAccent() : ExteriaColorTitle();
    _performer.text = ExteriaTrackPerformer(track);
    _length.text = track.duration > 0 ? ExteriaClock(track.duration) : @"";
    /* the cover shows once it is in; until then, and for songs without one, the square has the note */
    NSString *key = track.file.key;
    if (!(key == _coverKey || [key isEqualToString:_coverKey])) {
        [_coverKey release];
        _coverKey = [key copy];
        _cover.image = nil;
        if (key) {
            ExteriaSongCell *cell = self;
            [self retain];
            [media loadCoverForTrack:track maxSide:ICON_SIDE * ExteriaScreenScale() completion:^(UIImage *image) {
                if (image && [key isEqualToString:cell->_coverKey]) cell->_cover.image = image;
                [cell autorelease];
            }];
        }
    }
    BOOL covered = _cover.image != nil;
    ExteriaSymbol glyph = ExteriaSymbolMusic;
    if (current) glyph = state == ExteriaMusicStatePlaying ? ExteriaSymbolPause : ExteriaSymbolPlay;
    /* a cover keeps showing under a veil while its song is the current one, and the note is only for songs without a cover */
    _icon.hidden = covered && !current;
    _icon.backgroundColor = current ? (covered ? [UIColor colorWithWhite:0 alpha:0.5] : ExteriaColorAccent()) : ExteriaColorCard();
    _icon.image = ExteriaSymbolImage(glyph, 20, current ? [UIColor whiteColor] : ExteriaColorAccent());
    BOOL loading = current && state == ExteriaMusicStateLoading;
    if (loading) {
        _icon.image = nil;
        [_spinner startAnimating];
    } else {
        [_spinner stopAnimating];
    }
    self.accessibilityLabel = ExteriaTrackLine(track);
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    _icon.frame = CGRectMake(16, (ROW_HEIGHT - ICON_SIDE) / 2, ICON_SIDE, ICON_SIDE);
    _cover.frame = _icon.frame;
    _spinner.center = CGPointMake(CGRectGetMidX(_icon.frame), CGRectGetMidY(_icon.frame));
    CGFloat textX = 16 + ICON_SIDE + 12;
    CGFloat lengthWidth = 48;
    CGFloat textWidth = width - textX - lengthWidth - 16;
    BOOL hasPerformer = _performer.text.length > 0;
    _title.frame = CGRectMake(textX, hasPerformer ? 10 : 20, textWidth, 22);
    _performer.frame = CGRectMake(textX, 32, textWidth, 20);
    _length.frame = CGRectMake(width - lengthWidth - 16, 0, lengthWidth, ROW_HEIGHT);
}

@end

@interface ExteriaMusicListController () <UITableViewDataSource, UITableViewDelegate> {
    ExteriaDialog *_dialog;
    ExteriaMedia *_first;
    NSMutableArray *_tracks;
    NSInteger _total;
    BOOL _loading;
    BOOL _loaded;
    NSString *_errorName;
    UITableView *_table;
    UILabel *_message;
    UIView *_panel;
    ExteriaMusicCard *_card;
    ExteriaEmojiLabel *_panelTitle;
    ExteriaEmojiLabel *_panelPerformer;
    UISlider *_slider;
    UILabel *_elapsed;
    UILabel *_remaining;
    UIButton *_previous;
    UIButton *_toggle;
    UIButton *_next;
    UIButton *_speed;
    BOOL _scrubbing;
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaMusicListController

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog first:(ExteriaMedia *)first avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _dialog = [dialog retain];
    _first = [first retain];
    _tracks = [[NSMutableArray alloc] init];
    if (first) [_tracks addObject:first];
    _total = first ? 1 : 0;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.screenTitle = NSLocalizedString(@"music.title", nil);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    _table.dataSource = nil;
    _table.delegate = nil;
    [_dialog release];
    [_first release];
    [_tracks release];
    [_errorName release];
    [_table release];
    [_message release];
    [_panel release];
    [_card release];
    [_panelTitle release];
    [_panelPerformer release];
    [_slider release];
    [_elapsed release];
    [_remaining release];
    [_previous release];
    [_toggle release];
    [_next release];
    [_speed release];
    [super dealloc];
}

/* titles and performers are the track's own text, so they go through the layer that finds a font for any character */
static ExteriaEmojiLabel *ExteriaListTextLabel(UIColor *color, UIFont *font, NSInteger alignment) {
    ExteriaEmojiLabel *label = [[ExteriaEmojiLabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = font;
    label.textAlignment = alignment;
    return label;
}

static UILabel *ExteriaListLabel(UIColor *color, UIFont *font, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = font;
    label.textAlignment = alignment;
    return label;
}

static UIButton *ExteriaPanelButton(ExteriaSymbol symbol, CGFloat size, id target, SEL action) {
    UIButton *button = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [button setImage:ExteriaSymbolImage(symbol, size, ExteriaColorTitle()) forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

/* the classic theme keeps the plain panel; the modern one has the card */
- (void)buildClassicPanelInView:(UIView *)root {
    _panel = [[UIView alloc] init];
    _panel.backgroundColor = ExteriaColorCard();
    _panel.layer.cornerRadius = 20;
    _panel.hidden = YES;
    [root addSubview:_panel];
    _panelTitle = ExteriaListTextLabel(ExteriaColorTitle(), ExteriaFontSemibold(16), ExteriaTextAlignmentCenter);
    [_panel addSubview:_panelTitle];
    _panelPerformer = ExteriaListTextLabel(ExteriaColorSecondary(), ExteriaFontRegular(14), ExteriaTextAlignmentCenter);
    [_panel addSubview:_panelPerformer];
    _slider = [[ExteriaSlider alloc] init];
    _slider.accessibilityLabel = NSLocalizedString(@"media.seek", nil);
    [_slider addTarget:self action:@selector(scrubBegan) forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(scrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_slider addTarget:self action:@selector(scrubMoved) forControlEvents:UIControlEventValueChanged];
    [_panel addSubview:_slider];
    _elapsed = ExteriaListLabel(ExteriaColorSecondary(), ExteriaFontRegular(12), ExteriaTextAlignmentLeft);
    [_panel addSubview:_elapsed];
    _remaining = ExteriaListLabel(ExteriaColorSecondary(), ExteriaFontRegular(12), ExteriaTextAlignmentRight);
    [_panel addSubview:_remaining];
    _previous = ExteriaPanelButton(ExteriaSymbolPrevious, 24, self, @selector(previousTapped));
    _previous.accessibilityLabel = NSLocalizedString(@"music.previous", nil);
    [_panel addSubview:_previous];
    _toggle = ExteriaPanelButton(ExteriaSymbolPlay, 32, self, @selector(toggleTapped));
    [_panel addSubview:_toggle];
    _next = ExteriaPanelButton(ExteriaSymbolNext, 24, self, @selector(nextTapped));
    _next.accessibilityLabel = NSLocalizedString(@"music.next", nil);
    [_panel addSubview:_next];
    _speed = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _speed.titleLabel.font = ExteriaFontSemibold(14);
    [_speed setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    _speed.layer.cornerRadius = 12;
    _speed.layer.borderWidth = 1;
    _speed.layer.borderColor = ExteriaColorAccent().CGColor;
    [_speed addTarget:self action:@selector(speedTapped) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:_speed];
}

- (void)buildBodyInView:(UIView *)root {
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.rowHeight = ROW_HEIGHT;
    _table.dataSource = self;
    _table.delegate = self;
    [root addSubview:_table];
    _message = ExteriaListLabel(ExteriaColorSecondary(), ExteriaFontRegular(15), ExteriaTextAlignmentCenter);
    _message.numberOfLines = 0;
    [root addSubview:_message];

    if (ExteriaThemeIsClassic()) {
        [self buildClassicPanelInView:root];
    } else {
        _card = [[ExteriaMusicCard alloc] init];
        _card.hidden = YES;
        [root addSubview:_card];
    }

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(playerChanged:) name:ExteriaMusicPlayerDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(playerTicked:) name:ExteriaMusicPlayerDidTickNotification object:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadMore];
    [self refreshPanel];
}

#pragma mark data

- (void)loadMore {
    if (_loading || (_loaded && (NSInteger)_tracks.count >= _total)) return;
    _loading = YES;
    /* the song the profile showed is the first of the list, so a page that comes back with it must not list it twice */
    NSInteger offset = _loaded ? (NSInteger)_tracks.count : 0;
    ExteriaWeakReference *me = _weak;
    [self retain];
    [self.session loadSavedMusicOfDialog:_dialog offset:offset completion:^(NSArray *tracks, NSInteger total, NSString *errorName) {
        [self autorelease];
        ExteriaMusicListController *list = me.target;
        if (!list) return;
        list->_loading = NO;
        if (!tracks) {
            NSLog(@"exteria: saved music not loaded: %@", errorName);
            [list->_errorName release];
            list->_errorName = [errorName copy];
            [list showState];
            return;
        }
        [list->_errorName release];
        list->_errorName = nil;
        if (!list->_loaded) [list->_tracks removeAllObjects];
        list->_loaded = YES;
        [list->_tracks addObjectsFromArray:tracks];
        list->_total = total;
        /* a page with no songs ends the list, whatever the count said */
        if (!tracks.count) list->_total = (NSInteger)list->_tracks.count;
        [list->_table reloadData];
        [list showState];
    }];
}

- (void)showState {
    NSString *text = @"";
    if (!_tracks.count) {
        if (_errorName) text = [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), _errorName];
        else if (_loaded) text = NSLocalizedString(@"music.empty", nil);
        else text = NSLocalizedString(@"profile.loading", nil);
    }
    _message.text = text;
    _message.hidden = text.length == 0;
    [self.view setNeedsLayout];
}

#pragma mark table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"song";
    ExteriaSongCell *cell = (ExteriaSongCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaSongCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    ExteriaMedia *track = [_tracks objectAtIndex:(NSUInteger)indexPath.row];
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    [cell configureWithTrack:track state:player.state current:[player isCurrentTrack:track] media:self.media];
    if ((NSUInteger)indexPath.row + LOAD_AHEAD >= _tracks.count) [self loadMore];
    return cell;
}

/* only the person's own profile can lose a song, and the server has the last word: the row goes after it agrees */
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return _dialog.saved && _loaded;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return NSLocalizedString(@"music.remove", nil);
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete || (NSUInteger)indexPath.row >= _tracks.count) return;
    ExteriaMedia *song = [_tracks objectAtIndex:(NSUInteger)indexPath.row];
    ExteriaWeakReference *me = _weak;
    [self retain];
    [self.session saveMusic:song unsave:YES completion:^(NSString *errorName) {
        [self autorelease];
        ExteriaMusicListController *list = me.target;
        if (!list) return;
        if (errorName) {
            NSLog(@"exteria: song not removed from the profile: %@", errorName);
            [list->_table reloadData];
            ExteriaGiftAlert(nil, [errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                         : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]);
            return;
        }
        NSUInteger at = [list->_tracks indexOfObjectIdenticalTo:song];
        if (at == NSNotFound) return;
        [list->_tracks removeObjectAtIndex:at];
        list->_total = MAX(0, list->_total - 1);
        [list->_table deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:(NSInteger)at inSection:0]]
                            withRowAnimation:UITableViewRowAnimationFade];
        [list showState];
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ExteriaMedia *track = [_tracks objectAtIndex:(NSUInteger)indexPath.row];
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    if ([player isCurrentTrack:track] && player.state != ExteriaMusicStateFailed) [player togglePause];
    else [player playTrack:track queue:_tracks media:self.media];
}

#pragma mark player

- (void)playerChanged:(NSNotification *)note {
    (void)note;
    for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
        ExteriaSongCell *cell = (ExteriaSongCell *)[_table cellForRowAtIndexPath:path];
        ExteriaMedia *track = [_tracks objectAtIndex:(NSUInteger)path.row];
        ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
        [cell configureWithTrack:track state:player.state current:[player isCurrentTrack:track] media:self.media];
    }
    [self refreshPanel];
}

- (void)playerTicked:(NSNotification *)note {
    (void)note;
    [self refreshProgress];
}

- (void)refreshProgress {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    NSTimeInterval length = player.duration;
    if (!_scrubbing) _slider.value = length > 0 ? (float)(player.position / length) : 0;
    NSTimeInterval shown = _scrubbing ? length * _slider.value : player.position;
    _elapsed.text = ExteriaClock(shown);
    _remaining.text = length > 0 ? [@"-" stringByAppendingString:ExteriaClock(length - shown)] : @"";
}

- (void)refreshPanel {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    BOOL shown = player.state != ExteriaMusicStateIdle;
    UIView *dock = _card ? (UIView *)_card : _panel;
    if (dock.hidden == shown) {
        dock.hidden = !shown;
        [self.view setNeedsLayout];
        if (shown) [_card reveal];
    }
    /* the card follows the player on its own */
    if (!shown || _card) return;
    _panelTitle.text = ExteriaTrackTitle(player.track);
    _panelPerformer.text = player.state == ExteriaMusicStateFailed ? NSLocalizedString(@"music.failed", nil) : ExteriaTrackPerformer(player.track);
    BOOL playing = player.state == ExteriaMusicStatePlaying || player.state == ExteriaMusicStateLoading;
    [_toggle setImage:ExteriaSymbolImage(playing ? ExteriaSymbolPause : ExteriaSymbolPlay, 32, ExteriaColorTitle()) forState:UIControlStateNormal];
    _toggle.accessibilityLabel = NSLocalizedString(playing ? @"music.pause" : @"music.play", nil);
    _previous.enabled = player.queue.count > 1 || player.position > 3;
    _next.enabled = [player.queue indexOfObject:player.track] != NSNotFound && [player.queue indexOfObject:player.track] + 1 < player.queue.count;
    [_speed setTitle:ExteriaSpeedText(player.speed) forState:UIControlStateNormal];
    _slider.enabled = player.state == ExteriaMusicStatePlaying || player.state == ExteriaMusicStatePaused;
    [self refreshProgress];
}

- (void)scrubBegan { _scrubbing = YES; }
- (void)scrubMoved { [self refreshProgress]; }

- (void)scrubEnded {
    _scrubbing = NO;
    [[ExteriaMusicPlayer sharedPlayer] seekToFraction:_slider.value];
}

- (void)previousTapped { [[ExteriaMusicPlayer sharedPlayer] previous]; }
- (void)toggleTapped { [[ExteriaMusicPlayer sharedPlayer] togglePause]; }
- (void)nextTapped { [[ExteriaMusicPlayer sharedPlayer] next]; }
- (void)speedTapped { [[ExteriaMusicPlayer sharedPlayer] cycleSpeed]; }

#pragma mark layout

- (void)layoutBody:(CGRect)body {
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat width = body.size.width;
    UIView *dock = _card ? (UIView *)_card : _panel;
    CGFloat panelHeight = _card ? [ExteriaMusicCard height] : PANEL_HEIGHT;
    CGFloat panel = dock.hidden ? 0 : panelHeight + MAX(insets.bottom, 8) + 8;
    _table.frame = CGRectMake(body.origin.x, body.origin.y, width, body.size.height - panel);
    CGSize fit = _message.text.length ? [_message sizeThatFits:CGSizeMake(width - 64, 200)] : CGSizeZero;
    _message.frame = CGRectMake(body.origin.x + 32, body.origin.y + 40, width - 64, fit.height);
    if (dock.hidden) return;
    CGFloat side = MIN(width - 16, 460);
    dock.frame = CGRectMake(CGRectGetMidX(body) - side / 2, CGRectGetMaxY(body) - panelHeight - MAX(insets.bottom, 8), side, panelHeight);
    if (_card) return;
    _panelTitle.frame = CGRectMake(16, 10, side - 32, 22);
    _panelPerformer.frame = CGRectMake(16, 32, side - 32, 18);
    _slider.frame = CGRectMake(16, 54, side - 32, 22);
    _elapsed.frame = CGRectMake(16, 74, 60, 14);
    _remaining.frame = CGRectMake(side - 76, 74, 60, 14);
    _toggle.frame = CGRectMake((side - 56) / 2, 84, 56, 40);
    _previous.frame = CGRectMake(_toggle.frame.origin.x - 70, _toggle.frame.origin.y, 56, _toggle.frame.size.height);
    _next.frame = CGRectMake(CGRectGetMaxX(_toggle.frame) + 14, _toggle.frame.origin.y, 56, _toggle.frame.size.height);
    _speed.frame = CGRectMake(side - 16 - 52, 90, 52, 28);
}

@end
