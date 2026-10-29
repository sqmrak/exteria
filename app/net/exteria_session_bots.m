#import "exteria_session_bots.h"
#import "exteria_session_internal.h"

#import "exteria_rpc.h"
#import "exteria_remote_file.h"
#include "exteria_gifts.h"
#include "exteria_profile.h"

#define WEB_FILE_LIMIT (256 * 1024)

static exteria_peer_ref ExteriaPeerRefOfPerson(ExteriaPerson *person) {
    exteria_peer_ref ref;
    memset(&ref, 0, sizeof(ref));
    ref.kind = 1;
    ref.id = person.userId;
    ref.access_hash = person.accessHash;
    return ref;
}

/* the name a failed parse is reported under, so a screen shows one text for "the server sent something odd" */
static NSString *ExteriaParseFailure(const char *method, exteria_status status) {
    NSLog(@"exteria: %s answer rejected: %s", method, exteria_status_name(status));
    return @"INTERNAL";
}

@implementation ExteriaSession (Bots)

#pragma mark names and info

- (void)resolveUsername:(NSString *)name completion:(ExteriaResolveCompletion)completion {
    ExteriaResolveCompletion done = [completion copy];
    NSString *username = [name copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_resolve_request(arena, username.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        ExteriaDialog *dialog = nil;
        ExteriaPerson *person = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
            if ([error isEqualToString:@"USERNAME_NOT_OCCUPIED"] || [error isEqualToString:@"USERNAME_INVALID"]) error = @"USERNAME_NOT_FOUND";
        } else {
            exteria_resolved resolved;
            exteria_status status = exteria_resolve_parse(result->value, [self workerAccount], &resolved);
            if (status == EXTERIA_OK) {
                dialog = [[[ExteriaDialog alloc] initWithRow:&resolved.dialog] autorelease];
                if (resolved.is_user) person = [[[ExteriaPerson alloc] initWithRow:&resolved.person] autorelease];
            } else {
                error = status == EXTERIA_E_NOTFOUND ? @"USERNAME_NOT_FOUND" : ExteriaParseFailure("contacts.resolveUsername", status);
            }
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(dialog, person, deliveredError); [done release]; }];
    }];
    [username release];
}

- (void)loadStoredPersonOfUserId:(long long)userId completion:(void (^)(ExteriaPerson *))completion {
    void (^done)(ExteriaPerson *) = [completion copy];
    [self post:^{
        ExteriaPerson *held = userId > 0 ? [self storedPersonWithKey:(int64_t)userId] : nil;
        [self deliverMain:^{ done(held); [done release]; }];
    }];
}

- (void)checkInviteHash:(NSString *)hash completion:(ExteriaInviteCheckCompletion)completion {
    ExteriaInviteCheckCompletion done = [completion copy];
    NSString *value = [hash copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_invite_check_request(arena, value.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        ExteriaDialog *member = nil;
        NSString *title = nil, *about = nil, *error = nil;
        exteria_invite invite;
        memset(&invite, 0, sizeof(invite));
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_status status = exteria_invite_parse(result->value, [self workerAccount], &invite);
            if (status != EXTERIA_OK) {
                error = ExteriaParseFailure("messages.checkChatInvite", status);
            } else {
                title = [NSString stringWithUTF8String:invite.title];
                about = [NSString stringWithUTF8String:invite.about];
                if (invite.member) member = [[[ExteriaDialog alloc] initWithRow:&invite.dialog] autorelease];
            }
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        NSInteger count = invite.participants;
        BOOL broadcast = invite.broadcast, request = invite.request_needed;
        ExteriaRemoteFile *photo = [ExteriaRemoteFile fileForMedia:&invite.photo];
        [self deliverMain:^{ done(member, title, about, photo, count, broadcast, request, deliveredError); [done release]; }];
    }];
    [value release];
}

