#import <UIKit/UIKit.h>

#import "exteria_symbol.h"
#include "exteria_motion.h"

/* the bars and cards the photo and video editors set over the picture. in the modern look a card floats clear of the edges with rounded corners and blurs the picture
   behind it (a dark system blur where UIVisualEffectView exists, ios 8 and later, found by class so the older slices never link it, and a dark translucent plate
   before that); in the classic look it is the toolbar of the old system, edge to edge. subviews go to content */
@interface ExteriaEditorPanel : UIView
@property (nonatomic, readonly) UIView *content;
@property (nonatomic, readonly) BOOL floating;
@end

typedef enum {
    /* an icon over a short caption, for a row of tools */
    ExteriaEditorButtonTool,
    /* a circle with an icon only */
    ExteriaEditorButtonRound,
    /* a capsule with a caption, and an icon before it when there is one */
    ExteriaEditorButtonPill,
    /* the same capsule filled with the accent of the app, for the button that finishes the work */
    ExteriaEditorButtonAccent
} ExteriaEditorButtonStyle;

/* a button of the editors. it shrinks under the finger and springs back, lights up (accent tint behind it) while lit, dims when disabled, and swaps its icon with a
   short scale and fade. the classic look has no plates: white marks that turn blue when lit */
@interface ExteriaEditorButton : UIControl
- (id)initWithStyle:(ExteriaEditorButtonStyle)style symbol:(ExteriaSymbol)symbol title:(NSString *)title;
/* a button with a caption only */
- (id)initWithStyle:(ExteriaEditorButtonStyle)style title:(NSString *)title;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign, getter=isLit) BOOL lit;
- (void)setLit:(BOOL)lit animated:(BOOL)animated;
- (void)setSymbol:(ExteriaSymbol)symbol animated:(BOOL)animated;
- (void)setTitle:(NSString *)title animated:(BOOL)animated;
/* the icon turns a quarter, or flips over, and settles with a spring; for rotate and mirror */
- (void)playQuarterTurn;
- (void)playFlip;
@end

/* the factor the sizes of the bars and the buttons of the editors are multiplied by: an ipad shows them a quarter larger, a phone as drawn */
CGFloat ExteriaEditorScale(void);
/* shows or hides a card or a row: it slides by distance (positive is down) and fades, springs in and leaves fast, and does not take touches while it is away */
void ExteriaEditorPresent(UIView *view, BOOL shown, CGFloat distance);
/* puts views in one after another, each rising from distance below and fading in, step seconds apart; the views are already where they belong */
void ExteriaEditorRise(NSArray *views, CGFloat distance, NSTimeInterval step);
/* a small pop of a view, to say that its value changed */
void ExteriaEditorPop(UIView *view);
