#import "exteria_message_stats_controller.h"

#import "exteria_avatar_cache.h"
#import "exteria_avatar_view.h"
#import "exteria_chart_view.h"
#import "exteria_emoji_label.h"
#import "exteria_message.h"
#import "exteria_person.h"
#import "exteria_session_stats.h"
#import "exteria_theme.h"
#import "exteria_time.h"
#import "exteria_weak_reference.h"

/* the public forwards past this many are not listed, as the reactors of a post are not */
#define FORWARDS_MAX 300
/* a post with this few points in its graph is a young one: its daily graph is nearly empty, and the server offers the hourly one around its last day */
#define ZOOM_POINTS_MAX 5

@interface ExteriaStatsForwardRowView : UIView {
    ExteriaAvatarView *_avatar;
    ExteriaEmojiLabel *_name;
    ExteriaEmojiLabel *_line;
    ExteriaPerson *_person;
    ExteriaAvatarCache *_cache;
}
- (id)initWithPerson:(ExteriaPerson *)person key:(long long)key name:(NSString *)name line:(NSString *)line cache:(ExteriaAvatarCache *)cache;
@end

@implementation ExteriaStatsForwardRowView

- (id)initWithPerson:(ExteriaPerson *)person key:(long long)key name:(NSString *)name line:(NSString *)line cache:(ExteriaAvatarCache *)cache {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _person = [person retain];
    _cache = [cache retain];
    _avatar = [[ExteriaAvatarView alloc] init];
    _avatar.circular = YES;
    _avatar.seed = (NSUInteger)((key < 0 ? -key : key) % 1000003);
    _avatar.initials = person ? person.initials : ExteriaInitialsOfName(name);
    [self addSubview:_avatar];
    _name = [[ExteriaEmojiLabel alloc] init];
    _name.font = ExteriaFontSemibold(16);
    _name.textColor = ExteriaColorTitle();
    _name.dropsUndrawable = YES;
    _name.text = name;
    [self addSubview:_name];
    _line = [[ExteriaEmojiLabel alloc] init];
    _line.font = ExteriaFontRegular(14);
    _line.textColor = ExteriaColorSecondary();
    _line.text = line;
    [self addSubview:_line];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", name, line];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [_avatar setPhoto:_person.photo cache:_cache];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _avatar.frame = CGRectMake(12, 10, 44, 44);
    _name.frame = CGRectMake(68, 8, MAX(0, self.bounds.size.width - 80), 24);
    _line.frame = CGRectMake(68, 32, MAX(0, self.bounds.size.width - 80), 22);
}

- (void)dealloc {
    [_avatar release];
    [_name release];
    [_line release];
    [_person release];
    [_cache release];
    [super dealloc];
}

@end

@interface ExteriaMessageStatsController () {
    ExteriaSession *_session;
    ExteriaDialog *_dialog;
    ExteriaAvatarCache *_avatars;
    int32_t _messageId;
    int32_t _messageViews;
    int32_t _messageForwards;
    int32_t _messageReactions;
    ExteriaWeakReference *_weak;

    ExteriaStatsGraph *_viewsGraph;
    ExteriaStatsGraph *_reactionsGraph;
    int32_t _dc;
    BOOL _graphsLoading;
    BOOL _graphsStarted;
    NSString *_graphsError;
    /* the chart views live on between rebuilds, which a page of public forwards causes, so a series the person switched off stays off */
    NSMutableDictionary *_chartViews;

    NSMutableArray *_forwards;
    NSMutableDictionary *_people;
    NSMutableSet *_offsets;
    NSString *_next;
    NSString *_forwardsError;
    int32_t _forwardsTotal;
    BOOL _forwardsLoading;
    BOOL _forwardsStarted;
    BOOL _forwardsLimited;
}
@end

