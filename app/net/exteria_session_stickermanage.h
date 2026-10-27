#import <Foundation/Foundation.h>

#import "exteria_session.h"

/* posted on the main thread after the installed sets were taken away or put in another order, so what keeps a copy of the list (the sticker panel) asks again */
extern NSString *const ExteriaStickerSetsDidChangeNotification;

/* the installed sticker sets of the account, from messages.uninstallStickerSet and messages.reorderStickerSets */
@interface ExteriaSession (StickerManage)

- (void)uninstallStickerSet:(ExteriaStickerSet *)set completion:(void (^)(NSString *errorName))completion;
/* puts a set into the installed ones; the notification above follows, so the sticker panel picks it up */
- (void)installStickerSet:(ExteriaStickerSet *)set completion:(void (^)(NSString *errorName))completion;
/* the set a sticker belongs to, by the id and hash its document names: the header (title, short name, whether it is installed) and the stickers in set order */
- (void)loadStickerPackWithId:(long long)setId accessHash:(long long)accessHash
                   completion:(void (^)(ExteriaStickerSet *set, NSArray *stickers, NSString *errorName))completion;
/* the trending sets of stickers, ExteriaStickerSet items, with installed set for the ones the account already has */
- (void)loadFeaturedStickerSets:(ExteriaListCompletion)completion;
/* the sets the account put into its archive, newest first, up to limit of them; total is how many the archive holds in all */
- (void)loadArchivedStickerSetsLimit:(int32_t)limit completion:(void (^)(NSArray *sets, int32_t total, NSString *errorName))completion;
/* puts the set first and leaves the others in the order they have in sets, which must be the list as the server gave it */
- (void)moveStickerSetToTop:(ExteriaStickerSet *)set among:(NSArray *)sets completion:(void (^)(NSString *errorName))completion;

@end
