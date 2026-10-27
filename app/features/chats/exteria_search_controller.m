#import "exteria_search_controller.h"
#import "exteria_string_drawing.h"
#import "exteria_lite_mode.h"
#import "exteria_animation.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_view.h"
#import "exteria_bar_button.h"
#import "exteria_chat_controller.h"
#import "exteria_community_screen.h"
#import "exteria_topics_screen.h"
#import "exteria_emoji_label.h"
#import "exteria_filter_bar.h"
#import "exteria_lottie_view.h"
#import "exteria_platform.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_time.h"
#import "exteria_weak_reference.h"

#define BAR_HEIGHT 44.0
#define FIELD_HEIGHT 38.0
#define CHIPS_HEIGHT 44.0
#define ROW_HEIGHT 64.0
#define PEERS_HEIGHT 104.0
#define SECTION_HEIGHT 34.0
#define RECENT_MAX 12
#define SERVER_DELAY 0.4
static NSString *const ExteriaRecentChatsKey = @"ExteriaRecentChats";

/* the order of the kinds as they stand on the strip */
typedef enum {
    ExteriaSearchTabChats,
    ExteriaSearchTabChannels,
    ExteriaSearchTabApps,
    ExteriaSearchTabPosts,
    ExteriaSearchTabMedia,
    ExteriaSearchTabDownloads,
    ExteriaSearchTabLinks,
    ExteriaSearchTabFiles,
    ExteriaSearchTabMusic,
    ExteriaSearchTabVoice,
    ExteriaSearchTabCount
} ExteriaSearchTab;

/* what stands on the screen: the people and the recent chats, a list of results, a wait, a failure, or the duck */
typedef enum { ExteriaSearchStateStart, ExteriaSearchStateResults, ExteriaSearchStateLoading, ExteriaSearchStateFailed, ExteriaSearchStateEmpty, ExteriaSearchStateHint } ExteriaSearchState;

static BOOL ExteriaTabIsLocal(NSInteger tab) {
    return tab == ExteriaSearchTabChats || tab == ExteriaSearchTabChannels || tab == ExteriaSearchTabApps;
}

static exteria_search_kind ExteriaServerKindOfTab(NSInteger tab) {
    switch (tab) {
    case ExteriaSearchTabPosts: return EXTERIA_SEARCH_POSTS;
    case ExteriaSearchTabMedia: return EXTERIA_SEARCH_MEDIA;
    case ExteriaSearchTabLinks: return EXTERIA_SEARCH_LINKS;
    case ExteriaSearchTabFiles: return EXTERIA_SEARCH_FILES;
    case ExteriaSearchTabMusic: return EXTERIA_SEARCH_MUSIC;
    default: return EXTERIA_SEARCH_VOICE;
    }
}

/* a row of the results: a chat with a line under its name, and for a found message the day it was written */
@interface ExteriaSearchCell : UITableViewCell {
    ExteriaAvatarView *_avatar;
    ExteriaEmojiLabel *_title;
    ExteriaEmojiLabel *_subtitle;
    UILabel *_date;
    UIView *_line;
}
- (void)configureWithDialog:(ExteriaDialog *)dialog showsDate:(BOOL)showsDate avatars:(ExteriaAvatarCache *)avatars;
@end

@implementation ExteriaSearchCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    UIView *selected = [[[UIView alloc] init] autorelease];
    selected.backgroundColor = ExteriaColorField();
    self.selectedBackgroundView = selected;
    _avatar = [[ExteriaAvatarView alloc] init];
    [self.contentView addSubview:_avatar];
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.font = ExteriaFontSemibold(16);
    _title.textColor = ExteriaColorTitle();
    [self.contentView addSubview:_title];
    _subtitle = [[ExteriaEmojiLabel alloc] init];
    _subtitle.font = ExteriaFontRegular(14);
    _subtitle.textColor = ExteriaColorSecondary();
    [self.contentView addSubview:_subtitle];
    _date = [[UILabel alloc] init];
    ExteriaLabelFitToWidth(_date, 9);
    _date.backgroundColor = [UIColor clearColor];
    _date.font = ExteriaFontRegular(12.5);
    _date.textColor = ExteriaColorSecondary();
    _date.textAlignment = ExteriaTextAlignmentRight;
    [self.contentView addSubview:_date];
    _line = [[UIView alloc] init];
    _line.backgroundColor = ExteriaColorHairline();
    [self.contentView addSubview:_line];
    return self;
}

