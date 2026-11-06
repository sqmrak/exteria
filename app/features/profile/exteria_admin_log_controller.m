#import "exteria_admin_log_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_centered_hint_field.h"
#import "exteria_channel_errors.h"
#import "exteria_session_admin_log.h"
#import "exteria_theme.h"
#import "exteria_time.h"
#import "exteria_weak_reference.h"

#define SEARCH_HEIGHT 52.0
#define SEARCH_DELAY 0.35
#define SIDE_MARGIN 16.0
#define TIME_WIDTH 52.0
#define CELL_PAD 10.0
#define DETAIL_LINES 6

/* an event with the two texts its row shows, made once when the page arrives so scrolling does not format them again */
@interface ExteriaAdminLogRow : NSObject {
    ExteriaAdminEvent *_event;
    NSString *_sentence;
    NSString *_detail;
}
@property (nonatomic, readonly) ExteriaAdminEvent *event;
@property (nonatomic, readonly) NSString *sentence;
@property (nonatomic, readonly) NSString *detail;
@end

static NSString *ExteriaLogText(NSString *key) {
    return NSLocalizedString(key, nil);
}

/* "30 s", "5 min", "2 h", "3 d": the whole unit the number of seconds fills */
static NSString *ExteriaLogDuration(int32_t seconds) {
    if (seconds % 86400 == 0 && seconds >= 86400) return [NSString stringWithFormat:ExteriaLogText(@"adminlog.unit.d"), seconds / 86400];
    if (seconds % 3600 == 0 && seconds >= 3600) return [NSString stringWithFormat:ExteriaLogText(@"adminlog.unit.h"), seconds / 3600];
    if (seconds % 60 == 0 && seconds >= 60) return [NSString stringWithFormat:ExteriaLogText(@"adminlog.unit.min"), seconds / 60];
    return [NSString stringWithFormat:ExteriaLogText(@"adminlog.unit.s"), seconds];
}

static NSString *ExteriaLogActor(ExteriaAdminEvent *event) {
    return event.actorName.length ? event.actorName : ExteriaLogText(@"adminlog.someone");
}

static NSString *ExteriaLogTarget(ExteriaAdminEvent *event) {
    return event.targetName.length ? event.targetName : ExteriaLogText(@"adminlog.someone");
}

