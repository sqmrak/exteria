#import "exteria_voip_socket.h"

#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

/* the pair that makes a socket a VoIP socket */
typedef struct {
    CFReadStreamRef read;
    CFWriteStreamRef write;
} ExteriaVoipStreams;

BOOL ExteriaVoipSocketSupported(void) {
    /* asked from the worker and the main thread alike, so the answer is made once */
    static BOOL supported;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSInteger major = [[[UIDevice currentDevice] systemVersion] integerValue];
        supported = major >= 5 && major <= 6;
    });
    return supported;
}

static void ExteriaVoipStreamEvent(CFReadStreamRef stream, CFStreamEventType event, void *info) {
    (void)stream;
    (void)info;
    NSLog(@"exteria: the voip stream of the link reported event %lu", (unsigned long)event);
}

/* runs on the main thread, where the streams live; they own copy and close it with themselves */
static ExteriaVoipStreams *ExteriaVoipOpen(int copy) {
    ExteriaVoipStreams *streams = calloc(1, sizeof(*streams));
    if (!streams) {
        close(copy);
        return NULL;
    }
    CFStreamCreatePairWithSocket(NULL, (CFSocketNativeHandle)copy, &streams->read, &streams->write);
    if (!streams->read || !streams->write) {
        NSLog(@"exteria: cannot make streams for the link");
        close(copy);
        goto fail;
    }
    CFReadStreamSetProperty(streams->read, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    CFWriteStreamSetProperty(streams->write, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    /* the service type only takes on a stream that is not open yet */
    if (!CFReadStreamSetProperty(streams->read, kCFStreamNetworkServiceType, kCFStreamNetworkServiceTypeVoIP) ||
        !CFWriteStreamSetProperty(streams->write, kCFStreamNetworkServiceType, kCFStreamNetworkServiceTypeVoIP)) {
        NSLog(@"exteria: the system did not take the voip service type");
        goto fail;
    }
    CFStreamClientContext context = {0, NULL, NULL, NULL, NULL};
    CFReadStreamSetClient(streams->read, kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, ExteriaVoipStreamEvent, &context);
    CFReadStreamScheduleWithRunLoop(streams->read, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    CFWriteStreamScheduleWithRunLoop(streams->write, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    if (!CFReadStreamOpen(streams->read) || !CFWriteStreamOpen(streams->write)) {
        NSLog(@"exteria: the voip streams did not open");
        goto fail;
    }
    return streams;
fail:
    if (streams->read) CFRelease(streams->read);
    if (streams->write) CFRelease(streams->write);
    free(streams);
    return NULL;
}

static void ExteriaVoipClose(ExteriaVoipStreams *streams) {
    CFReadStreamSetClient(streams->read, 0, NULL, NULL);
    CFReadStreamUnscheduleFromRunLoop(streams->read, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    CFWriteStreamUnscheduleFromRunLoop(streams->write, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    CFReadStreamClose(streams->read);
    CFWriteStreamClose(streams->write);
    CFRelease(streams->read);
    CFRelease(streams->write);
    free(streams);
}

/* a slot the main thread fills, so a detach that follows an attach at once still finds the streams: the queue keeps their order */
typedef struct {
    ExteriaVoipStreams *streams;
} ExteriaVoipHandle;

void *ExteriaVoipSocketAttach(int fd) {
    if (fd < 0 || !ExteriaVoipSocketSupported()) return NULL;
    /* the connection also asks the kernel to probe an idle link, so a dead one is noticed while the app sleeps */
    int on = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &on, sizeof(on)) != 0) NSLog(@"exteria: SO_KEEPALIVE failed, errno %d", errno);
#ifdef TCP_KEEPALIVE
    int idle = 60;
    if (setsockopt(fd, IPPROTO_TCP, TCP_KEEPALIVE, &idle, sizeof(idle)) != 0) NSLog(@"exteria: TCP_KEEPALIVE failed, errno %d", errno);
#endif
    /* a copy of the descriptor, so the streams stay valid when the worker closes its own before they were made */
    int copy = dup(fd);
    if (copy < 0) {
        NSLog(@"exteria: dup of the link failed, errno %d", errno);
        return NULL;
    }
    ExteriaVoipHandle *handle = calloc(1, sizeof(*handle));
    if (!handle) {
        close(copy);
        return NULL;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ handle->streams = ExteriaVoipOpen(copy); });
    return handle;
}

void ExteriaVoipSocketDetach(void *opaque) {
    ExteriaVoipHandle *handle = opaque;
    if (!handle) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (handle->streams) ExteriaVoipClose(handle->streams);
        free(handle);
    });
}
