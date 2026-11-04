#import <QuartzCore/QuartzCore.h>
#import "exteria_community_controller.h"

#import "exteria_chat_controller.h"
#import "exteria_community.h"
#import "exteria_dialog_cell.h"
#import "exteria_draft.h"
#import "exteria_theme.h"
#import "exteria_topics_screen.h"

#define HEADER_HEIGHT 52.0
#define SIDE_MARGIN 16.0
/* the sections stand on rounded cards that keep this far from the edges of the screen, and a gap lies between two cards */
#define CARD_INSET 12.0
#define CARD_RADIUS 22.0
#define CARD_GAP 14.0
#define SWITCH_PAD 20.0

typedef enum { ExteriaCardTop, ExteriaCardMiddle, ExteriaCardBottom, ExteriaCardSingle } ExteriaCardPart;

/* the piece of a card that one row or header stands on: the corners that touch the edge of the card are round, the others square */
@interface ExteriaCardBackdrop : UIView {
    ExteriaCardPart _part;
}
@property (nonatomic, assign) ExteriaCardPart part;
@end

@implementation ExteriaCardBackdrop
@synthesize part = _part;
- (void)setPart:(ExteriaCardPart)part {
    _part = part;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    UIRectCorner corners = _part == ExteriaCardTop ? (UIRectCornerTopLeft | UIRectCornerTopRight)
                         : _part == ExteriaCardBottom ? (UIRectCornerBottomLeft | UIRectCornerBottomRight)
                         : _part == ExteriaCardSingle ? UIRectCornerAllCorners : (UIRectCorner)0;
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.path = [UIBezierPath bezierPathWithRoundedRect:self.bounds byRoundingCorners:corners cornerRadii:CGSizeMake(CARD_RADIUS, CARD_RADIUS)].CGPath;
    self.layer.mask = mask;
}
@end

static ExteriaCardBackdrop *ExteriaCardBackdropOf(ExteriaCardPart part, UIColor *color) {
    ExteriaCardBackdrop *view = [[[ExteriaCardBackdrop alloc] init] autorelease];
    view.backgroundColor = color;
    view.part = part;
    return view;
}

/* a chat of the community on its card: the row is narrowed to the card, so everything the row draws keeps its own margins inside it */
@interface ExteriaCommunityChatCell : ExteriaDialogCell
@end

@implementation ExteriaCommunityChatCell
- (void)setFrame:(CGRect)frame {
    [super setFrame:CGRectInset(frame, CARD_INSET, 0)];
}
@end

/* the switch and its words on a card of their own */
@interface ExteriaCommunitySwitchCell : UITableViewCell {
    UILabel *_title;
    UILabel *_hint;
    UISwitch *_switch;
}
@property (nonatomic, readonly) UILabel *title;
@property (nonatomic, readonly) UILabel *hint;
@property (nonatomic, readonly) UISwitch *toggle;
+ (CGFloat)heightForHint:(NSString *)hint width:(CGFloat)width;
@end

@implementation ExteriaCommunitySwitchCell
@synthesize title = _title;
@synthesize hint = _hint;
@synthesize toggle = _switch;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundView = ExteriaCardBackdropOf(ExteriaCardSingle, ExteriaColorCard());
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.font = ExteriaFontRegular(18);
    _title.textColor = ExteriaColorTitle();
    [self.contentView addSubview:_title];
    _hint = [[UILabel alloc] init];
    _hint.backgroundColor = [UIColor clearColor];
    _hint.font = ExteriaFontRegular(15);
    _hint.textColor = ExteriaColorSecondary();
    _hint.numberOfLines = 0;
    [self.contentView addSubview:_hint];
    _switch = [[UISwitch alloc] init];
    [self.contentView addSubview:_switch];
    return self;
}

- (void)dealloc {
    [_title release];
    [_hint release];
    [_switch release];
    [super dealloc];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:CGRectInset(frame, CARD_INSET, 0)];
}

