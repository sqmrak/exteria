#import "exteria_developers.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_emoji_label.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_dialog.h"
#import "exteria_person.h"
#import "exteria_session_bots.h"
#import "exteria_session_profile.h"
#import "exteria_custom_emoji.h"

/* the class methods stand in for a target the plate's gestures and its timer can reach without holding anything */
@interface ExteriaDeveloperPlateTarget : NSObject
+ (void)hide;
+ (void)tapped:(UITapGestureRecognizer *)tap;
@end

NSString *const ExteriaOpenTeamPersonNotification = @"ExteriaOpenTeamPerson";

void ExteriaLoadTeamPerson(ExteriaSession *session, long long userId, void (^completion)(ExteriaPerson *, NSString *)) {
    NSString *hint = ExteriaTeamUsername(userId);
    if (!session || !hint || !completion) {
        if (completion) completion(nil, @"USER_ID_INVALID");
        return;
    }
    [session loadStoredPersonOfUserId:userId completion:^(ExteriaPerson *held) {
        ExteriaDialog *dialog = held ? [ExteriaDialog dialogWithPerson:held] : nil;
        if (dialog) {
            [session loadFullUserOfDialog:dialog completion:^(ExteriaFullUser *full, NSString *error) {
                if (full.person && full.person.userId == userId) completion(full.person, nil);
                else {
                    NSLog(@"exteria: team user %lld could not be refreshed: %@", userId, error ? error : @"unexpected user");
                    completion(held, nil);
                }
            }];
        } else {
            [session resolveUsername:hint completion:^(ExteriaDialog *resolved, ExteriaPerson *person, NSString *error) {
                (void)resolved;
                if (person.userId == userId) completion(person, nil);
                else completion(nil, error ? error : @"USER_ID_INVALID");
            }];
        }
    }];
}

BOOL ExteriaIsDeveloperId(long long userId) { return exteria_team_is_developer(userId) != 0; }
NSUInteger ExteriaMarksOfId(long long userId) { return exteria_team_marks(userId); }
NSString *ExteriaTeamUsername(long long userId) {
    const exteria_team_member *member = exteria_team_member_for_id(userId);
    return member ? [NSString stringWithUTF8String:member->username] : nil;
}
NSArray *ExteriaOfficialTesterIds(void) {
    NSMutableArray *ids = [NSMutableArray array];
    for (size_t i = 0; i < exteria_team_member_count(); ++i) {
        const exteria_team_member *member = exteria_team_member_at(i);
        if (member->official_list) [ids addObject:[NSNumber numberWithLongLong:member->id]];
    }
    return ids;
}
NSUInteger ExteriaDialogIsDeveloper(ExteriaDialog *dialog) {
    return dialog && dialog.peerKind == 1 && !dialog.saved ? ExteriaMarksOfId(dialog.peerId) : 0;
}
NSUInteger ExteriaPersonIsDeveloper(ExteriaPerson *person) {
    return person ? ExteriaMarksOfId(person.userId) : 0;
}

NSUInteger ExteriaMarkForDocument(long long document) {
    if (document == EXTERIA_MANAGER_DOCUMENT) return ExteriaMarkManager;
    if (document == EXTERIA_PROMOTION_DOCUMENT) return ExteriaMarkPromotion;
    if (document == EXTERIA_BUG_HUNTER_DOCUMENT) return ExteriaMarkBugHunter;
    if (document == EXTERIA_DEVELOPER_DOCUMENT) return ExteriaMarkDeveloper;
    if (document == EXTERIA_LEAD_DOCUMENT) return ExteriaMarkLead;
    if (document == EXTERIA_SENKO_DOCUMENT) return ExteriaMarkSenko;
    if (document == EXTERIA_TESTER_DOCUMENT) return ExteriaMarkTester;
    if (document == EXTERIA_OFFICIAL_TESTER_DOCUMENT) return ExteriaMarkOfficialTester;
    if (document == EXTERIA_CAUTION_DOCUMENT) return ExteriaMarkCaution;
    return 0;
}

/* the plate is a view of the app, not a system alert: the name on it is drawn by the label that knows odd nicks and emoji, and it comes up at once */
#define PLATE_SECONDS 3.2
#define PLATE_SIDE 52.0

static UIView *ExteriaPlate;

static void ExteriaHidePlate(UIView *plate) {
    if (ExteriaPlate != plate) return;
    ExteriaPlate = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:[ExteriaDeveloperPlateTarget class]];
    [UIView animateWithDuration:0.18 animations:^{
        plate.alpha = 0;
        plate.transform = CGAffineTransformMakeScale(0.94, 0.94);
    } completion:^(BOOL finished) {
        (void)finished;
        [plate removeFromSuperview];
        [plate release];
    }];
}

@implementation ExteriaDeveloperPlateTarget
+ (void)hide { if (ExteriaPlate) ExteriaHidePlate(ExteriaPlate); }
+ (void)tapped:(UITapGestureRecognizer *)tap { if (tap.view == ExteriaPlate) ExteriaHidePlate(ExteriaPlate); }
@end

