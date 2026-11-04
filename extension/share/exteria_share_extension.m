#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

/* the share sheet extension of ios 8 and later. The sdk of the armv7 slice (ios 6.1) has no NSExtensionContext or NSItemProvider, so both are reached by name at run time on
   the two slices. The extension only collects what was shared into the folder of the app group, and wakes the app, which asks the person for the chat and sends it. */

#define GROUP_IDENTIFIER @"group.com.sqmrak.exteria"
#define SHARE_FOLDER @"Share"
#define MANIFEST_NAME @"manifest.plist"
#define ITEMS_MAX 10
#define JPEG_QUALITY 0.9
#define WAKE_URL @"exteria://share"

@interface ExteriaShareViewController : UIViewController {
    UIActivityIndicatorView *_spinner;
    UILabel *_label;
    NSString *_folder;
    NSMutableArray *_files;
    NSMutableArray *_texts;
    NSString *_failure;
    NSUInteger _pending;
}
@end

static BOOL ExteriaShareRussian(void) {
    NSString *language = [[NSLocale preferredLanguages] count] ? [[NSLocale preferredLanguages] objectAtIndex:0] : @"en";
    return [language hasPrefix:@"ru"];
}

@implementation ExteriaShareViewController

- (void)dealloc {
    [_spinner release];
    [_label release];
    [_folder release];
    [_files release];
    [_texts release];
    [_failure release];
    [super dealloc];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIView *card = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 110)] autorelease];
    card.backgroundColor = [UIColor colorWithWhite:1 alpha:0.96];
    card.layer.cornerRadius = 14;
    card.center = CGPointMake(root.bounds.size.width / 2, root.bounds.size.height / 2);
    card.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.center = CGPointMake(110, 38);
    [_spinner startAnimating];
    [card addSubview:_spinner];
    _label = [[UILabel alloc] initWithFrame:CGRectMake(10, 66, 200, 30)];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.font = [UIFont systemFontOfSize:15];
    _label.textColor = [UIColor darkGrayColor];
    _label.backgroundColor = [UIColor clearColor];
    _label.text = ExteriaShareRussian() ? @"Подготовка…" : @"Preparing…";
    [card addSubview:_label];
    [root addSubview:card];
    self.view = root;
}

- (id)context {
    return [self valueForKey:@"extensionContext"];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_folder) return;
    [self collect];
}

#pragma mark shared folder

/* the folder of the app group; nil when the system gives this extension no container for the group (the build is not signed with the group) */
- (NSString *)shareRoot {
    NSFileManager *manager = [NSFileManager defaultManager];
    SEL select = NSSelectorFromString(@"containerURLForSecurityApplicationGroupIdentifier:");
    if (![manager respondsToSelector:select]) return nil;
    NSURL *container = ((id (*)(id, SEL, NSString *))objc_msgSend)(manager, select, GROUP_IDENTIFIER);
    return container ? [[container path] stringByAppendingPathComponent:SHARE_FOLDER] : nil;
}

- (NSString *)uniqueNameFor:(NSString *)name {
    NSString *candidate = name.length ? name : @"file";
    NSString *base = [candidate stringByDeletingPathExtension], *extension = [candidate pathExtension];
    NSUInteger n = 1;
    while ([[NSFileManager defaultManager] fileExistsAtPath:[_folder stringByAppendingPathComponent:candidate]]) {
        candidate = [NSString stringWithFormat:extension.length ? @"%@ %lu.%@" : @"%@ %lu%@", base, (unsigned long)++n, extension];
    }
    return candidate;
}

#pragma mark collecting

- (void)collect {
    NSString *root = [self shareRoot];
    if (!root) { [self failWith:ExteriaShareRussian() ? @"Нет общего контейнера Exteria" : @"No shared container for Exteria"]; return; }
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString *identifier = [(NSString *)CFUUIDCreateString(NULL, uuid) autorelease];
    CFRelease(uuid);
    _folder = [[root stringByAppendingPathComponent:identifier] retain];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:_folder withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"exteria share: cannot create %@: %@", _folder, error);
        [self failWith:ExteriaShareRussian() ? @"Не удалось сохранить файлы" : @"The files could not be kept"];
        return;
    }
    _files = [[NSMutableArray alloc] init];
    _texts = [[NSMutableArray alloc] init];
    NSMutableArray *providers = [NSMutableArray array];
    for (id item in [[self context] valueForKey:@"inputItems"]) {
        NSString *title = [item valueForKey:@"attributedContentText"] ? [[item valueForKey:@"attributedContentText"] string] : nil;
        if (title.length) [_texts addObject:title];
        for (id provider in [item valueForKey:@"attachments"]) if (providers.count < ITEMS_MAX) [providers addObject:provider];
    }
    if (!providers.count) {
        if (_texts.count) [self finish];
        else [self failWith:ExteriaShareRussian() ? @"Нечего отправлять" : @"Nothing to send"];
        return;
    }
    _pending = providers.count;
    for (id provider in providers) [self load:provider];
}

static BOOL ExteriaProviderHas(id provider, NSString *type) {
    return ((BOOL (*)(id, SEL, NSString *))objc_msgSend)(provider, NSSelectorFromString(@"hasItemConformingToTypeIdentifier:"), type);
}

