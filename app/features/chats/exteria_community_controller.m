#import "exteria_community_controller.h"

#import "exteria_chat_controller.h"
#import "exteria_community.h"
#import "exteria_dialog_cell.h"
#import "exteria_draft.h"
#import "exteria_theme.h"
#import "exteria_topics_screen.h"

#define SWITCH_ROW_HEIGHT 56.0
#define HEADER_HEIGHT 38.0
#define SIDE_MARGIN 16.0

enum { SectionSwitch, SectionJoined, SectionViewable, SectionCount };

@interface ExteriaCommunityController () {
    ExteriaDialog *_community;
    NSArray *_known;
    ExteriaCommunity *_loaded;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    UISwitch *_switch;
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
    [_switch release];
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
    return indexPath.section == SectionSwitch ? SWITCH_ROW_HEIGHT : [ExteriaDialogCell rowHeight];
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
    UILabel *label = [self captionWithText:NSLocalizedString(section == SectionJoined ? @"community.joined" : @"community.viewable", nil)
                                      font:ExteriaFontSemibold(15)];
    label.frame = CGRectMake(SIDE_MARGIN, 0, header.bounds.size.width - SIDE_MARGIN * 2, HEADER_HEIGHT);
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:label];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section != SectionSwitch) return 0;
    CGSize fit = [[self captionWithText:NSLocalizedString(@"community.collapse.hint", nil) font:ExteriaFontRegular(14)]
                  sizeThatFits:CGSizeMake(tableView.bounds.size.width - SIDE_MARGIN * 2, 200)];
    return ceil(fit.height) + 16;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section != SectionSwitch) return nil;
    UIView *footer = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, [self tableView:tableView heightForFooterInSection:section])] autorelease];
    UILabel *label = [self captionWithText:NSLocalizedString(@"community.collapse.hint", nil) font:ExteriaFontRegular(14)];
    label.frame = CGRectMake(SIDE_MARGIN, 0, footer.bounds.size.width - SIDE_MARGIN * 2, footer.bounds.size.height - 8);
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [footer addSubview:label];
    return footer;
}

- (UITableViewCell *)switchCell:(UITableView *)tableView {
    static NSString *identifier = @"switch";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = ExteriaFontRegular(17);
        cell.textLabel.textColor = ExteriaColorTitle();
        cell.textLabel.backgroundColor = [UIColor clearColor];
        if (!_switch) {
            _switch = [[UISwitch alloc] init];
            [_switch addTarget:self action:@selector(collapseChanged:) forControlEvents:UIControlEventValueChanged];
        }
        cell.accessoryView = _switch;
    }
    cell.textLabel.text = NSLocalizedString(@"community.collapse", nil);
    _switch.on = _loaded.collapsed;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == SectionSwitch) return [self switchCell:tableView];
    static NSString *identifier = @"chat";
    ExteriaDialogCell *cell = (ExteriaDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    ExteriaDialog *chat = [[self chatsOfSection:indexPath.section] objectAtIndex:(NSUInteger)indexPath.row];
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
        _switch.on = !collapsed;
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