- (void)joinInviteHash:(NSString *)hash completion:(void (^)(ExteriaDialog *, NSString *))completion {
    void (^done)(ExteriaDialog *, NSString *) = [completion copy];
    NSString *value = [hash copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_invite_import_request(arena, value.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        ExteriaDialog *dialog = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_dialog_row row;
            exteria_status status = exteria_invite_joined_parse(result->value, [self workerAccount], &row);
            if (status == EXTERIA_OK) dialog = [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
            else error = status == EXTERIA_E_UNSUPPORTED ? @"JOIN_WEBVIEW" : ExteriaParseFailure("messages.importChatInvite", status);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(dialog, deliveredError); [done release]; }];
    }];
    [value release];
}

- (void)addContactPhone:(NSString *)phone firstName:(NSString *)first lastName:(NSString *)last completion:(void (^)(BOOL, NSString *))completion {
    void (^done)(BOOL, NSString *) = [completion copy];
    NSString *number = [phone copy], *given = [first copy], *family = [last copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_contact_import_request(arena, number.UTF8String, given.UTF8String, family.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        BOOL found = NO;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            size_t imported = 0;
            if (exteria_contact_import_parse(result->value, &imported) == EXTERIA_OK) found = imported > 0;
            else error = @"INTERNAL";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(found, delivered); [done release]; }];
    }];
    [number release];
    [given release];
    [family release];
}

- (void)editContact:(ExteriaPerson *)person firstName:(NSString *)first lastName:(NSString *)last completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref user = ExteriaPeerRefOfPerson(person);
    NSString *given = [first copy], *family = [last copy], *phone = [person.phone copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_contact_edit_request(arena, &user, given.UTF8String, family.length ? family.UTF8String : "", phone.length ? phone.UTF8String : "", request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
    [given release];
    [family release];
    [phone release];
}

- (void)loadBotInfoOfPerson:(ExteriaPerson *)bot completion:(void (^)(ExteriaBotInfo *, NSString *))completion {
    void (^done)(ExteriaBotInfo *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfPerson(bot);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_full_user_peer_request(arena, &peer, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        ExteriaBotInfo *info = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_bot_info *row = calloc(1, sizeof(*row));
            exteria_status status = row ? exteria_bot_info_parse(result->value, row) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) info = [ExteriaBotInfo infoWithRow:row];
            else error = ExteriaParseFailure("users.getFullUser", status);
            free(row);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(info, deliveredError); [done release]; }];
    }];
}

- (void)startBot:(ExteriaPerson *)bot inDialog:(ExteriaDialog *)dialog param:(NSString *)param randomId:(long long)randomId
      completion:(ExteriaSendCompletion)completion {
    ExteriaSendCompletion done = [completion copy];
    exteria_peer_ref botRef = ExteriaPeerRefOfPerson(bot), peer = ExteriaPeerRefOfDialog(dialog);
    NSString *text = [param copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_start_bot_request(arena, &botRef, &peer, randomId, text.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishSend:result randomId:randomId completion:done];
    }];
    [text release];
}

#pragma mark buttons

- (void)pressButton:(ExteriaMarkupButton *)button ofMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog password:(NSString *)password
         completion:(ExteriaCallbackCompletion)completion {
    ExteriaCallbackCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    BOOL game = button.kind == EXTERIA_BUTTON_GAME;
    NSData *data = [button.data retain];
    BOOL needsPassword = button.row.password;
    NSString *secret = [password copy];
    if (needsPassword && !secret.length) {
        [self deliverMain:^{ done(nil, @"PASSWORD_REQUIRED"); [done release]; }];
        [data release];
        [secret release];
        return;
    }
    void (^finish)(const exteria_mt_rpc_result *) = ^(const exteria_mt_rpc_result *result) {
        ExteriaCallbackAnswer *answer = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_callback_answer *row = calloc(1, sizeof(*row));
            exteria_status status = row ? exteria_callback_parse(result->value, row) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) answer = [ExteriaCallbackAnswer answerWithRow:row];
            else error = ExteriaParseFailure("messages.getBotCallbackAnswer", status);
            free(row);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(answer, deliveredError); [done release]; }];
    };
    void (^finishCopy)(const exteria_mt_rpc_result *) = [finish copy];
    if (!needsPassword) {
        [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_callback_request(arena, &peer, messageId, data.bytes, data.length, game, NULL, request);
        } handler:finishCopy];
    } else {
        /* the proof is computed from the server's challenge, so the password goes first and the press second */
        [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
            return exteria_password_request(arena, request);
        } handler:^(const exteria_mt_rpc_result *challenge) {
            if (challenge->status != EXTERIA_OK) {
                finishCopy(challenge);
                return;
            }
            [self submitBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
                exteria_tl_value *check = NULL;
                exteria_status status = exteria_password_input(arena, challenge->value, secret.UTF8String, &check);
                if (status == EXTERIA_OK) status = exteria_callback_request(arena, &peer, messageId, data.bytes, data.length, game, check, request);
                return status;
            } handler:finishCopy];
        }];
    }
    [finishCopy release];
    [data release];
    [secret release];
}

