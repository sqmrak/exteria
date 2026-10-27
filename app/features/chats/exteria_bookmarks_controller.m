#import "exteria_bookmarks_controller.h"
#import "exteria_string_drawing.h"

#import "exteria_bookmark_store.h"
#import "exteria_chat_controller.h"
#import "exteria_emoji_label.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_time.h"

#define ROW_HEIGHT 66.0
#define SIDE 16.0
#define TIME_WIDTH 70.0

@interface ExteriaBookmarkCell : UITableViewCell {
    ExteriaEmojiLabel *_title;
    ExteriaEmojiLabel *_text;
    UILabel *_time;
}
- (void)configureWithBookmark:(ExteriaBookmark *)bookmark;
@end

@implementation ExteriaBookmarkCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    UIView *selected = [[[UIView alloc] init] autorelease];
    selected.backgroundColor = ExteriaColorField();
    self.selectedBackgroundView = selected;
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.font = ExteriaFontSemibold(15.5);
    _title.textColor = ExteriaColorTitle();
    [self.contentView addSubview:_title];
    _text = [[ExteriaEmojiLabel alloc] init];
    _text.font = ExteriaFontRegular(14);
    _text.textColor = ExteriaColorSecondary();
    _text.numberOfLines = 2;
    [self.contentView addSubview:_text];
    _time = [[UILabel alloc] init];
    ExteriaLabelFitToWidth(_time, 9);
    _time.backgroundColor = [UIColor clearColor];
    _time.font = ExteriaFontRegular(12.5);
    _time.textColor = ExteriaColorSecondary();
    _time.textAlignment = ExteriaTextAlignmentRight;
    [self.contentView addSubview:_time];
    return self;
}

- (void)dealloc {
    [_title release];
    [_text release];
    [_time release];
    [super dealloc];
}

- (void)configureWithBookmark:(ExteriaBookmark *)bookmark {
    _title.text = bookmark.title;
    _text.text = bookmark.text;
    _time.text = ExteriaListTimeText(bookmark.date);
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", bookmark.title, bookmark.text];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    _time.frame = CGRectMake(width - SIDE - TIME_WIDTH, 11, TIME_WIDTH, 18);
    _title.frame = CGRectMake(SIDE, 10, width - 2 * SIDE - TIME_WIDTH - 6, 20);
    _text.frame = CGRectMake(SIDE, 32, width - 2 * SIDE, 32);
}

@end

@interface ExteriaBookmarksController () {
    ExteriaStickerLibrary *_stickers;
    UITableView *_table;
    UILabel *_empty;
}
@end

@implementation ExteriaBookmarksController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _stickers = [stickers retain];
    self.screenTitle = NSLocalizedString(@"bookmarks.title", nil);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.dataSource = nil;
    _table.delegate = nil;
    [_table release];
    [_empty release];
    [_stickers release];
    [super dealloc];
}

- (NSArray *)entries {
    return [ExteriaBookmarks bookmarksForSession:self.session].entries;
}

- (void)buildBodyInView:(UIView *)root {
    _table = [[UITableView alloc] init];
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorColor = ExteriaColorHairline();
    _table.rowHeight = ROW_HEIGHT;
    _table.dataSource = self;
    _table.delegate = self;
    [root addSubview:_table];
    _empty = [[UILabel alloc] init];
    _empty.backgroundColor = [UIColor clearColor];
    _empty.textColor = ExteriaColorSecondary();
    _empty.textAlignment = ExteriaTextAlignmentCenter;
    _empty.font = ExteriaFontRegular(16);
    _empty.numberOfLines = 0;
    _empty.text = NSLocalizedString(@"bookmarks.empty", nil);
    [root addSubview:_empty];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changed) name:ExteriaBookmarksDidChangeNotification object:nil];
    [self refreshEmpty];
}

- (void)layoutBody:(CGRect)body {
    _table.frame = body;
    _empty.frame = CGRectMake(body.origin.x + 24, CGRectGetMidY(body) - 40, body.size.width - 48, 80);
}

- (void)refreshEmpty {
    _empty.hidden = [self entries].count > 0;
    _table.hidden = !_empty.hidden;
}

- (void)changed {
    [_table reloadData];
    [self refreshEmpty];
}

#pragma mark table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)[self entries].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"bookmark";
    ExteriaBookmarkCell *cell = (ExteriaBookmarkCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaBookmarkCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    [cell configureWithBookmark:[[self entries] objectAtIndex:(NSUInteger)indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ExteriaBookmark *entry = [[self entries] objectAtIndex:(NSUInteger)indexPath.row];
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:self.session dialog:[entry dialog] avatars:self.avatars media:self.media
                                                                         stickers:_stickers] autorelease];
    chat.startMessageId = entry.messageId;
    [self.navigationController pushViewController:chat animated:YES];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return UITableViewCellEditingStyleDelete;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return NSLocalizedString(@"bookmarks.remove", nil);
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (style != UITableViewCellEditingStyleDelete) return;
    ExteriaBookmark *entry = [[self entries] objectAtIndex:(NSUInteger)indexPath.row];
    /* the notification of the store reloads the table, with the row gone */
    if (![[ExteriaBookmarks bookmarksForSession:self.session] removeEntry:entry]) ExteriaGiftAlert(nil, NSLocalizedString(@"bookmarks.failed", nil));
}

@end
