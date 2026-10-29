#import "exteria_developers.h"
#import "exteria_group_tabs_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_person_cell.h"
#import "exteria_pill_tabs_view.h"
#import "exteria_symbol.h"
#import "exteria_time.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"
#import "exteria_music_player.h"

#define TABS_GAP 10.0
#define PAGE 30
#define COLUMNS 3
#define CELL_GAP 2.0
#define MORE_HEIGHT 48.0
#define EMPTY_HEIGHT 80.0

typedef enum { ExteriaGroupTabMembers, ExteriaGroupTabMedia, ExteriaGroupTabFiles, ExteriaGroupTabLinks, ExteriaGroupTabAudio, ExteriaGroupTabVoice, ExteriaGroupTabCount } ExteriaGroupTab;

@interface ExteriaGroupTabsView () {
    ExteriaSession *_session;
    ExteriaDialog *_dialog;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    ExteriaPillTabsView *_tabs;
    UIView *_body;
    UILabel *_empty;
    NSMutableArray *_items[ExteriaGroupTabCount];
    BOOL _loaded[ExteriaGroupTabCount];
    BOOL _loading[ExteriaGroupTabCount];
    BOOL _finished[ExteriaGroupTabCount];
    BOOL _failed[ExteriaGroupTabCount];
    NSUInteger _tab;
    BOOL _forUser;
    CGFloat _width;
    CGFloat _bodyHeight;
    id<ExteriaGroupTabsDelegate> _delegate;
}
@end

@implementation ExteriaGroupTabsView

@synthesize delegate = _delegate;

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    return [self initWithSession:session dialog:dialog avatars:avatars media:media forUser:NO];
}

- (NSUInteger)selectedTab {
    return _tab;
}

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
              forUser:(BOOL)forUser {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _forUser = forUser;
    _session = [session retain];
    _dialog = [dialog retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    for (int i = 0; i < ExteriaGroupTabCount; ++i) _items[i] = [[NSMutableArray alloc] init];
    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(forUser ? @"gifts.title" : @"group.tab.members", nil), NSLocalizedString(@"group.tab.media", nil),
                                                NSLocalizedString(@"group.tab.files", nil), NSLocalizedString(@"group.tab.links", nil), NSLocalizedString(@"group.tab.audio", nil), NSLocalizedString(@"group.tab.voice", nil), nil];
    BOOL skipFirst = dialog.saved;
    if (skipFirst) {
        titles = [titles subarrayWithRange:NSMakeRange(1, titles.count - 1)];
        _tab = ExteriaGroupTabMedia;
    }
    _tabs = [[ExteriaPillTabsView alloc] initWithTitles:titles];
    ExteriaWeakReference *me = _weak;
    _tabs.changeHandler = ^(NSUInteger index) { [(ExteriaGroupTabsView *)me.target chooseTab:skipFirst ? index + 1 : index]; };
    [self addSubview:_tabs];
    _body = [[UIView alloc] init];
    _body.backgroundColor = ExteriaColorCard();
    _body.layer.cornerRadius = 14;
    _body.clipsToBounds = YES;
    [self addSubview:_body];
    _empty = [[UILabel alloc] init];
    _empty.backgroundColor = [UIColor clearColor];
    _empty.textColor = ExteriaColorSecondary();
    _empty.font = ExteriaFontRegular(15);
    _empty.textAlignment = ExteriaTextAlignmentCenter;
    [self load];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_dialog release];
    [_avatars release];
    [_media release];
    [_tabs release];
    [_body release];
    [_empty release];
    for (int i = 0; i < ExteriaGroupTabCount; ++i) [_items[i] release];
    [super dealloc];
}

#pragma mark loading

- (void)reloadMembers {
    /* a page in flight would add its rows to the fresh list, so the reload waits for it to land and the tab shows what it has until then */
    if (_loading[ExteriaGroupTabMembers]) return;
    [_items[ExteriaGroupTabMembers] removeAllObjects];
    _loaded[ExteriaGroupTabMembers] = NO;
    _finished[ExteriaGroupTabMembers] = NO;
    if (_tab == ExteriaGroupTabMembers) [self load];
    [self rebuild];
}

- (void)chooseTab:(NSUInteger)index {
    if (index >= ExteriaGroupTabCount || index == _tab) return;
    _tab = index;
    [self load];
    [self rebuild];
    if ([_delegate respondsToSelector:@selector(groupTabsDidChooseTab:)]) [_delegate groupTabsDidChooseTab:self];
}