/* the key of the sentence, with the state of a switch as its last part; nil for the kinds that need more than a format */
static NSString *ExteriaLogKey(ExteriaAdminEvent *event) {
    switch (event.kind) {
    case EXTERIA_LOG_JOIN: return @"adminlog.join";
    case EXTERIA_LOG_JOIN_BY_INVITE: return @"adminlog.join.invite";
    case EXTERIA_LOG_JOIN_BY_REQUEST: return @"adminlog.join.request";
    case EXTERIA_LOG_LEAVE: return @"adminlog.leave";
    case EXTERIA_LOG_INVITE: return @"adminlog.invite";
    case EXTERIA_LOG_BAN: return @"adminlog.ban";
    case EXTERIA_LOG_RESTRICT: return @"adminlog.restrict";
    case EXTERIA_LOG_UNBAN: return @"adminlog.unban";
    case EXTERIA_LOG_PROMOTE: return @"adminlog.promote";
    case EXTERIA_LOG_ADMIN_RIGHTS: return @"adminlog.rights";
    case EXTERIA_LOG_DEMOTE: return @"adminlog.demote";
    case EXTERIA_LOG_EDIT_RANK: return @"adminlog.rank";
    case EXTERIA_LOG_TITLE: return @"adminlog.title.change";
    case EXTERIA_LOG_ABOUT: return @"adminlog.about";
    case EXTERIA_LOG_USERNAME: return @"adminlog.username";
    case EXTERIA_LOG_PHOTO: return @"adminlog.photo";
    case EXTERIA_LOG_INVITES: return event.flag ? @"adminlog.invites.1" : @"adminlog.invites.0";
    case EXTERIA_LOG_SIGNATURES: return event.flag ? @"adminlog.signatures.1" : @"adminlog.signatures.0";
    case EXTERIA_LOG_SIGNATURE_PROFILES: return event.flag ? @"adminlog.signprofiles.1" : @"adminlog.signprofiles.0";
    case EXTERIA_LOG_HISTORY_HIDDEN: return event.flag ? @"adminlog.history.1" : @"adminlog.history.0";
    case EXTERIA_LOG_NO_FORWARDS: return event.flag ? @"adminlog.forwards.1" : @"adminlog.forwards.0";
    case EXTERIA_LOG_FORUM: return event.flag ? @"adminlog.forum.1" : @"adminlog.forum.0";
    case EXTERIA_LOG_ANTI_SPAM: return event.flag ? @"adminlog.antispam.1" : @"adminlog.antispam.0";
    case EXTERIA_LOG_SLOW_MODE: return event.number > 0 ? @"adminlog.slow.1" : @"adminlog.slow.0";
    case EXTERIA_LOG_HISTORY_TTL: return event.number > 0 ? @"adminlog.ttl.1" : @"adminlog.ttl.0";
    case EXTERIA_LOG_LINKED_CHAT: return event.flag ? @"adminlog.linked.1" : @"adminlog.linked.0";
    case EXTERIA_LOG_DEFAULT_RIGHTS: return @"adminlog.defaultrights";
    case EXTERIA_LOG_PIN: return @"adminlog.pin";
    case EXTERIA_LOG_UNPIN: return @"adminlog.unpin";
    case EXTERIA_LOG_EDIT_MESSAGE: return @"adminlog.message.edit";
    case EXTERIA_LOG_DELETE_MESSAGE: return @"adminlog.message.delete";
    case EXTERIA_LOG_SEND_MESSAGE: return @"adminlog.message.send";
    case EXTERIA_LOG_STOP_POLL: return @"adminlog.poll.stop";
    case EXTERIA_LOG_CALL_START: return @"adminlog.call.start";
    case EXTERIA_LOG_CALL_END: return @"adminlog.call.end";
    case EXTERIA_LOG_TOPIC_CREATE: return @"adminlog.topic.create";
    case EXTERIA_LOG_TOPIC_EDIT: return @"adminlog.topic.edit";
    case EXTERIA_LOG_TOPIC_DELETE: return @"adminlog.topic.delete";
    case EXTERIA_LOG_INVITE_REVOKE: return @"adminlog.invite.revoke";
    case EXTERIA_LOG_INVITE_DELETE: return @"adminlog.invite.delete";
    case EXTERIA_LOG_OTHER: break;
    }
    return @"adminlog.other";
}

static NSString *ExteriaLogSentence(ExteriaAdminEvent *event) {
    NSString *format = ExteriaLogText(ExteriaLogKey(event));
    NSString *actor = ExteriaLogActor(event);
    switch (event.kind) {
    case EXTERIA_LOG_SLOW_MODE:
    case EXTERIA_LOG_HISTORY_TTL:
        return [NSString stringWithFormat:format, actor, ExteriaLogDuration(event.number)];
    case EXTERIA_LOG_INVITE: case EXTERIA_LOG_BAN: case EXTERIA_LOG_RESTRICT: case EXTERIA_LOG_UNBAN: case EXTERIA_LOG_PROMOTE:
    case EXTERIA_LOG_ADMIN_RIGHTS: case EXTERIA_LOG_DEMOTE: case EXTERIA_LOG_EDIT_RANK: case EXTERIA_LOG_JOIN_BY_REQUEST:
        return [NSString stringWithFormat:format, actor, ExteriaLogTarget(event)];
    case EXTERIA_LOG_LINKED_CHAT:
        return [NSString stringWithFormat:format, actor, ExteriaLogTarget(event)];
    default:
        return [NSString stringWithFormat:format, actor];
    }
}

/* the words of a message: its text, or a mark for a message that is only media */
static NSString *ExteriaLogBody(NSString *text, BOOL hasMedia) {
    if (text.length) return text;
    return hasMedia ? ExteriaLogText(@"adminlog.media") : @"";
}