/* the most specific kind the provider holds: a movie or a picture or a file, then a link, then text */
- (void)load:(id)provider {
    NSArray *kinds = [NSArray arrayWithObjects:@"public.movie", @"public.image", @"public.file-url", @"public.url", @"public.plain-text", @"public.data", nil];
    NSString *chosen = nil;
    for (NSString *kind in kinds) if (ExteriaProviderHas(provider, kind)) { chosen = kind; break; }
    if (!chosen) { [self loaded:nil]; return; }
    void (^handler)(id, NSError *) = ^(id item, NSError *error) {
        if (error) NSLog(@"exteria share: an attachment did not load: %@", error);
        [self loaded:item ? [self keep:item kind:chosen provider:provider] : nil];
    };
    ((void (*)(id, SEL, NSString *, NSDictionary *, void (^)(id, NSError *)))objc_msgSend)(provider,
        NSSelectorFromString(@"loadItemForTypeIdentifier:options:completionHandler:"), chosen, nil, handler);
}

/* on a queue of the system: one item is written into the folder, and the name or text it left is returned for the manifest */
- (id)keep:(id)item kind:(NSString *)kind provider:(id)provider {
    (void)provider;
    NSFileManager *manager = [NSFileManager defaultManager];
    if ([item isKindOfClass:[NSURL class]] && [(NSURL *)item isFileURL]) {
        /* the providers answer on several queues, and the name is chosen and taken under one lock so two files of one name do not meet */
        @synchronized (self) {
            NSString *name = [self uniqueNameFor:[(NSURL *)item lastPathComponent]];
            NSError *error = nil;
            if ([manager copyItemAtPath:[(NSURL *)item path] toPath:[_folder stringByAppendingPathComponent:name] error:&error]) return [NSDictionary dictionaryWithObject:name forKey:@"file"];
            NSLog(@"exteria share: cannot copy %@: %@", [(NSURL *)item lastPathComponent], error);
            return nil;
        }
    }
    if ([item isKindOfClass:[NSURL class]]) return [NSDictionary dictionaryWithObject:[(NSURL *)item absoluteString] forKey:@"text"];
    if ([item isKindOfClass:[NSString class]]) return [NSDictionary dictionaryWithObject:item forKey:@"text"];
    NSData *data = nil;
    NSString *extension = @"dat";
    if ([item isKindOfClass:[UIImage class]]) { data = UIImageJPEGRepresentation(item, JPEG_QUALITY); extension = @"jpg"; }
    else if ([item isKindOfClass:[NSData class]]) {
        data = item;
        extension = [kind isEqualToString:@"public.image"] ? @"jpg" : ([kind isEqualToString:@"public.movie"] ? @"mov" : @"dat");
    }
    if (!data.length) return nil;
    @synchronized (self) {
        NSString *name = [self uniqueNameFor:[@"shared." stringByAppendingString:extension]];
        if ([data writeToFile:[_folder stringByAppendingPathComponent:name] atomically:YES]) return [NSDictionary dictionaryWithObject:name forKey:@"file"];
        NSLog(@"exteria share: cannot write %@", name);
        return nil;
    }
}

- (void)loaded:(NSDictionary *)entry {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *file = [entry objectForKey:@"file"], *text = [entry objectForKey:@"text"];
        if (file) [_files addObject:file];
        if (text) [_texts addObject:text];
        if (--_pending == 0) [self finish];
    });
}

#pragma mark finishing

- (void)finish {
    if (!_files.count && !_texts.count) { [self failWith:ExteriaShareRussian() ? @"Не удалось прочитать вложения" : @"The attachments could not be read"]; return; }
    NSDictionary *manifest = [NSDictionary dictionaryWithObjectsAndKeys:_files, @"files", [_texts componentsJoinedByString:@"\n"], @"text", nil];
    if (![manifest writeToFile:[_folder stringByAppendingPathComponent:MANIFEST_NAME] atomically:YES]) {
        [self failWith:ExteriaShareRussian() ? @"Не удалось сохранить файлы" : @"The files could not be kept"];
        return;
    }
    [self wakeApp];
    [[self context] performSelector:NSSelectorFromString(@"completeRequestReturningItems:completionHandler:") withObject:nil withObject:nil];
}

/* the app is opened through the responder chain, the only way a share extension of ios 8 to 10 has; if nothing on the chain can open it, the app takes the folder
   the next time it comes to the front */
- (void)wakeApp {
    NSURL *url = [NSURL URLWithString:WAKE_URL];
    SEL open = NSSelectorFromString(@"openURL:");
    for (UIResponder *responder = [self nextResponder]; responder; responder = [responder nextResponder]) {
        if (![responder respondsToSelector:open]) continue;
        ((BOOL (*)(id, SEL, NSURL *))objc_msgSend)(responder, open, url);
        return;
    }
    NSLog(@"exteria share: no responder opens the app, it will find the files when it is opened");
}

- (void)failWith:(NSString *)text {
    NSLog(@"exteria share: %@", text);
    [_failure release];
    _failure = [text copy];
    if (_folder) [[NSFileManager defaultManager] removeItemAtPath:_folder error:NULL];
    [_spinner stopAnimating];
    _label.text = text;
    _label.numberOfLines = 2;
    [self performSelector:@selector(cancelRequest) withObject:nil afterDelay:1.8];
}

- (void)cancelRequest {
    NSError *error = [NSError errorWithDomain:@"ExteriaShare" code:1 userInfo:[NSDictionary dictionaryWithObject:_failure ? _failure : @"" forKey:NSLocalizedDescriptionKey]];
    [[self context] performSelector:NSSelectorFromString(@"cancelRequestWithError:") withObject:error];
}

@end