void ExteriaShowMarkNotice(NSString *name, NSUInteger mark) {
    UIView *window = ExteriaOverlayHost();
    if (!window) return;
    if (ExteriaPlate) {
        UIView *old = ExteriaPlate;
        ExteriaPlate = nil;
        [old removeFromSuperview];
        [old release];
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:[ExteriaDeveloperPlateTarget class]];
    CGFloat width = MIN(window.bounds.size.width - 32, 360);
    CGFloat textX = 16 + PLATE_SIDE + 12;
    CGFloat textWidth = MAX(1, width - textX - 16);
    UIView *plate = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 84)];
    plate.backgroundColor = ExteriaColorCard();
    plate.layer.cornerRadius = 20;
    plate.layer.shadowColor = [UIColor blackColor].CGColor;
    plate.layer.shadowOpacity = 0.28f;
    plate.layer.shadowRadius = 14;
    plate.layer.shadowOffset = CGSizeMake(0, 4);
    UIImage *badge = mark == ExteriaMarkManager ? [ExteriaCustomEmoji imageForDocument:EXTERIA_MANAGER_DOCUMENT] : mark == ExteriaMarkOfficialTester ? [ExteriaCustomEmoji imageForDocument:EXTERIA_OFFICIAL_TESTER_DOCUMENT] : mark == ExteriaMarkBugHunter ? [ExteriaCustomEmoji imageForDocument:EXTERIA_BUG_HUNTER_DOCUMENT] : mark == ExteriaMarkPromotion ? [ExteriaCustomEmoji imageForDocument:EXTERIA_PROMOTION_DOCUMENT] : mark == ExteriaMarkCaution ? [ExteriaCustomEmoji imageForDocument:EXTERIA_CAUTION_DOCUMENT] :
        [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:mark == ExteriaMarkTester ? @"badge_tester" : (mark == ExteriaMarkSenko ? @"badge_senko" : (mark == ExteriaMarkLead ? @"badge_lead" : @"badge_developer")) ofType:@"png"]];
    UIImageView *hammer = [[[UIImageView alloc] initWithImage:badge] autorelease];
    hammer.contentMode = UIViewContentModeScaleAspectFit;
    [plate addSubview:hammer];
    ExteriaEmojiLabel *who = [[[ExteriaEmojiLabel alloc] init] autorelease];
    who.font = ExteriaFontSemibold(17);
    who.textColor = ExteriaColorTitle();
    who.dropsUndrawable = YES;
    who.text = mark == ExteriaMarkBugHunter ? NSLocalizedString(@"developer.bug_hunter.title", nil) : (name.length ? name : NSLocalizedString(@"developer.someone", nil));
    who.frame = CGRectMake(textX, 17, textWidth, 22);
    [plate addSubview:who];
    UILabel *what = [[[UILabel alloc] init] autorelease];
    what.backgroundColor = [UIColor clearColor];
    what.font = ExteriaFontRegular(14);
    what.textColor = ExteriaColorSecondary();
    what.numberOfLines = 0;
    what.lineBreakMode = UILineBreakModeWordWrap;
    what.text = NSLocalizedString(mark == ExteriaMarkManager ? @"developer.manager" : mark == ExteriaMarkOfficialTester ? @"developer.official_tester" : mark == ExteriaMarkBugHunter ? @"developer.bug_hunter.notice" : (mark == ExteriaMarkPromotion ? @"developer.promotion" : (mark == ExteriaMarkCaution ? @"developer.caution" : (mark == ExteriaMarkTester ? @"developer.tester" : (mark == ExteriaMarkSenko ? @"developer.senko" : (mark == ExteriaMarkLead ? @"developer.lead" : @"developer.notice"))))), nil);
    CGFloat textHeight = MAX(34, ceil([what sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height));
    CGFloat height = MAX(84, 41 + textHeight + 9);
    what.frame = CGRectMake(textX, 41, textWidth, textHeight);
    [plate addSubview:what];
    plate.bounds = CGRectMake(0, 0, width, height);
    hammer.frame = CGRectMake(16, (height - PLATE_SIDE) / 2, PLATE_SIDE, PLATE_SIDE);
    CGFloat top = ExteriaStatusBarHeight() + 10;
    plate.center = CGPointMake(CGRectGetMidX(window.bounds), top + height / 2);
    plate.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [plate addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:[ExteriaDeveloperPlateTarget class] action:@selector(tapped:)] autorelease]];
    [window addSubview:plate];
    ExteriaPlate = plate;
    plate.alpha = 0;
    plate.transform = CGAffineTransformMakeTranslation(0, -24);
    [UIView animateWithDuration:0.24 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        plate.alpha = 1;
        plate.transform = CGAffineTransformIdentity;
    } completion:nil];
    [[ExteriaDeveloperPlateTarget class] performSelector:@selector(hide) withObject:nil afterDelay:PLATE_SECONDS];
}
