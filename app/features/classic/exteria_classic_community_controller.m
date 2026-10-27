#import "exteria_classic_community_controller.h"

#import "exteria_chat_controller.h"
#import "exteria_classic_chrome.h"
#import "exteria_classic_dialog_cell.h"
#import "exteria_community.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"
#import "exteria_topics_screen.h"

enum { SectionSwitch, SectionJoined, SectionViewable, SectionCount };

@interface ExteriaClassicCommunityController () {
    ExteriaSession *_session;
    ExteriaDialog *_community;
    NSArray *_known;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    ExteriaCommunity *_loaded;
    UILabel *_status;
    UISwitch *_switch;
    BOOL _loading;
    void (^_closeHandler)(void);
}
@end

@implementation ExteriaClassicCommunityController

@synthesize closeHandler = _closeHandler;

- (id)initWithSession:(ExteriaSession *)session community:(ExteriaDialog *)community known:(NSArray *)known avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (!self) return nil;
    _session = [session retain];
    _community = [community retain];
    _known = [known copy];
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    self.title = community.title;
    self.navigationItem.titleView = ExteriaClassicTitleView(community.title, nil);
    return self;
}

- (void)dealloc {
    if ([self isViewLoaded]) {
        self.tableView.delegate = nil;
        self.tableView.dataSource = nil;
    }
    [_session release];
    [_community release];
    [_known release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_loaded release];
    [_status release];
    [_switch release];
    [_closeHandler release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UITableView *table = self.tableView;
    ExteriaClassicStyleTable(table);
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = ExteriaColorSecondary();
    _status.textAlignment = ExteriaTextAlignmentCenter;
    _status.numberOfLines = 0;
    _status.font = [UIFont systemFontOfSize:16];
    _status.frame = table.backgroundView.bounds;
    _status.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [table.backgroundView addSubview:_status];
    [self reload];
}

- (void)reload {
    if (_loading) return;
    _loading = YES;
    [self retain];
    [_session loadCommunity:_community knownDialogs:_known completion:^(ExteriaCommunity *community, NSString *errorName) {
        [self autorelease];
        _loading = NO;
        if (!community) {
            /* a community already on screen stays; only an empty screen shows the failure */
            if (!_loaded) {
                _status.text = [errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                       : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName ? errorName : @"?"];
            } else {
                NSLog(@"exteria: refresh of the community failed: %@", errorName);
            }
            return;
        }
        [_loaded release];
        _loaded = [community retain];
        _status.text = @"";
        [self.tableView reloadData];
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if ([self isMovingFromParentViewController] && _closeHandler) _closeHandler();
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

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == SectionSwitch || ![self chatsOfSection:section].count) return nil;
    return NSLocalizedString(section == SectionJoined ? @"community.joined" : @"community.viewable", nil);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    return section == SectionSwitch ? NSLocalizedString(@"community.collapse.hint", nil) : nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForHeaderInSection:section];
    if (!text.length) return nil;
    return ExteriaClassicGroupedHeader(text, tableView.bounds.size.width,
        [self tableView:tableView heightForHeaderInSection:section], ExteriaColorSecondary());
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForHeaderInSection:section];
    if (!text.length) return 10;
    CGSize fit = ExteriaStringSizeIn(text, [UIFont boldSystemFontOfSize:17], CGSizeMake(MAX(1, tableView.bounds.size.width - 2 * ExteriaClassicGroupedTextInset(tableView.bounds.size.width)), CGFLOAT_MAX));
    return MAX(40, ceil(fit.height) + 16);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    if (!text.length) return nil;
    UIView *holder = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width,
        [self tableView:tableView heightForFooterInSection:section])] autorelease];
    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectInset(holder.bounds, 20, 6)] autorelease];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.backgroundColor = [UIColor clearColor];
    label.textColor = ExteriaColorSecondary();
    label.font = [UIFont systemFontOfSize:14];
    label.numberOfLines = 0;
    label.text = text;
    [holder addSubview:label];
    return holder;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    if (!text.length) return 10;
    CGSize fit = ExteriaStringSizeIn(text, [UIFont systemFontOfSize:14], CGSizeMake(MAX(1, tableView.bounds.size.width - 40), CGFLOAT_MAX));
    return ceil(fit.height) + 12;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return indexPath.section == SectionSwitch ? 44 : [ExteriaClassicDialogCell rowHeight];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == SectionSwitch) {
        static NSString *switchIdentifier = @"switch";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:switchIdentifier];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:switchIdentifier] autorelease];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            if (!_switch) {
                _switch = [[UISwitch alloc] init];
                [_switch addTarget:self action:@selector(collapseChanged:) forControlEvents:UIControlEventValueChanged];
            }
            cell.accessoryView = _switch;
        }
        ExteriaClassicStyleCell(cell);
        cell.textLabel.backgroundColor = [UIColor clearColor];
        cell.textLabel.text = NSLocalizedString(@"community.collapse", nil);
        _switch.on = _loaded.collapsed;
        return cell;
    }
    static NSString *identifier = @"chat";
    ExteriaClassicDialogCell *cell = (ExteriaClassicDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaClassicDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    cell.media = _media;
    [cell configureWithDialog:[[self chatsOfSection:indexPath.section] objectAtIndex:(NSUInteger)indexPath.row] avatars:_avatars];
    return cell;
}

- (void)collapseChanged:(UISwitch *)sender {
    BOOL collapsed = sender.on;
    _loaded.collapsed = collapsed;
    [_session setCommunity:_community collapsed:collapsed completion:^(NSString *errorName) {
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
        [self.navigationController pushViewController:ExteriaTopicsScreen(_session, chat, _avatars, _media, _stickers, ^{ [self reload]; }) animated:YES];
        return;
    }
    ExteriaChatController *screen = [[[ExteriaChatController alloc] initWithSession:_session dialog:chat avatars:_avatars media:_media stickers:_stickers] autorelease];
    screen.hidesBottomBarWhenPushed = YES;
    /* reading changed the counts of the chats, so they load again once the person is back */
    screen.closeHandler = ^{ [self reload]; };
    [self.navigationController pushViewController:screen animated:YES];
}

@end
