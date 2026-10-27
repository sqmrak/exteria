#import <Foundation/Foundation.h>

/* what the app sent and received, kept across launches; main thread only */

typedef struct ExteriaTrafficTotals {
    unsigned long long sent[2];         /* 0 Wi-Fi, 1 mobile */
    unsigned long long received[2];
    NSTimeInterval since;               /* when the counting began, or was reset */
} ExteriaTrafficTotals;

/* once at launch: names the network the connections run on and flushes the counters every half minute */
void ExteriaTrafficStart(void);
/* whether the phone is on the mobile network, which is when no Wi-Fi interface has an address */
BOOL ExteriaNetworkOnCellular(void);
/* adds what the sockets counted since the last call to the totals, and says the network class for what follows */
void ExteriaTrafficFlush(void);
ExteriaTrafficTotals ExteriaTrafficRead(void);
void ExteriaTrafficReset(void);
