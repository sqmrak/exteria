#import "exteria_music_sheet.h"

#import <QuartzCore/QuartzCore.h>
#import "exteria_emoji_label.h"
#import "exteria_music_player.h"
#import "exteria_platform.h"
#import "exteria_remote_file.h"
#import "exteria_slider.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define ROW_HEIGHT 60.0
#define COVER_SIDE 44.0
#define HEADER_HEIGHT 190.0

@interface ExteriaQueueCell : UITableViewCell {
    UIImageView *_cover;
    ExteriaEmojiLabel *_title;
    ExteriaEmojiLabel *_performer;
    NSString *_key;
    ExteriaWeakReference *_weak;
}
- (void)showTrack:(ExteriaMedia *)track player:(ExteriaMusicPlayer *)player;
@end

@implementation ExteriaQueueCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.backgroundColor = [UIColor clearColor];
    _cover = [[UIImageView alloc] init];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = 5;
    [self.contentView addSubview:_cover];
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.font = ExteriaFontSemibold(15);
    [self.contentView addSubview:_title];
    _performer = [[ExteriaEmojiLabel alloc] init];
    _performer.font = ExteriaFontRegular(13);
    _performer.textColor = ExteriaColorSecondary();
    [self.contentView addSubview:_performer];
    return self;
}
- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_key release];
    [_cover release];
    [_title release];
    [_performer release];
    [super dealloc];
}
- (void)showTrack:(ExteriaMedia *)track player:(ExteriaMusicPlayer *)player {
    _title.text = ExteriaTrackTitle(track);
    _title.textColor = [player isCurrentTrack:track] ? ExteriaColorAccent() : ExteriaColorTitle();
    _performer.text = ExteriaTrackPerformer(track);
    NSString *key = track.file.key;
    if (!(key == _key || [key isEqualToString:_key])) {
        [_key release];
        _key = [key copy];
        _cover.image = nil;
        if (key.length) {
            ExteriaWeakReference *weak = _weak;
            [player.media loadCoverForTrack:track maxSide:COVER_SIDE * ExteriaScreenScale() completion:^(UIImage *image) {
                ExteriaQueueCell *cell = weak.target;
                if (cell && [key isEqualToString:cell->_key]) cell->_cover.image = image ? image : ExteriaSymbolImage(ExteriaSymbolMusic, 24, ExteriaColorAccent());
            }];
        }
    }
    if (!_cover.image) _cover.image = ExteriaSymbolImage(ExteriaSymbolMusic, 24, ExteriaColorAccent());
    _cover.backgroundColor = ExteriaColorField();
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    _cover.frame = CGRectMake(14, 8, COVER_SIDE, COVER_SIDE);
    _title.frame = CGRectMake(70, _performer.text.length ? 8 : 19, MAX(0, width - 84), 22);
    _performer.frame = CGRectMake(70, 31, MAX(0, width - 84), 19);
}
@end

@interface ExteriaMusicSheet () <UITableViewDataSource, UITableViewDelegate> {
    UIView *_panel;
    UITableView *_table;
    UIImageView *_cover;
    ExteriaEmojiLabel *_title;
    ExteriaEmojiLabel *_performer;
    UISlider *_slider;
    UILabel *_elapsed;
    UILabel *_remaining;
    UIButton *_toggle;
    BOOL _scrubbing;
    NSArray *_shownQueue;
    ExteriaMedia *_shownTrack;
    ExteriaMusicState _shownState;
}
@end

