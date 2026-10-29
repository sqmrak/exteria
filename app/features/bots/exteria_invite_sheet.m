#import "exteria_invite_sheet.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_avatar_view.h"
#import "exteria_dismiss_pan.h"
#import "exteria_media_cache.h"
#import "exteria_person.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

@interface ExteriaInviteSheet () {
    UIView *_shade;
    UIView *_card;
    UIScrollView *_content;
    ExteriaAvatarView *_avatar;
    UILabel *_title;
    UILabel *_subtitle;
    UILabel *_about;
    UILabel *_request;
    UIButton *_join;
    UIButton *_close;
    void (^_joinHandler)(void);
    ExteriaWeakReference *_weak;
    BOOL _closing;
}
@end

@implementation ExteriaInviteSheet

static UILabel *InviteLabel(UIFont *font, UIColor *color) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    label.textAlignment = ExteriaTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}

+ (void)showInView:(UIView *)host title:(NSString *)title subtitle:(NSString *)subtitle about:(NSString *)about
             photo:(ExteriaRemoteFile *)photo media:(ExteriaMediaCache *)media requestNeeded:(BOOL)requestNeeded join:(void (^)(void))join {
    if (!host) { NSLog(@"exteria: no host for invite sheet"); return; }
    ExteriaInviteSheet *sheet = [[[ExteriaInviteSheet alloc] initWithFrame:host.bounds] autorelease];
    sheet.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sheet->_joinHandler = [join copy];
    sheet->_weak = [[ExteriaWeakReference referenceTo:sheet] retain];
    sheet->_shade = [[UIView alloc] initWithFrame:sheet.bounds];
    sheet->_shade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sheet->_shade.backgroundColor = [UIColor blackColor];
    sheet->_shade.alpha = 0;
    [sheet->_shade addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:sheet action:@selector(cancel)] autorelease]];
    [sheet addSubview:sheet->_shade];
    sheet->_card = [[UIView alloc] init];
    sheet->_card.backgroundColor = ExteriaColorCard();
    sheet->_card.layer.cornerRadius = 22;
    sheet->_card.clipsToBounds = YES;
    [sheet addSubview:sheet->_card];
    ExteriaAddDismissPan(sheet->_card, sheet, @selector(cancel));
    sheet->_content = [[UIScrollView alloc] init];
    sheet->_content.showsVerticalScrollIndicator = NO;
    [sheet->_card addSubview:sheet->_content];
    sheet->_avatar = [[ExteriaAvatarView alloc] init];
    sheet->_avatar.circular = YES;
    sheet->_avatar.initials = ExteriaInitialsOfName(title);
    sheet->_avatar.seed = (NSUInteger)[title hash];
    [sheet->_content addSubview:sheet->_avatar];
    sheet->_title = [InviteLabel(ExteriaFontBold(20), ExteriaColorTitle()) retain];
    sheet->_title.text = title;
    [sheet->_content addSubview:sheet->_title];
    sheet->_subtitle = [InviteLabel(ExteriaFontRegular(13), ExteriaColorSecondary()) retain];
    sheet->_subtitle.text = subtitle;
    [sheet->_content addSubview:sheet->_subtitle];
    sheet->_about = [InviteLabel(ExteriaFontRegular(15), ExteriaColorTitle()) retain];
    sheet->_about.text = about;
    [sheet->_content addSubview:sheet->_about];
    sheet->_request = [InviteLabel(ExteriaFontRegular(13), ExteriaColorSecondary()) retain];
    sheet->_request.text = requestNeeded ? NSLocalizedString(@"invite.request", nil) : nil;
    [sheet->_content addSubview:sheet->_request];
    sheet->_join = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    sheet->_join.backgroundColor = ExteriaColorAccent();
    sheet->_join.layer.cornerRadius = 23;
    sheet->_join.titleLabel.font = ExteriaFontSemibold(16);
    [sheet->_join setTitle:NSLocalizedString(requestNeeded ? @"invite.send" : @"invite.join", nil) forState:UIControlStateNormal];
    [sheet->_join setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [sheet->_join addTarget:sheet action:@selector(joinTapped) forControlEvents:UIControlEventTouchUpInside];
    [sheet->_card addSubview:sheet->_join];
    sheet->_close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    sheet->_close.titleLabel.font = ExteriaFontRegular(27);
    [sheet->_close setTitle:@"×" forState:UIControlStateNormal];
    sheet->_close.accessibilityLabel = NSLocalizedString(@"picker.cancel", nil);
    [sheet->_close setTitleColor:ExteriaColorSecondary() forState:UIControlStateNormal];
    [sheet->_close addTarget:sheet action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [sheet->_card addSubview:sheet->_close];
    [host addSubview:sheet];
    [sheet setNeedsLayout];
    [sheet layoutIfNeeded];
    if (photo && media) {
        ExteriaWeakReference *weak = sheet->_weak;
        [media loadImageForFile:photo maxSide:180 * ExteriaScreenScale() completion:^(UIImage *image) {
            ExteriaInviteSheet *owner = weak.target;
            if (owner && image) [owner->_avatar showImage:image];
        }];
    }
    sheet->_card.transform = CGAffineTransformMakeTranslation(0, sheet->_card.bounds.size.height + 30);
    ExteriaAnimateView(sheet->_shade, CGAffineTransformIdentity, 0.45, EXTERIA_MOTION_ENTER, nil);
    ExteriaAnimateView(sheet->_card, CGAffineTransformIdentity, 1, EXTERIA_MOTION_ENTER, nil);
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_shade release]; [_card release]; [_content release]; [_avatar release];
    [_title release]; [_subtitle release]; [_about release]; [_request release];
    [_join release]; [_close release]; [_joinHandler release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MAX(1, MIN(420, self.bounds.size.width - 20));
    CGFloat inner = MAX(1, width - 48);
    CGFloat y = 24;
    _avatar.frame = CGRectMake(floor((width - 90) / 2), y, 90, 90);
    y += 102;
    UILabel *labels[] = {_title, _subtitle, _about, _request};
    for (NSUInteger i = 0; i < 4; ++i) {
        UILabel *label = labels[i];
        if (!label.text.length) { label.frame = CGRectZero; continue; }
        CGFloat height = ceil([label sizeThatFits:CGSizeMake(inner, 2000)].height);
        label.frame = CGRectMake(24, y, inner, height);
        y += height + (i == 0 ? 4 : 12);
    }
    CGFloat safeBottom = ExteriaSafeInsets(self).bottom;
    CGFloat maxHeight = MAX(100, self.bounds.size.height - ExteriaStatusBarHeight() - 12 - safeBottom);
    CGFloat height = MIN(y + 70, maxHeight);
    _card.frame = CGRectMake(floor((self.bounds.size.width - width) / 2), self.bounds.size.height - safeBottom - height, width, height);
    _content.frame = CGRectMake(0, 0, width, MAX(0, height - 70));
    _content.contentSize = CGSizeMake(width, y);
    _content.scrollEnabled = y > _content.bounds.size.height;
    _join.frame = CGRectMake(20, height - 58, MAX(1, width - 40), 46);
    _close.frame = CGRectMake(width - 48, 4, 44, 44);
}

- (void)leaveJoining:(BOOL)joining {
    if (_closing) return;
    _closing = YES;
    self.userInteractionEnabled = NO;
    void (^handler)(void) = joining ? [_joinHandler copy] : nil;
    [self retain];
    ExteriaAnimateView(_shade, CGAffineTransformIdentity, 0, EXTERIA_MOTION_EXIT, nil);
    ExteriaAnimateView(_card, CGAffineTransformMakeTranslation(0, _card.bounds.size.height + 30), 1, EXTERIA_MOTION_EXIT, ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        if (handler) handler();
        [handler release];
        [self release];
    });
}
- (void)cancel { [self leaveJoining:NO]; }
- (void)joinTapped { [self leaveJoining:YES]; }
@end
