#import "exteria_crash_log.h"

#import <UIKit/UIKit.h>

#include <execinfo.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <pthread.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <signal.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/ucontext.h>
#include <time.h>
#include <unistd.h>

#define LOG_LIMIT (64 * 1024)
#define FRAMES_MAX 48
#define ALT_STACK_BYTES (64 * 1024)
#define FRAME_SCAN_BYTES 4096

/* set before the handlers are installed and only read by them */
static char sPath[1024];
static char sMarker[1024];
static uintptr_t sTextLow;
static uintptr_t sTextHigh;
static intptr_t sSlide;
static char sBuild[33];
static NSUncaughtExceptionHandler *sPreviousHandler;

/* nothing below allocates or takes a lock: a handler runs on a thread that may be in the middle of malloc */
static void ExteriaPut(int fd, const char *text) {
    size_t length = strlen(text);
    while (length) {
        ssize_t done = write(fd, text, length);
        if (done <= 0) return;
        text += done;
        length -= (size_t)done;
    }
}

static void ExteriaPutNumber(int fd, unsigned long long value, unsigned base) {
    char digits[24];
    int at = (int)sizeof(digits) - 1;
    digits[at] = 0;
    do {
        digits[--at] = "0123456789abcdef"[value % base];
        value /= base;
    } while (value && at > 0);
    ExteriaPut(fd, digits + at);
}

static void ExteriaPutHex(int fd, unsigned long long value) {
    ExteriaPut(fd, " 0x");
    ExteriaPutNumber(fd, value, 16);
}

static void ExteriaPutImage(int fd) {
    ExteriaPut(fd, " slide");
    ExteriaPutHex(fd, (unsigned long long)(uintptr_t)sSlide);
    /* a log can survive an update, so the next run's report header may name a different binary */
    ExteriaPut(fd, " build ");
    ExteriaPut(fd, sBuild[0] ? sBuild : "unknown");
}

static void ExteriaCrashSignal(int signal_number, siginfo_t *info, void *context) {
    (void)context;
    int fd = open(sPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        ExteriaPut(fd, "crash at ");
        ExteriaPutNumber(fd, (unsigned long long)time(NULL), 10);
        ExteriaPut(fd, " signal ");
        ExteriaPutNumber(fd, (unsigned long long)signal_number, 10);
        ExteriaPut(fd, " code ");
        ExteriaPutNumber(fd, (unsigned long long)(info ? info->si_code : 0), 10);
        ExteriaPut(fd, " fault");
        ExteriaPutHex(fd, (unsigned long long)(uintptr_t)(info ? info->si_addr : NULL));
        ExteriaPutImage(fd);
        ExteriaPut(fd, "\nstack");
        void *frames[FRAMES_MAX];
        int count = backtrace(frames, FRAMES_MAX);
        for (int i = 0; i < count; ++i) ExteriaPutHex(fd, (unsigned long long)((uintptr_t)frames[i] - (uintptr_t)sSlide));
        ExteriaPut(fd, "\n");
        close(fd);
    }
    /* the handler was installed with SA_RESETHAND, so leaving it runs the faulting instruction again and the system makes its own report; a signal sent with
       raise or abort needs to be sent again */
    if (signal_number == SIGABRT || signal_number == SIGTRAP) {
        signal(signal_number, SIG_DFL);
        raise(signal_number);
    }
}

/* the __TEXT range and UUID of this binary are read before any signal handler is installed */
static void ExteriaFindImage(void) {
    const struct mach_header *header = _dyld_get_image_header(0);
    if (!header) return;
#ifdef __LP64__
    const struct load_command *command = (const struct load_command *)((const char *)header + sizeof(struct mach_header_64));
#else
    const struct load_command *command = (const struct load_command *)((const char *)header + sizeof(struct mach_header));
#endif
    for (uint32_t i = 0; i < header->ncmds; ++i) {
#ifdef __LP64__
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            if (strcmp(segment->segname, "__TEXT") == 0) {
                sTextLow = (uintptr_t)header;
                sTextHigh = sTextLow + (uintptr_t)segment->vmsize;
            }
        }
#else
        if (command->cmd == LC_SEGMENT) {
            const struct segment_command *segment = (const struct segment_command *)command;
            if (strcmp(segment->segname, "__TEXT") == 0) {
                sTextLow = (uintptr_t)header;
                sTextHigh = sTextLow + (uintptr_t)segment->vmsize;
            }
        }
#endif
        if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
            const struct uuid_command *identifier = (const struct uuid_command *)command;
            static const char hex[] = "0123456789abcdef";
            for (size_t j = 0; j < 16; ++j) {
                sBuild[j * 2] = hex[identifier->uuid[j] >> 4];
                sBuild[j * 2 + 1] = hex[identifier->uuid[j] & 15];
            }
            sBuild[32] = 0;
        }
        command = (const struct load_command *)((const char *)command + command->cmdsize);
    }
}