@implementation ExteriaMessageStatsController

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog message:(ExteriaMessage *)message avatars:(ExteriaAvatarCache *)avatars {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _dialog = [dialog retain];
    _avatars = [avatars retain];
    _messageId = message.messageId;
    _messageViews = message.views;
    _messageForwards = message.forwards;
    for (ExteriaReaction *reaction in message.reactions) {
        if (reaction.row.kind != EXTERIA_REACTION_PAID) _messageReactions += reaction.row.count;
    }
    _forwards = [[NSMutableArray alloc] init];
    _people = [[NSMutableDictionary alloc] init];
    _offsets = [[NSMutableSet alloc] init];
    _chartViews = [[NSMutableDictionary alloc] init];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"stats.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_dialog release];
    [_avatars release];
    [_viewsGraph release];
    [_reactionsGraph release];
    [_graphsError release];
    [_forwards release];
    [_people release];
    [_offsets release];
    [_chartViews release];
    [_next release];
    [_forwardsError release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self loadGraphs];
}

- (void)themeDidChange { [self rebuild]; }

#pragma mark graphs

- (void)loadGraphs {
    if (_graphsLoading) return;
    _graphsLoading = YES;
    [_graphsError release];
    _graphsError = nil;
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    [_session loadStatsOfMessageId:_messageId ofDialog:_dialog completion:^(ExteriaStatsGraph *views, ExteriaStatsGraph *reactions, int32_t dc, NSString *errorName) {
        ExteriaMessageStatsController *page = weak.target;
        if (!page) return;
        page->_graphsLoading = NO;
        page->_graphsStarted = YES;
        if (errorName) {
            page->_graphsError = [errorName copy];
        } else {
            page->_dc = dc;
            page->_viewsGraph = [views retain];
            page->_reactionsGraph = [reactions retain];
            [page completeGraphs];
            [page loadForwards];
        }
        [page rebuild];
    }];
}

/* a graph that came as a token is asked for, and a young post gets the hourly graph in place of an almost empty daily one */
- (void)completeGraphs {
    ExteriaWeakReference *weak = _weak;
    ExteriaStatsGraph *views = _viewsGraph, *reactions = _reactionsGraph;
    if (views.kind == EXTERIA_GRAPH_ASYNC) {
        [_session loadGraphWithToken:views.token x:0 hasX:NO dc:_dc completion:^(ExteriaStatsGraph *graph, NSString *errorName) {
            ExteriaMessageStatsController *page = weak.target;
            if (!page || page->_viewsGraph != views) return;
            if (graph) {
                [page->_viewsGraph release];
                page->_viewsGraph = [graph retain];
                [page zoomViewsGraph];
            } else {
                NSLog(@"exteria: the views graph did not load: %@", errorName);
            }
            [page rebuild];
        }];
    } else {
        [self zoomViewsGraph];
    }
    if (reactions.kind == EXTERIA_GRAPH_ASYNC) {
        [_session loadGraphWithToken:reactions.token x:0 hasX:NO dc:_dc completion:^(ExteriaStatsGraph *graph, NSString *errorName) {
            ExteriaMessageStatsController *page = weak.target;
            if (!page || page->_reactionsGraph != reactions) return;
            if (graph) {
                [page->_reactionsGraph release];
                page->_reactionsGraph = [graph retain];
            } else {
                NSLog(@"exteria: the reactions graph did not load: %@", errorName);
            }
            [page rebuild];
        }];
    }
}

- (void)zoomViewsGraph {
    ExteriaStatsGraph *views = _viewsGraph;
    const exteria_chart *chart = views.chartData.chart;
    if (views.kind != EXTERIA_GRAPH_JSON || !chart || chart->points > ZOOM_POINTS_MAX || !views.zoomToken.length) return;
    ExteriaWeakReference *weak = _weak;
    [_session loadGraphWithToken:views.zoomToken x:chart->x[chart->points - 1] hasX:YES dc:_dc completion:^(ExteriaStatsGraph *graph, NSString *errorName) {
        ExteriaMessageStatsController *page = weak.target;
        if (!page || page->_viewsGraph != views) return;
        /* the daily graph stays when the hourly one is not there, which is the case for a post of the last hours */
        if (graph && graph.kind == EXTERIA_GRAPH_JSON) {
            [page->_viewsGraph release];
            page->_viewsGraph = [graph retain];
            [page rebuild];
        } else if (errorName) {
            NSLog(@"exteria: the hourly views graph did not load: %@", errorName);
        }
    }];
}

