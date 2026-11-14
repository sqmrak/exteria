#import "exteria_chart_view.h"

#import "exteria_theme.h"

#define PLOT_HEIGHT 190.0
#define TITLE_HEIGHT 30.0
#define AXIS_HEIGHT 22.0
#define LEFT_MARGIN 38.0
#define RIGHT_MARGIN 12.0
#define CHIP_HEIGHT 28.0
#define CHIP_GAP 8.0
#define GRID_LINES 4

@implementation ExteriaChartView

@synthesize data = _data;
@synthesize title = _title;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.contentMode = UIViewContentModeRedraw;
    _selected = -1;
    return self;
}

- (void)dealloc {
    [_data release];
    [_title release];
    [super dealloc];
}

- (void)setData:(ExteriaChartData *)data {
    if (data == _data) return;
    [_data release];
    _data = [data retain];
    memset(_hidden, 0, sizeof(_hidden));
    _selected = -1;
    [self setNeedsDisplay];
}

+ (NSString *)shortNumber:(int64_t)value {
    double v = (double)value;
    if (value < 0) return [NSString stringWithFormat:@"-%@", [self shortNumber:-value]];
    if (value >= 1000000000LL) return [NSString stringWithFormat:@"%.1fB", v / 1e9];
    if (value >= 1000000) return [NSString stringWithFormat:@"%.1fM", v / 1e6];
    if (value >= 10000) return [NSString stringWithFormat:@"%.0fK", v / 1e3];
    if (value >= 1000) return [NSString stringWithFormat:@"%.1fK", v / 1e3];
    return [NSString stringWithFormat:@"%lld", (long long)value];
}

static UIColor *ExteriaChartColor(uint32_t rgb, CGFloat alpha) {
    return [UIColor colorWithRed:(CGFloat)((rgb >> 16) & 0xff) / 255 green:(CGFloat)((rgb >> 8) & 0xff) / 255 blue:(CGFloat)(rgb & 0xff) / 255 alpha:alpha];
}

/* the legend wraps: every chip is as wide as its name, and a chip that does not fit starts the next row */
- (CGFloat)layoutLegendInWidth:(CGFloat)width {
    const exteria_chart *chart = _data.chart;
    CGFloat x = 12, y = 0;
    if (!chart) return 0;
    for (uint32_t i = 0; i < chart->line_count; ++i) {
        NSString *name = [NSString stringWithUTF8String:chart->lines[i].name];
        CGFloat w = MIN(width - 24, [name sizeWithFont:ExteriaFontMedium(13)].width + 38);
        if (x + w > width - 12 && x > 12) {
            x = 12;
            y += CHIP_HEIGHT + CHIP_GAP;
        }
        _chips[i] = CGRectMake(x, y, w, CHIP_HEIGHT);
        x += w + CHIP_GAP;
    }
    return chart->line_count ? y + CHIP_HEIGHT + CHIP_GAP : 0;
}

- (CGFloat)heightForWidth:(CGFloat)width {
    if (!_data.chart) return TITLE_HEIGHT + 60;
    return TITLE_HEIGHT + PLOT_HEIGHT + AXIS_HEIGHT + 8 + [self layoutLegendInWidth:width] + 6;
}

/* the value that tops the plot and a step between the lines that is 1, 2 or 5 times a power of ten */
static void ExteriaChartScale(int64_t maximum, int64_t *top, int64_t *step) {
    int64_t unit = 1;
    int64_t raw = maximum < GRID_LINES ? GRID_LINES : maximum;
    while (raw / unit >= 10 * GRID_LINES) unit *= 10;
    int64_t base = (raw + GRID_LINES - 1) / GRID_LINES;
    int64_t s = unit;
    int64_t multiples[3] = {1, 2, 5};
    for (int round = 0; round < 8; ++round) {
        BOOL found = NO;
        for (int i = 0; i < 3; ++i) {
            if (multiples[i] * s >= base) { s = multiples[i] * s; found = YES; break; }
        }
        if (found) break;
        s *= 10;
    }
    *step = s;
    *top = s * GRID_LINES;
}

