#import "exteria_developers.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_emoji_label.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_dialog.h"
#import "exteria_person.h"
#import "exteria_session_bots.h"
#import "exteria_custom_emoji.h"

/* the class methods stand in for a target the plate's gestures and its timer can reach without holding anything */
@interface ExteriaDeveloperPlateTarget : NSObject
+ (void)hide;
+ (void)tapped:(UITapGestureRecognizer *)tap;
@end

NSString *const ExteriaDevelopersDidChangeNotification = @"ExteriaDevelopersDidChange";

/* the usernames of the credits in About; a rename there is a rename here */
static NSString *const ExteriaDeveloperNames[] = {
    @"sqmrak", @"QWERTYU1OPZ", @"LimeDev", @"menstry", @"anazerka", @"loveiOS6", @"nestorvashenko", @"svcayon4ik", @"illyagif"
};
#define DEVELOPER_COUNT (sizeof(ExteriaDeveloperNames) / sizeof(ExteriaDeveloperNames[0]))
/* the people who tested Exteria wear the net */
static NSString *const ExteriaTesterNames[] = {@"s3dativee", @"inraxx", @"Vladus324", @"shizotoaster", @"fly1ngangel", @"not_a_modder",
                                                    @"vladosik228", @"xaxaxaxaxxaxaxaxaxaxaxaxaxaxa", @"Lineysom", @"KirillPro671488", @"kfrom7", @"Maks_097", @"QuaIcomm"};
#define TESTER_COUNT (sizeof(ExteriaTesterNames) / sizeof(ExteriaTesterNames[0]))
static NSString *const ExteriaCautionName = @"cmp_73";
#define LOOKUP_COUNT (DEVELOPER_COUNT + TESTER_COUNT + 1)

static NSString *const ExteriaDeveloperIdsKey = @"exteria.developers.ids";
static NSString *const ExteriaDeveloperCheckedKey = @"exteria.developers.checked";
#define RECHECK_SECONDS (7.0 * 24 * 3600)

/* main thread only: user ids by lowercase username */
static NSMutableDictionary *ExteriaDeveloperIds(void) {
    static NSMutableDictionary *ids;
    if (!ids) {
        NSDictionary *stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:ExteriaDeveloperIdsKey];
        ids = [[NSMutableDictionary alloc] initWithDictionary:stored];
    }
    return ids;
}

/* the person whose Senko this is and who leads Exteria: the one name that wears the fox tail and the crossed hammers */
static NSString *const ExteriaSenkoDeveloper = @"sqmrak";

static BOOL ExteriaNameIn(NSString *username, NSString *const *names, NSUInteger count) {
    if (!username.length) return NO;
    for (NSUInteger i = 0; i < count; ++i) {
        if ([names[i] caseInsensitiveCompare:username] == NSOrderedSame) return YES;
    }
    return NO;
}

static BOOL ExteriaIdIn(long long userId, NSString *const *names, NSUInteger count) {
    if (userId <= 0) return NO;
    NSDictionary *ids = ExteriaDeveloperIds();
    for (NSUInteger i = 0; i < count; ++i) {
        if ([[ids objectForKey:names[i].lowercaseString] longLongValue] == userId) return YES;
    }
    return NO;
}

BOOL ExteriaIsDeveloperUsername(NSString *username) {
    return ExteriaNameIn(username, ExteriaDeveloperNames, DEVELOPER_COUNT);
}

BOOL ExteriaIsDeveloperId(long long userId) {
    return ExteriaIdIn(userId, ExteriaDeveloperNames, DEVELOPER_COUNT);
}

static NSUInteger ExteriaMarksOfUsername(NSString *username) {
    NSUInteger marks = 0;
    if (ExteriaIsDeveloperUsername(username)) marks |= ExteriaMarkDeveloper;
    if ([ExteriaSenkoDeveloper caseInsensitiveCompare:username ? username : @""] == NSOrderedSame) marks = (marks & ~(NSUInteger)ExteriaMarkDeveloper) | ExteriaMarkSenko | ExteriaMarkLead;
    if (ExteriaNameIn(username, ExteriaTesterNames, TESTER_COUNT)) marks |= ExteriaMarkTester;
    if (ExteriaNameIn(username, &ExteriaCautionName, 1)) marks |= ExteriaMarkCaution;
    return marks;
}

NSUInteger ExteriaMarksOfId(long long userId) {
    NSUInteger marks = 0;
    if (ExteriaIsDeveloperId(userId)) marks |= ExteriaMarkDeveloper;
    if (ExteriaIdIn(userId, &ExteriaSenkoDeveloper, 1)) marks = (marks & ~(NSUInteger)ExteriaMarkDeveloper) | ExteriaMarkSenko | ExteriaMarkLead;
    if (ExteriaIdIn(userId, ExteriaTesterNames, TESTER_COUNT)) marks |= ExteriaMarkTester;
    if (ExteriaIdIn(userId, &ExteriaCautionName, 1)) marks |= ExteriaMarkCaution;
    return marks;
}

