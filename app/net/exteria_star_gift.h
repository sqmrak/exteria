#import <Foundation/Foundation.h>

#import "exteria_dialog.h"
#import "exteria_message.h"
#import "exteria_person.h"
#import "exteria_photo.h"
#import "exteria_session.h"

#include "exteria_gifts.h"

/* a gift of the catalog or a unique one, as the screens draw it; built off the main thread */
@interface ExteriaStarGift : NSObject {
    exteria_gift _gift;
    NSString *_title;
    NSString *_slug;
    NSString *_model;
    NSString *_pattern;
    NSString *_backdrop;
    NSString *_ownerName;
    ExteriaMedia *_sticker;
    ExteriaMedia *_patternSticker;
}
+ (ExteriaStarGift *)giftWithRow:(const exteria_gift *)row;
@property (nonatomic, readonly) exteria_gift row;
@property (nonatomic, readonly) long long giftId;
@property (nonatomic, readonly) BOOL unique;
@property (nonatomic, readonly) BOOL limited;
@property (nonatomic, readonly) BOOL soldOut;
@property (nonatomic, readonly) BOOL birthday;
@property (nonatomic, readonly) BOOL requiresPremium;
/* sold by bidding, which this client cannot do */
@property (nonatomic, readonly) BOOL auction;
@property (nonatomic, readonly) BOOL canBuy;
@property (nonatomic, readonly) long long stars;
@property (nonatomic, readonly) long long convertStars;
@property (nonatomic, readonly) long long upgradeStars;
/* a limited gift: how many are left of how many; a unique one: how many exist now of how many can */
@property (nonatomic, readonly) int32_t remains;
@property (nonatomic, readonly) int32_t total;
@property (nonatomic, readonly) int32_t number;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *slug;
@property (nonatomic, readonly, copy) NSString *model;
@property (nonatomic, readonly, copy) NSString *pattern;
@property (nonatomic, readonly, copy) NSString *backdrop;
@property (nonatomic, readonly, copy) NSString *ownerName;
@property (nonatomic, readonly) long long ownerId;
@property (nonatomic, readonly) BOOL hasBackdropColors;
/* the colors of a unique gift's backdrop as 0xRRGGBB */
@property (nonatomic, readonly) uint32_t backdropCenter;
@property (nonatomic, readonly) uint32_t backdropEdge;
@property (nonatomic, readonly) uint32_t backdropText;
/* the color of the pattern symbols, and the symbol itself; nil when the gift has none */
@property (nonatomic, readonly) uint32_t backdropPattern;
@property (nonatomic, readonly, retain) ExteriaMedia *patternSticker;
/* how rare the model, the pattern and the backdrop are in thousandths, zero when unknown */
@property (nonatomic, readonly) int32_t modelPermille;
@property (nonatomic, readonly) int32_t patternPermille;
@property (nonatomic, readonly) int32_t backdropPermille;
@property (nonatomic, readonly, retain) ExteriaMedia *sticker;
@end

/* a gift on a profile and what its owner can do with it */
@interface ExteriaSavedGift : NSObject {
    ExteriaStarGift *_gift;
    NSString *_fromName;
    NSString *_note;
    NSArray *_noteEntities;
    ExteriaPerson *_fromPerson;
    long long _fromId;
    int32_t _date;
    int32_t _messageId;
    BOOL _nameHidden;
    BOOL _hidden;
    BOOL _canUpgrade;
    BOOL _pinned;
    BOOL _refunded;
    long long _convertStars;
    long long _upgradeStars;
    long long _transferStars;
    int32_t _canTransferAt;
}
+ (ExteriaSavedGift *)savedGiftWithRow:(const exteria_saved_gift *)row;
@property (nonatomic, readonly, retain) ExteriaStarGift *gift;
@property (nonatomic, readonly) long long fromId;
@property (nonatomic, readonly, copy) NSString *fromName;
/* the sender as the answer carries them, nil when they hid their name or the answer lacks them */
@property (nonatomic, readonly, retain) ExteriaPerson *fromPerson;
@property (nonatomic, readonly) ExteriaPhoto *fromPhoto;
@property (nonatomic, readonly, copy) NSString *note;
@property (nonatomic, readonly, retain) NSArray *noteEntities;
@property (nonatomic, readonly) int32_t date;
/* names the gift to the server; zero for a gift on a profile that is not ours */
@property (nonatomic, readonly) int32_t messageId;
@property (nonatomic, readonly) BOOL nameHidden;
/* hidden from the profile */
@property (nonatomic, readonly) BOOL hidden;
@property (nonatomic, readonly) BOOL canUpgrade;
@property (nonatomic, readonly) BOOL pinned;
@property (nonatomic, readonly) long long convertStars;
/* whether conversion is still offered at this time */
- (BOOL)canConvertAt:(int64_t)now period:(int32_t)period;
@property (nonatomic, readonly) long long upgradeStars;
@property (nonatomic, readonly) long long transferStars;
@property (nonatomic, readonly) int32_t canTransferAt;
@end

