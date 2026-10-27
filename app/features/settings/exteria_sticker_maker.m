#import "exteria_sticker_maker.h"

#import "exteria_alert.h"
#import "exteria_gift_screen.h"
#import "exteria_session_stickermake.h"
#import "exteria_session_stickermanage.h"
#import "exteria_theme.h"

#include "exteria_sticker_make.h"

/* the longest side and the size a static sticker may have */
#define STICKER_SIDE 512.0
#define STICKER_BYTES_MAX 512000
/* the sets made here are remembered to add to, at most this many */
#define MINE_MAX 5
#define NAME_TRIES 3

@interface ExteriaStickerMaker () <UIImagePickerControllerDelegate, UINavigationControllerDelegate> {
    ExteriaSession *_session;
    UIViewController *_host;
    void (^_done)(NSString *);
    NSString *_path;
    NSString *_emoji;
    UIView *_cover;
}
@end

@implementation ExteriaStickerMaker

+ (void)startWithSession:(ExteriaSession *)session host:(UIViewController *)host done:(void (^)(NSString *))done {
    ExteriaStickerMaker *maker = [[ExteriaStickerMaker alloc] init];
    maker->_session = [session retain];
    maker->_host = [host retain];
    maker->_done = [done copy];
    [maker chooseCut];
}

- (void)dealloc {
    if (_path) [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
    [_session release];
    [_host release];
    [_done release];
    [_path release];
    [_emoji release];
    [_cover release];
    [super dealloc];
}

/* every way out of the flow goes through here, which gives back the count the start took */
- (void)finish {
    [self setBusy:NO];
    [self release];
}

- (NSString *)mineKey {
    return [NSString stringWithFormat:@"exteria.stickers.mine.%lld", [ExteriaSession accountIdInDirectory:_session.directory]];
}

/* the sets made here, newest first: dictionaries with the public name and the title */
- (NSArray *)mine {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:[self mineKey]];
    return [stored isKindOfClass:[NSArray class]] ? stored : [NSArray array];
}

- (void)remember:(NSString *)name title:(NSString *)title {
    NSMutableArray *sets = [NSMutableArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:name, @"name", title, @"title", nil]];
    for (NSDictionary *set in [self mine]) {
        if (![[set objectForKey:@"name"] isEqualToString:name] && sets.count < MINE_MAX) [sets addObject:set];
    }
    [[NSUserDefaults standardUserDefaults] setObject:sets forKey:[self mineKey]];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setBusy:(BOOL)busy {
    if (!busy) {
        [_cover removeFromSuperview];
        [_cover release];
        _cover = nil;
        return;
    }
    if (_cover || !_host.view) return;
    _cover = [[UIView alloc] initWithFrame:_host.view.bounds];
    _cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _cover.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    UIActivityIndicatorView *spinner = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge] autorelease];
    spinner.center = CGPointMake(_cover.bounds.size.width / 2, _cover.bounds.size.height / 2);
    spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [spinner startAnimating];
    [_cover addSubview:spinner];
    [_host.view addSubview:_cover];
}

#pragma mark picture

- (void)chooseCut {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        ExteriaShowNotice(nil, NSLocalizedString(@"attach.gallery.unavailable", nil));
        [self finish];
        return;
    }
    NSArray *buttons = [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"sticker.make.square", nil), NSLocalizedString(@"sticker.make.whole", nil), nil];
    ExteriaShowAlert(NSLocalizedString(@"sticker.make.title", nil), NSLocalizedString(@"sticker.make.cut", nil), buttons, 0, NO, ^(NSInteger index, NSString *text) {
        (void)text;
        if (index == 1 || index == 2) [self pickWhole:index == 2];
        else [self finish];
    });
}

- (void)pickWhole:(BOOL)whole {
    UIImagePickerController *picker = [[[UIImagePickerController alloc] init] autorelease];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.allowsEditing = !whole;
    picker.delegate = self;
    [_host presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
    [self finish];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = [info objectForKey:UIImagePickerControllerEditedImage];
    if (!image) image = [info objectForKey:UIImagePickerControllerOriginalImage];
    [image retain];
    [picker dismissViewControllerAnimated:YES completion:nil];
    [self setBusy:YES];
    /* off the main thread: the picture is drawn into a canvas whose long side is 512 and written as a PNG, which keeps the clear parts clear */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        CGSize size = image.size;
        NSString *path = nil;
        NSData *png = nil;
        if (size.width >= 1 && size.height >= 1) {
            CGFloat scale = STICKER_SIDE / MAX(size.width, size.height);
            CGSize out = CGSizeMake(MAX(1, floor(size.width * scale)), MAX(1, floor(size.height * scale)));
            UIGraphicsBeginImageContextWithOptions(out, NO, 1.0);
            [image drawInRect:CGRectMake(0, 0, out.width, out.height)];
            UIImage *fitted = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            png = UIImagePNGRepresentation(fitted);
            NSString *candidate = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"sticker-%u.png", arc4random()]];
            if (png.length && png.length <= STICKER_BYTES_MAX && [png writeToFile:candidate atomically:YES]) path = [[candidate copy] autorelease];
        }
        NSString *delivered = [path retain];
        BOOL tooBig = png.length > STICKER_BYTES_MAX;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            if (delivered) {
                _path = delivered;
                [self askEmoji];
            } else {
                NSLog(@"exteria: the sticker picture was not prepared (%lu bytes)", (unsigned long)png.length);
                ExteriaShowNotice(nil, NSLocalizedString(tooBig ? @"sticker.make.toobig" : @"sticker.make.failed", nil));
                [self finish];
            }
        });
        [image release];
        [pool drain];
    });
}

