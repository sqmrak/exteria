#import "exteria_developer_badges_controller.h"

#import "exteria_animation.h"
#import "exteria_custom_emoji.h"
#import "exteria_developers.h"
#import "exteria_emoji_label.h"
#import "exteria_name_badge.h"
#import "exteria_person.h"
#import "exteria_session.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

/* one badge: its bit, its picture and the words of its row */
typedef struct {
    NSUInteger mark;
    long long document;
    NSString *title;
    NSString *info;
} ExteriaBadgeEntry;

static const ExteriaBadgeEntry ExteriaBadgeEntries[] = {
    {ExteriaMarkLead, EXTERIA_LEAD_DOCUMENT, @"developer.mark.lead", @"developer.lead"},
    {ExteriaMarkDeveloper, EXTERIA_DEVELOPER_DOCUMENT, @"developer.mark.developer", @"developer.notice"},
    {ExteriaMarkSenko, EXTERIA_SENKO_DOCUMENT, @"developer.mark.senko", @"developer.senko"},
    {ExteriaMarkTester, EXTERIA_TESTER_DOCUMENT, @"developer.mark.tester", @"developer.tester"},
    {ExteriaMarkOfficialTester, EXTERIA_OFFICIAL_TESTER_DOCUMENT, @"developer.mark.official", @"developer.official_tester"},
    {ExteriaMarkBugHunter, EXTERIA_BUG_HUNTER_DOCUMENT, @"developer.mark.hunter", @"developer.bug_hunter.notice"},
    {ExteriaMarkManager, EXTERIA_MANAGER_DOCUMENT, @"developer.mark.manager", @"developer.manager"},
    {ExteriaMarkPromotion, EXTERIA_PROMOTION_DOCUMENT, @"developer.mark.promotion", @"developer.promotion"},
    {ExteriaMarkCaution, EXTERIA_CAUTION_DOCUMENT, @"developer.mark.caution", @"developer.caution"},
};
#define BADGE_COUNT (sizeof(ExteriaBadgeEntries) / sizeof(ExteriaBadgeEntries[0]))

/* the card at the top: the name of the account with the badges it wears now, large, on a ground that changes with each tap */
@interface ExteriaBadgePreview : UIView {
    ExteriaEmojiLabel *_name;
    UILabel *_caption;
}
- (void)showName:(NSString *)name marks:(NSUInteger)marks custom:(BOOL)custom;
@end

@implementation ExteriaBadgePreview

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _name = [[ExteriaEmojiLabel alloc] init];
    _name.font = ExteriaFontBold(26);
    _name.textColor = ExteriaColorTitle();
    _name.textAlignment = ExteriaTextAlignmentCenter;
    _name.dropsUndrawable = YES;
    [self addSubview:_name];
    _caption = [[UILabel alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.font = ExteriaFontRegular(13);
    _caption.textColor = ExteriaColorSecondary();
    _caption.textAlignment = ExteriaTextAlignmentCenter;
    [self addSubview:_caption];
    return self;
}

- (void)dealloc {
    [_name release];
    [_caption release];
    [super dealloc];
}

- (void)showName:(NSString *)name marks:(NSUInteger)marks custom:(BOOL)custom {
    NSArray *entities = nil;
    _name.text = ExteriaNameWithBadges(name, 0, marks, &entities);
    _name.entities = entities;
    _caption.text = NSLocalizedString(custom ? @"developer.badges.preview.local" : @"developer.badges.preview.real", nil);
    /* the name pops a little at each change, so a tap is seen where the eyes are */
    _name.transform = CGAffineTransformMakeScale(0.94, 0.94);
    ExteriaAnimateView(_name, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _name.frame = CGRectMake(16, 26, MAX(0, size.width - 32), 40);
    _caption.frame = CGRectMake(16, 70, MAX(0, size.width - 32), 18);
}

@end

@interface ExteriaDeveloperBadgesController () {
    ExteriaSession *_session;
    ExteriaWeakReference *_weak;
    long long _userId;
    NSString *_name;
    ExteriaBadgePreview *_preview;
}
@end

@implementation ExteriaDeveloperBadgesController

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    ExteriaPerson *own = [session ownPerson];
    _userId = own.userId;
    _name = [(own.name.length ? own.name : NSLocalizedString(@"developer.popup.someone", nil)) copy];
    self.pageTitle = NSLocalizedString(@"developer.badges", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_name release];
    [_preview release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _preview = [[ExteriaBadgePreview alloc] initWithFrame:CGRectZero];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaDeveloperBadgesController alloc] initWithSession:_session] autorelease];
}

- (NSUInteger)marks {
    return ExteriaMarksOfId(_userId);
}

/* a tap takes the badge or gives it back; the first tap sets the badges of this phone to the ones the account really has plus or minus that one */
- (void)toggle:(NSUInteger)mark {
    NSUInteger marks = [self marks];
    if (marks & mark) marks &= ~mark;
    else marks |= mark;
    ExteriaSetLocalMarks(_userId, marks);
    [self rebuild];
}

- (void)setAll:(BOOL)on {
    NSUInteger all = 0;
    for (size_t i = 0; i < BADGE_COUNT; ++i) all |= ExteriaBadgeEntries[i].mark;
    ExteriaSetLocalMarks(_userId, on ? all : 0);
    [self rebuild];
}

- (void)restore {
    ExteriaClearLocalMarks(_userId);
    [self rebuild];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSUInteger marks = [self marks];
    NSMutableArray *rows = [NSMutableArray array];
    for (size_t i = 0; i < BADGE_COUNT; ++i) {
        NSUInteger mark = ExteriaBadgeEntries[i].mark;
        UIImage *picture = [ExteriaCustomEmoji imageForDocument:ExteriaBadgeEntries[i].document];
        BOOL on = (marks & mark) != 0;
        ExteriaSettingsRow *row = [ExteriaSettingsRow rowWithTileImage:picture title:NSLocalizedString(ExteriaBadgeEntries[i].title, nil)
                                                              subtitle:NSLocalizedString(ExteriaBadgeEntries[i].info, nil) tap:^{ [(ExteriaDeveloperBadgesController *)weak.target toggle:mark]; }];
        if (on) row.trailingImage = ExteriaSymbolImage(ExteriaSymbolCheck, 22, ExteriaColorAccent());
        [rows addObject:row];
    }
    ExteriaSettingsRow *previewRow = [ExteriaSettingsRow viewRowWithView:_preview height:^CGFloat(CGFloat width) { (void)width; return 104; }];
    [_preview showName:_name marks:marks custom:ExteriaHasLocalMarks(_userId)];
    NSMutableArray *tools = [NSMutableArray arrayWithObjects:
        [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolCheckDouble title:NSLocalizedString(@"developer.badges.all", nil) destructive:NO tap:^{ [(ExteriaDeveloperBadgesController *)weak.target setAll:YES]; }],
        [ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolClose title:NSLocalizedString(@"developer.badges.none", nil) destructive:NO tap:^{ [(ExteriaDeveloperBadgesController *)weak.target setAll:NO]; }], nil];
    if (ExteriaHasLocalMarks(_userId)) {
        [tools addObject:[ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolRotate title:NSLocalizedString(@"developer.badges.restore", nil) destructive:YES
                                                             tap:^{ [(ExteriaDeveloperBadgesController *)weak.target restore]; }]];
    }
    self.sections = [NSArray arrayWithObjects:
        [ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:previewRow]],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"developer.badges.header", nil) footer:NSLocalizedString(@"developer.badges.info", nil) rows:rows],
        [ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:tools], nil];
}

@end