typedef enum {
    ExteriaPaymentGiftSend,
    ExteriaPaymentGiftUpgrade,
    ExteriaPaymentGiftTransfer
} ExteriaPaymentKind;

/* what the server asked for a gift action: the form is valid for a short while, so pay it soon after quoting */
@interface ExteriaPaymentQuote : NSObject {
@public
    ExteriaPaymentKind kind;
    long long formId;
    long long stars;
    long long giftId;
    int32_t messageId;
    BOOL hideName;
    BOOL includeUpgrade;
    BOOL keepDetails;
    exteria_peer_ref peer;
    NSString *note;
}
@property (nonatomic, readonly) long long stars;
@end

typedef void (^ExteriaSavedGiftsCompletion)(NSArray *gifts, NSInteger total, NSString *nextOffset, NSString *errorName);

/* gifts: the catalog, the gifts of a profile, the star balance */
@interface ExteriaSession (Gifts)

/* ExteriaStarGift items that can be sent, the ones that sold out last */
- (void)loadGiftCatalog:(ExteriaListCompletion)completion;
/* one page of the gifts on the profile of a user, newest first; offset is nil for the first page and the previous nextOffset
   after that, which is nil on the last page */
- (void)loadSavedGiftsOfDialog:(ExteriaDialog *)dialog offset:(NSString *)offset completion:(ExteriaSavedGiftsCompletion)completion;
- (void)loadStarsBalance:(void (^)(long long stars, NSString *errorName))completion;
/* the current conversion window from Telegram's app configuration */
- (void)loadGiftConvertPeriod:(void (^)(int32_t seconds, NSString *errorName))completion;

/* asks the server what a send, an upgrade or a hand over costs */
- (void)quoteSendingGift:(ExteriaStarGift *)gift toDialog:(ExteriaDialog *)dialog note:(NSString *)note hideName:(BOOL)hideName
          includeUpgrade:(BOOL)includeUpgrade completion:(void (^)(ExteriaPaymentQuote *quote, NSString *errorName))completion;
- (void)quoteUpgradingGift:(ExteriaSavedGift *)gift keepDetails:(BOOL)keepDetails
                completion:(void (^)(ExteriaPaymentQuote *quote, NSString *errorName))completion;
- (void)quoteTransferringGift:(ExteriaSavedGift *)gift toDialog:(ExteriaDialog *)dialog
                   completion:(void (^)(ExteriaPaymentQuote *quote, NSString *errorName))completion;
/* pays a quote in stars; the balance is checked first */
- (void)payQuote:(ExteriaPaymentQuote *)quote completion:(void (^)(NSString *errorName))completion;

/* what the owner of a gift can do without paying */
- (void)setGift:(ExteriaSavedGift *)gift hidden:(BOOL)hidden completion:(void (^)(NSString *errorName))completion;
- (void)convertGift:(ExteriaSavedGift *)gift completion:(void (^)(NSString *errorName))completion;
- (void)upgradeGift:(ExteriaSavedGift *)gift keepDetails:(BOOL)keepDetails completion:(void (^)(NSString *errorName))completion;
- (void)transferGift:(ExteriaSavedGift *)gift toDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;
/* the gifts that stay on top of the profile, at most six */
- (void)pinGifts:(NSArray *)gifts completion:(void (^)(NSString *errorName))completion;

@end