- (void)dealloc {
    [_avatar release];
    [_title release];
    [_subtitle release];
    [_date release];
    [_line release];
    [super dealloc];
}

- (void)configureWithDialog:(ExteriaDialog *)dialog showsDate:(BOOL)showsDate avatars:(ExteriaAvatarCache *)avatars {
    _avatar.seed = dialog.avatarSeed;
    _avatar.initials = dialog.initials;
    _avatar.deleted = dialog.deleted;
    _avatar.accent = dialog.saved;
    _avatar.showsSymbol = dialog.saved;
    _avatar.symbol = ExteriaSymbolBookmark;
    [_avatar setPhoto:dialog.saved ? nil : dialog.photo cache:avatars];
    _title.text = dialog.title;
    _subtitle.text = dialog.preview;
    _date.text = showsDate ? ExteriaListTimeText(dialog.date) : @"";
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat hairline = 1.0 / ExteriaScreenScale();
    _avatar.frame = CGRectMake(14, (ROW_HEIGHT - 48) / 2, 48, 48);
    CGFloat textX = 76;
    CGFloat dateWidth = _date.text.length ? 64 : 0;
    _date.frame = CGRectMake(width - 14 - dateWidth, 13, dateWidth, 18);
    _title.frame = CGRectMake(textX, 11, MAX(0, width - textX - 14 - (dateWidth ? dateWidth + 6 : 0)), 21);
    _subtitle.frame = CGRectMake(textX, 34, MAX(0, width - textX - 14), 19);
    _line.frame = CGRectMake(textX, ROW_HEIGHT - hairline, width - textX, hairline);
}

@end

/* the people on top: a sideways strip of round avatars with a first name under each */
@interface ExteriaTopPeersView : UIScrollView {
    id _target;
}
@property (nonatomic, assign) id target;
- (void)setDialogs:(NSArray *)dialogs avatars:(ExteriaAvatarCache *)avatars;
@end

@implementation ExteriaTopPeersView

@synthesize target = _target;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.showsHorizontalScrollIndicator = NO;
    self.scrollsToTop = NO;
    return self;
}

- (void)setDialogs:(NSArray *)dialogs avatars:(ExteriaAvatarCache *)avatars {
    for (UIView *view in [[self.subviews copy] autorelease]) [view removeFromSuperview];
    CGFloat x = 12;
    for (NSUInteger i = 0; i < dialogs.count; ++i) {
        ExteriaDialog *dialog = [dialogs objectAtIndex:i];
        UIControl *item = [[[UIControl alloc] initWithFrame:CGRectMake(x, 10, 72, 84)] autorelease];
        item.tag = (NSInteger)i;
        [item addTarget:_target action:@selector(peerTapped:) forControlEvents:UIControlEventTouchUpInside];
        ExteriaAvatarView *avatar = [[[ExteriaAvatarView alloc] initWithFrame:CGRectMake(8, 0, 56, 56)] autorelease];
        avatar.seed = dialog.avatarSeed;
        avatar.initials = dialog.initials;
        avatar.deleted = dialog.deleted;
        avatar.circular = YES;
        avatar.userInteractionEnabled = NO;
        [avatar setPhoto:dialog.photo cache:avatars];
        [item addSubview:avatar];
        ExteriaEmojiLabel *name = [[[ExteriaEmojiLabel alloc] initWithFrame:CGRectMake(0, 61, 72, 18)] autorelease];
        name.font = ExteriaFontRegular(12.5);
        name.textColor = ExteriaColorTitle();
        name.textAlignment = ExteriaTextAlignmentCenter;
        NSString *first = [[dialog.title componentsSeparatedByString:@" "] objectAtIndex:0];
        name.text = first;
        [item addSubview:name];
        [self addSubview:item];
        x += 76;
    }
    self.contentSize = CGSizeMake(x + 8, self.bounds.size.height);
}

@end

@interface ExteriaSearchController () <UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate, ExteriaFilterBarDelegate> {
    ExteriaSession *_session;
    NSArray *_dialogs;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    ExteriaWeakReference *_weak;

    UITextField *_field;
    ExteriaBarButton *_cancel;
    ExteriaFilterBar *_tabs;
    UITableView *_table;
    ExteriaTopPeersView *_peers;
    UIView *_emptyView;
    ExteriaLottieView *_duck;
    UILabel *_emptyTitle;
    UILabel *_emptyText;
    UIActivityIndicatorView *_spinner;
    UIButton *_retry;