#pragma mark inline mode

- (void)loadVenueSearchBot:(void (^)(ExteriaPerson *, NSString *))completion {
    void (^done)(ExteriaPerson *, NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        *request = exteria_tl_new_obj(arena,"help.getConfig");
        return *request ? EXTERIA_OK : EXTERIA_E_NOMEM;
    } handler:^(const exteria_mt_rpc_result *result) {
        const uint8_t *bytes = NULL;
        size_t length = 0;
        NSString *name = nil;
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        if (!error && exteria_tl_get_bytes(result->value,"venue_search_username",&bytes,&length) == EXTERIA_OK && length > 0 && length <= 64) {
            BOOL valid = YES;
            for (size_t i=0;i<length;++i) if (!((bytes[i]>='a' && bytes[i]<='z') || (bytes[i]>='A' && bytes[i]<='Z') ||
                (bytes[i]>='0' && bytes[i]<='9') || bytes[i]=='_')) valid = NO;
            if (valid) name = [[[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding] autorelease];
        }
        [self deliverMain:^{
            if (!name) { done(nil,error ? error : @"VENUE_SEARCH_UNAVAILABLE"); [done release]; return; }
            [self resolveUsername:name completion:^(ExteriaDialog *dialog,ExteriaPerson *person,NSString *failure) {
                (void)dialog;
                done(person.bot ? person : nil,failure ? failure : (person.bot ? nil : @"VENUE_SEARCH_UNAVAILABLE"));
                [done release];
            }];
        }];
    }];
}

- (void)searchInline:(NSString *)query bot:(ExteriaPerson *)bot inDialog:(ExteriaDialog *)dialog offset:(NSString *)offset
          completion:(void (^)(ExteriaInlinePage *, NSString *))completion {
    exteria_geo_point point;
    memset(&point,0,sizeof(point));
    [self searchInline:query bot:bot inDialog:dialog offset:offset location:point completion:completion];
}

- (void)searchVenues:(NSString *)query latitude:(double)latitude longitude:(double)longitude bot:(ExteriaPerson *)bot
           inDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaInlinePage *, NSString *))completion {
    exteria_geo_point point;
    memset(&point,0,sizeof(point));
    point.valid=1; point.latitude=latitude; point.longitude=longitude;
    [self searchInline:query bot:bot inDialog:dialog offset:@"" location:point completion:completion];
}

