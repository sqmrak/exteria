#import <UIKit/UIKit.h>

#import "exteria_session_stats.h"

/* the charts of the statistics of a post: lines, areas, steps and bars over a time axis, with a legend that switches series
   off and a marker that follows the finger and names the values at that time. It is drawn with Core Graphics, so it runs on iOS 5 */
@interface ExteriaChartView : UIView {
    ExteriaChartData *_data;
    NSString *_title;
    BOOL _hidden[EXTERIA_CHART_LINES_MAX];
    NSInteger _selected;
    CGRect _chips[EXTERIA_CHART_LINES_MAX];
    CGFloat _legendHeight;
}

@property (nonatomic, retain) ExteriaChartData *data;
@property (nonatomic, copy) NSString *title;

/* the height the chart needs at a width: plot, axis and the rows of the legend */
- (CGFloat)heightForWidth:(CGFloat)width;
/* a number as a short text: 1.2K, 3.4M */
+ (NSString *)shortNumber:(int64_t)value;
@end