- (void)finishTab:(NSUInteger)tab added:(NSUInteger)added error:(NSString *)errorName {
    _loading[tab] = NO;
    if (errorName) {
        NSLog(@"exteria: the group tab %lu of %lld did not load: %@", (unsigned long)tab, _dialog.peerId, errorName);
        _failed[tab] = YES;
        [self rebuild];
        return;
    }
    _failed[tab] = NO;
    _loaded[tab] = YES;
    if (added == 0) _finished[tab] = YES;
    [self rebuild];
}

/* the next page of the chosen tab; a page that brings nothing ends the list */
- (void)load {
    NSUInteger tab = _tab;
    if (_loading[tab] || _finished[tab]) return;
    /* the gifts of a user come from the screen's own feed */
    if (_forUser && tab == ExteriaGroupTabMembers) {
        _loaded[tab] = _finished[tab] = YES;
        return;
    }
    _loading[tab] = YES;
    _failed[tab] = NO;
    ExteriaWeakReference *me = _weak;
    [self retain];
    if (tab == ExteriaGroupTabMembers) {
        [_session loadMembersOfDialog:_dialog list:ExteriaChannelListSubscribers query:nil offset:(NSInteger)_items[tab].count
                           completion:^(NSArray *members, NSInteger total, NSString *errorName) {
            [self autorelease];
            ExteriaGroupTabsView *view = me.target;
            if (!view) return;
            [view->_items[tab] addObjectsFromArray:members];
            if (total > 0 && (NSInteger)view->_items[tab].count >= total) view->_finished[tab] = YES;
            [view finishTab:tab added:members.count error:errorName];
        }];
        return;
    }
    exteria_shared_kind kind = tab == ExteriaGroupTabMedia ? EXTERIA_SHARED_MEDIA : (tab == ExteriaGroupTabFiles ? EXTERIA_SHARED_FILES : (tab == ExteriaGroupTabAudio ? EXTERIA_SHARED_AUDIO : (tab == ExteriaGroupTabVoice ? EXTERIA_SHARED_VOICE : EXTERIA_SHARED_LINKS)));
    int32_t before = _items[tab].count ? [(ExteriaMessage *)[_items[tab] lastObject] messageId] : 0;
    [_session loadSharedOfDialog:_dialog kind:kind beforeId:before limit:PAGE completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        [self autorelease];
        (void)people;
        ExteriaGroupTabsView *view = me.target;
        if (!view) return;
        /* the server filters by what the message holds, so a page of the links tab can carry a message with no readable link; those are dropped here */
        NSUInteger added = messages.count;
        for (ExteriaMessage *message in messages) {
            if (tab == ExteriaGroupTabLinks && ![view linkOfMessage:message]) continue;
            [view->_items[tab] addObject:message];
        }
        [view finishTab:tab added:added error:errorName];
    }];
}

#pragma mark rows

- (NSURL *)linkOfMessage:(ExteriaMessage *)message {
    NSString *text = message.text;
    if (!text.length) return nil;
    static NSDataDetector *detector;
    if (!detector) detector = [[NSDataDetector dataDetectorWithTypes:(NSTextCheckingTypes)NSTextCheckingTypeLink error:NULL] retain];
    NSTextCheckingResult *found = [detector firstMatchInString:text options:0 range:NSMakeRange(0, MIN(text.length, 4096))];
    return found.URL;
}

static NSString *ExteriaGroupSizeText(long long bytes) {
    if (bytes < 1024) return [NSString stringWithFormat:@"%lld B", bytes];
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
    return [NSString stringWithFormat:@"%.1f MB", bytes / 1048576.0];
}

static NSString *ExteriaGroupDateText(int32_t date) {
    static NSDateFormatter *formatter;
    if (!formatter) {
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterNoStyle;
    }
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:date]];
}