- (void)searchInline:(NSString *)query bot:(ExteriaPerson *)bot inDialog:(ExteriaDialog *)dialog offset:(NSString *)offset
           location:(exteria_geo_point)point completion:(void (^)(ExteriaInlinePage *, NSString *))completion {
    void (^done)(ExteriaInlinePage *, NSString *) = [completion copy];
    exteria_peer_ref botRef = ExteriaPeerRefOfPerson(bot), peer = ExteriaPeerRefOfDialog(dialog);
    NSString *text = [query copy], *start = [(offset ? offset : @"") copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        exteria_status status = exteria_inline_query_request(arena, &botRef, &peer, text.UTF8String, start.UTF8String, request);
        if (status == EXTERIA_OK && point.valid) {
            exteria_tl_value *geo = NULL;
            status = exteria_geo_input(arena,&point,&geo);
            if (status == EXTERIA_OK) status = exteria_tl_set(*request,"geo_point",geo);
        }
        return status;
    } handler:^(const exteria_mt_rpc_result *result) {
        ExteriaInlinePage *page = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_inline_result *rows = calloc(EXTERIA_INLINE_RESULTS_MAX, sizeof(*rows));
            exteria_inline_page row;
            size_t count = 0;
            exteria_status status = rows ? exteria_inline_results_parse(result->value, &row, rows, EXTERIA_INLINE_RESULTS_MAX, &count) : EXTERIA_E_NOMEM;
            if (status == EXTERIA_OK) {
                NSMutableArray *results = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [results addObject:[ExteriaInlineResult resultWithRow:&rows[i]]];
                page = [ExteriaInlinePage pageWithRow:&row results:results];
            } else {
                error = ExteriaParseFailure("messages.getInlineBotResults", status);
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(page, deliveredError); [done release]; }];
    }];
    [text release];
    [start release];
}

- (void)sendInlineResult:(ExteriaInlineResult *)result queryId:(long long)queryId toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId
              completion:(ExteriaSendCompletion)completion {
    [self sendInlineResult:result queryId:queryId toDialog:dialog randomId:randomId replyTo:0 completion:completion];
}

- (void)sendInlineResult:(ExteriaInlineResult *)result queryId:(long long)queryId toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId
              replyTo:(int32_t)replyTo completion:(ExteriaSendCompletion)completion {
    ExteriaSendCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *resultId = [result.resultId copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        exteria_status status = exteria_inline_send_request(arena, &peer, randomId, queryId, resultId.UTF8String, request);
        if (status == EXTERIA_OK) status = exteria_set_reply(arena, *request, &peer, replyTo);
        return status;
    } handler:^(const exteria_mt_rpc_result *reply) {
        [self finishSend:reply randomId:randomId completion:done];
    }];
    [resultId release];
}

- (void)loadWebFile:(ExteriaWebFile *)file completion:(void (^)(NSData *, NSString *))completion {
    void (^done)(NSData *, NSString *) = [completion copy];
    NSString *url = [file.url copy];
    long long hash = file.accessHash;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        exteria_tl_value *location = exteria_tl_new_obj(arena, "inputWebFileLocation");
        *request = exteria_tl_new_obj(arena, "upload.getWebFile");
        if (!location || !*request) return EXTERIA_E_NOMEM;
        exteria_status status = exteria_tl_set_str(arena, location, "url", url.UTF8String);
        if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, location, "access_hash", hash);
        if (status == EXTERIA_OK) status = exteria_tl_set(*request, "location", location);
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, *request, "offset", 0);
        if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, *request, "limit", WEB_FILE_LIMIT);
        return status;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSData *data = nil;
        NSString *error = nil;
        const uint8_t *bytes = NULL;
        size_t len = 0;
        if (result->status != EXTERIA_OK) error = ExteriaRpcErrorName(result);
        else if (exteria_tl_get_bytes(result->value, "bytes", &bytes, &len) == EXTERIA_OK && len > 0 && len <= WEB_FILE_LIMIT) data = [NSData dataWithBytes:bytes length:len];
        else error = @"INTERNAL";
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(data, deliveredError); [done release]; }];
    }];
    [url release];
}

- (void)loadUser:(long long)userId ofMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaPerson *, NSString *))completion {
    void (^done)(ExteriaPerson *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_user_from_message_request(arena, &peer, messageId, userId, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        ExteriaPerson *person = nil;
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_person_row row;
            exteria_status status = exteria_user_from_message_parse(result->value, userId, &row);
            if (status == EXTERIA_OK) person = [[[ExteriaPerson alloc] initWithRow:&row] autorelease];
            else error = status == EXTERIA_E_NOTFOUND ? @"USER_ID_INVALID" : ExteriaParseFailure("users.getUsers", status);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(person, deliveredError); [done release]; }];
    }];
}

