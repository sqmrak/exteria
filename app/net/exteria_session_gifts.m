#import "exteria_session_internal.h"

#import "exteria_rpc.h"
#import "exteria_star_gift.h"

/* the server sends the text of a gift note as is, so the limit is the core's */
@implementation ExteriaSession (Gifts)

- (void)loadGiftConvertPeriod:(void (^)(int32_t, NSString *))completion {
    void (^done)(int32_t, NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        *request = exteria_tl_new_obj(arena, "help.getAppConfig");
        return *request ? exteria_tl_set_i32(arena, *request, "hash", 0) : EXTERIA_E_NOMEM;
    } handler:^(const exteria_mt_rpc_result *result) {
        int32_t period = 0;
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        if (!error && exteria_gift_convert_period_parse(result->value, &period) != EXTERIA_OK) error = @"CONFIG_INVALID";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(period, delivered); [done release]; }];
    }];
}

- (void)loadGiftCatalog:(ExteriaListCompletion)completion {
    ExteriaListCompletion done = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_gifts_request(arena, 0, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *gifts = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_gift *rows = calloc(EXTERIA_GIFTS_MAX, sizeof(*rows));
            size_t count = 0;
            int32_t hash = 0;
            exteria_status status = rows ? exteria_gifts_parse(result->value, rows, EXTERIA_GIFTS_MAX, &count, &hash) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                gifts = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [gifts addObject:[ExteriaStarGift giftWithRow:&rows[i]]];
            } else {
                NSLog(@"exteria: payments.getStarGifts answer rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:gifts error:error completion:done];
        [done release];
    }];
}

- (void)loadSavedGiftsOfDialog:(ExteriaDialog *)dialog offset:(NSString *)offset completion:(ExteriaSavedGiftsCompletion)completion {
    ExteriaSavedGiftsCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *start = offset ? [offset copy] : [@"" copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_saved_gifts_request(arena, &peer, start.UTF8String, 30, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSMutableArray *gifts = nil;
        NSString *next = nil;
        NSString *error = nil;
        NSInteger total = 0;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_saved_gift *rows = calloc(EXTERIA_SAVED_GIFTS_MAX, sizeof(*rows));
            exteria_saved_gift_page page;
            size_t count = 0;
            exteria_status status = rows ? exteria_saved_gifts_parse(result->value, rows, EXTERIA_SAVED_GIFTS_MAX, &count, &page) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                gifts = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [gifts addObject:[ExteriaSavedGift savedGiftWithRow:&rows[i]]];
                total = page.total;
                if (page.next_offset[0]) next = [NSString stringWithUTF8String:page.next_offset];
            } else {
                NSLog(@"exteria: payments.getSavedStarGifts answer rejected: %s", exteria_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredGifts = [[gifts copy] autorelease];
        NSString *deliveredNext = [[next copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredGifts, total, deliveredNext, deliveredError); [done release]; }];
    }];
    [start release];
}

- (void)loadStarsBalance:(void (^)(long long, NSString *))completion {
    void (^done)(long long, NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_stars_balance_request(arena, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        int64_t stars = 0;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_status status = exteria_stars_balance_parse(result->value, &stars);
            if (status != EXTERIA_OK) {
                NSLog(@"exteria: payments.getStarsStatus answer rejected: %s", exteria_status_name(status));
                error = status == EXTERIA_E_UNSUPPORTED ? @"STARS_UNSUPPORTED" : @"INTERNAL";
            }
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(stars, deliveredError); [done release]; }];
    }];
}

/* worker only: the invoice a quote stands for */
static exteria_status ExteriaBuildInvoice(exteria_arena *arena, ExteriaPaymentQuote *quote, exteria_tl_value **invoice) {
    switch (quote->kind) {
    case ExteriaPaymentGiftSend:
        return exteria_gift_invoice_send(arena, &quote->peer, quote->giftId, quote->note.UTF8String, quote->hideName, quote->includeUpgrade, invoice);
    case ExteriaPaymentGiftUpgrade:
        return exteria_gift_invoice_upgrade(arena, quote->messageId, quote->keepDetails, invoice);
    case ExteriaPaymentGiftTransfer:
        return exteria_gift_invoice_transfer(arena, quote->messageId, &quote->peer, invoice);
    }
    return EXTERIA_E_ARG;
}

- (void)askForm:(ExteriaPaymentQuote *)quote completion:(void (^)(ExteriaPaymentQuote *, NSString *))completion {
    void (^done)(ExteriaPaymentQuote *, NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        exteria_tl_value *invoice = NULL;
        exteria_status status = ExteriaBuildInvoice(arena, quote, &invoice);
        if (status == EXTERIA_OK) status = exteria_payment_form_request(arena, invoice, request);
        return status;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        int64_t form = 0, stars = 0;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_status status = exteria_payment_form_parse(result->value, &form, &stars);
            if (status != EXTERIA_OK) {
                NSLog(@"exteria: payments.getPaymentForm answer rejected: %s", exteria_status_name(status));
                error = status == EXTERIA_E_UNSUPPORTED ? @"STARS_UNSUPPORTED" : @"INTERNAL";
            }
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{
            if (!deliveredError) {
                quote->formId = form;
                quote->stars = stars;
            }
            done(deliveredError ? nil : quote, deliveredError);
            [done release];
        }];
    }];
}