#pragma mark steps

- (void)askEmoji {
    ExteriaPromptTextOrCancel(NSLocalizedString(@"sticker.make.emoji", nil), NSLocalizedString(@"sticker.make.emoji.info", nil), @"\U0001F600", nil, ^(NSString *text) {
        NSString *emoji = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!exteria_sticker_emoji_valid(emoji.UTF8String)) {
            ExteriaShowNotice(nil, NSLocalizedString(@"sticker.make.emoji.bad", nil));
            [self askEmoji];
            return;
        }
        _emoji = [emoji copy];
        [self chooseSet];
    }, ^{ [self finish]; });
}

- (void)chooseSet {
    NSArray *mine = [self mine];
    if (!mine.count) {
        [self askTitle];
        return;
    }
    NSMutableArray *buttons = [NSMutableArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"sticker.make.new", nil), nil];
    for (NSDictionary *set in mine) [buttons addObject:[set objectForKey:@"title"]];
    ExteriaShowAlert(NSLocalizedString(@"sticker.make.where", nil), nil, buttons, 0, NO, ^(NSInteger index, NSString *text) {
        (void)text;
        if (index == 1) [self askTitle];
        else if (index >= 2 && (NSUInteger)index - 2 < mine.count) [self addToSet:[mine objectAtIndex:(NSUInteger)index - 2]];
        else [self finish];
    });
}

- (void)askTitle {
    ExteriaPromptTextOrCancel(NSLocalizedString(@"sticker.make.settitle", nil), nil, nil, NSLocalizedString(@"sticker.make.settitle.placeholder", nil), ^(NSString *text) {
        NSString *title = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!exteria_sticker_title_valid(title.UTF8String)) {
            ExteriaShowNotice(nil, NSLocalizedString(@"sticker.make.settitle.bad", nil));
            [self askTitle];
            return;
        }
        [self createSetTitled:title];
    }, ^{ [self finish]; });
}

/* the public name comes from the title: its letters and digits, and four digits to keep names of like titles apart; a name the server has is tried again */
- (NSString *)nameForTitle:(NSString *)title {
    NSMutableString *base = [NSMutableString string];
    for (NSUInteger i = 0; i < title.length && base.length < 24; ++i) {
        unichar c = [title characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) [base appendFormat:@"%C", c];
    }
    if (!base.length || !((([base characterAtIndex:0]) >= 'a' && [base characterAtIndex:0] <= 'z') || ([base characterAtIndex:0] >= 'A' && [base characterAtIndex:0] <= 'Z')))
        [base insertString:@"stickers" atIndex:0];
    return [NSString stringWithFormat:@"%@_%04u", base, arc4random() % 10000];
}

- (void)createSetTitled:(NSString *)title {
    [self setBusy:YES];
    [self tryName:[self nameForTitle:title] title:title tries:NAME_TRIES];
}

- (void)tryName:(NSString *)name title:(NSString *)title tries:(int)tries {
    [_session checkStickerShortName:name completion:^(NSString *errorName) {
        if (errorName && [errorName isEqualToString:@"NAME_OCCUPIED"] && tries > 1) {
            [self tryName:[self nameForTitle:title] title:title tries:tries - 1];
            return;
        }
        if (errorName) {
            [self fail:errorName];
            return;
        }
        [_session uploadStickerAtPath:_path completion:^(ExteriaStickerDocument *document, NSString *uploadError) {
            if (!document) {
                [self fail:uploadError];
                return;
            }
            [_session createStickerSetTitle:title shortName:name document:document emoji:_emoji completion:^(NSString *shortName, NSString *createError) {
                if (!shortName) {
                    [self fail:createError];
                    return;
                }
                [self remember:shortName title:title];
                [self succeedInSet:shortName title:title];
            }];
        }];
    }];
}

- (void)addToSet:(NSDictionary *)set {
    NSString *name = [set objectForKey:@"name"], *title = [set objectForKey:@"title"];
    [self setBusy:YES];
    [_session uploadStickerAtPath:_path completion:^(ExteriaStickerDocument *document, NSString *uploadError) {
        if (!document) {
            [self fail:uploadError];
            return;
        }
        [_session addStickerDocument:document emoji:_emoji toSetNamed:name completion:^(NSString *shortName, NSString *addError) {
            if (!shortName) {
                [self fail:addError];
                return;
            }
            [self succeedInSet:shortName title:title];
        }];
    }];
}

- (void)succeedInSet:(NSString *)shortName title:(NSString *)title {
    void (^done)(NSString *) = [_done retain];
    /* the new set is among the account's own now, so the lists that keep sets ask the server again */
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaStickerSetsDidChangeNotification object:nil];
    [self setBusy:NO];
    ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"sticker.make.done", nil), title]);
    if (done) done(shortName);
    [done release];
    [self finish];
}

/* the methods that make sets are for bots on some accounts; the person is told so, and where the official way is */
- (void)fail:(NSString *)errorName {
    NSLog(@"exteria: the sticker was not made: %@", errorName);
    BOOL refused = [errorName isEqualToString:@"BOT_METHOD_INVALID"] || [errorName isEqualToString:@"USER_BOT_REQUIRED"] || [errorName isEqualToString:@"METHOD_INVALID"] ||
                   [errorName isEqualToString:@"BOT_MISSING"];
    ExteriaShowNotice(nil, refused ? NSLocalizedString(@"sticker.make.refused", nil) : ExteriaGiftErrorText(errorName));
    [self finish];
}

@end
