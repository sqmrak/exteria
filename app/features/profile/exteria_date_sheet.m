#import "exteria_date_sheet.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_platform.h"
#import "exteria_theme.h"

#define PANEL_HEIGHT 330.0

@interface ExteriaDateSheet () {
    UIView *_dim;
    UIView *_panel;
    UIDatePicker *_picker;
    UISwitch *_hideYear;
    UILabel *_hideLabel;
    UIButton *_cancel;
    UIButton *_remove;
    UIButton *_done;
    BOOL _canRemove;
    void (^_doneHandler)(int32_t, int32_t, int32_t);
    void (^_removeHandler)(void);
}
@end

@implementation ExteriaDateSheet

@synthesize doneHandler = _doneHandler;
@synthesize removeHandler = _removeHandler;
@synthesize canRemove = _canRemove;

static UIButton *ExteriaSheetButton(NSString *title, UIColor *color, BOOL bold) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:color forState:UIControlStateNormal];
    button.titleLabel.font = bold ? ExteriaFontSemibold(17) : ExteriaFontRegular(17);
    return button;
}

- (id)initWithDay:(int32_t)day month:(int32_t)month year:(int32_t)year {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dim = [[UIView alloc] init];
    _dim.backgroundColor = [UIColor blackColor];
    _dim.alpha = 0;
    [self addSubview:_dim];
    [_dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelTapped)] autorelease]];
    _panel = [[UIView alloc] init];
    _panel.backgroundColor = ExteriaColorCard();
    [self addSubview:_panel];
    _picker = [[UIDatePicker alloc] init];
    _picker.datePickerMode = UIDatePickerModeDate;
    _picker.maximumDate = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *parts = [[[NSDateComponents alloc] init] autorelease];
    parts.day = day > 0 ? day : 1;
    parts.month = month > 0 ? month : 1;
    parts.year = year > 0 ? year : 2000;
    NSDate *start = [calendar dateFromComponents:parts];
    if (start) _picker.date = start;
    [_panel addSubview:_picker];
    _hideLabel = [[UILabel alloc] init];
    _hideLabel.backgroundColor = [UIColor clearColor];
    _hideLabel.font = ExteriaFontRegular(16);
    _hideLabel.textColor = ExteriaColorTitle();
    _hideLabel.text = NSLocalizedString(@"profile.birthday.noyear", nil);
    [_panel addSubview:_hideLabel];
    _hideYear = [[UISwitch alloc] init];
    _hideYear.on = year == 0;
    [_panel addSubview:_hideYear];
    _cancel = [ExteriaSheetButton(NSLocalizedString(@"picker.cancel", nil), ExteriaColorAccent(), NO) retain];
    [_cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:_cancel];
    _remove = [ExteriaSheetButton(NSLocalizedString(@"profile.birthday.remove", nil), ExteriaColorBadgeRed(), NO) retain];
    [_remove addTarget:self action:@selector(removeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:_remove];
    _done = [ExteriaSheetButton(NSLocalizedString(@"profile.edit.save", nil), ExteriaColorAccent(), YES) retain];
    [_done addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:_done];
    return self;
}

- (void)dealloc {
    [_dim release];
    [_panel release];
    [_picker release];
    [_hideYear release];
    [_hideLabel release];
    [_cancel release];
    [_remove release];
    [_done release];
    [_doneHandler release];
    [_removeHandler release];
    [super dealloc];
}

- (void)setCanRemove:(BOOL)canRemove {
    _canRemove = canRemove;
    _remove.hidden = !canRemove;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    UIEdgeInsets safe = ExteriaSafeInsets(self);
    /* the panel stands in a column of a page on a tablet and clear of the notch in landscape, and runs under the home indicator with its controls above it */
    CGRect column = ExteriaContentColumn(size, safe, EXTERIA_COLUMN_PAGE);
    CGFloat width = column.size.width;
    _dim.frame = self.bounds;
    CGFloat height = PANEL_HEIGHT + safe.bottom;
    /* frame changes under a transform shift the panel while ios 6 lays out the closing sheet */
    _panel.bounds = CGRectMake(0, 0, width, height);
    _panel.center = CGPointMake(column.origin.x + width / 2, size.height - height / 2);
    _cancel.frame = CGRectMake(8, 6, 90, 44);
    _remove.frame = CGRectMake((width - 110) / 2, 6, 110, 44);
    _remove.hidden = !_canRemove;
    _done.frame = CGRectMake(width - 98, 6, 90, 44);
    _picker.frame = CGRectMake(0, 54, width, 216);
    _hideLabel.frame = CGRectMake(16, 276, width - 100, 44);
    _hideYear.center = CGPointMake(width - 16 - _hideYear.bounds.size.width / 2, 298);
}

- (void)showInView:(UIView *)host {
    self.frame = host.bounds;
    [host addSubview:self];
    [self layoutIfNeeded];
    _panel.transform = CGAffineTransformMakeTranslation(0, _panel.bounds.size.height);
    [UIView animateWithDuration:0.24 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _dim.alpha = 0.4;
        _panel.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)leaveThen:(void (^)(void))after {
    void (^next)(void) = [after copy];
    self.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        _dim.alpha = 0;
        _panel.transform = CGAffineTransformMakeTranslation(0, _panel.bounds.size.height);
    } completion:^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        if (next) next();
        [next release];
    }];
}

- (void)cancelTapped {
    [self leaveThen:nil];
}

- (void)removeTapped {
    void (^handler)(void) = [_removeHandler retain];
    [self leaveThen:^{ if (handler) handler(); [handler release]; }];
}

- (void)doneTapped {
    NSDateComponents *parts = [[NSCalendar currentCalendar] components:NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit fromDate:_picker.date];
    int32_t day = (int32_t)parts.day, month = (int32_t)parts.month, year = _hideYear.on ? 0 : (int32_t)parts.year;
    void (^handler)(int32_t, int32_t, int32_t) = [_doneHandler retain];
    [self leaveThen:^{ if (handler) handler(day, month, year); [handler release]; }];
}

@end