static NSString *ExteriaLogDetail(ExteriaAdminEvent *event) {
    NSString *before = event.beforeText, *after = event.afterText;
    switch (event.kind) {
    case EXTERIA_LOG_TITLE: case EXTERIA_LOG_ABOUT: case EXTERIA_LOG_USERNAME: case EXTERIA_LOG_EDIT_RANK: case EXTERIA_LOG_TOPIC_EDIT:
        if (!before.length) return after;
        if (!after.length) return [NSString stringWithFormat:ExteriaLogText(@"adminlog.was"), before];
        return [NSString stringWithFormat:@"%@\n%@", after, [NSString stringWithFormat:ExteriaLogText(@"adminlog.was"), before]];
    case EXTERIA_LOG_EDIT_MESSAGE: {
        NSString *now = ExteriaLogBody(after, event.hasMedia);
        return before.length ? [NSString stringWithFormat:@"%@\n%@", now, [NSString stringWithFormat:ExteriaLogText(@"adminlog.was"), before]] : now;
    }
    case EXTERIA_LOG_DELETE_MESSAGE: return ExteriaLogBody(before, event.hasMedia);
    case EXTERIA_LOG_PIN: case EXTERIA_LOG_UNPIN: case EXTERIA_LOG_SEND_MESSAGE: case EXTERIA_LOG_STOP_POLL:
        return ExteriaLogBody(after, event.hasMedia);
    case EXTERIA_LOG_PROMOTE: return after;
    case EXTERIA_LOG_TOPIC_CREATE: case EXTERIA_LOG_INVITE_REVOKE: case EXTERIA_LOG_INVITE_DELETE: return after;
    case EXTERIA_LOG_TOPIC_DELETE: return before;
    default: return @"";
    }
}

@implementation ExteriaAdminLogRow

@synthesize event = _event;
@synthesize sentence = _sentence;
@synthesize detail = _detail;

- (id)initWithEvent:(ExteriaAdminEvent *)event {
    self = [super init];
    if (!self) return nil;
    _event = [event retain];
    _sentence = [ExteriaLogSentence(event) copy];
    _detail = [ExteriaLogDetail(event) copy];
    return self;
}

- (void)dealloc {
    [_event release];
    [_sentence release];
    [_detail release];
    [super dealloc];
}

@end

@interface ExteriaAdminLogCell : UITableViewCell {
    UILabel *_sentence;
    UILabel *_detail;
    UILabel *_time;
}
+ (UIFont *)sentenceFont;
+ (UIFont *)detailFont;
+ (CGFloat)heightOfRow:(ExteriaAdminLogRow *)row width:(CGFloat)width;
- (void)configureWithRow:(ExteriaAdminLogRow *)row;
@end

@implementation ExteriaAdminLogCell

+ (UIFont *)sentenceFont { return ExteriaFontMedium(15); }
+ (UIFont *)detailFont { return ExteriaFontRegular(14); }

+ (CGFloat)textWidthOfWidth:(CGFloat)width {
    return width - SIDE_MARGIN * 2 - TIME_WIDTH;
}

+ (CGFloat)heightOfRow:(ExteriaAdminLogRow *)row width:(CGFloat)width {
    CGFloat textWidth = [self textWidthOfWidth:width];
    CGFloat height = CELL_PAD + ceil([row.sentence sizeWithFont:[self sentenceFont] constrainedToSize:CGSizeMake(textWidth, 3 * 20) lineBreakMode:UILineBreakModeWordWrap].height);
    if (row.detail.length) {
        height += 3 + ceil([row.detail sizeWithFont:[self detailFont] constrainedToSize:CGSizeMake(textWidth, DETAIL_LINES * 18) lineBreakMode:UILineBreakModeTailTruncation].height);
    }
    return height + CELL_PAD;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [UIColor clearColor];
    _sentence = [[UILabel alloc] init];
    _sentence.backgroundColor = [UIColor clearColor];
    _sentence.font = [ExteriaAdminLogCell sentenceFont];
    _sentence.textColor = ExteriaColorTitle();
    _sentence.numberOfLines = 3;
    [self.contentView addSubview:_sentence];
    _detail = [[UILabel alloc] init];
    _detail.backgroundColor = [UIColor clearColor];
    _detail.font = [ExteriaAdminLogCell detailFont];
    _detail.textColor = ExteriaColorSecondary();
    _detail.numberOfLines = DETAIL_LINES;
    [self.contentView addSubview:_detail];
    _time = [[UILabel alloc] init];
    _time.backgroundColor = [UIColor clearColor];
    _time.font = ExteriaFontRegular(13);
    _time.textColor = ExteriaColorSecondary();
    _time.textAlignment = ExteriaTextAlignmentRight;
    [self.contentView addSubview:_time];
    return self;
}

