#import "exteria_logs_controller.h"

#import <QuartzCore/QuartzCore.h>

#include "exteria_zipw.h"

#import "exteria_alert.h"
#import "exteria_chat_item.h"
#import "exteria_person.h"
#import "exteria_problem_report.h"
#import "exteria_session.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define VIEW_TAIL_BYTES (64 * 1024)
#define EXPORT_FILE_BYTES (2 * 1024 * 1024)
#define CARD_PAD 14.0
#define CARD_MARGIN 12.0

typedef enum { ExteriaLogDirLibraryLogs, ExteriaLogDirCaches, ExteriaLogDirDocuments } ExteriaLogDir;

typedef struct {
    NSString *titleKey;
    NSString *infoKey;
    ExteriaLogDir directory;
    NSString *file;
} ExteriaLogSource;

/* the three files the app writes: stderr of the process, the record the crash handler leaves, and the trace of the last call */
static const ExteriaLogSource ExteriaLogSources[] = {
    {@"logs.general", @"logs.general.info", ExteriaLogDirLibraryLogs, @"exteria.log"},
    {@"logs.crash", @"logs.crash.info", ExteriaLogDirCaches, @"exteria-crash.log"},
    {@"logs.call", @"logs.call.info", ExteriaLogDirDocuments, @"exteria-call-trace.log"},
};
#define LOG_SOURCE_COUNT (sizeof(ExteriaLogSources) / sizeof(ExteriaLogSources[0]))

static NSString *ExteriaLogPath(const ExteriaLogSource *source) {
    NSSearchPathDirectory base = source->directory == ExteriaLogDirCaches ? NSCachesDirectory : (source->directory == ExteriaLogDirDocuments ? NSDocumentDirectory : NSLibraryDirectory);
    NSString *root = [NSSearchPathForDirectoriesInDomains(base, NSUserDomainMask, YES) objectAtIndex:0];
    if (source->directory == ExteriaLogDirLibraryLogs) root = [root stringByAppendingPathComponent:@"Logs"];
    return [root stringByAppendingPathComponent:source->file];
}

/* the last bytes of a file, from the start of a whole line when the file is longer; nil when it cannot be read */
static NSData *ExteriaLogTail(NSString *path, unsigned long long limit) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return nil;
    unsigned long long size = [handle seekToEndOfFile];
    unsigned long long start = size > limit ? size - limit : 0;
    [handle seekToFileOffset:start];
    NSData *data = [handle readDataToEndOfFile];
    [handle closeFile];
    if (start > 0) {
        const char *bytes = data.bytes;
        const char *newline = memchr(bytes, '\n', data.length);
        if (newline) data = [data subdataWithRange:NSMakeRange((NSUInteger)(newline - bytes) + 1, data.length - (NSUInteger)(newline - bytes) - 1)];
    }
    return data;
}

static NSString *ExteriaLogSafeName(NSString *name) {
    NSMutableString *safe = [NSMutableString string];
    for (NSUInteger i = 0; i < name.length; ++i) {
        unichar c = [name characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-') [safe appendFormat:@"%C", c];
    }
    return safe;
}

/* presents a file to the person: the share sheet where the system has one, the open-in menu of older ones */
static UIDocumentInteractionController *sDocumentController;
void ExteriaShareFile(UIViewController *host, NSString *path) {
    NSURL *url = [NSURL fileURLWithPath:path];
    Class activityClass = NSClassFromString(@"UIActivityViewController");
    if (activityClass) {
        id activity = [[[activityClass alloc] initWithActivityItems:[NSArray arrayWithObject:url] applicationActivities:nil] autorelease];
        if ([activity respondsToSelector:NSSelectorFromString(@"popoverPresentationController")]) {
            id popover = [activity performSelector:NSSelectorFromString(@"popoverPresentationController")];
            [popover setValue:host.view forKey:@"sourceView"];
            [popover setValue:[NSValue valueWithCGRect:CGRectMake(CGRectGetMidX(host.view.bounds), CGRectGetMidY(host.view.bounds), 1, 1)] forKey:@"sourceRect"];
        }
        [host presentViewController:activity animated:YES completion:nil];
        return;
    }
    [sDocumentController release];
    sDocumentController = [[UIDocumentInteractionController interactionControllerWithURL:url] retain];
    if (![sDocumentController presentOpenInMenuFromRect:CGRectMake(CGRectGetMidX(host.view.bounds), CGRectGetMidY(host.view.bounds), 1, 1) inView:host.view animated:YES])
        ExteriaShowNotice(nil, NSLocalizedString(@"logs.share.unavailable", nil));
}

#pragma mark viewer

@interface ExteriaLogViewController : ExteriaSettingsPageController {
    NSString *_path;
    NSString *_logName;
    UIView *_card;
    UITextView *_text;
    ExteriaWeakReference *_weak;
    NSUInteger _token;
}
- (id)initWithPath:(NSString *)path title:(NSString *)title;
@end

@implementation ExteriaLogViewController

- (id)initWithPath:(NSString *)path title:(NSString *)title {
    self = [super init];
    if (!self) return nil;
    _path = [path copy];
    _logName = [title copy];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = title;
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_path release];
    [_logName release];
    [_card release];
    [_text release];
    [super dealloc];
}