    NSString *_query;
    NSArray *_rows;
    /* the public chats the server found for the text, shown under the local results on the chat kinds */
    NSArray *_global;
    NSArray *_recent;
    ExteriaSearchState _state;
    NSUInteger _generation;
    CGFloat _keyboardOverlap;
    BOOL _observing;
    BOOL _focused;
}
@end

@implementation ExteriaSearchController

- (id)initWithSession:(ExteriaSession *)session dialogs:(NSArray *)dialogs avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _dialogs = [dialogs retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _query = [@"" copy];
    _rows = [[NSArray alloc] init];
    _recent = [[NSArray alloc] init];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _field.delegate = nil;
    _table.delegate = nil;
    _table.dataSource = nil;
    _tabs.delegate = nil;
    [_session release];
    [_dialogs release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_field release];
    [_cancel release];
    [_tabs release];
    [_table release];
    [_peers release];
    [_emptyView release];
    [_duck release];
    [_emptyTitle release];
    [_emptyText release];
    [_spinner release];
    [_retry release];
    [_query release];
    [_rows release];
    [_global release];
    [_recent release];
    [super dealloc];
}

#pragma mark recent

- (NSString *)recentKeyOf:(ExteriaDialog *)dialog {
    return [NSString stringWithFormat:@"%d:%lld", (int)dialog.peerKind, dialog.peerId];
}

- (void)loadRecent {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:ExteriaRecentChatsKey];
    NSMutableArray *found = [NSMutableArray array];
    for (id key in stored) {
        if (![key isKindOfClass:[NSString class]]) continue;
        for (ExteriaDialog *dialog in _dialogs) {
            if (!dialog.folder && [[self recentKeyOf:dialog] isEqualToString:key]) {
                [found addObject:dialog];
                break;
            }
        }
    }
    [_recent release];
    _recent = [found retain];
}

- (void)remember:(ExteriaDialog *)dialog {
    NSMutableArray *keys = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:ExteriaRecentChatsKey]];
    NSString *key = [self recentKeyOf:dialog];
    [keys removeObject:key];
    [keys insertObject:key atIndex:0];
    while (keys.count > RECENT_MAX) [keys removeLastObject];
    [[NSUserDefaults standardUserDefaults] setObject:keys forKey:ExteriaRecentChatsKey];
}

- (void)clearRecent {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:ExteriaRecentChatsKey];
    [self loadRecent];
    [self refreshState];
}

#pragma mark views

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = ExteriaColorScreen();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _field = [[UITextField alloc] init];
    _field.backgroundColor = ExteriaColorField();
    _field.layer.cornerRadius = FIELD_HEIGHT / 2;
    _field.delegate = self;
    _field.placeholder = NSLocalizedString(@"chats.search", nil);
    _field.font = ExteriaFontRegular(16);
    _field.textColor = ExteriaColorTitle();
    _field.autocorrectionType = UITextAutocorrectionTypeNo;
    _field.returnKeyType = UIReturnKeySearch;
    _field.keyboardAppearance = ExteriaThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    _field.clearButtonMode = UITextFieldViewModeWhileEditing;
    _field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    UIImageView *glass = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolMagnifier, 16, ExteriaColorMuted())] autorelease];
    glass.contentMode = UIViewContentModeCenter;
    glass.frame = CGRectMake(0, 0, 38, FIELD_HEIGHT);
    _field.leftView = glass;
    _field.leftViewMode = UITextFieldViewModeAlways;
    [_field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
    [root addSubview:_field];

    _cancel = [[ExteriaBarButton alloc] init];
    _cancel.title = NSLocalizedString(@"picker.cancel", nil);
    [_cancel addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_cancel];

    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(@"search.tab.chats", nil), NSLocalizedString(@"search.tab.channels", nil),
                       NSLocalizedString(@"search.tab.apps", nil), NSLocalizedString(@"search.tab.posts", nil), NSLocalizedString(@"search.tab.media", nil),
                       NSLocalizedString(@"search.tab.downloads", nil), NSLocalizedString(@"search.tab.links", nil), NSLocalizedString(@"search.tab.files", nil),
                       NSLocalizedString(@"search.tab.music", nil), NSLocalizedString(@"search.tab.voice", nil), nil];
    _tabs = [[ExteriaFilterBar alloc] initWithTitles:titles];
    _tabs.delegate = self;
    [root addSubview:_tabs];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    ExteriaScrollViewOwnsInsets(_table);
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = ROW_HEIGHT;
    [root addSubview:_table];
    _peers = [[ExteriaTopPeersView alloc] initWithFrame:CGRectMake(0, 0, 320, PEERS_HEIGHT)];
    _peers.target = self;

    _emptyView = [[UIView alloc] init];
    _emptyView.hidden = YES;
    [root addSubview:_emptyView];
    _duck = [[ExteriaLottieView alloc] initWithAnimationNamed:@"search_empty"];
    [_emptyView addSubview:_duck];
    _emptyTitle = [[UILabel alloc] init];
    _emptyTitle.backgroundColor = [UIColor clearColor];
    _emptyTitle.textColor = ExteriaColorTitle();
    _emptyTitle.textAlignment = ExteriaTextAlignmentCenter;
    [_emptyView addSubview:_emptyTitle];
    _emptyText = [[UILabel alloc] init];
    _emptyText.backgroundColor = [UIColor clearColor];
    _emptyText.textColor = ExteriaColorSecondary();
    _emptyText.textAlignment = ExteriaTextAlignmentCenter;
    _emptyText.numberOfLines = 0;
    [_emptyView addSubview:_emptyText];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:ExteriaThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [root addSubview:_spinner];
    _retry = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_retry setTitle:NSLocalizedString(@"list.retry", nil) forState:UIControlStateNormal];
    [_retry setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(runSearch) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES;
    [root addSubview:_retry];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadRecent];
    [self refreshState];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