- (void)dealloc {
    [_sentence release];
    [_detail release];
    [_time release];
    [super dealloc];
}

- (void)configureWithRow:(ExteriaAdminLogRow *)row {
    _sentence.text = row.sentence;
    _detail.text = row.detail;
    _time.text = ExteriaClockText(row.event.date);
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat textWidth = [ExteriaAdminLogCell textWidthOfWidth:width];
    CGSize sentence = [_sentence.text sizeWithFont:_sentence.font constrainedToSize:CGSizeMake(textWidth, 3 * 20) lineBreakMode:UILineBreakModeWordWrap];
    _sentence.frame = CGRectMake(SIDE_MARGIN, CELL_PAD, textWidth, ceil(sentence.height));
    CGFloat bottom = CGRectGetMaxY(_sentence.frame);
    if (_detail.text.length) {
        CGSize detail = [_detail.text sizeWithFont:_detail.font constrainedToSize:CGSizeMake(textWidth, DETAIL_LINES * 18) lineBreakMode:UILineBreakModeTailTruncation];
        _detail.frame = CGRectMake(SIDE_MARGIN, bottom + 3, textWidth, ceil(detail.height));
    } else {
        _detail.frame = CGRectZero;
    }
    _time.frame = CGRectMake(width - SIDE_MARGIN - TIME_WIDTH, CELL_PAD, TIME_WIDTH, 18);
}

@end

@interface ExteriaAdminLogController () {
    ExteriaFullChannel *_channel;
    ExteriaWeakReference *_weak;
    NSMutableArray *_rows;
    NSString *_query;
    BOOL _loading;
    BOOL _done;
    BOOL _failed;
    NSString *_failureName;
    /* an answer to an older query or an older reload is dropped, so rows of a search never land in the plain list */
    NSUInteger _generation;
    UITableView *_table;
    UIView *_searchBar;
    UITextField *_search;
    UIActivityIndicatorView *_spinner;
    UILabel *_status;
}
@end

@implementation ExteriaAdminLogController

- (id)initWithSession:(ExteriaSession *)session channel:(ExteriaFullChannel *)channel avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _channel = [channel retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _rows = [[NSMutableArray alloc] init];
    _query = [@"" copy];
    self.screenTitle = NSLocalizedString(@"adminlog.title", nil);
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_weak clear];
    [_weak release];
    _table.dataSource = nil;
    _table.delegate = nil;
    _search.delegate = nil;
    [_channel release];
    [_rows release];
    [_query release];
    [_failureName release];
    [_table release];
    [_searchBar release];
    [_search release];
    [_spinner release];
    [_status release];
    [super dealloc];
}

#pragma mark view

- (void)buildBodyInView:(UIView *)root {
    _table = [[UITableView alloc] init];
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    [root addSubview:_table];
    _searchBar = [[UIView alloc] init];
    _search = [[ExteriaCenteredHintField alloc] init];
    _search.delegate = self;
    _search.font = ExteriaFontRegular(16);
    _search.textColor = ExteriaColorTitle();
    _search.placeholder = NSLocalizedString(@"adminlog.search", nil);
    _search.clearButtonMode = UITextFieldViewModeWhileEditing;
    _search.returnKeyType = UIReturnKeySearch;
    _search.autocorrectionType = UITextAutocorrectionTypeNo;
    _search.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _search.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _search.keyboardAppearance = ExteriaThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    _search.backgroundColor = ExteriaColorField();
    _search.layer.cornerRadius = 12;
    UIView *pad = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 10)] autorelease];
    _search.leftView = pad;
    _search.leftViewMode = UITextFieldViewModeAlways;
    [_searchBar addSubview:_search];
    _table.tableHeaderView = _searchBar;
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:ExteriaThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [root addSubview:_spinner];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = ExteriaColorSecondary();
    _status.font = ExteriaFontRegular(15);
    _status.textAlignment = ExteriaTextAlignmentCenter;
    _status.numberOfLines = 0;
    [root addSubview:_status];
}

