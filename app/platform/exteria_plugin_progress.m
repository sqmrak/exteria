#import "exteria_plugin_progress.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#import "exteria_platform.h"
#import "exteria_plugins.h"
#import "exteria_theme.h"

#define PANEL_WIDTH 280.0
#define TEXT_MAX 2048
#define BUTTONS_MAX 3

@interface ExteriaProgressPanel : UIView {
    NSNumber *_token;
    UILabel *_title;
    UILabel *_message;
    UIProgressView *_bar;
    UIView *_card;
    NSMutableArray *_buttons;
}
- (id)initWithToken:(NSNumber *)token title:(NSString *)title message:(NSString *)message percent:(int)percent buttons:(NSArray *)buttons;
- (void)setMessage:(NSString *)message percent:(int)percent;
- (NSNumber *)token;
@end

static NSMutableDictionary *g_panels;

@implementation ExteriaProgressPanel

- (id)initWithToken:(NSNumber *)token title:(NSString *)title message:(NSString *)message percent:(int)percent buttons:(NSArray *)buttons {
    self = [super initWithFrame:[[UIScreen mainScreen] bounds]];
    if (!self) return nil;
    _token = [token retain];
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.cornerRadius = 14;
    [self addSubview:_card];
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.textColor = ExteriaColorTitle();
    _title.font = ExteriaFontRegular(17);
    _title.numberOfLines = 2;
    _title.textAlignment = ExteriaTextAlignmentCenter;
    _title.text = title;
    [_card addSubview:_title];
    _message = [[UILabel alloc] init];
    _message.backgroundColor = [UIColor clearColor];
    _message.textColor = ExteriaColorMessage();
    _message.font = ExteriaFontRegular(14);
    _message.numberOfLines = 0;
    _message.textAlignment = ExteriaTextAlignmentCenter;
    _message.text = message;
    [_card addSubview:_message];
    _bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _bar.progress = (float)percent / 100.0f;
    [_card addSubview:_bar];
    _buttons = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < buttons.count && i < BUTTONS_MAX; ++i) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = (NSInteger)i;
        [button setTitle:[buttons objectAtIndex:i] forState:UIControlStateNormal];
        [button setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
        button.titleLabel.font = ExteriaFontRegular(17);
        [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:button];
        [_buttons addObject:button];
    }
    return self;
}

- (void)dealloc {
    [_token release];
    [_title release];
    [_message release];
    [_bar release];
    [_card release];
    [_buttons release];
    [super dealloc];
}

- (NSNumber *)token {
    return _token;
}

- (void)setMessage:(NSString *)message percent:(int)percent {
    _message.text = message;
    _bar.progress = (float)percent / 100.0f;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat inner = PANEL_WIDTH - 32;
    CGFloat y = 18;
    CGSize title = [_title sizeThatFits:CGSizeMake(inner, 60)];
    _title.frame = CGRectMake(16, y, inner, title.height);
    y += title.height + 8;
    CGSize message = [_message sizeThatFits:CGSizeMake(inner, 400)];
    _message.frame = CGRectMake(16, y, inner, message.height);
    y += message.height + 14;
    _bar.frame = CGRectMake(16, y, inner, 9);
    y += 9 + 16;
    CGFloat rowHeight = 44;
    NSUInteger count = _buttons.count;
    for (NSUInteger i = 0; i < count; ++i) {
        CGFloat each = PANEL_WIDTH / (CGFloat)count;
        [[_buttons objectAtIndex:i] setFrame:CGRectMake(each * (CGFloat)i, y, each, rowHeight)];
    }
    if (count) y += rowHeight;
    CGSize bounds = self.bounds.size;
    _card.frame = CGRectMake(floor((bounds.width - PANEL_WIDTH) / 2), floor((bounds.height - y) / 2), PANEL_WIDTH, y);
}

- (void)tapped:(UIButton *)button {
    NSNumber *token = [[_token retain] autorelease];
    NSInteger index = button.tag;
    [g_panels removeObjectForKey:token];
    [self removeFromSuperview];
    ExteriaPluginsCallHost(@"alert_result", [NSArray arrayWithObjects:token, [NSNumber numberWithInteger:index], @"", nil]);
}

@end

void ExteriaPluginProgressReset(void) {
    for (ExteriaProgressPanel *panel in [g_panels allValues]) [panel removeFromSuperview];
    [g_panels removeAllObjects];
}

static NSString *text_of(id value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [value length] > TEXT_MAX ? [value substringToIndex:TEXT_MAX] : value;
}

static int percent_of(id value) {
    int percent = [value isKindOfClass:[NSNumber class]] ? [value intValue] : 0;
    return percent < 0 ? 0 : (percent > 100 ? 100 : percent);
}

exteria_status ExteriaPluginProgressService(NSString *name, NSDictionary *request, NSDictionary **reply, NSString **failure) {
    NSNumber *token = [request objectForKey:@"token"];
    if (![token isKindOfClass:[NSNumber class]]) {
        if (failure) *failure = @"no token";
        return EXTERIA_E_ARG;
    }
    if (!g_panels) g_panels = [[NSMutableDictionary alloc] init];
    ExteriaProgressPanel *panel = [g_panels objectForKey:token];
    *reply = [NSDictionary dictionary];
    if ([name isEqualToString:@"progress.show"]) {
        NSArray *buttons = [request objectForKey:@"buttons"];
        if (panel) return EXTERIA_OK;
        if (![buttons isKindOfClass:[NSArray class]]) buttons = [NSArray array];
        UIWindow *window = [[UIApplication sharedApplication] keyWindow];
        if (!window) {
            if (failure) *failure = @"no window to show the panel in";
            return EXTERIA_E_STATE;
        }
        for (id caption in buttons) if (![caption isKindOfClass:[NSString class]]) { if (failure) *failure = @"a button needs a caption"; return EXTERIA_E_ARG; }
        panel = [[[ExteriaProgressPanel alloc] initWithToken:token title:text_of([request objectForKey:@"title"]) message:text_of([request objectForKey:@"message"])
                                                     percent:percent_of([request objectForKey:@"percent"]) buttons:buttons] autorelease];
        [g_panels setObject:panel forKey:token];
        [window addSubview:panel];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"progress.update"]) {
        [panel setMessage:text_of([request objectForKey:@"message"]) percent:percent_of([request objectForKey:@"percent"])];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"progress.close"]) {
        [panel removeFromSuperview];
        [g_panels removeObjectForKey:token];
        return EXTERIA_OK;
    }
    return EXTERIA_E_UNSUPPORTED;
}