- (BOOL)shouldAutorotate {
    return YES;
}

/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations {
    return ExteriaOrientationMask();
}
#pragma clang diagnostic pop

#pragma mark layout

- (void)layoutSearch {
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGRect column = ExteriaContentColumn(size, insets, EXTERIA_COLUMN_LIST);
    CGFloat left = column.origin.x, width = column.size.width, edge = CGRectGetMaxX(column);
    CGFloat top = insets.top + 6;
    _field.frame = CGRectMake(left + 14, top, width - 28 - 76, FIELD_HEIGHT);
    /* the cancel stands on the line of the field; the button keeps 14 points of padding at its right end, the margin the field has on the left */
    _cancel.frame = CGRectMake(CGRectGetMaxX(_field.frame), top, edge - CGRectGetMaxX(_field.frame), FIELD_HEIGHT);
    CGFloat tabsY = insets.top + BAR_HEIGHT + 4;
    _tabs.frame = CGRectMake(left, tabsY, width, CHIPS_HEIGHT);
    CGFloat bodyY = tabsY + CHIPS_HEIGHT;
    CGFloat bodyHeight = MAX(0, size.height - _keyboardOverlap - bodyY);
    _table.frame = CGRectMake(left, bodyY, width, bodyHeight);
    _table.contentInset = UIEdgeInsetsMake(0, 0, _keyboardOverlap > 0 ? 0 : insets.bottom, 0);
    _table.scrollIndicatorInsets = _table.contentInset;
    _emptyView.frame = CGRectMake(left, bodyY, width, bodyHeight);
    _peers.frame = CGRectMake(0, 0, width, PEERS_HEIGHT);
    CGFloat block = 130 + 12 + 24 + 6 + 62;
    CGFloat y = MAX(8, (bodyHeight - block) / 2 - 20);
    _duck.frame = CGRectMake((width - 130) / 2, y, 130, 130);
    _emptyTitle.font = ExteriaFontBold(19);
    _emptyTitle.frame = CGRectMake(24, y + 142, width - 48, 24);
    _emptyText.font = ExteriaFontRegular(15);
    _emptyText.frame = CGRectMake(32, y + 172, width - 64, 62);
    CGPoint middle = CGPointMake(CGRectGetMidX(column), bodyY + bodyHeight / 2 - 20);
    _spinner.center = middle;
    _retry.titleLabel.font = ExteriaFontSemibold(17);
    _retry.frame = CGRectMake(middle.x - 70, middle.y + 10, 140, 40);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutSearch];
}

