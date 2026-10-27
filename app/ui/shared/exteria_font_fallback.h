#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>

/* fonts for the characters that neither the app's font nor the system's own fonts can draw, so that styled
   letters, rare symbols and scripts the system lacks never show as a box */
void ExteriaApplyFontFallback(NSMutableAttributedString *string, CTFontRef base, CGFloat size);

/* for a short label that carries no entities, such as the name of a person */
void ExteriaDropUndrawableCharacters(NSMutableAttributedString *string, CTFontRef base);