/* a line says how bad it is by its words; the colors come from the theme, so the page reads the same in the light, the dark and the classic one */
static UIColor *ExteriaLogLineColor(NSString *line) {
    NSString *lower = [line lowercaseString];
    if ([lower rangeOfString:@"fail"].length || [lower rangeOfString:@"error"].length || [lower rangeOfString:@"rejected"].length ||
        [lower rangeOfString:@"crash"].length || [lower rangeOfString:@"cannot"].length || [lower rangeOfString:@"signal"].length) return ExteriaColorBadgeRed();
    if ([lower rangeOfString:@"warn"].length || [lower rangeOfString:@"timeout"].length || [lower rangeOfString:@"retry"].length || [lower rangeOfString:@"memory"].length)
        return ExteriaColorAccent();
    return ExteriaColorTitle();
}

- (UIFont *)logFont {
    UIFont *font = [UIFont fontWithName:@"Menlo-Regular" size:11];
    return font ? font : [UIFont fontWithName:@"Courier" size:11];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reloadText];
}

- (void)reloadText {
    [self showText:NSLocalizedString(@"logs.loading", nil) plain:YES];
    ExteriaWeakReference *weak = _weak;
    NSString *path = _path;
    NSUInteger token = ++_token;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSData *data = ExteriaLogTail(path, VIEW_TAIL_BYTES);
        NSString *text = data.length ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            ExteriaLogViewController *me = weak.target;
            if (!me || token != me->_token) return;
            if (text.length) [me showText:text plain:NO];
            else [me showText:NSLocalizedString(data ? @"logs.empty" : @"logs.missing", nil) plain:YES];
        });
        [pool release];
    });
}

- (void)themeDidChange {
    [super themeDidChange];
    [self reloadText];
}

/* the whole text is one non-scrolling view in the header of the page, so the table scrolls it and the bar of the page stays the page's own */
- (void)showText:(NSString *)text plain:(BOOL)plain {
    UIFont *font = [self logFont];
    CGFloat width = self.view.bounds.size.width > 0 ? self.view.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
    CGFloat inner = width - 2 * CARD_MARGIN - 2 * CARD_PAD;
    if (!_card) {
        _card = [[UIView alloc] init];
        _card.layer.cornerRadius = 14;
        _text = [[UITextView alloc] init];
        _text.editable = NO;
        _text.scrollEnabled = NO;
        _text.backgroundColor = [UIColor clearColor];
        _text.contentInset = UIEdgeInsetsZero;
        [_card addSubview:_text];
    }
    _card.backgroundColor = ExteriaColorCard();
    if (!plain && [_text respondsToSelector:@selector(setAttributedText:)]) {
        NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] init] autorelease];
        NSDictionary *dim = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, ExteriaColorSecondary(), NSForegroundColorAttributeName, nil];
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, ExteriaLogLineColor(line), NSForegroundColorAttributeName, nil];
            /* the "exteria:" lead that every line of the app carries is quieter than what follows it */
            NSRange lead = [line hasPrefix:@"exteria:"] ? NSMakeRange(0, 8) : NSMakeRange(0, 0);
            [styled appendAttributedString:[[[NSAttributedString alloc] initWithString:[line substringToIndex:lead.length] attributes:dim] autorelease]];
            [styled appendAttributedString:[[[NSAttributedString alloc] initWithString:[[line substringFromIndex:lead.length] stringByAppendingString:@"\n"] attributes:attributes] autorelease]];
        }
        _text.attributedText = styled;
    } else {
        _text.font = font;
        _text.textColor = plain ? ExteriaColorSecondary() : ExteriaColorTitle();
        _text.text = text;
    }
    CGSize size = [_text sizeThatFits:CGSizeMake(inner + 16, CGFLOAT_MAX)];
    CGFloat height = ceil(size.height);
    _text.frame = CGRectMake(CARD_PAD - 8, CARD_PAD - 8, inner + 16, height);
    _card.frame = CGRectMake(CARD_MARGIN, 8, width - 2 * CARD_MARGIN, height + 2 * CARD_PAD - 16);
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, CGRectGetMaxY(_card.frame) + 8)] autorelease];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:_card];
    self.headerView = header;
}

