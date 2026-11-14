#import <Foundation/Foundation.h>

#import "exteria_dialog.h"
#import "exteria_session.h"

#include "exteria_stats.h"

/* a chart the server drew, owned by the object; its numbers are read on the main thread only */
@interface ExteriaChartData : NSObject {
    exteria_chart *_chart;
}
/* takes the chart over: it is freed with the object */
- (id)initWithChart:(exteria_chart *)chart;
@property (nonatomic, readonly) const exteria_chart *chart;
@end

@interface ExteriaStatsGraph : NSObject {
    exteria_graph_kind _kind;
    ExteriaChartData *_chartData;
    NSString *_token;
    NSString *_zoomToken;
    NSString *_errorText;
}
/* takes the chart out of the graph; the graph struct is empty afterwards */
- (id)initWithGraph:(exteria_stats_graph *)graph;
@property (nonatomic, readonly) exteria_graph_kind kind;
@property (nonatomic, readonly, retain) ExteriaChartData *chartData;
/* async: loads the graph itself; json: loads the finer step of the same range, when the server offers one */
@property (nonatomic, readonly, copy) NSString *token;
@property (nonatomic, readonly, copy) NSString *zoomToken;
@property (nonatomic, readonly, copy) NSString *errorText;
@end

/* the statistics of one post of a channel the account is an admin of; they live on a data center of their own, which every call after the
   first one is told to use. every completion runs on the main thread, with an error name when the server or the link refused */
@interface ExteriaSession (Stats)

- (void)loadStatsOfMessageId:(int32_t)messageId ofDialog:(ExteriaDialog *)dialog
                  completion:(void (^)(ExteriaStatsGraph *views, ExteriaStatsGraph *reactions, int32_t dc, NSString *errorName))completion;
/* a graph that came as a token, or the finer step of a graph around x (unix milliseconds) when hasX is set */
- (void)loadGraphWithToken:(NSString *)token x:(int64_t)x hasX:(BOOL)hasX dc:(int32_t)dc
                completion:(void (^)(ExteriaStatsGraph *graph, NSString *errorName))completion;
/* one page of the public channels and stories that forwarded the post: dictionaries with peer (the signed id of the channel), item (the
   message or story id), date, views and story; people names the channels; next is nil at the end */
- (void)loadPublicForwardsOfMessageId:(int32_t)messageId ofDialog:(ExteriaDialog *)dialog dc:(int32_t)dc offset:(NSString *)offset
                           completion:(void (^)(NSArray *items, NSDictionary *people, NSString *next, int32_t total, NSString *errorName))completion;

@end