NSUInteger ExteriaDialogIsDeveloper(ExteriaDialog *dialog) {
    return dialog && dialog.peerKind == 1 && !dialog.saved ? ExteriaMarksOfId(dialog.peerId) : 0;
}

NSUInteger ExteriaPersonIsDeveloper(ExteriaPerson *person) {
    if (!person) return 0;
    return ExteriaMarksOfUsername(person.username) | ExteriaMarksOfId(person.userId);
}

/* each mark takes a space and a 24 point picture, about this much of the end of the line */
#define MARK_WIDTH 30.0

NSUInteger ExteriaMarkAtDistance(NSUInteger marks, CGFloat distanceFromEnd) {
    if (distanceFromEnd < -8) return 0;
    /* the line ends with the tester's net, the fox tail before it, the hammer before that */
    NSUInteger order[5] = {ExteriaMarkCaution, ExteriaMarkTester, ExteriaMarkSenko, ExteriaMarkLead, ExteriaMarkDeveloper};
    CGFloat edge = 0;
    for (int i = 0; i < 5; ++i) {
        if (!(marks & order[i])) continue;
        edge += MARK_WIDTH + (order[i] == ExteriaMarkCaution ? 24.0 * (EXTERIA_CAUTION_BADGE_RATIO - 1) : 0);
        if (distanceFromEnd < edge) return order[i];
    }
    return 0;
}

void ExteriaLearnDevelopers(ExteriaSession *session) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *ids = ExteriaDeveloperIds();
    NSDate *checked = [defaults objectForKey:ExteriaDeveloperCheckedKey];
    if (!session) return;
    if (checked && -[checked timeIntervalSinceNow] < RECHECK_SECONDS && ids.count >= LOOKUP_COUNT &&
        [ids objectForKey:ExteriaCautionName.lowercaseString]) return;
    /* the date moves first, so a screen that is opened again does not send the requests twice while they are on their way */
    [defaults setObject:[NSDate date] forKey:ExteriaDeveloperCheckedKey];
    for (NSUInteger i = 0; i < LOOKUP_COUNT; ++i) {
        NSString *name = i < DEVELOPER_COUNT ? ExteriaDeveloperNames[i] :
            (i < DEVELOPER_COUNT + TESTER_COUNT ? ExteriaTesterNames[i - DEVELOPER_COUNT] : ExteriaCautionName);
        /* a name that was resolved within the week is not asked again, so a name added to the lists costs one request, not nineteen */
        if (checked && -[checked timeIntervalSinceNow] < RECHECK_SECONDS && [ids objectForKey:name.lowercaseString]) continue;
        [session resolveUsername:name completion:^(ExteriaDialog *dialog, ExteriaPerson *person, NSString *errorName) {
            (void)dialog;
            if (!person || person.userId <= 0) {
                NSLog(@"exteria: developer @%@ not resolved: %@", name, errorName ? errorName : @"no user");
                return;
            }
            NSNumber *known = [ids objectForKey:name.lowercaseString];
            if ([known longLongValue] == person.userId) return;
            [ids setObject:[NSNumber numberWithLongLong:person.userId] forKey:name.lowercaseString];
            [[NSUserDefaults standardUserDefaults] setObject:[NSDictionary dictionaryWithDictionary:ids] forKey:ExteriaDeveloperIdsKey];
            [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDevelopersDidChangeNotification object:nil];
        }];
    }
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
    UIImage *badge = mark == ExteriaMarkCaution ? [ExteriaCustomEmoji imageForDocument:EXTERIA_CAUTION_DOCUMENT] :
        [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:mark == ExteriaMarkTester ? @"badge_tester" : (mark == ExteriaMarkSenko ? @"badge_senko" : (mark == ExteriaMarkLead ? @"badge_lead" : @"badge_developer")) ofType:@"png"]];
    UIImageView *hammer = [[[UIImageView alloc] initWithImage:badge] autorelease];
    hammer.contentMode = UIViewContentModeScaleAspectFit;
    [plate addSubview:hammer];
    ExteriaEmojiLabel *who = [[[ExteriaEmojiLabel alloc] init] autorelease];
    who.font = ExteriaFontSemibold(17);
    who.textColor = ExteriaColorTitle();
    who.dropsUndrawable = YES;
    who.text = name.length ? name : NSLocalizedString(@"developer.someone", nil);
    who.frame = CGRectMake(textX, 17, textWidth, 22);
    [plate addSubview:who];
    UILabel *what = [[[UILabel alloc] init] autorelease];
    what.backgroundColor = [UIColor clearColor];
    what.font = ExteriaFontRegular(14);
    what.textColor = ExteriaColorSecondary();
    what.numberOfLines = 0;
    what.lineBreakMode = UILineBreakModeWordWrap;
    what.text = NSLocalizedString(mark == ExteriaMarkCaution ? @"developer.caution" : (mark == ExteriaMarkTester ? @"developer.tester" : (mark == ExteriaMarkSenko ? @"developer.senko" : (mark == ExteriaMarkLead ? @"developer.lead" : @"developer.notice"))), nil);
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