#pragma mark public forwards

- (void)loadForwards {
    if (_forwardsLoading || (_forwardsStarted && !_next && !_forwardsError) || _forwards.count >= FORWARDS_MAX) return;
    NSString *cursor = [[_next copy] autorelease];
    _forwardsLoading = YES;
    [_forwardsError release];
    _forwardsError = nil;
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    [_session loadPublicForwardsOfMessageId:_messageId ofDialog:_dialog dc:_dc offset:cursor completion:^(NSArray *items, NSDictionary *people, NSString *next, int32_t total, NSString *errorName) {
        ExteriaMessageStatsController *page = weak.target;
        if (!page) return;
        page->_forwardsLoading = NO;
        page->_forwardsStarted = YES;
        if (errorName) {
            page->_forwardsError = [[NSString stringWithFormat:NSLocalizedString(@"stats.error", nil), errorName] copy];
        } else if (next && ([page->_offsets containsObject:next] || (cursor && [next isEqualToString:cursor]))) {
            page->_forwardsError = [NSLocalizedString(@"stats.badpage", nil) copy];
        } else {
            if (cursor) [page->_offsets addObject:cursor];
            [page->_people addEntriesFromDictionary:people];
            NSUInteger room = FORWARDS_MAX - page->_forwards.count;
            NSUInteger take = MIN(room, items.count);
            if (take) [page->_forwards addObjectsFromArray:[items subarrayWithRange:NSMakeRange(0, take)]];
            page->_forwardsTotal = total;
            page->_forwardsLimited = take < items.count || (next && page->_forwards.count >= FORWARDS_MAX);
            [page->_next release];
            page->_next = [next copy];
        }
        [page rebuild];
    }];
}

#pragma mark rows

static NSString *ExteriaStatsCount(int64_t value) {
    return [NSString stringWithFormat:@"%lld", (long long)value];
}