@implementation ExteriaMusicSheet
+ (void)present {
    UIView *host = ExteriaOverlayHost();
    if (!host || ![ExteriaMusicPlayer sharedPlayer].track) return;
    for (UIView *view in host.subviews) if ([view isKindOfClass:self]) return;
    ExteriaMusicSheet *sheet = [[[self alloc] initWithFrame:host.bounds] autorelease];
    [host addSubview:sheet];
}
static UIButton *SheetButton(ExteriaSymbol symbol, id target, SEL action, NSString *label) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:ExteriaSymbolImage(symbol, 24, ExteriaColorTitle()) forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    button.accessibilityLabel = NSLocalizedString(label, nil);
    return button;
}
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIView *dim = [[[UIView alloc] initWithFrame:self.bounds] autorelease];
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    [dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)] autorelease]];
    [self addSubview:dim];
    _panel = [[UIView alloc] init];
    _panel.backgroundColor = ExteriaColorCard();
    _panel.layer.cornerRadius = 12;
    _panel.clipsToBounds = YES;
    [self addSubview:_panel];
    _cover = [[UIImageView alloc] init];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = 5;
    [_panel addSubview:_cover];
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.font = ExteriaFontSemibold(16);
    _title.textColor = ExteriaColorTitle();
    [_panel addSubview:_title];
    _performer = [[ExteriaEmojiLabel alloc] init];
    _performer.font = ExteriaFontRegular(14);
    _performer.textColor = ExteriaColorSecondary();
    [_panel addSubview:_performer];
    _slider = [[ExteriaSlider alloc] init];
    _slider.accessibilityLabel = NSLocalizedString(@"media.seek", nil);
    [_slider addTarget:self action:@selector(scrubBegan) forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(scrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_panel addSubview:_slider];
    _elapsed = [[UILabel alloc] init];
    _remaining = [[UILabel alloc] init];
    for (UILabel *label in [NSArray arrayWithObjects:_elapsed, _remaining, nil]) {
        label.backgroundColor = [UIColor clearColor]; label.font = ExteriaFontRegular(12); label.textColor = ExteriaColorSecondary(); [_panel addSubview:label];
    }
    _remaining.textAlignment = ExteriaTextAlignmentRight;
    UIButton *previous = SheetButton(ExteriaSymbolPrevious, self, @selector(previous), @"music.previous");
    previous.tag = 1; [_panel addSubview:previous];
    _toggle = [SheetButton(ExteriaSymbolPlay, self, @selector(toggle), @"music.play") retain];
    [_panel addSubview:_toggle];
    UIButton *next = SheetButton(ExteriaSymbolNext, self, @selector(next), @"music.next");
    next.tag = 2; [_panel addSubview:next];
    UIButton *close = SheetButton(ExteriaSymbolClose, self, @selector(dismiss), @"notice.cancel");
    close.tag = 3; [_panel addSubview:close];
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor = [UIColor clearColor];
    _table.rowHeight = ROW_HEIGHT;
    _table.dataSource = self; _table.delegate = self;
    [_panel addSubview:_table];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(changed:) name:ExteriaMusicPlayerDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(tick:) name:ExteriaMusicPlayerDidTickNotification object:nil];
    [self refresh];
    return self;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.dataSource = nil; _table.delegate = nil;
    [_panel release]; [_table release]; [_cover release]; [_title release]; [_performer release];
    [_slider release]; [_elapsed release]; [_remaining release]; [_toggle release];
    [_shownQueue release]; [_shownTrack release];
    [super dealloc];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MIN(self.bounds.size.width, 480);
    CGFloat height = MIN(self.bounds.size.height - ExteriaSafeInsets(self).top - 12, 620);
    _panel.frame = CGRectMake((self.bounds.size.width - width) / 2, self.bounds.size.height - height, width, height);
    _cover.frame = CGRectMake(16, 20, 54, 54);
    _title.frame = CGRectMake(82, 23, MAX(0, width - 140), 22);
    _performer.frame = CGRectMake(82, 47, MAX(0, width - 140), 20);
    [_panel viewWithTag:3].frame = CGRectMake(width - 48, 8, 40, 40);
    _slider.frame = CGRectMake(16, 78, width - 32, 24);
    _elapsed.frame = CGRectMake(18, 101, 64, 18);
    _remaining.frame = CGRectMake(width - 82, 101, 64, 18);
    CGFloat center = width / 2;
    _toggle.frame = CGRectMake(center - 24, 126, 48, 48);
    [_panel viewWithTag:1].frame = CGRectMake(center - 94, 126, 48, 48);
    [_panel viewWithTag:2].frame = CGRectMake(center + 46, 126, 48, 48);
    _table.frame = CGRectMake(0, HEADER_HEIGHT, width, MAX(0, height - HEADER_HEIGHT));
    _table.contentInset = UIEdgeInsetsMake(0, 0, ExteriaSafeInsets(self).bottom, 0);
}
static NSString *SheetTime(NSTimeInterval value) {
    NSInteger seconds = MAX(0, (NSInteger)value);
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
}
- (void)refresh {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    if (!player.track) { [self dismiss]; return; }
    _title.text = ExteriaTrackTitle(player.track);
    _performer.text = player.state == ExteriaMusicStateFailed ? NSLocalizedString(@"music.failed", nil) : ExteriaTrackPerformer(player.track);
    _cover.image = player.cover ? player.cover : ExteriaSymbolImage(ExteriaSymbolMusic, 28, ExteriaColorAccent());
    _cover.backgroundColor = ExteriaColorField();
    BOOL playing = player.state == ExteriaMusicStatePlaying || player.state == ExteriaMusicStateLoading;
    [_toggle setImage:ExteriaSymbolImage(playing ? ExteriaSymbolPause : ExteriaSymbolPlay, 28, ExteriaColorTitle()) forState:UIControlStateNormal];
    _toggle.accessibilityLabel = NSLocalizedString(playing ? @"music.pause" : @"music.play", nil);
    _slider.enabled = player.state == ExteriaMusicStatePlaying || player.state == ExteriaMusicStatePaused;
    if (_shownQueue != player.queue || _shownTrack != player.track || _shownState != player.state) {
        [_shownQueue release]; _shownQueue = [player.queue retain];
        [_shownTrack release]; _shownTrack = [player.track retain];
        _shownState = player.state;
        [_table reloadData];
    }
    [self tick:nil];
}
- (void)changed:(NSNotification *)note { (void)note; [self refresh]; }
- (void)tick:(NSNotification *)note {
    (void)note;
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    if (!_scrubbing) _slider.value = player.duration > 0 ? player.position / player.duration : 0;
    _elapsed.text = SheetTime(player.position);
    _remaining.text = [@"-" stringByAppendingString:SheetTime(player.duration - player.position)];
}
- (void)scrubBegan { _scrubbing = YES; }
- (void)scrubEnded { _scrubbing = NO; [[ExteriaMusicPlayer sharedPlayer] seekToFraction:_slider.value]; }
- (void)previous { [[ExteriaMusicPlayer sharedPlayer] previous]; }
- (void)toggle { [[ExteriaMusicPlayer sharedPlayer] togglePause]; }
- (void)next { [[ExteriaMusicPlayer sharedPlayer] next]; }
- (void)dismiss { [self removeFromSuperview]; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; (void)section; return (NSInteger)[ExteriaMusicPlayer sharedPlayer].queue.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    ExteriaQueueCell *cell = (ExteriaQueueCell *)[table dequeueReusableCellWithIdentifier:@"track"];
    if (!cell) cell = [[[ExteriaQueueCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"track"] autorelease];
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    [cell showTrack:[player.queue objectAtIndex:(NSUInteger)path.row] player:player];
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    [[ExteriaMusicPlayer sharedPlayer] playQueueTrackAtIndex:(NSUInteger)path.row];
}
@end