#pragma mark signing in on a site

- (void)finishUrlAuth:(const exteria_mt_rpc_result *)result method:(const char *)method completion:(void (^)(ExteriaUrlAuth *, NSString *))done {
    ExteriaUrlAuth *auth = nil;
    NSString *error = nil;
    if (result->status != EXTERIA_OK) {
        error = ExteriaRpcErrorName(result);
    } else {
        exteria_url_auth *row = calloc(1, sizeof(*row));
        exteria_status status = row ? exteria_url_auth_parse(result->value, row) : EXTERIA_E_NOMEM;
        if (status == EXTERIA_OK) auth = [ExteriaUrlAuth authWithRow:row];
        else error = ExteriaParseFailure(method, status);
        free(row);
    }
    [self noteRpcError:error];
    NSString *deliveredError = [[error copy] autorelease];
    [self deliverMain:^{ done(auth, deliveredError); [done release]; }];
}

- (void)requestUrlAuthForButton:(ExteriaMarkupButton *)button ofMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog
                     completion:(void (^)(ExteriaUrlAuth *, NSString *))completion {
    void (^done)(ExteriaUrlAuth *, NSString *) = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    int32_t buttonId = button.row.button_id;
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_url_auth_request(arena, &peer, messageId, buttonId, NULL, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishUrlAuth:result method:"messages.requestUrlAuth" completion:done];
    }];
}

- (void)requestUrlAuthForUrl:(NSString *)url completion:(void (^)(ExteriaUrlAuth *, NSString *))completion {
    void (^done)(ExteriaUrlAuth *, NSString *) = [completion copy];
    NSString *address = [url copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_url_auth_request(arena, NULL, 0, 0, address.UTF8String, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishUrlAuth:result method:"messages.requestUrlAuth" completion:done];
    }];
    [address release];
}

- (void)acceptUrlAuth:(ExteriaUrlAuth *)auth button:(ExteriaMarkupButton *)button ofMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog
         writeAllowed:(BOOL)writeAllowed code:(NSString *)code completion:(void (^)(ExteriaUrlAuth *, NSString *))completion {
    void (^done)(ExteriaUrlAuth *, NSString *) = [completion copy];
    BOOL forButton = button != nil && dialog != nil;
    exteria_peer_ref peer;
    memset(&peer, 0, sizeof(peer));
    if (forButton) peer = ExteriaPeerRefOfDialog(dialog);
    int32_t buttonId = button.row.button_id;
    NSString *address = [(forButton ? @"" : auth.url) copy], *match = [code copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_url_auth_accept_request(arena, forButton ? &peer : NULL, messageId, buttonId, address.UTF8String, writeAllowed, 0,
                                               match.length ? match.UTF8String : NULL, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishUrlAuth:result method:"messages.acceptUrlAuth" completion:done];
    }];
    [address release];
    [match release];
}

#pragma mark invoices

- (void)loadStarsInvoice:(ExteriaStarsInvoice *)invoice completion:(void (^)(ExteriaStarsInvoice *, NSString *))completion {
    void (^done)(ExteriaStarsInvoice *, NSString *) = [completion copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        exteria_tl_value *input = NULL;
        exteria_status status = invoice->slug ? exteria_invoice_slug_input(arena, invoice->slug.UTF8String, &input)
                                              : exteria_invoice_message_input(arena, &invoice->peer, invoice->messageId, &input);
        if (status == EXTERIA_OK) status = exteria_payment_form_request(arena, input, request);
        return status;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        exteria_stars_form form;
        memset(&form, 0, sizeof(form));
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_status status = exteria_stars_form_parse(result->value, &form);
            if (status == EXTERIA_E_UNSUPPORTED) error = @"STARS_UNSUPPORTED";
            else if (status != EXTERIA_OK) error = ExteriaParseFailure("payments.getPaymentForm", status);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        NSString *title = [NSString stringWithUTF8String:form.title], *text = [NSString stringWithUTF8String:form.description];
        [self deliverMain:^{
            if (!deliveredError) {
                invoice->formId = form.form_id;
                invoice->botId = form.bot_id;
                invoice->stars = form.stars;
                [invoice->title release];
                invoice->title = [(title ? title : @"") copy];
                [invoice->invoiceDescription release];
                invoice->invoiceDescription = [(text ? text : @"") copy];
            }
            done(deliveredError ? nil : invoice, deliveredError);
            [done release];
        }];
    }];
}

- (void)loadStarsInvoiceOfMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaStarsInvoice *, NSString *))completion {
    ExteriaStarsInvoice *invoice = [[[ExteriaStarsInvoice alloc] init] autorelease];
    invoice->peer = ExteriaPeerRefOfDialog(dialog);
    invoice->messageId = messageId;
    [self loadStarsInvoice:invoice completion:completion];
}

- (void)loadStarsInvoiceOfSlug:(NSString *)slug completion:(void (^)(ExteriaStarsInvoice *, NSString *))completion {
    ExteriaStarsInvoice *invoice = [[[ExteriaStarsInvoice alloc] init] autorelease];
    invoice->slug = [slug copy];
    [self loadStarsInvoice:invoice completion:completion];
}

- (void)payStarsInvoice:(ExteriaStarsInvoice *)invoice completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    ExteriaStarsInvoice *held = [invoice retain];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        exteria_tl_value *input = NULL;
        exteria_status status = held->slug ? exteria_invoice_slug_input(arena, held->slug.UTF8String, &input)
                                           : exteria_invoice_message_input(arena, &held->peer, held->messageId, &input);
        if (status == EXTERIA_OK) status = exteria_payment_send_request(arena, held->formId, input, request);
        return status;
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != EXTERIA_OK) {
            error = ExteriaRpcErrorName(result);
        } else {
            exteria_status status = exteria_payment_result_check(result->value);
            if (status == EXTERIA_E_UNSUPPORTED) error = @"STARS_UNSUPPORTED";
            else if (status != EXTERIA_OK) error = ExteriaParseFailure("payments.sendStarsForm", status);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredError); [done release]; }];
    }];
    [held release];
}

#pragma mark answers to a keyboard

- (void)sendContactPhone:(NSString *)phone name:(NSString *)name toDialog:(ExteriaDialog *)dialog randomId:(long long)randomId
              completion:(ExteriaSendCompletion)completion {
    ExteriaSendCompletion done = [completion copy];
    exteria_peer_ref peer = ExteriaPeerRefOfDialog(dialog);
    NSString *number = [phone copy], *first = [name copy];
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_send_contact_request(arena, &peer, number.UTF8String, first.UTF8String, "", randomId, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        [self finishSend:result randomId:randomId completion:done];
    }];
    [number release];
    [first release];
}

- (void)sendRequestedDialogs:(NSArray *)dialogs buttonId:(int32_t)buttonId ofMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog
                  completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    exteria_peer_ref chat = ExteriaPeerRefOfDialog(dialog);
    NSUInteger count = MIN(dialogs.count, (NSUInteger)10);
    NSMutableData *packed = [NSMutableData dataWithLength:(count ? count : 1) * sizeof(exteria_peer_ref)];
    exteria_peer_ref *peers = packed.mutableBytes;
    for (NSUInteger i = 0; i < count; ++i) peers[i] = ExteriaPeerRefOfDialog([dialogs objectAtIndex:i]);
    [self invokeBuilt:^exteria_status(exteria_arena *arena, exteria_tl_value **request) {
        return exteria_requested_peers_request(arena, &chat, messageId, buttonId, packed.bytes, count, request);
    } handler:^(const exteria_mt_rpc_result *result) {
        NSString *error = result->status == EXTERIA_OK ? nil : ExteriaRpcErrorName(result);
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredError); [done release]; }];
    }];
}

@end
