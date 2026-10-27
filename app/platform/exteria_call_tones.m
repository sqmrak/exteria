#import "exteria_call_tones.h"

#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>

/* looked up at run time like the other AVFoundation classes: the arm64 slice is linked against an sdk where AVAudioPlayer lives in AVFAudio, which ios 10
   does not have */
static id ExteriaTonePlayer;

typedef struct {
    NSString *name;
    NSString *type;
    /* AVAudioPlayer loops after the first play, so -1 is for ever and 2 is three plays */
    NSInteger loops;
    NSTimeInterval seconds;
} ExteriaToneSpec;

static ExteriaToneSpec ExteriaToneFor(ExteriaCallTone tone) {
    switch (tone) {
    case ExteriaCallToneRingback: return (ExteriaToneSpec){@"voip_ringback", @"caf", -1, 0};
    case ExteriaCallToneConnecting: return (ExteriaToneSpec){@"voip_connecting", @"mp3", -1, 0};
    case ExteriaCallToneBusy: return (ExteriaToneSpec){@"voip_busy", @"caf", 2, 3.0};
    case ExteriaCallToneFailed: return (ExteriaToneSpec){@"voip_fail", @"caf", 0, 2.05};
    case ExteriaCallToneEnded: return (ExteriaToneSpec){@"voip_end", @"caf", 0, 1.2};
    }
    return (ExteriaToneSpec){nil, nil, 0, 0};
}

NSTimeInterval ExteriaCallToneDuration(ExteriaCallTone tone) {
    return ExteriaToneFor(tone).seconds;
}

void ExteriaCallToneStop(void) {
    [ExteriaTonePlayer stop];
    [ExteriaTonePlayer release];
    ExteriaTonePlayer = nil;
}

void ExteriaCallToneStart(ExteriaCallTone tone) {
    ExteriaToneSpec spec = ExteriaToneFor(tone);
    ExteriaCallToneStop();
    NSString *path = spec.name ? [[NSBundle mainBundle] pathForResource:spec.name ofType:spec.type] : nil;
    Class playerClass = NSClassFromString(@"AVAudioPlayer");
    if (!path || !playerClass) {
        NSLog(@"exteria: the call tone %@ is not available", spec.name);
        return;
    }
    NSError *error = nil;
    id player = [[playerClass alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
    if (!player) {
        NSLog(@"exteria: the call tone %@ would not open: %@", spec.name, error);
        return;
    }
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(player, @selector(setNumberOfLoops:), spec.loops);
    ((BOOL (*)(id, SEL))objc_msgSend)(player, @selector(prepareToPlay));
    /* the class is found by name, so the compiler has no one declaration to take play from: it is AVAudioPlayer's, which answers whether it started */
    if (!((BOOL (*)(id, SEL))objc_msgSend)(player, @selector(play))) NSLog(@"exteria: the call tone %@ would not play", spec.name);
    ExteriaTonePlayer = player;
}