#pragma mark keyboard

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    if (!_observing) {
        _observing = YES;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
        [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    }
    /* coming back from a chat shows the chats you opened lately, with the one you just opened first */
    /* the screen opens without a push, so it fades in and grows from a little larger, the way the search brings
       its results in */
    if (!_focused) {
        CGFloat scale = ExteriaLiteEnabled(EXTERIA_LITE_CHAT_SCALE) ? 1.04f : 1;
        ExteriaAnimateEnter(self.view, CGAffineTransformMakeScale(scale, scale), 0, EXTERIA_MOTION_ENTER);
    }
    [self loadRecent];
    [_table reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    /* the keyboard comes up when the screen opens, not again when a chat opened from here is left */
    if (!_focused) {
        _focused = YES;
        [_field becomeFirstResponder];
    }
    [self updateDuck];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_duck setPlaying:NO];
}

- (void)keyboardChanged:(NSNotification *)note {
    UIWindow *window = self.view.window;
    if (!window) return;
    NSDictionary *info = note.userInfo;
    CGFloat overlap = 0;
    if ([note.name isEqualToString:UIKeyboardWillChangeFrameNotification]) {
        CGRect end = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
        CGRect inView = [self.view convertRect:[window convertRect:end fromWindow:nil] fromView:window];
        overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - inView.origin.y);
    }
    _keyboardOverlap = overlap;
    NSTimeInterval duration = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    NSInteger curve = [[info objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];
    [UIView animateWithDuration:duration delay:0 options:(UIViewAnimationOptions)(curve << 16) animations:^{ [self layoutSearch]; } completion:nil];
}

- (void)close {
    [_field resignFirstResponder];
    CATransition *fade = [CATransition animation];
    fade.type = kCATransitionFade;
    fade.duration = 0.2;
    [self.navigationController.view.layer addAnimation:fade forKey:@"search"];
    [self.navigationController popViewControllerAnimated:NO];
}

#pragma mark query

- (void)textChanged {
    NSString *text = [_field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text isEqualToString:_query]) return;
    [_query release];
    _query = [text copy];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runSearch) object:nil];
    ++_generation;
    if (ExteriaTabIsLocal(_tabs.selectedIndex) || !_query.length) {
        [self runSearch];
        return;
    }
    /* the server is asked once the typing pauses, and what is on the screen waits meanwhile */
    _state = ExteriaSearchStateLoading;
    [self refreshState];
    [self performSelector:@selector(runSearch) withObject:nil afterDelay:SERVER_DELAY];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

- (BOOL)textFieldShouldClear:(UITextField *)field {
    (void)field;
    [self performSelector:@selector(textChanged) withObject:nil afterDelay:0];
    return YES;
}

- (void)filterBar:(ExteriaFilterBar *)bar didSelectIndex:(NSInteger)index {
    (void)bar;
    (void)index;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runSearch) object:nil];
    ++_generation;
    [self runSearch];
}

- (BOOL)dialog:(ExteriaDialog *)dialog fitsTab:(NSInteger)tab {
    switch (tab) {
    case ExteriaSearchTabChats: return dialog.kind == EXTERIA_DIALOG_USER || dialog.kind == EXTERIA_DIALOG_GROUP;
    case ExteriaSearchTabChannels: return dialog.kind == EXTERIA_DIALOG_CHANNEL;
    default: return dialog.kind == EXTERIA_DIALOG_BOT;
    }
}

/* looks for the query on the kind of results the strip has selected */
- (void)runSearch {
    NSInteger tab = _tabs.selectedIndex;
    NSUInteger generation = _generation;
    [_rows release];
    _rows = [[NSArray alloc] init];
    [_global release];
    _global = nil;
    if (tab == ExteriaSearchTabDownloads) {
        _state = ExteriaSearchStateHint;
    } else if (ExteriaTabIsLocal(tab)) {
        NSMutableArray *found = [NSMutableArray array];
        for (ExteriaDialog *dialog in _dialogs) {
            if (dialog.folder || ![self dialog:dialog fitsTab:tab]) continue;
            if (_query.length && [dialog.title rangeOfString:_query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) continue;
            [found addObject:dialog];
        }
        [_rows release];
        _rows = [found retain];
        /* with nothing local the screen waits for the server's public chats before it says there is nothing */
        _state = !_query.length ? ExteriaSearchStateStart : (found.count ? ExteriaSearchStateResults : ExteriaSearchStateLoading);
        [self scheduleGlobal];
    } else if (!_query.length) {
        _state = ExteriaSearchStateHint;
    } else {
        _state = ExteriaSearchStateLoading;
        [self refreshState];
        ExteriaWeakReference *weak = _weak;
        [_session searchGlobal:_query kind:ExteriaServerKindOfTab(tab) offsetRate:0 completion:^(NSArray *dialogs, int32_t nextRate, NSString *errorName) {
            (void)nextRate;
            ExteriaSearchController *search = weak.target;
            if (!search || generation != search->_generation) return;
            [search didSearch:dialogs error:errorName];
        }];
        return;
    }
    [self refreshState];
}

/* the server is asked for public chats once the typing pauses */
- (void)scheduleGlobal {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runGlobal) object:nil];
    if (_query.length) [self performSelector:@selector(runGlobal) withObject:nil afterDelay:SERVER_DELAY];
}