+ (CGFloat)heightForHint:(NSString *)hint width:(CGFloat)width {
    UILabel *probe = [[[UILabel alloc] init] autorelease];
    probe.font = ExteriaFontRegular(15);
    probe.numberOfLines = 0;
    probe.text = hint;
    CGFloat text = ceil([probe sizeThatFits:CGSizeMake(MAX(1, width - 2 * CARD_INSET - 2 * SWITCH_PAD), CGFLOAT_MAX)].height);
    return SWITCH_PAD + 32 + 12 + text + SWITCH_PAD;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGSize toggle = _switch.bounds.size;
    _switch.frame = CGRectMake(width - SWITCH_PAD - toggle.width, SWITCH_PAD + (32 - toggle.height) / 2, toggle.width, toggle.height);
    _title.frame = CGRectMake(SWITCH_PAD, SWITCH_PAD, MAX(0, width - 2 * SWITCH_PAD - toggle.width - 8), 32);
    CGSize hint = [_hint sizeThatFits:CGSizeMake(MAX(1, width - 2 * SWITCH_PAD), CGFLOAT_MAX)];
    _hint.frame = CGRectMake(SWITCH_PAD, SWITCH_PAD + 32 + 12, MAX(1, width - 2 * SWITCH_PAD), ceil(hint.height));
}
@end

enum { SectionSwitch, SectionJoined, SectionViewable, SectionCount };

@interface ExteriaCommunityController () {
    ExteriaDialog *_community;
    NSArray *_known;
    ExteriaCommunity *_loaded;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    void (^_closeHandler)(void);
}
@end

@implementation ExteriaCommunityController

@synthesize closeHandler = _closeHandler;

- (id)initWithSession:(ExteriaSession *)session community:(ExteriaDialog *)community known:(NSArray *)known avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers {
    self = [super initWithSession:session];
    if (!self) return nil;
    _community = [community retain];
    _known = [known copy];
    _media = [media retain];
    _stickers = [stickers retain];
    self.avatars = avatars;
    self.heading = community.title;
    self.showsBack = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(draftChanged:) name:ExteriaDraftDidChangeNotification object:session.drafts];
    return self;
}

- (void)draftChanged:(NSNotification *)note {
    (void)note;
    if (self.isViewLoaded && _loaded) [self.table reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaDraftDidChangeNotification object:nil];
    [_community release];
    [_known release];
    [_loaded release];
    [_media release];
    [_stickers release];
    [_closeHandler release];
    [super dealloc];
}

- (void)loadItemsWithCompletion:(ExteriaListCompletion)completion {
    [self.session loadCommunity:_community knownDialogs:_known completion:^(ExteriaCommunity *community, NSString *errorName) {
        completion(community ? [NSArray arrayWithObject:community] : nil, errorName);
    }];
}

- (void)didReceiveItems:(NSArray *)items {
    [_loaded release];
    _loaded = [[items objectAtIndex:0] retain];
    /* how many chats the community holds, the ones the account is in and the ones it may look at */
    NSUInteger total = _loaded.joined.count + _loaded.viewable.count;
    self.subheading = total ? [NSString stringWithFormat:NSLocalizedString(@"community.chats.count", nil), (unsigned long)total] : nil;
}

/* the switch row is always there once the community is in, so the list never reads as empty */
- (NSInteger)itemCount {
    return _loaded ? 1 : 0;
}

- (NSArray *)chatsOfSection:(NSInteger)section {
    return section == SectionJoined ? _loaded.joined : _loaded.viewable;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return _loaded ? SectionCount : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == SectionSwitch ? 1 : (NSInteger)[self chatsOfSection:section].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section == SectionSwitch) return [ExteriaCommunitySwitchCell heightForHint:NSLocalizedString(@"community.collapse.hint", nil) width:tableView.bounds.size.width];
    return [ExteriaDialogCell rowHeight];
}