/* a chained handler may pass invalid context pointers, so the kernel copies them before any field is read */
static BOOL ExteriaCopyCrashMemory(uintptr_t address, void *out, size_t size) {
    vm_size_t copied = 0;
    if (address < 4096 || !size || address > UINTPTR_MAX - size) return NO;
    return vm_read_overwrite(mach_task_self(), (vm_address_t)address, (vm_size_t)size, (vm_address_t)out, &copied) == KERN_SUCCESS && copied == size;
}

/* ios 6.1.3 armv7 calls the handler with (signal, 1, signal) instead of the siginfo and ucontext pointers, so both
   copies fail. the kernel still lays the frame out as siginfo, ucontext, mcontext above the handler's own frame; it is
   found by the ucontext that names a mcontext right behind it and the siginfo before it that names the signal */
static BOOL ExteriaFindSignalFrame(int signal_number, siginfo_t *info, void *context, siginfo_t *details, ucontext_t *saved, _STRUCT_MCONTEXT *machine) {
    if (ExteriaCopyCrashMemory((uintptr_t)info, details, sizeof(*details)) && ExteriaCopyCrashMemory((uintptr_t)context, saved, sizeof(*saved)) &&
        ExteriaCopyCrashMemory((uintptr_t)saved->uc_mcontext, machine, sizeof(*machine))) return YES;
    uintptr_t start = (uintptr_t)__builtin_frame_address(0);
    for (uintptr_t at = (start + sizeof(uintptr_t) - 1) & ~(uintptr_t)(sizeof(uintptr_t) - 1); at - start < FRAME_SCAN_BYTES; at += sizeof(uintptr_t)) {
        if (!ExteriaCopyCrashMemory(at, saved, sizeof(*saved)) || saved->uc_mcsize != sizeof(*machine)) continue;
        uintptr_t mcontext = (uintptr_t)saved->uc_mcontext;
        if (mcontext <= at || mcontext - at > 1024) continue;
        if (!ExteriaCopyCrashMemory(at - sizeof(*details), details, sizeof(*details)) || details->si_signo != signal_number) continue;
        if (ExteriaCopyCrashMemory(mcontext, machine, sizeof(*machine))) return YES;
    }
    return NO;
}

static void ExteriaFaultSignal(int signal_number, siginfo_t *info, void *context) {
    int fd = open(sPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        ExteriaPut(fd, "fault at ");
        ExteriaPutNumber(fd, (unsigned long long)time(NULL), 10);
        ExteriaPut(fd, " signal ");
        ExteriaPutNumber(fd, (unsigned long long)signal_number, 10);
        ExteriaPut(fd, pthread_main_np() ? " main" : " worker");
        ExteriaPutImage(fd);
        siginfo_t details;
        ucontext_t saved;
        _STRUCT_MCONTEXT machine;
        if (ExteriaFindSignalFrame(signal_number, info, context, &details, &saved, &machine)) {
            ExteriaPut(fd, " address");
            ExteriaPutHex(fd, (uintptr_t)details.si_addr);
            uintptr_t pc, lr, sp, fp;
#if defined(__LP64__)
            pc = (uintptr_t)machine.__ss.__pc;
            lr = (uintptr_t)machine.__ss.__lr;
            sp = (uintptr_t)machine.__ss.__sp;
            fp = (uintptr_t)machine.__ss.__fp;
#else
            pc = machine.__ss.__pc;
            lr = machine.__ss.__lr;
            sp = machine.__ss.__sp;
            fp = machine.__ss.__r[7];
#endif
            ExteriaPut(fd, " pc"); ExteriaPutHex(fd, pc);
            ExteriaPut(fd, " lr"); ExteriaPutHex(fd, lr);
            ExteriaPut(fd, " sp"); ExteriaPutHex(fd, sp);
            uintptr_t addresses[FRAMES_MAX + 2] = {pc, lr};
            int count = 2;
            /* the handler runs on an alternate stack; only the interrupted thread's frame chain holds its callers */
            for (int i = 0; i < FRAMES_MAX && fp >= sp && fp - sp < 8 * 1024 * 1024 && fp % sizeof(uintptr_t) == 0; ++i) {
                uintptr_t frame[2];
                if (!ExteriaCopyCrashMemory(fp, frame, sizeof(frame))) break;
                addresses[count++] = frame[1];
                if (frame[0] <= fp) break;
                fp = frame[0];
            }
            ExteriaPut(fd, "\nstack");
            for (int i = 0; i < count; ++i)
                if (addresses[i] >= sTextLow && addresses[i] < sTextHigh) ExteriaPutHex(fd, addresses[i] - (uintptr_t)sSlide);
            ExteriaPut(fd, "\nraw stack");
            for (int i = 0; i < count; ++i) ExteriaPutHex(fd, addresses[i]);
        } else {
            ExteriaPut(fd, " context unavailable");
        }
        ExteriaPut(fd, "\n");
        close(fd);
    }
    signal(signal_number, SIG_DFL);
}