- (void)runGlobal {
    NSUInteger generation = _generation;
    NSInteger tab = _tabs.selectedIndex;
    ExteriaWeakReference *weak = _weak;
    [_session searchPeers:_query completion:^(NSArray *dialogs, NSString *errorName) {
        ExteriaSearchController *search = weak.target;
        if (!search || generation != search->_generation) return;
        [search didFindGlobal:dialogs forTab:tab error:errorName];
    }];
}

- (void)didFindGlobal:(NSArray *)dialogs forTab:(NSInteger)tab error:(NSString *)errorName {
    if (!dialogs) NSLog(@"exteria: global search failed: %@", errorName);
    NSMutableSet *known = [NSMutableSet set];
    for (ExteriaDialog *dialog in _rows) [known addObject:[self recentKeyOf:dialog]];
    NSMutableArray *fresh = [NSMutableArray array];
    for (ExteriaDialog *dialog in dialogs) {
        if (![self dialog:dialog fitsTab:tab] || [known containsObject:[self recentKeyOf:dialog]]) continue;
        [fresh addObject:dialog];
    }
    [_global release];
    _global = fresh.count ? [fresh retain] : nil;
    _state = (_rows.count || _global.count) ? ExteriaSearchStateResults : ExteriaSearchStateEmpty;
    [self refreshState];
}

- (void)didSearch:(NSArray *)dialogs error:(NSString *)errorName {
    if (!dialogs) {
        NSLog(@"exteria: search failed: %@", errorName);
        _state = ExteriaSearchStateFailed;
    } else {
        [_rows release];
        _rows = [dialogs retain];
        _state = dialogs.count ? ExteriaSearchStateResults : ExteriaSearchStateEmpty;
    }
    [self refreshState];
}

#pragma mark state

- (void)updateDuck {
    [_duck setPlaying:!_emptyView.hidden && self.view.window != nil];
}

- (void)refreshState {
    BOOL showsEmpty = _state == ExteriaSearchStateEmpty || _state == ExteriaSearchStateHint;
    _emptyView.hidden = !showsEmpty;
    _duck.hidden = _state != ExteriaSearchStateEmpty;
    if (_state == ExteriaSearchStateEmpty) {
        _emptyTitle.text = NSLocalizedString(@"search.empty.title", nil);
        _emptyText.text = [NSString stringWithFormat:NSLocalizedString(@"search.empty.text", nil), _query];
    } else if (_state == ExteriaSearchStateHint) {
        BOOL downloads = _tabs.selectedIndex == ExteriaSearchTabDownloads;
        _emptyTitle.text = downloads ? NSLocalizedString(@"search.downloads.title", nil) : @"";
        _emptyText.text = downloads ? NSLocalizedString(@"search.downloads.text", nil) : NSLocalizedString(@"search.hint", nil);
    }
    if (_state == ExteriaSearchStateLoading) [_spinner startAnimating];
    else [_spinner stopAnimating];
    _retry.hidden = _state != ExteriaSearchStateFailed;
    BOOL listed = _state == ExteriaSearchStateResults || _state == ExteriaSearchStateStart;
    _table.hidden = !listed;
    [self updateHeader];
    [_table reloadData];
    [self updateDuck];
    [self layoutSearch];
}

/* the people on top belong to the empty field on the chat kinds only */
- (void)updateHeader {
    BOOL showsPeers = _state == ExteriaSearchStateStart && _tabs.selectedIndex == ExteriaSearchTabChats;
    if (!showsPeers) {
        _table.tableHeaderView = nil;
        return;
    }
    NSMutableArray *people = [NSMutableArray array];
    for (ExteriaDialog *dialog in _dialogs) {
        if (people.count >= 10) break;
        if (dialog.kind == EXTERIA_DIALOG_USER && !dialog.saved && !dialog.folder) [people addObject:dialog];
    }
    if (!people.count) {
        _table.tableHeaderView = nil;
        return;
    }
    [_peers setDialogs:people avatars:_avatars];
    _table.tableHeaderView = _peers;
}

