#import "exteria_developers.h"
#import "exteria_calls_controller.h"

#import "exteria_chat_controller.h"
#import "exteria_person_cell.h"
#import "exteria_session_calllog.h"
#import "exteria_sheet.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_time.h"
#import "exteria_weak_reference.h"

@interface ExteriaCallsController () {
    NSArray *_entries;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickerLibrary;
}
@end

@implementation ExteriaCallsController

@synthesize media = _media;
@synthesize stickerLibrary = _stickerLibrary;

- (id)initWithSession:(ExteriaSession *)session {
    self = [super initWithSession:session];
    if (!self) return nil;
    self.heading = NSLocalizedString(@"tab.calls", nil);
    return self;
}

- (void)dealloc {
    [_entries release];
    [_media release];
    [_stickerLibrary release];
    [super dealloc];
}

/* a call can end with the app on screen, and the log is asked again each time the tab comes back */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)loadItemsWithCompletion:(ExteriaListCompletion)completion {
    [self.session loadCallLog:completion];
}

- (void)didReceiveItems:(NSArray *)items {
    [_entries release];
    _entries = [items retain];
}

- (NSInteger)itemCount {
    return (NSInteger)_entries.count;
}

- (NSString *)emptyText {
    return NSLocalizedString(@"calls.empty", nil);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_entries.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return [ExteriaPersonCell rowHeight];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"call";
    ExteriaPersonCell *cell = (ExteriaPersonCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaPersonCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    ExteriaCallLogEntry *entry = [_entries objectAtIndex:(NSUInteger)indexPath.row];
    BOOL bad = entry.missed && !entry.outgoing;
    cell.developer = ExteriaMarksOfId(entry.userId);
    [cell configureWithName:entry.name initials:entry.initials seed:(NSUInteger)(entry.userId % 1000003)
                   subtitle:[entry summaryText] subtitleColor:bad ? ExteriaColorBadgeRed() : nil
                   trailing:ExteriaListTimeText(entry.date) symbol:entry.video ? ExteriaSymbolVideoCallMenu : ExteriaSymbolPhone showsSymbol:YES
                  nameColor:bad ? ExteriaColorBadgeRed() : nil photo:entry.photo avatars:self.avatars];
    cell.avatarDeleted = entry.deleted;
    return cell;
}

- (void)openChatOf:(ExteriaCallLogEntry *)entry {
    ExteriaDialog *dialog = [entry dialog];
    if (!dialog) return;
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:self.session dialog:dialog avatars:self.avatars
                                                                           media:_media stickers:_stickerLibrary] autorelease];
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ExteriaCallLogEntry *entry = [_entries objectAtIndex:(NSUInteger)indexPath.row];
    if (![entry dialog]) return;
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"calls.callback", nil), NSLocalizedString(@"calls.openchat", nil), nil];
    [ExteriaSheet presentInView:self.view title:entry.name message:nil options:options destructive:nil cancelTitle:NSLocalizedString(@"picker.cancel", nil)
                        handler:^(NSUInteger index) {
        ExteriaCallsController *me = weak.target;
        if (!me) return;
        if (index == 0) [me.session startCallToDialog:[entry dialog]];
        else [me openChatOf:entry];
    }];
}

@end