- (void)layoutBody:(CGRect)body {
    _table.frame = body;
    _searchBar.frame = CGRectMake(0, 0, body.size.width, SEARCH_HEIGHT);
    _search.frame = CGRectMake(14, 8, body.size.width - 28, SEARCH_HEIGHT - 16);
    _table.tableHeaderView = _searchBar;
    _spinner.center = CGPointMake(CGRectGetMidX(body), body.origin.y + SEARCH_HEIGHT + 60);
    _status.frame = CGRectMake(body.origin.x + 24, body.origin.y + SEARCH_HEIGHT + 30, body.size.width - 48, 60);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reload];
}

#pragma mark loading

- (void)reload {
    _generation++;
    [_rows removeAllObjects];
    _done = NO;
    _failed = NO;
    _loading = NO;
    [_table reloadData];
    [self loadMore];
}

- (void)updateStatus {
    if (_loading && !_rows.count) {
        [_spinner startAnimating];
        _status.text = @"";
        return;
    }
    [_spinner stopAnimating];
    if (_failed && !_rows.count) _status.text = ExteriaChannelErrorText(_failureName);
    else if (_done && !_rows.count) _status.text = NSLocalizedString(_query.length ? @"adminlog.nothing" : @"adminlog.empty", nil);
    else _status.text = @"";
}

- (void)loadMore {
    if (_loading || _done) return;
    _loading = YES;
    _failed = NO;
    NSUInteger generation = _generation;
    ExteriaWeakReference *weak = _weak;
    ExteriaAdminLogRow *last = [_rows lastObject];
    long long before = last ? last.event.eventId : 0;
    [self updateStatus];
    [self retain];
    [self.session loadAdminLogOfDialog:_channel.dialog query:_query beforeId:before completion:^(NSArray *events, NSString *errorName) {
        [self autorelease];
        ExteriaAdminLogController *me = weak.target;
        if (!me || generation != me->_generation) return;
        me->_loading = NO;
        if (!events) {
            NSLog(@"exteria: the recent actions of channel %lld did not load: %@", me->_channel.dialog.peerId, errorName);
            me->_failed = YES;
            [me->_failureName release];
            me->_failureName = [errorName copy];
            [me updateStatus];
            return;
        }
        for (ExteriaAdminEvent *event in events) [me->_rows addObject:[[[ExteriaAdminLogRow alloc] initWithEvent:event] autorelease]];
        /* a short page is the end; the server keeps the actions of two days only */
        me->_done = events.count < EXTERIA_ADMIN_LOG_PAGE;
        [me->_table reloadData];
        [me updateStatus];
    }];
}

#pragma mark search

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *next = [field.text stringByReplacingCharactersInRange:range withString:string];
    if (next.length > EXTERIA_ADMIN_LOG_QUERY_MAX / 4) return NO;
    [self queryChangedTo:next];
    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)field {
    (void)field;
    [self queryChangedTo:@""];
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

- (void)queryChangedTo:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed isEqualToString:_query]) return;
    [_query release];
    _query = [trimmed copy];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
    [self performSelector:@selector(reload) withObject:nil afterDelay:SEARCH_DELAY];
}

#pragma mark table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_rows.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [ExteriaAdminLogCell heightOfRow:[_rows objectAtIndex:(NSUInteger)indexPath.row] width:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUInteger index = (NSUInteger)indexPath.row;
    if (index + 4 >= _rows.count) [self loadMore];
    static NSString *identifier = @"event";
    ExteriaAdminLogCell *cell = (ExteriaAdminLogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaAdminLogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    [cell configureWithRow:[_rows objectAtIndex:index]];
    return cell;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    (void)scrollView;
    [_search resignFirstResponder];
}

@end
