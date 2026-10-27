#import "exteria_sticker_library.h"

#import "exteria_session_stickermanage.h"

@interface ExteriaStickerLibrary () {
    NSArray *_sets;
    NSMutableDictionary *_stickers;
    /* one request at a time per thing asked for, the others wait for its answer */
    NSMutableArray *_setWaiters;
    NSMutableDictionary *_stickerWaiters;
    NSDictionary *_animatedEmoji;
    NSMutableArray *_animatedEmojiWaiters;
    NSString *_animatedEmojiError;
    NSTimeInterval _animatedEmojiRetryAfter;
}
@end

@implementation ExteriaStickerLibrary

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _stickers = [[NSMutableDictionary alloc] init];
    _stickerWaiters = [[NSMutableDictionary alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setsChanged) name:ExteriaStickerSetsDidChangeNotification object:nil];
    return self;
}

/* sets were taken away or put in another order: the list kept here is stale, and the next panel asks the server again */
- (void)setsChanged {
    [_sets release];
    _sets = nil;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_session release];
    [_sets release];
    [_stickers release];
    [_setWaiters release];
    [_stickerWaiters release];
    [_animatedEmoji release];
    [_animatedEmojiWaiters release];
    [_animatedEmojiError release];
    [super dealloc];
}

- (void)loadSets:(void (^)(NSArray *, NSString *))completion {
    if (_sets) {
        completion(_sets, nil);
        return;
    }
    if (_setWaiters) {
        [_setWaiters addObject:[[completion copy] autorelease]];
        return;
    }
    _setWaiters = [[NSMutableArray alloc] initWithObjects:[[completion copy] autorelease], nil];
    [_session loadStickerSets:^(NSArray *sets, NSString *errorName) {
        if (sets) _sets = [sets retain];
        NSArray *waiters = [_setWaiters autorelease];
        _setWaiters = nil;
        for (void (^waiter)(NSArray *, NSString *) in waiters) waiter(sets, errorName);
    }];
}

- (void)loadStickersOfSet:(ExteriaStickerSet *)set completion:(void (^)(NSArray *, NSString *))completion {
    NSNumber *key = [NSNumber numberWithLongLong:set.setId];
    NSArray *kept = [_stickers objectForKey:key];
    if (kept) {
        completion(kept, nil);
        return;
    }
    NSMutableArray *waiting = [_stickerWaiters objectForKey:key];
    if (waiting) {
        [waiting addObject:[[completion copy] autorelease]];
        return;
    }
    [_stickerWaiters setObject:[NSMutableArray arrayWithObject:[[completion copy] autorelease]] forKey:key];
    [_session loadStickersOfSet:set completion:^(NSArray *stickers, NSString *errorName) {
        if (stickers) [_stickers setObject:stickers forKey:key];
        NSArray *waiters = [[_stickerWaiters objectForKey:key] retain];
        [_stickerWaiters removeObjectForKey:key];
        for (void (^waiter)(NSArray *, NSString *) in waiters) waiter(stickers, errorName);
        [waiters release];
    }];
}

- (void)loadRecent:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    [_session loadRecentStickers:^(NSArray *stickers, NSString *errorName) {
        done(stickers, errorName);
        [done release];
    }];
}

- (void)loadFaved:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    [_session loadFavedStickers:^(NSArray *stickers, NSString *errorName) { done(stickers, errorName); [done release]; }];
}

- (void)loadGifs:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    [_session loadSavedGifs:^(NSArray *gifs, NSString *errorName) { done(gifs, errorName); [done release]; }];
}

- (void)faveSticker:(ExteriaSticker *)sticker unfave:(BOOL)unfave completion:(void (^)(NSString *))completion {
    [_session faveSticker:sticker unfave:unfave completion:completion];
}

- (void)clearRecent:(void (^)(NSString *))completion {
    [_session clearRecentStickers:completion];
}

- (void)loadAnimationForEmoji:(NSString *)emoji completion:(void (^)(ExteriaSticker *, NSString *))completion {
    /* the official pack names emoji without U+FE0F, as Telegram's clients do */
    NSString *key = [emoji stringByReplacingOccurrencesOfString:@"\uFE0F" withString:@""];
    if (_animatedEmoji) {
        completion([_animatedEmoji objectForKey:key], nil);
        return;
    }
    if ([NSDate timeIntervalSinceReferenceDate] < _animatedEmojiRetryAfter) {
        completion(nil, _animatedEmojiError);
        return;
    }
    void (^waiter)(NSDictionary *, NSString *) = ^(NSDictionary *animations, NSString *error) {
        completion([animations objectForKey:key], error);
    };
    if (_animatedEmojiWaiters) {
        [_animatedEmojiWaiters addObject:[[waiter copy] autorelease]];
        return;
    }
    _animatedEmojiWaiters = [[NSMutableArray alloc] initWithObjects:[[waiter copy] autorelease], nil];
    [_session loadAnimatedEmojiStickers:^(NSArray *stickers, NSString *error) {
        if (stickers) {
            NSMutableDictionary *animations = [NSMutableDictionary dictionaryWithCapacity:stickers.count];
            for (ExteriaSticker *sticker in stickers) {
                NSString *emoticon = [sticker.media.alt stringByReplacingOccurrencesOfString:@"\uFE0F" withString:@""];
                if (emoticon.length && ![animations objectForKey:emoticon]) [animations setObject:sticker forKey:emoticon];
            }
            _animatedEmoji = [animations copy];
        } else {
            NSLog(@"exteria: animated emoji pack did not load: %@", error);
            [_animatedEmojiError release];
            _animatedEmojiError = [(error ? error : @"INTERNAL") copy];
            /* a screenful of emoji must not repeat a failed RPC for every visible row */
            _animatedEmojiRetryAfter = [NSDate timeIntervalSinceReferenceDate] + 30;
        }
        NSArray *waiters = [_animatedEmojiWaiters autorelease];
        _animatedEmojiWaiters = nil;
        for (void (^done)(NSDictionary *, NSString *) in waiters) done(_animatedEmoji, _animatedEmoji ? nil : _animatedEmojiError);
    }];
}

@end
