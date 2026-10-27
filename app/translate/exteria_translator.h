#import <Foundation/Foundation.h>

#import "exteria_session.h"

/* the result of a translation: the new text and, when the original had styled runs, the runs carried over (ExteriaTextEntity, UTF-16 ranges) */
@interface ExteriaTranslation : NSObject {
    NSString *_text;
    NSArray *_entities;
}
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly, copy) NSArray *entities;
@end

/* one translation by the service the person chose in the settings (Google, Yandex, LingoCloud, DeepL, Telegram,
   TranSmart or the AI translator); the original text is never altered */
@interface ExteriaTranslateJob : NSObject

/* language is a code ("ru", "pt-BR"). context holds the lines of the chat before the message, for the AI
   translator when the person turned the context on, and may be nil */
+ (ExteriaTranslateJob *)translateText:(NSString *)text entities:(NSArray *)entities to:(NSString *)language context:(NSString *)context
                               session:(ExteriaSession *)session completion:(void (^)(ExteriaTranslation *translation, NSString *failure))completion;
- (void)cancel;

@end