- (NSDateFormatter *)formatterForSpan:(int64_t)span {
    static NSDateFormatter *hours = nil, *days = nil;
    if (!hours) {
        hours = [[NSDateFormatter alloc] init];
        [hours setDateFormat:@"HH:mm"];
        days = [[NSDateFormatter alloc] init];
        [days setDateFormat:@"d MMM"];
    }
    return span > 0 && span < 3 * 24 * 3600 * 1000LL ? hours : days;
}

- (NSString *)dateTextAt:(NSUInteger)index fullDate:(BOOL)full {
    const exteria_chart *chart = _data.chart;
    int64_t span = chart->points > 1 ? chart->x[chart->points - 1] - chart->x[0] : 0;
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)chart->x[index] / 1000.0];
    NSString *text = [[self formatterForSpan:span] stringFromDate:date];
    if (full && span > 0 && span < 3 * 24 * 3600 * 1000LL) {
        static NSDateFormatter *day = nil;
        if (!day) {
            day = [[NSDateFormatter alloc] init];
            [day setDateFormat:@"d MMM"];
        }
        return [NSString stringWithFormat:@"%@ %@", [day stringFromDate:date], text];
    }
    if (full) {
        static NSDateFormatter *year = nil;
        if (!year) {
            year = [[NSDateFormatter alloc] init];
            [year setDateFormat:@"d MMM yyyy"];
        }
        return [year stringFromDate:date];
    }
    return text;
}

- (BOOL)hasVisibleLine {
    const exteria_chart *chart = _data.chart;
    for (uint32_t i = 0; chart && i < chart->line_count; ++i) if (!_hidden[i]) return YES;
    return NO;
}