- (void)quoteSendingGift:(ExteriaStarGift *)gift toDialog:(ExteriaDialog *)dialog note:(NSString *)note hideName:(BOOL)hideName
          includeUpgrade:(BOOL)includeUpgrade completion:(void (^)(ExteriaPaymentQuote *, NSString *))completion {
    ExteriaPaymentQuote *quote = [[[ExteriaPaymentQuote alloc] init] autorelease];
    quote->kind = ExteriaPaymentGiftSend;
    quote->giftId = gift.giftId;
    quote->peer = ExteriaPeerRefOfDialog(dialog);
    quote->note = [(note ? note : @"") copy];
    quote->hideName = hideName;
    quote->includeUpgrade = includeUpgrade;
    [self askForm:quote completion:completion];
}

- (void)quoteUpgradingGift:(ExteriaSavedGift *)gift keepDetails:(BOOL)keepDetails completion:(void (^)(ExteriaPaymentQuote *, NSString *))completion {
    ExteriaPaymentQuote *quote = [[[ExteriaPaymentQuote alloc] init] autorelease];
    quote->kind = ExteriaPaymentGiftUpgrade;
    quote->messageId = gift.messageId;
    quote->keepDetails = keepDetails;
    [self askForm:quote completion:completion];
}

- (void)quoteTransferringGift:(ExteriaSavedGift *)gift toDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaPaymentQuote *, NSString *))completion {
    ExteriaPaymentQuote *quote = [[[ExteriaPaymentQuote alloc] init] autorelease];
    quote->kind = ExteriaPaymentGiftTransfer;
    quote->messageId = gift.messageId;
    quote->peer = ExteriaPeerRefOfDialog(dialog);
    [self askForm:quote completion:completion];
}

- (void)payQuote:(ExteriaPaymentQuote *)quote completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self loadStarsBalance:^(long long balance, NSString *balanceError) {
        if (balanceError) { done(balanceError); [done release]; return; }
        if (balance < quote->stars) { done(@"BALANCE_LOW"); [done release]; return; }
        [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            exteria_tl_value *invoice = NULL;
            exteria_status status = ExteriaBuildInvoice(arena, quote, &invoice);
            if (status == EXTERIA_OK) status = exteria_payment_send_request(arena, quote->formId, invoice, request);
            return status;
        } handler:^(const exteria_mt_rpc_result *result) {
            NSString *error = nil;
            if (result->status != EXTERIA_OK) {
                error = ExteriaRpcErrorName(result);
            } else {
                exteria_status status = exteria_payment_result_check(result->value);
                if (status != EXTERIA_OK) {
                    NSLog(@"exteria: payments.sendStarsForm answer rejected: %s", exteria_status_name(status));
                    error = status == EXTERIA_E_UNSUPPORTED ? @"STARS_UNSUPPORTED" : @"INTERNAL";
                }
            }
            [self noteRpcError:error];
            NSString *deliveredError = [[error copy] autorelease];
            [self deliverMain:^{ done(deliveredError); [done release]; }];
        }];
    }];
}

/* a request with no answer worth reading: the server says true, or an error name */
- (void)runGiftRequest:(exteria_status (^)(exteria_arena *arena, exteria_tl_value **request))build completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredError); [done release]; }];
    }];
}

- (void)setGift:(ExteriaSavedGift *)gift hidden:(BOOL)hidden completion:(void (^)(NSString *))completion {
    int32_t messageId = gift.messageId;
    [self runGiftRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_gift_save_request(arena, messageId, hidden, request);
    } completion:completion];
}

- (void)convertGift:(ExteriaSavedGift *)gift completion:(void (^)(NSString *))completion {
    int32_t messageId = gift.messageId;
    [self runGiftRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_gift_convert_request(arena, messageId, request);
    } completion:completion];
}

- (void)upgradeGift:(ExteriaSavedGift *)gift keepDetails:(BOOL)keepDetails completion:(void (^)(NSString *))completion {
    int32_t messageId = gift.messageId;
    [self runGiftRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_gift_upgrade_request(arena, messageId, keepDetails, request);
    } completion:completion];
}

- (void)transferGift:(ExteriaSavedGift *)gift toDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    int32_t messageId = gift.messageId;
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self runGiftRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_gift_transfer_request(arena, messageId, &peer, request);
    } completion:completion];
}

- (void)pinGifts:(NSArray *)gifts completion:(void (^)(NSString *))completion {
    NSMutableData *ids = [NSMutableData data];
    for (ExteriaSavedGift *gift in gifts) {
        int32_t messageId = gift.messageId;
        [ids appendBytes:&messageId length:sizeof(messageId)];
    }
    size_t count = ids.length / sizeof(int32_t);
    [self runGiftRequest:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_gift_pin_request(arena, ids.bytes, count, request);
    } completion:completion];
}

@end
