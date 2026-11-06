#import "exteria_date_time_picker.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_theme.h"

@implementation ExteriaDateTimePicker {
    UIView *_card;
    UIDatePicker *_picker;
    void (^_done)(NSDate *date);
    void (^_cancelled)(void);
}

- (id)initWithFrame:(CGRect)frame mode:(UIDatePickerMode)mode initialDate:(NSDate *)initialDate minimumDate:(NSDate *)minimumDate
               done:(void (^)(NSDate *date))done cancelled:(void (^)(void))cancelled {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _done = [done copy];
    _cancelled = [cancelled copy];
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.cornerRadius = 14;
    _card.layer.masksToBounds = YES;
    [self addSubview:_card];
    _picker = [[UIDatePicker alloc] init];
    _picker.datePickerMode = mode;
    if (initialDate) _picker.date = initialDate;
    if (minimumDate) {
        _picker.minimumDate = minimumDate;
        if ([_picker.date compare:minimumDate] == NSOrderedAscending) _picker.date = minimumDate;
    }
    [_card addSubview:_picker];
    NSString *titles[2] = {NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"tr.ok", nil)};
    for (int i = 0; i < 2; ++i) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = i;
        [button setTitle:titles[i] forState:UIControlStateNormal];
        [button setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
        button.titleLabel.font = i ? ExteriaFontSemibold(17) : ExteriaFontRegular(17);
        [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:button];
    }
    return self;
}

- (void)dealloc {
    [_card release];
    [_picker release];
    [_done release];
    [_cancelled release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MIN(self.bounds.size.width - 20, 360), pickerHeight = 216, bar = 50;
    CGFloat height = bar + pickerHeight;
    _card.frame = CGRectMake(floor((self.bounds.size.width - width) / 2), floor((self.bounds.size.height - height) / 2), width, height);
    _picker.frame = CGRectMake(0, bar, width, pickerHeight);
    for (UIView *view in _card.subviews) {
        if (![view isKindOfClass:[UIButton class]]) continue;
        view.frame = CGRectMake(view.tag ? width - 110 : 0, 0, 110, bar);
    }
}

- (void)tapped:(UIButton *)button {
    NSDate *date = button.tag ? _picker.date : nil;
    void (^done)(NSDate *) = [_done retain];
    void (^cancelled)(void) = [_cancelled retain];
    [self removeFromSuperview];
    if (date) { if (done) done(date); }
    else if (cancelled) cancelled();
    [done release];
    [cancelled release];
}

@end