/* the height each series reaches at a point: its own value, or the sum of the visible series below it when the chart is stacked */
- (int64_t)topOfLine:(uint32_t)line at:(NSUInteger)index {
    const exteria_chart *chart = _data.chart;
    int64_t total = 0;
    if (chart->percentage) {
        int64_t whole = 0;
        for (uint32_t i = 0; i < chart->line_count; ++i) if (!_hidden[i]) whole += chart->lines[i].y[index];
        if (whole <= 0) return 0;
        for (uint32_t i = 0; i <= line; ++i) if (!_hidden[i]) total += chart->lines[i].y[index];
        return total * 100 / whole;
    }
    if (!chart->stacked) return chart->lines[line].y[index];
    for (uint32_t i = 0; i <= line; ++i) if (!_hidden[i]) total += chart->lines[i].y[index];
    return total;
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    const exteria_chart *chart = _data.chart;
    CGContextRef g = UIGraphicsGetCurrentContext();
    CGFloat width = self.bounds.size.width;
    if (_title.length) {
        [ExteriaColorTitle() set];
        [_title drawAtPoint:CGPointMake(12, 6) withFont:ExteriaFontSemibold(16)];
    }
    if (!chart || !chart->points) return;
    CGRect plot = CGRectMake(LEFT_MARGIN, TITLE_HEIGHT + 6, MAX(10, width - LEFT_MARGIN - RIGHT_MARGIN), PLOT_HEIGHT - 6);
    int64_t maximum = 0;
    for (uint32_t l = 0; l < chart->line_count; ++l) {
        if (_hidden[l]) continue;
        for (uint32_t i = 0; i < chart->points; ++i) {
            int64_t v = [self topOfLine:l at:i];
            if (v > maximum) maximum = v;
        }
    }
    int64_t top, step;
    ExteriaChartScale(maximum, &top, &step);
    UIFont *small = ExteriaFontRegular(11);
    CGContextSetLineWidth(g, 0.5);
    for (int i = 0; i <= GRID_LINES; ++i) {
        CGFloat y = floor(CGRectGetMaxY(plot) - plot.size.height * i / GRID_LINES) + 0.25;
        [ExteriaColorHairline() setStroke];
        CGContextMoveToPoint(g, plot.origin.x, y);
        CGContextAddLineToPoint(g, CGRectGetMaxX(plot), y);
        CGContextStrokePath(g);
        [ExteriaColorSecondary() set];
        NSString *label = [ExteriaChartView shortNumber:step * i];
        CGSize size = [label sizeWithFont:small];
        [label drawAtPoint:CGPointMake(plot.origin.x - size.width - 5, y - size.height / 2) withFont:small];
    }
    /* x positions: bars sit in the middle of their slot, lines and areas run from edge to edge */
    BOOL hasBars = NO;
    for (uint32_t l = 0; l < chart->line_count; ++l) hasBars = hasBars || chart->lines[l].kind == EXTERIA_CHART_BAR;
    CGFloat slot = plot.size.width / (CGFloat)chart->points;
    CGFloat (^xAt)(NSUInteger) = ^CGFloat(NSUInteger i) {
        if (hasBars) return plot.origin.x + slot * ((CGFloat)i + 0.5);
        return chart->points > 1 ? plot.origin.x + plot.size.width * (CGFloat)i / (CGFloat)(chart->points - 1) : CGRectGetMidX(plot);
    };
    CGFloat (^yAt)(int64_t) = ^CGFloat(int64_t v) {
        return CGRectGetMaxY(plot) - plot.size.height * (CGFloat)v / (CGFloat)top;
    };
    CGContextSaveGState(g);
    CGContextClipToRect(g, CGRectInset(plot, -2, -2));
    for (int pass = 0; pass < 2; ++pass) {
        /* areas and bars first, lines over them */
        for (uint32_t l = chart->line_count; l-- > 0;) {
            const exteria_chart_line *line = &chart->lines[l];
            BOOL solid = line->kind == EXTERIA_CHART_BAR || line->kind == EXTERIA_CHART_AREA;
            if (_hidden[l] || solid != (pass == 0)) continue;
            UIColor *color = ExteriaChartColor(line->color, 1);
            if (line->kind == EXTERIA_CHART_BAR) {
                [color setFill];
                for (uint32_t i = 0; i < chart->points; ++i) {
                    int64_t upper = [self topOfLine:l at:i], lower = upper - (chart->stacked || chart->percentage ? [self ownValueOfLine:l at:i upper:upper] : upper);
                    if (lower < 0) lower = 0;
                    CGFloat x = xAt(i) - slot * 0.4;
                    CGContextFillRect(g, CGRectMake(x, yAt(upper), MAX(1, slot * 0.8), MAX(0, yAt(lower) - yAt(upper))));
                }
            } else if (line->kind == EXTERIA_CHART_AREA) {
                [ExteriaChartColor(line->color, 0.55) setFill];
                CGContextBeginPath(g);
                for (uint32_t i = 0; i < chart->points; ++i) {
                    CGFloat y = yAt([self topOfLine:l at:i]);
                    if (i == 0) CGContextMoveToPoint(g, xAt(0), y);
                    else CGContextAddLineToPoint(g, xAt(i), y);
                }
                for (uint32_t i = chart->points; i-- > 0;) {
                    int64_t lowerTop = 0;
                    for (uint32_t k = l; k-- > 0;) if (!_hidden[k]) { lowerTop = [self topOfLine:k at:i]; break; }
                    if (!(chart->stacked || chart->percentage)) lowerTop = 0;
                    CGContextAddLineToPoint(g, xAt(i), yAt(lowerTop));
                }
                CGContextClosePath(g);
                CGContextFillPath(g);
            } else {
                [color setStroke];
                CGContextSetLineWidth(g, 2);
                CGContextSetLineJoin(g, kCGLineJoinRound);
                CGContextBeginPath(g);
                for (uint32_t i = 0; i < chart->points; ++i) {
                    CGFloat x = xAt(i), y = yAt([self topOfLine:l at:i]);
                    if (i == 0) CGContextMoveToPoint(g, x, y);
                    else if (line->kind == EXTERIA_CHART_STEP) {
                        CGContextAddLineToPoint(g, x, yAt([self topOfLine:l at:i - 1]));
                        CGContextAddLineToPoint(g, x, y);
                    } else CGContextAddLineToPoint(g, x, y);
                }
                CGContextStrokePath(g);
            }
        }
    }
    CGContextRestoreGState(g);
    /* the time axis: at most five labels, spread over the points */
    NSUInteger labels = MIN((NSUInteger)5, (NSUInteger)chart->points);
    [ExteriaColorSecondary() set];
    for (NSUInteger k = 0; k < labels; ++k) {
        NSUInteger index = labels > 1 ? (NSUInteger)((double)k * (double)(chart->points - 1) / (double)(labels - 1) + 0.5) : 0;
        NSString *text = [self dateTextAt:index fullDate:NO];
        CGSize size = [text sizeWithFont:small];
        CGFloat x = MIN(MAX(xAt(index) - size.width / 2, 2), width - size.width - 2);
        [text drawAtPoint:CGPointMake(x, CGRectGetMaxY(plot) + 5) withFont:small];
    }
    if (_selected >= 0 && (NSUInteger)_selected < chart->points) [self drawMarkerAt:(NSUInteger)_selected plot:plot x:xAt((NSUInteger)_selected) yAt:yAt context:g];
    [self drawLegendOriginY:CGRectGetMaxY(plot) + AXIS_HEIGHT + 4 context:g];
}