- (UILabel *)captionWithText:(NSString *)text font:(UIFont *)font {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = ExteriaColorSecondary();
    label.font = font;
    label.numberOfLines = 0;
    label.text = text;
    return label;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section != SectionSwitch && [self chatsOfSection:section].count ? HEADER_HEIGHT : 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == SectionSwitch || ![self chatsOfSection:section].count) return nil;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, HEADER_HEIGHT)] autorelease];
    /* the headers of a plain table stay at the top while the rows go on under them, so a clear one let the chats show through and the words lay on the words of a row */
    header.backgroundColor = ExteriaColorScreen();
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    /* the title stands in the top of the card that holds the chats */
    ExteriaCardBackdrop *card = ExteriaCardBackdropOf(ExteriaCardTop, ExteriaColorCard());
    card.frame = CGRectMake(CARD_INSET, 0, header.bounds.size.width - 2 * CARD_INSET, HEADER_HEIGHT);
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:card];
    UILabel *label = [self captionWithText:NSLocalizedString(section == SectionJoined ? @"community.joined" : @"community.viewable", nil)
                                      font:ExteriaFontSemibold(17)];
    label.frame = CGRectMake(SWITCH_PAD, 8, card.bounds.size.width - 2 * SWITCH_PAD, HEADER_HEIGHT - 8);
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [card addSubview:label];
    return header;
}

/* the gap under a card, which keeps the next card apart; the switch card has no footer words since they stand inside it */
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    (void)tableView;
    return section == SectionSwitch || [self chatsOfSection:section].count ? CARD_GAP : 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    UIView *gap = [[[UIView alloc] init] autorelease];
    gap.backgroundColor = ExteriaColorScreen();
    return gap;
}

- (UITableViewCell *)switchCell:(UITableView *)tableView {
    static NSString *identifier = @"switch";
    ExteriaCommunitySwitchCell *cell = (ExteriaCommunitySwitchCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[ExteriaCommunitySwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
        [cell.toggle addTarget:self action:@selector(collapseChanged:) forControlEvents:UIControlEventValueChanged];
    }
    cell.title.text = NSLocalizedString(@"community.collapse", nil);
    cell.hint.text = NSLocalizedString(@"community.collapse.hint", nil);
    cell.toggle.on = _loaded.collapsed;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == SectionSwitch) return [self switchCell:tableView];
    static NSString *identifier = @"chat";
    ExteriaDialogCell *cell = (ExteriaDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaCommunityChatCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    NSArray *chats = [self chatsOfSection:indexPath.section];
    /* the title above is the top of the card, so the first row is a middle one, and the last row closes the card */
    ExteriaCardPart part = (NSUInteger)indexPath.row + 1 == chats.count ? ExteriaCardBottom : ExteriaCardMiddle;
    cell.backgroundView = ExteriaCardBackdropOf(part, ExteriaColorCard());
    cell.selectedBackgroundView = ExteriaCardBackdropOf(part, ExteriaColorField());
    ExteriaDialog *chat = [chats objectAtIndex:(NSUInteger)indexPath.row];
    [cell configureWithDialog:chat avatars:self.avatars action:ExteriaDialogActionNone];
    [cell showDraft:ExteriaVisibleDraft(self.session.drafts, chat)];
    [cell layoutIfNeeded];
    return cell;
}

- (void)collapseChanged:(UISwitch *)sender {
    BOOL collapsed = sender.on;
    _loaded.collapsed = collapsed;
    [self.session setCommunity:_community collapsed:collapsed completion:^(NSString *errorName) {
        if (!errorName) return;
        NSLog(@"exteria: folding community %lld failed: %@", _community.peerId, errorName);
        /* the list keeps what the server has, so the switch goes back to it and the person is told */
        _loaded.collapsed = !collapsed;
        sender.on = !collapsed;
        Class alertClass = NSClassFromString(@"UIAlertView");
        id alert = [[alertClass alloc] initWithTitle:nil message:[NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]
                                            delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
        [alert show];
        [alert release];
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == SectionSwitch) return;
    ExteriaDialog *chat = [[self chatsOfSection:indexPath.section] objectAtIndex:(NSUInteger)indexPath.row];
    if (chat.forum) {
        [self.navigationController pushViewController:ExteriaTopicsScreen(self.session, chat, self.avatars, _media, _stickers,
                                                                          ^{ [self reloadDiscardingRunning]; }) animated:YES];
        return;
    }
    ExteriaChatController *screen = [[[ExteriaChatController alloc] initWithSession:self.session dialog:chat avatars:self.avatars
                                                                              media:_media stickers:_stickers] autorelease];
    /* reading changed the counts of the chats, so they load again once the person is back */
    screen.closeHandler = ^{ [self reloadDiscardingRunning]; };
    [self.navigationController pushViewController:screen animated:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if ([self isMovingFromParentViewController] && _closeHandler) _closeHandler();
}

@end