- (ExteriaSettingsRow *)chartRowForGraph:(ExteriaStatsGraph *)graph title:(NSString *)title {
    ExteriaChartView *chart = [_chartViews objectForKey:title];
    if (!chart || chart.data != graph.chartData) {
        chart = [[[ExteriaChartView alloc] initWithFrame:CGRectZero] autorelease];
        chart.title = title;
        chart.data = graph.chartData;
        [_chartViews setObject:chart forKey:title];
    }
    return [ExteriaSettingsRow viewRowWithView:chart height:^CGFloat(CGFloat width) { return [chart heightForWidth:width]; }];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];

    NSMutableArray *overview = [NSMutableArray array];
    [overview addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"stats.views", nil) value:ExteriaStatsCount(_messageViews) tap:nil]];
    if (_messageReactions > 0) [overview addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"stats.reactions", nil) value:ExteriaStatsCount(_messageReactions) tap:nil]];
    if (_messageForwards > 0) {
        [overview addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"stats.shares", nil) value:ExteriaStatsCount(_messageForwards) tap:nil]];
        if (_forwardsStarted && !_forwardsError) {
            int32_t publicShares = MIN(_forwardsTotal, _messageForwards);
            [overview addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"stats.shares.public", nil) value:ExteriaStatsCount(publicShares) tap:nil]];
            [overview addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"stats.shares.private", nil) value:ExteriaStatsCount(_messageForwards - publicShares) tap:nil]];
        }
    }
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:overview]];

    NSMutableArray *charts = [NSMutableArray array];
    if (_graphsLoading) {
        [charts addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"stats.loading", nil) value:nil tap:nil]];
    } else if (_graphsError) {
        NSString *text;
        if ([_graphsError isEqualToString:@"CHAT_ADMIN_REQUIRED"]) text = NSLocalizedString(@"stats.denied", nil);
        else if ([_graphsError hasPrefix:@"FLOOD_WAIT_"] || [_graphsError hasPrefix:@"FLOOD_PREMIUM_WAIT_"])
            text = [NSString stringWithFormat:NSLocalizedString(@"stats.wait", nil), [[_graphsError substringFromIndex:[_graphsError rangeOfString:@"_" options:NSBackwardsSearch].location + 1] intValue]];
        else text = [NSString stringWithFormat:NSLocalizedString(@"stats.error", nil), _graphsError];
        [charts addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"stats.retry", nil) subtitle:text value:nil tap:^{
            [(ExteriaMessageStatsController *)weak.target loadGraphs];
        }]];
    } else {
        struct { ExteriaStatsGraph *graph; NSString *title; } entries[2] = {
            {_viewsGraph, NSLocalizedString(@"stats.chart.views", nil)},
            {_reactionsGraph, NSLocalizedString(@"stats.chart.reactions", nil)}
        };
        for (int i = 0; i < 2; ++i) {
            ExteriaStatsGraph *graph = entries[i].graph;
            if (graph.kind == EXTERIA_GRAPH_JSON) {
                [charts addObject:[self chartRowForGraph:graph title:entries[i].title]];
            } else if (graph.kind == EXTERIA_GRAPH_ASYNC) {
                [charts addObject:[ExteriaSettingsRow rowWithTitle:entries[i].title subtitle:NSLocalizedString(@"stats.loading", nil) value:nil tap:nil]];
            } else if (graph.kind == EXTERIA_GRAPH_ERROR) {
                /* the server says why, usually that the post is too young or too few people reacted */
                [charts addObject:[ExteriaSettingsRow rowWithTitle:entries[i].title subtitle:graph.errorText value:nil tap:nil]];
            }
        }
    }
    if (charts.count) [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:charts]];

    if (_forwardsStarted || _forwardsLoading || _forwardsError) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *entry in _forwards) {
            NSNumber *key = [entry objectForKey:@"peer"];
            ExteriaPerson *person = [_people objectForKey:key];
            NSString *name = person.name.length ? person.name : [NSString stringWithFormat:@"ID %@", key];
            int32_t views = [[entry objectForKey:@"views"] intValue];
            int32_t date = [[entry objectForKey:@"date"] intValue];
            BOOL story = [[entry objectForKey:@"story"] boolValue];
            NSMutableArray *parts = [NSMutableArray array];
            if (story) [parts addObject:NSLocalizedString(@"stats.forwards.story", nil)];
            if (views > 0) [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"stats.forwards.views", nil), (int)views]];
            if (date > 0) [parts addObject:ExteriaMediaTimeText(date)];
            ExteriaStatsForwardRowView *view = [[[ExteriaStatsForwardRowView alloc] initWithPerson:person key:key.longLongValue name:name
                                                                                              line:[parts componentsJoinedByString:@" · "] cache:_avatars] autorelease];
            [rows addObject:[ExteriaSettingsRow viewRowWithView:view height:^CGFloat(CGFloat width) { (void)width; return 64; }]];
        }
        if (_forwardsLoading) {
            [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"stats.loading", nil) value:nil tap:nil]];
        } else if (_forwardsError) {
            [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"stats.retry", nil) subtitle:_forwardsError value:nil tap:^{
                [(ExteriaMessageStatsController *)weak.target loadForwards];
            }]];
        } else if (_next && _forwards.count < FORWARDS_MAX) {
            [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"group.tab.more", nil) value:nil tap:^{
                [(ExteriaMessageStatsController *)weak.target loadForwards];
            }]];
        } else if (!_forwards.count) {
            [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"stats.forwards.empty", nil) value:nil tap:nil]];
        }
        NSString *footer = _forwardsLimited ? NSLocalizedString(@"stats.forwards.limit", nil) : nil;
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"stats.forwards.header", nil) footer:footer rows:rows]];
    }
    self.sections = sections;
    [self reloadSettings];
}

@end