- (void)peerTapped:(UIControl *)item {
    NSMutableArray *people = [NSMutableArray array];
    for (ExteriaDialog *dialog in _dialogs) {
        if (people.count >= 10) break;
        if (dialog.kind == EXTERIA_DIALOG_USER && !dialog.saved && !dialog.folder) [people addObject:dialog];
    }
    if ((NSUInteger)item.tag < people.count) [self open:[people objectAtIndex:(NSUInteger)item.tag] remember:YES];
}

#pragma mark table

/* the recent chats are shown on the chat kinds they fit, the rest of the screen shows what the last search found */
- (NSArray *)visibleRows {
    if (_state != ExteriaSearchStateStart) return _rows;
    NSMutableArray *fitting = [NSMutableArray array];
    for (ExteriaDialog *dialog in _recent) if ([self dialog:dialog fitsTab:_tabs.selectedIndex]) [fitting addObject:dialog];
    return fitting;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return _global.count && _state == ExteriaSearchStateResults ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 1 ? (NSInteger)_global.count : (NSInteger)[[self visibleRows] count];
}

- (ExteriaDialog *)dialogAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1 ? [_global objectAtIndex:(NSUInteger)indexPath.row] : [[self visibleRows] objectAtIndex:(NSUInteger)indexPath.row];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 1) return SECTION_HEIGHT;
    return _state == ExteriaSearchStateStart && [[self visibleRows] count] ? SECTION_HEIGHT : 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == 1) {
        UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, SECTION_HEIGHT)] autorelease];
        header.backgroundColor = ExteriaColorField();
        UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(14, 0, tableView.bounds.size.width - 28, SECTION_HEIGHT)] autorelease];
        title.backgroundColor = [UIColor clearColor];
        title.font = ExteriaFontSemibold(15);
        title.textColor = ExteriaColorSecondary();
        title.text = NSLocalizedString(@"search.global", nil);
        [header addSubview:title];
        return header;
    }
    if (_state != ExteriaSearchStateStart || ![[self visibleRows] count]) return nil;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, SECTION_HEIGHT)] autorelease];
    header.backgroundColor = ExteriaColorField();
    UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(14, 0, 200, SECTION_HEIGHT)] autorelease];
    title.backgroundColor = [UIColor clearColor];
    title.font = ExteriaFontSemibold(15);
    title.textColor = ExteriaColorSecondary();
    title.text = NSLocalizedString(@"search.recent", nil);
    [header addSubview:title];
    UIButton *clear = [UIButton buttonWithType:UIButtonTypeCustom];
    clear.frame = CGRectMake(tableView.bounds.size.width - 110, 0, 100, SECTION_HEIGHT);
    clear.titleLabel.font = ExteriaFontRegular(15);
    clear.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    [clear setTitle:NSLocalizedString(@"search.clear", nil) forState:UIControlStateNormal];
    [clear setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [clear addTarget:self action:@selector(clearRecent) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:clear];
    return header;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"result";
    ExteriaSearchCell *cell = (ExteriaSearchCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaSearchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    BOOL message = !ExteriaTabIsLocal(_tabs.selectedIndex) && _state == ExteriaSearchStateResults;
    [cell configureWithDialog:[self dialogAtIndexPath:indexPath] showsDate:message avatars:_avatars];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BOOL local = ExteriaTabIsLocal(_tabs.selectedIndex) || _state == ExteriaSearchStateStart;
    [self open:[self dialogAtIndexPath:indexPath] remember:local];
}

- (void)open:(ExteriaDialog *)dialog remember:(BOOL)remember {
    [_field resignFirstResponder];
    if (remember) [self remember:dialog];
    if (dialog.community) {
        [self.navigationController pushViewController:ExteriaCommunityScreen(_session, dialog, nil, _avatars, _media, _stickers, nil) animated:YES];
        return;
    }
    if (dialog.forum) {
        [self.navigationController pushViewController:ExteriaTopicsScreen(_session, dialog, _avatars, _media, _stickers, nil) animated:YES];
        return;
    }
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    (void)scrollView;
    [_field resignFirstResponder];
}

@end