/* what a stacked series adds on its own at a point, which is the gap between its top and the top of the visible series below it */
- (int64_t)ownValueOfLine:(uint32_t)line at:(NSUInteger)index upper:(int64_t)upper {
    for (uint32_t k = line; k-- > 0;) if (!_hidden[k]) return upper - [self topOfLine:k at:index];
    return upper;
}

- (void)drawMarkerAt:(NSUInteger)index plot:(CGRect)plot x:(CGFloat)x yAt:(CGFloat (^)(int64_t))yAt context:(CGContextRef)g {
    const exteria_chart *chart = _data.chart;
    CGContextSetLineWidth(g, 1);
    [ExteriaColorSecondary() setStroke];
    CGContextMoveToPoint(g, x, plot.origin.y);
    CGContextAddLineToPoint(g, x, CGRectGetMaxY(plot));
    CGContextStrokePath(g);
    NSMutableArray *rows = [NSMutableArray array];
    for (uint32_t l = 0; l < chart->line_count; ++l) {
        if (_hidden[l]) continue;
        if (chart->lines[l].kind != EXTERIA_CHART_BAR) {
            [ExteriaColorScreen() setFill];
            [ExteriaChartColor(chart->lines[l].color, 1) setStroke];
            CGContextSetLineWidth(g, 2);
            CGRect dot = CGRectMake(x - 3.5, yAt([self topOfLine:l at:index]) - 3.5, 7, 7);
            CGContextFillEllipseInRect(g, dot);
            CGContextStrokeEllipseInRect(g, dot);
        }
        [rows addObject:[NSArray arrayWithObjects:[NSString stringWithUTF8String:chart->lines[l].name],
                         [NSString stringWithFormat:@"%lld", (long long)chart->lines[l].y[index]], [NSNumber numberWithUnsignedInt:chart->lines[l].color], nil]];
    }
    NSString *heading = [self dateTextAt:index fullDate:YES];
    UIFont *font = ExteriaFontMedium(12), *bold = ExteriaFontSemibold(12);
    CGFloat inner = [heading sizeWithFont:bold].width;
    for (NSArray *row in rows) {
        CGFloat w = [[row objectAtIndex:0] sizeWithFont:font].width + 14 + [[row objectAtIndex:1] sizeWithFont:bold].width;
        if (w > inner) inner = w;
    }
    CGFloat boxW = inner + 20, boxH = 10 + 18 + (CGFloat)rows.count * 17;
    CGFloat boxX = x + 12;
    if (boxX + boxW > self.bounds.size.width - 4) boxX = x - 12 - boxW;
    boxX = MAX(4, boxX);
    CGRect box = CGRectMake(boxX, plot.origin.y + 4, boxW, boxH);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:8];
    [ExteriaColorCard() setFill];
    [path fill];
    [ExteriaColorHairline() setStroke];
    path.lineWidth = 0.5;
    [path stroke];
    [ExteriaColorTitle() set];
    [heading drawAtPoint:CGPointMake(box.origin.x + 10, box.origin.y + 6) withFont:bold];
    CGFloat y = box.origin.y + 6 + 18;
    for (NSArray *row in rows) {
        [ExteriaChartColor([[row objectAtIndex:2] unsignedIntValue], 1) set];
        NSString *name = [row objectAtIndex:0], *value = [row objectAtIndex:1];
        [name drawAtPoint:CGPointMake(box.origin.x + 10, y) withFont:font];
        [value drawAtPoint:CGPointMake(CGRectGetMaxX(box) - 10 - [value sizeWithFont:bold].width, y) withFont:bold];
        y += 17;
    }
}

