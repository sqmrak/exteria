#import <UIKit/UIKit.h>

/* the Shiro screens follow Material 3 Expressive: tonal surfaces from one raspberry seed, Rubik for every text,
   large rounded shapes, springy motion */

UIColor *ExteriaShiroColorSurface(void);
/* the plate of the account */
UIColor *ExteriaShiroColorSurfaceContainer(void);
/* the resting face of the power shape and the fill of quiet buttons */
UIColor *ExteriaShiroColorSurfaceHighest(void);
UIColor *ExteriaShiroColorOnSurface(void);
UIColor *ExteriaShiroColorOnSurfaceVariant(void);
UIColor *ExteriaShiroColorOutline(void);
UIColor *ExteriaShiroColorPrimary(void);
UIColor *ExteriaShiroColorOnPrimary(void);
UIColor *ExteriaShiroColorPrimaryContainer(void);
UIColor *ExteriaShiroColorOnPrimaryContainer(void);
UIColor *ExteriaShiroColorSecondaryContainer(void);
UIColor *ExteriaShiroColorOnSecondaryContainer(void);
UIColor *ExteriaShiroColorError(void);
UIColor *ExteriaShiroColorErrorContainer(void);
UIColor *ExteriaShiroColorOnErrorContainer(void);

/* the colors one lap of the shimmering title passes through, the first one repeated at the end is left to the caller */
NSArray *ExteriaShiroShimmerColors(void);

/* Rubik at the weight of the Material type scale; the system face stands in where the font file is missing from the bundle */
UIFont *ExteriaShiroFontDisplay(CGFloat size);
UIFont *ExteriaShiroFontBody(CGFloat size, BOOL medium);

/* the size of "1.2 MB" style text for a byte count */
NSString *ExteriaShiroByteText(unsigned long long bytes);
