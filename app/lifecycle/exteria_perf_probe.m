#import "exteria_perf_probe.h"

#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <pthread.h>

@interface ExteriaPerfProbe : NSObject {
    CADisplayLink *_link;
    double _windowStart;
    int _frames;
    int _slow;
    double _worstGap;
    double _last;
}
@end

static ExteriaPerfProbe *probe;
static volatile double ExteriaHeartbeat;
#if defined(__arm__)
static mach_port_t ExteriaMainThread;
#endif

#if defined(__arm__)
/* two words at an address of this process, read through the kernel so that a frame pointer that points nowhere
   gives a failure and not a crash of the sampler */
static BOOL ExteriaReadFrame(uintptr_t address, uintptr_t words[2]) {
    vm_size_t got = 0;
    return vm_read_overwrite(mach_task_self(), (vm_address_t)address, 2 * sizeof(uintptr_t), (vm_address_t)words, &got) == KERN_SUCCESS && got == 2 * sizeof(uintptr_t);
}

/* while the main thread has not ticked for 30 ms, a helper thread freezes it every few milliseconds and writes
   where it stands */
static void *ExteriaSampler(void *unused) {
    (void)unused;
    intptr_t slide = _dyld_get_image_vmaddr_slide(0);
    double lastSample = 0;
    for (;;) {
        usleep(5000);
        double now = CACurrentMediaTime();
        if (ExteriaHeartbeat == 0 || now - ExteriaHeartbeat < 0.030 || now - lastSample < 0.015) continue;
        lastSample = now;
        if (thread_suspend(ExteriaMainThread) != KERN_SUCCESS) continue;
        arm_thread_state_t state;
        mach_msg_type_number_t count = ARM_THREAD_STATE_COUNT;
        char line[1024];
        int length = 0;
        if (thread_get_state(ExteriaMainThread, ARM_THREAD_STATE, (thread_state_t)&state, &count) == KERN_SUCCESS) {
            uintptr_t addresses[40];
            int n = 0;
            addresses[n++] = state.__pc;
            addresses[n++] = state.__lr;
            uintptr_t *frame = (uintptr_t *)state.__r[7];
            for (int depth = 0; depth < 37 && frame && ((uintptr_t)frame & 3) == 0 && (uintptr_t)frame > 0x1000; ++depth) {
                uintptr_t words[2];
                if (!ExteriaReadFrame((uintptr_t)frame, words)) break;
                addresses[n++] = words[1];
                if (words[0] <= (uintptr_t)frame) break;
                frame = (uintptr_t *)words[0];
            }
            length = snprintf(line, sizeof(line), "stall %.0f ms sample:", (now - ExteriaHeartbeat) * 1000);
            for (int i = 0; i < n && length < (int)sizeof(line) - 12; ++i) length += snprintf(line + length, sizeof(line) - (size_t)length, " %lx", (unsigned long)(addresses[i] - (uintptr_t)slide));
        }
        thread_resume(ExteriaMainThread);
        if (length > 0) ExteriaPerfLine([NSString stringWithUTF8String:line]);
    }
    return NULL;
}
#endif
static NSMutableDictionary *sums;
static BOOL ExteriaPerfOn;

double ExteriaPerfNow(void) { return CACurrentMediaTime(); }

void ExteriaPerfLine(NSString *line) {
    NSString *path = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"exteria-perf.log"];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    [handle seekToEndOfFile];
    [handle writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

void ExteriaPerfRecord(const char *name, double seconds) {
    if (!ExteriaPerfOn) return;
    if (!sums) sums = [[NSMutableDictionary alloc] init];
    NSString *key = [NSString stringWithUTF8String:name];
    NSMutableArray *entry = [sums objectForKey:key];
    if (!entry) {
        entry = [NSMutableArray arrayWithObjects:[NSNumber numberWithInt:0], [NSNumber numberWithDouble:0], [NSNumber numberWithDouble:0], nil];
        [sums setObject:entry forKey:key];
    }
    int count = [[entry objectAtIndex:0] intValue] + 1;
    double total = [[entry objectAtIndex:1] doubleValue] + seconds;
    double worst = MAX([[entry objectAtIndex:2] doubleValue], seconds);
    [entry replaceObjectAtIndex:0 withObject:[NSNumber numberWithInt:count]];
    [entry replaceObjectAtIndex:1 withObject:[NSNumber numberWithDouble:total]];
    [entry replaceObjectAtIndex:2 withObject:[NSNumber numberWithDouble:worst]];
    if (count % 15 == 0) {
        ExteriaPerfLine([NSString stringWithFormat:@"%@ n=%d avg %.1f ms worst %.1f ms", key, count, total / count * 1000, worst * 1000]);
        [sums removeObjectForKey:key];
    }
}

@implementation ExteriaPerfProbe

- (void)start {
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)tick:(CADisplayLink *)link {
    double now = link.timestamp;
    ExteriaHeartbeat = CACurrentMediaTime();
    if (_last > 0) {
        double gap = now - _last;
        if (gap > 0.025) ++_slow;
        _worstGap = MAX(_worstGap, gap);
    }
    _last = now;
    ++_frames;
    if (_windowStart == 0) _windowStart = now;
    if (now - _windowStart >= 1.0) {
        /* an idle screen draws nothing, so only a second with a slow frame is worth a line */
        if (_slow > 0) ExteriaPerfLine([NSString stringWithFormat:@"%d frames in %.2f s, %d slow, worst gap %.0f ms", _frames, now - _windowStart, _slow, _worstGap * 1000]);
        _windowStart = now;
        _frames = 0;
        _slow = 0;
        _worstGap = 0;
    }
}

@end

void ExteriaPerfStart(void) {
    if (probe) return;
    /* a display link on the main thread keeps the screen drawing at 60 Hz and the sampler wakes 200 times a second, so both stay off unless asked for */
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"exteria.perf"]) return;
    ExteriaPerfOn = YES;
    probe = [[ExteriaPerfProbe alloc] init];
    [probe start];
#if defined(__arm__)
    ExteriaMainThread = mach_thread_self();
    pthread_t sampler;
    pthread_create(&sampler, NULL, ExteriaSampler, NULL);
#endif
}