- (UIControl *)tapAreaAtIndex:(NSUInteger)index frame:(CGRect)frame {
    UIControl *area = [[[UIControl alloc] initWithFrame:frame] autorelease];
    area.tag = (NSInteger)index;
    [area addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    return area;
}

- (ExteriaPersonCell *)personRowWithFrame:(CGRect)frame {
    ExteriaPersonCell *cell = [[[ExteriaPersonCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];
    cell.frame = frame;
    cell.userInteractionEnabled = NO;
    [cell layoutIfNeeded];
    return cell;
}

- (void)rebuild {
    for (UIView *view in [[_body.subviews copy] autorelease]) [view removeFromSuperview];
    NSUInteger tab = _tab;
    NSArray *items = _items[tab];
    CGFloat width = _width;
    CGFloat y = 0;
    if (_forUser && tab == ExteriaGroupTabMembers) {
        _body.hidden = YES;
        _bodyHeight = 0;
        [self setNeedsLayout];
        [_delegate groupTabsDidResize:self];
        return;
    }
    _body.hidden = NO;
    if (tab == ExteriaGroupTabMedia) {
        CGFloat side = floor((width - CELL_GAP * (COLUMNS - 1)) / COLUMNS);
        for (NSUInteger i = 0; i < items.count; ++i) {
            ExteriaMessage *message = [items objectAtIndex:i];
            CGRect frame = CGRectMake((i % COLUMNS) * (side + CELL_GAP), (i / COLUMNS) * (side + CELL_GAP), side, side);
            [self addMediaTile:message frame:frame index:i];
        }
        y = items.count ? ceil(items.count / (double)COLUMNS) * (side + CELL_GAP) - CELL_GAP : 0;
    } else {
        CGFloat row = [ExteriaPersonCell rowHeight];
        for (NSUInteger i = 0; i < items.count; ++i) {
            CGRect frame = CGRectMake(0, y, width, row);
            [_body addSubview:[self rowForItem:[items objectAtIndex:i] tab:tab frame:frame]];
            [_body addSubview:[self tapAreaAtIndex:i frame:frame]];
            y += row;
        }
    }
    if (!items.count) {
        _empty.text = NSLocalizedString(_failed[tab] ? @"group.tab.failed" : (_loaded[tab] ? @"group.tab.empty" : @"group.tab.loading"), nil);
        _empty.frame = CGRectMake(0, 0, width, EMPTY_HEIGHT);
        [_body addSubview:_empty];
        y = EMPTY_HEIGHT;
    }
    if ((!items.count && _failed[tab]) || (items.count && !_finished[tab])) {
        UIButton *more = [UIButton buttonWithType:UIButtonTypeCustom];
        more.frame = CGRectMake(0, y, width, MORE_HEIGHT);
        more.titleLabel.font = ExteriaFontMedium(15);
        [more setTitle:NSLocalizedString(_failed[tab] ? @"article.retry" : @"group.tab.more", nil) forState:UIControlStateNormal];
        [more setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
        [more addTarget:self action:@selector(load) forControlEvents:UIControlEventTouchUpInside];
        [_body addSubview:more];
        y += MORE_HEIGHT;
    }
    _bodyHeight = y;
    [self setNeedsLayout];
    [_delegate groupTabsDidResize:self];
}

- (UIView *)rowForItem:(id)item tab:(NSUInteger)tab frame:(CGRect)frame {
    ExteriaPersonCell *cell = [self personRowWithFrame:frame];
    if (tab == ExteriaGroupTabMembers) {
        ExteriaChannelMember *member = item;
        ExteriaPerson *person = member.person;
        /* the role stands at the right, as in the member list group screen */
        NSString *trailing = nil;
        if (member.role == ExteriaChannelRoleCreator) {
            trailing = member.rank.length ? member.rank : NSLocalizedString(@"channel.role.creator", nil);
            cell.trailingTint = ExteriaMemberTagColor(YES);
        } else if (member.role == ExteriaChannelRoleAdmin) {
            trailing = member.rank.length ? member.rank : NSLocalizedString(@"channel.role.admin", nil);
            cell.trailingTint = ExteriaMemberTagColor(NO);
        } else if (member.rank.length) {
            trailing = member.rank;
            cell.trailingTint = ExteriaColorAccent();
        }
        UIColor *color = nil;
        NSString *subtitle;
        if (person.bot) {
            subtitle = NSLocalizedString(@"seen.bot", nil);
        } else {
            if (person.presence == EXTERIA_PRESENCE_ONLINE) color = ExteriaColorAccent();
            subtitle = ExteriaLastSeenText(person.presence, person.seen);
        }
        cell.developer = ExteriaPersonIsDeveloper(person);
        [cell configureWithName:person.name initials:person.initials seed:(NSUInteger)(person.userId % 1000003) subtitle:subtitle subtitleColor:color
                       trailing:trailing symbol:ExteriaSymbolChevronRight showsSymbol:NO nameColor:nil photo:person.photo avatars:_avatars];
        cell.avatarDeleted = person.deleted;
    } else if (tab == ExteriaGroupTabFiles || tab == ExteriaGroupTabAudio || tab == ExteriaGroupTabVoice) {
        ExteriaMessage *message = item;
        NSString *name = message.media.name.length ? message.media.name : (message.media.title.length ? message.media.title : NSLocalizedString(tab == ExteriaGroupTabVoice ? @"group.tab.voice" : @"group.tab.file", nil));
        NSString *extension = [[name pathExtension] uppercaseString];
        NSString *detail = [NSString stringWithFormat:@"%@, %@", ExteriaGroupSizeText(message.media.size), ExteriaGroupDateText(message.date)];
        [cell configureWithName:name initials:extension.length ? [extension substringToIndex:MIN(extension.length, 3)] : @"?" seed:(NSUInteger)message.messageId
                       subtitle:detail subtitleColor:nil trailing:nil symbol:ExteriaSymbolChevronRight showsSymbol:NO nameColor:nil photo:nil avatars:nil];
    } else {
        ExteriaMessage *message = item;
        NSURL *url = [self linkOfMessage:message];
        NSString *host = url.host.length ? url.host : url.absoluteString;
        [cell configureWithName:host initials:host.length ? [[host substringToIndex:1] uppercaseString] : @"?" seed:(NSUInteger)message.messageId
                       subtitle:url.absoluteString subtitleColor:nil trailing:nil symbol:ExteriaSymbolLink showsSymbol:NO nameColor:nil photo:nil avatars:nil];
    }
    return cell;
}

- (void)addMediaTile:(ExteriaMessage *)message frame:(CGRect)frame index:(NSUInteger)index {
    UIImageView *tile = [[[UIImageView alloc] initWithFrame:frame] autorelease];
    tile.contentMode = UIViewContentModeScaleAspectFill;
    tile.clipsToBounds = YES;
    tile.backgroundColor = ExteriaColorField();
    [_body addSubview:tile];
    ExteriaMedia *media = message.media;
    ExteriaRemoteFile *file = media.kind == EXTERIA_PREVIEW_PHOTO ? media.file : media.previewFile;
    if (file) {
        CGFloat side = frame.size.width * [UIScreen mainScreen].scale;
        UIImage *ready = [_media cachedImageForFile:file maxSide:side];
        if (ready) {
            tile.image = ready;
        } else {
            [_media loadImageForFile:file maxSide:side completion:^(UIImage *image) {
                if (image) tile.image = image;
            }];
        }
    }
    if (media.kind == EXTERIA_PREVIEW_GIF) {
        UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(frame.origin.x + 6, frame.origin.y + 6, 36, 20)] autorelease];
        label.text = @"GIF";
        label.font = ExteriaFontMedium(12);
        label.textColor = [UIColor whiteColor];
        label.textAlignment = ExteriaTextAlignmentCenter;
        label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        label.layer.cornerRadius = 10;
        label.clipsToBounds = YES;
        [_body addSubview:label];
    } else if (media.kind != EXTERIA_PREVIEW_PHOTO) {
        UIImageView *mark = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolPlay, 24, [UIColor whiteColor])] autorelease];
        mark.contentMode = UIViewContentModeCenter;
        mark.frame = frame;
        [_body addSubview:mark];
    }
    [_body addSubview:[self tapAreaAtIndex:index frame:frame]];
}