@end

#pragma mark list

@interface ExteriaLogsController () {
    ExteriaSession *_session;
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaLogsController

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"logs.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaLogsController alloc] initWithSession:_session] autorelease];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSFileManager *files = [NSFileManager defaultManager];
    NSDateFormatter *dates = [[[NSDateFormatter alloc] init] autorelease];
    [dates setDateStyle:NSDateFormatterShortStyle];
    [dates setTimeStyle:NSDateFormatterShortStyle];
    NSMutableArray *rows = [NSMutableArray array];
    for (size_t i = 0; i < LOG_SOURCE_COUNT; ++i) {
        const ExteriaLogSource *source = &ExteriaLogSources[i];
        NSString *path = ExteriaLogPath(source);
        NSDictionary *attributes = [files attributesOfItemAtPath:path error:NULL];
        NSString *title = NSLocalizedString(source->titleKey, nil);
        NSString *detail = attributes ? [NSString stringWithFormat:@"%@ · %@", ExteriaFileSizeText((long long)[attributes fileSize]), [dates stringFromDate:[attributes fileModificationDate]]]
                                      : NSLocalizedString(@"logs.missing", nil);
        [rows addObject:[ExteriaSettingsRow rowWithSymbol:i == 1 ? ExteriaSymbolReport : ExteriaSymbolDocument tone:ExteriaSettingsToneBlack title:title subtitle:detail value:nil tap:^{
            ExteriaLogsController *me = weak.target;
            if (!me) return;
            [me.navigationController pushViewController:[[[ExteriaLogViewController alloc] initWithPath:path title:title] autorelease] animated:YES];
        }]];
    }
    ExteriaSettingsRow *export = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolShare tone:ExteriaSettingsToneBlack title:NSLocalizedString(@"logs.export", nil)
                                                          subtitle:NSLocalizedString(@"logs.export.info", nil) value:nil tap:^{ [(ExteriaLogsController *)weak.target exportAll]; }];
    self.sections = [NSArray arrayWithObjects:
        [ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:export]],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"logs.files", nil) footer:NSLocalizedString(@"logs.files.info", nil) rows:rows], nil];
}

/* the name of the archive carries the username, and the account number when the account has none; only letters, digits, - and _ stay, since the name becomes a file */
- (NSString *)archiveName {
    NSString *name = ExteriaLogSafeName([_session ownPerson].username);
    if (!name.length) {
        long long account = [ExteriaSession accountIdInDirectory:_session.directory];
        name = account > 0 ? [NSString stringWithFormat:@"%lld", account] : @"user";
    }
    return [NSString stringWithFormat:@"exteria-%@.zip", name];
}

- (void)exportAll {
    ExteriaWeakReference *weak = _weak;
    NSString *archive = [NSTemporaryDirectory() stringByAppendingPathComponent:[self archiveName]];
    NSString *header = [NSString stringWithFormat:@"%@\n%@\n", ExteriaProblemReportHeader(), [NSDate date]];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [[NSFileManager defaultManager] removeItemAtPath:archive error:NULL];
        exteria_zipw *zip = NULL;
        exteria_status status = exteria_zipw_begin(archive.fileSystemRepresentation, &zip);
        int packed = 0;
        if (status == EXTERIA_OK) {
            NSData *info = [header dataUsingEncoding:NSUTF8StringEncoding];
            status = exteria_zipw_add(zip, "device.txt", info.bytes, info.length, 0644);
            for (size_t i = 0; i < LOG_SOURCE_COUNT && status == EXTERIA_OK; ++i) {
                NSData *data = ExteriaLogTail(ExteriaLogPath(&ExteriaLogSources[i]), EXPORT_FILE_BYTES);
                if (!data) continue;
                status = exteria_zipw_add(zip, ExteriaLogSources[i].file.UTF8String, data.bytes, data.length, 0644);
                ++packed;
            }
            if (status == EXTERIA_OK) status = exteria_zipw_finish(zip);
            else exteria_zipw_abort(zip);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            ExteriaLogsController *me = weak.target;
            if (!me) return;
            if (status != EXTERIA_OK) {
                NSLog(@"exteria: the logs were not packed: %s", exteria_status_name(status));
                ExteriaShowNotice(nil, NSLocalizedString(@"logs.export.failed", nil));
                return;
            }
            if (!packed) NSLog(@"exteria: the archive of the logs holds the device note only, no log exists yet");
            ExteriaShareFile(me, archive);
        });
        [pool release];
    });
}

@end
