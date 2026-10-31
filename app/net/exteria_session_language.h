#import <Foundation/Foundation.h>

#import "exteria_session.h"

/* a language pack as the server describes it (langpack.getLanguage), the words of a t.me/setlanguage link */
@interface ExteriaLanguagePack : NSObject {
    NSString *_name;
    NSString *_nativeName;
    NSString *_code;
    NSString *_baseCode;
    NSString *_translationsURL;
    int32_t _stringsCount;
    int32_t _translatedCount;
    BOOL _official;
    BOOL _rtl;
}
/* the name in English, and in the language itself */
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *nativeName;
@property (nonatomic, readonly, copy) NSString *code;
@property (nonatomic, readonly, copy) NSString *baseCode;
@property (nonatomic, readonly, copy) NSString *translationsURL;
@property (nonatomic, readonly) int32_t stringsCount;
@property (nonatomic, readonly) int32_t translatedCount;
@property (nonatomic, readonly) BOOL official;
@property (nonatomic, readonly) BOOL rtl;
@end

@interface ExteriaSession (Language)

/* the pack with this code for the "ios" platform. the completion gets the pack, or nil with the error name of the server (LANG_CODE_NOT_SUPPORTED for a
   code it does not have), TIMEOUT, or MALFORMED for an answer that is not a language pack; it runs on the main thread */
- (void)loadLanguagePack:(NSString *)code completion:(void (^)(ExteriaLanguagePack *pack, NSString *errorName))completion;

@end
