#import "exteria_row_icon.h"

#import <QuartzCore/QuartzCore.h>

#define ICON_SIDE 32.0

static UIImageView *ExteriaIconSquare(UIImage *glyph, UIColor *color) {
    UIImageView *view = [[[UIImageView alloc] initWithFrame:CGRectMake(0, 0, ICON_SIDE, ICON_SIDE)] autorelease];
    view.backgroundColor = color;
    view.layer.cornerRadius = 8;
    view.contentMode = UIViewContentModeCenter;
    view.image = glyph;
    return view;
}

UIImageView *ExteriaRowIcon(ExteriaSymbol symbol, UIColor *color) {
    return ExteriaIconSquare(ExteriaSymbolImage(symbol, 20, [UIColor whiteColor]), color);
}