- (void)rowTapped:(UIControl *)area {
    NSArray *items = _items[_tab];
    if ((NSUInteger)area.tag >= items.count) return;
    id item = [items objectAtIndex:(NSUInteger)area.tag];
    if (_tab == ExteriaGroupTabAudio) {
        NSMutableArray *queue = [NSMutableArray array];
        for (ExteriaMessage *message in items) if (message.media.file) [queue addObject:message.media];
        ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
        if ([player isCurrentTrack:((ExteriaMessage *)item).media]) [player togglePause];
        else [player playTrack:((ExteriaMessage *)item).media queue:queue media:_media];
        return;
    }
    if (_tab == ExteriaGroupTabMembers) {
        [_delegate groupTabs:self didOpenPerson:[(ExteriaChannelMember *)item person]];
        return;
    }
    if (_tab == ExteriaGroupTabMedia) {
        /* the pictures and videos that can be shown are the pages of the viewer */
        NSMutableArray *pages = [NSMutableArray array];
        for (ExteriaMessage *message in items) {
            exteria_preview_kind kind = message.media.kind;
            if (message.media.file && exteria_media_opens_viewer(kind)) [pages addObject:message];
        }
        if ([pages containsObject:item]) {
            [_delegate groupTabs:self didOpenMedia:item among:pages];
            return;
        }
    }
    [_delegate groupTabs:self didOpenMessage:item];
}

#pragma mark layout

- (CGFloat)heightForWidth:(CGFloat)width {
    if (fabs(width - _width) > 0.5) {
        _width = width;
        [self rebuild];
    }
    return 40.0 + (_body.hidden ? 0 : TABS_GAP + _bodyHeight);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _tabs.frame = CGRectMake(0, 0, width, 40.0);
    _body.frame = CGRectMake(0, 40.0 + TABS_GAP, width, _bodyHeight);
}

@end
