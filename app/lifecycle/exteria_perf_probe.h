#import <Foundation/Foundation.h>

/* logs frame rate drops and the time cells take, to find what slows the chat list; it does nothing unless the user
   default exteria.perf is set (defaults write <bundle id> exteria.perf -bool YES over ssh), since its display link
   and sampler cost power */
void ExteriaPerfStart(void);
void ExteriaPerfRecord(const char *name, double seconds);
double ExteriaPerfNow(void);
/* appends a line to Caches/exteria-perf.log, which can be read over ssh when no usb log is attached */
void ExteriaPerfLine(NSString *line);