static void ExteriaCrashException(NSException *exception) {
    int fd = open(sPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        ExteriaPut(fd, "exception at ");
        ExteriaPutNumber(fd, (unsigned long long)time(NULL), 10);
        ExteriaPutImage(fd);
        ExteriaPut(fd, "\n");
        ExteriaPut(fd, exception.name.UTF8String ? exception.name.UTF8String : "?");
        ExteriaPut(fd, ": ");
        ExteriaPut(fd, exception.reason.UTF8String ? exception.reason.UTF8String : "?");
        ExteriaPut(fd, "\nstack");
        for (NSNumber *address in exception.callStackReturnAddresses) ExteriaPutHex(fd, (unsigned long long)(address.unsignedLongLongValue - (unsigned long long)sSlide));
        ExteriaPut(fd, "\nsymbols\n");
        for (NSString *symbol in exception.callStackSymbols) {
            const char *line = [symbol UTF8String];
            if (line) { ExteriaPut(fd, line); ExteriaPut(fd, "\n"); }
        }
        close(fd);
    }
    if (sPreviousHandler) sPreviousHandler(exception);
}

void ExteriaCrashLogStart(void) {
    static BOOL started;
    if (started) return;
    started = YES;
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    const char *path = [[caches stringByAppendingPathComponent:@"exteria-crash.log"] fileSystemRepresentation];
    if (!path || strlen(path) >= sizeof(sPath)) {
        NSLog(@"exteria: the crash log path does not fit, no crash record");
        return;
    }
    strcpy(sPath, path);
    struct stat info;
    if (stat(sPath, &info) == 0 && info.st_size > LOG_LIMIT) unlink(sPath);
    sSlide = _dyld_get_image_vmaddr_slide(0);

    /* a stack of its own, so a crash from a stack overflow can still be written down */
    stack_t alternate;
    alternate.ss_sp = malloc(ALT_STACK_BYTES);
    alternate.ss_size = ALT_STACK_BYTES;
    alternate.ss_flags = 0;
    if (!alternate.ss_sp || sigaltstack(&alternate, NULL) != 0) NSLog(@"exteria: no alternate stack for the crash record");
    ExteriaFindImage();

    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = ExteriaCrashSignal;
    action.sa_flags = SA_SIGINFO | SA_RESETHAND | SA_ONSTACK;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGABRT, &action, NULL) != 0) NSLog(@"exteria: the crash record cannot catch signal %d", SIGABRT);
    /* the system's own reports of this app did not reach the phone's CrashReporter folder, so the faults are
       recorded here as well */
    action.sa_sigaction = ExteriaFaultSignal;
    action.sa_flags = SA_SIGINFO | SA_RESETHAND | SA_ONSTACK | SA_NODEFER;
    const int faults[] = {SIGSEGV, SIGBUS, SIGILL, SIGFPE};
    for (size_t i = 0; i < sizeof(faults) / sizeof(faults[0]); ++i) {
        if (sigaction(faults[i], &action, NULL) != 0) NSLog(@"exteria: the crash record cannot catch signal %d", faults[i]);
    }
    sPreviousHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(ExteriaCrashException);
}

#pragma mark memory

static unsigned long ExteriaResidentKilobytes(void) {
    struct task_basic_info info;
    mach_msg_type_number_t count = TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return 0;
    return (unsigned long)(info.resident_size / 1024);
}

static void ExteriaNote(const char *what, unsigned long number) {
    int fd = open(sPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    ExteriaPut(fd, what);
    ExteriaPut(fd, " at ");
    ExteriaPutNumber(fd, (unsigned long long)time(NULL), 10);
    ExteriaPut(fd, " resident ");
    ExteriaPutNumber(fd, number, 10);
    ExteriaPut(fd, " KB\n");
    close(fd);
}

/* a process that the system ends for its memory leaves no signal and no report */
void ExteriaCrashLogWatchMemory(void) {
    static BOOL watching;
    if (watching || !sPath[0]) return;
    watching = YES;
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    const char *marker = [[caches stringByAppendingPathComponent:@"exteria-running"] fileSystemRepresentation];
    if (!marker || strlen(marker) >= sizeof(sMarker)) return;
    strcpy(sMarker, marker);
    struct stat info;
    if (stat(sMarker, &info) == 0) ExteriaNote("previous run ended on screen", ExteriaResidentKilobytes());
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        (void)note;
        int fd = open(sMarker, O_WRONLY | O_CREAT, 0644);
        if (fd >= 0) close(fd);
    }];
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        (void)note;
        unlink(sMarker);
    }];
    [center addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        (void)note;
        ExteriaNote("memory warning", ExteriaResidentKilobytes());
    }];
}
