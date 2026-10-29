#import "exteria_dialog.h"
#import "exteria_session.h"
#import "exteria_star_gift.h"

/* the gift Exteria puts on the profiles of its developers, as it puts a mark after their names: it is made here and not by the server, so everybody who runs
   the app sees it, and it stands before every gift of the profile, pinned. its sender is @sqmrak, with the name and the picture the server has for him.
   empty for anyone else, for a chat that is not a person, and for a folder of gifts.
   they are made as the unique gifts of the server are: a number of their own that counts from 1, a model, a symbol and a backdrop, the backdrop drawn in soft
   expressive shapes (ExteriaGiftBackdropView.expressive) in colors of their own */
NSArray *ExteriaCustomGiftsForDialog(ExteriaDialog *owner);

/* "#001": the number of a gift of the app, in the three digits it is written with */
NSString *ExteriaCustomGiftNumberText(int32_t number);

/* whether the profile gets the gift and the sender is not known yet: the feed asks for him before it builds the gift */
BOOL ExteriaCustomGiftNeedsSender(ExteriaDialog *owner);
/* asks the server who @sqmrak is, once, and keeps the answer for the run; done runs on the main thread, also when he could not be had (the gift then names him
   without a picture) */
void ExteriaCustomGiftLoadSender(ExteriaSession *session, void (^done)(void));