- (void)drawLegendOriginY:(CGFloat)originY context:(CGContextRef)g {
    const exteria_chart *chart = _data.chart;
    [self layoutLegendInWidth:self.bounds.size.width];
    UIFont *font = ExteriaFontMedium(13);
    for (uint32_t i = 0; i < chart->line_count; ++i) {
        CGRect chip = CGRectOffset(_chips[i], 0, originY);
        UIColor *color = ExteriaChartColor(chart->lines[i].color, 1);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:chip cornerRadius:CHIP_HEIGHT / 2];
        if (_hidden[i]) {
            [ExteriaColorHairline() setStroke];
            path.lineWidth = 1;
            [path stroke];
            [ExteriaColorSecondary() set];
        } else {
            [color setFill];
            [path fill];
            [[UIColor whiteColor] set];
            CGContextSetLineWidth(g, 2);
            CGContextMoveToPoint(g, chip.origin.x + 10, chip.origin.y + 14.5);
            CGContextAddLineToPoint(g, chip.origin.x + 13.5, chip.origin.y + 18);
            CGContextAddLineToPoint(g, chip.origin.x + 19, chip.origin.y + 10);
            CGContextStrokePath(g);
        }
        NSString *name = [NSString stringWithUTF8String:chart->lines[i].name];
        [name drawInRect:CGRectMake(chip.origin.x + 26, chip.origin.y + 6, chip.size.width - 32, 18) withFont:font lineBreakMode:NSLineBreakByTruncatingTail];
    }
}

- (void)selectAtPoint:(CGPoint)point {
    const exteria_chart *chart = _data.chart;
    if (!chart || !chart->points) return;
    CGFloat width = self.bounds.size.width;
    CGFloat plotW = MAX(10, width - LEFT_MARGIN - RIGHT_MARGIN);
    CGFloat fraction = (point.x - LEFT_MARGIN) / plotW;
    NSInteger index = (NSInteger)floor(fraction * (CGFloat)chart->points);
    BOOL hasBars = NO;
    for (uint32_t l = 0; l < chart->line_count; ++l) hasBars = hasBars || chart->lines[l].kind == EXTERIA_CHART_BAR;
    if (!hasBars) index = chart->points > 1 ? (NSInteger)floor(fraction * (CGFloat)(chart->points - 1) + 0.5) : 0;
    index = MAX(0, MIN((NSInteger)chart->points - 1, index));
    if (index != _selected) {
        _selected = index;
        [self setNeedsDisplay];
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    (void)event;
    const exteria_chart *chart = _data.chart;
    CGPoint point = [[touches anyObject] locationInView:self];
    if (!chart) return;
    CGFloat legendTop = TITLE_HEIGHT + PLOT_HEIGHT + AXIS_HEIGHT + 4;
    if (point.y >= legendTop) {
        for (uint32_t i = 0; i < chart->line_count; ++i) {
            if (!CGRectContainsPoint(CGRectOffset(_chips[i], 0, legendTop), point)) continue;
            /* the last series on screen stays, or the chart would be empty with nothing to switch back on */
            if (!_hidden[i]) {
                NSUInteger shown = 0;
                for (uint32_t k = 0; k < chart->line_count; ++k) if (!_hidden[k]) ++shown;
                if (shown <= 1) return;
            }
            _hidden[i] = !_hidden[i];
            [self setNeedsDisplay];
            return;
        }
        return;
    }
    if (point.y >= TITLE_HEIGHT) [self selectAtPoint:point];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    (void)event;
    CGPoint point = [[touches anyObject] locationInView:self];
    if (point.y < TITLE_HEIGHT + PLOT_HEIGHT + AXIS_HEIGHT) [self selectAtPoint:point];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self setNeedsDisplay];
}

@end
