#import "exteria_proximity.h"

#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>

NSString *const ExteriaProximityDidChangeNotification = @"ExteriaProximityDidChange";

/* gravity along the screen's axis of view at which the phone counts as lying flat, in g: held to the ear it is tilted well past this */
#define FLAT_LIMIT 0.7
#define MOTION_INTERVAL 0.2

static NSInteger ExteriaProximityUsers;
static CMMotionManager *ExteriaMotion;

@interface ExteriaProximityRelay : NSObject
+ (ExteriaProximityRelay *)shared;
- (void)changed;
@end

@implementation ExteriaProximityRelay

+ (ExteriaProximityRelay *)shared {
    static ExteriaProximityRelay *relay;
    if (!relay) relay = [[ExteriaProximityRelay alloc] init];
    return relay;
}

- (void)changed {
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaProximityDidChangeNotification object:nil];
}

@end

BOOL ExteriaProximityAvailable(void) {
    static BOOL known, available;
    if (known) return available;
    known = YES;
    UIDevice *device = [UIDevice currentDevice];
    BOOL wasOn = device.proximityMonitoringEnabled;
    device.proximityMonitoringEnabled = YES;
    available = device.proximityMonitoringEnabled;
    device.proximityMonitoringEnabled = wasOn;
    return available;
}

BOOL ExteriaProximityStart(void) {
    UIDevice *device = [UIDevice currentDevice];
    if (ExteriaProximityUsers == 0) {
        device.proximityMonitoringEnabled = YES;
        /* a device with no sensor leaves the property off */
        if (!device.proximityMonitoringEnabled) return NO;
        [[NSNotificationCenter defaultCenter] addObserver:[ExteriaProximityRelay shared] selector:@selector(changed)
                                                     name:UIDeviceProximityStateDidChangeNotification object:nil];
        if ([CMMotionManager class]) {
            ExteriaMotion = [[CMMotionManager alloc] init];
            if (ExteriaMotion.accelerometerAvailable) {
                ExteriaMotion.accelerometerUpdateInterval = MOTION_INTERVAL;
                [ExteriaMotion startAccelerometerUpdates];
            }
        }
    }
    ++ExteriaProximityUsers;
    return YES;
}

void ExteriaProximityStop(void) {
    if (ExteriaProximityUsers == 0) return;
    if (--ExteriaProximityUsers > 0) return;
    [[NSNotificationCenter defaultCenter] removeObserver:[ExteriaProximityRelay shared] name:UIDeviceProximityStateDidChangeNotification object:nil];
    [UIDevice currentDevice].proximityMonitoringEnabled = NO;
    [ExteriaMotion stopAccelerometerUpdates];
    [ExteriaMotion release];
    ExteriaMotion = nil;
}

BOOL ExteriaProximityNear(void) {
    return ExteriaProximityUsers > 0 && [UIDevice currentDevice].proximityState;
}

BOOL ExteriaPhoneIsUpright(void) {
    CMAccelerometerData *sample = ExteriaMotion.accelerometerData;
    if (!sample) return YES;
    return fabs(sample.acceleration.z) < FLAT_LIMIT;
}
