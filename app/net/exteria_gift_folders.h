#import <Foundation/Foundation.h>

#import "exteria_dialog.h"
#import "exteria_session.h"
#import "exteria_star_gift.h"

/* a folder of the gifts on a profile, as the server keeps it */
@interface ExteriaGiftFolder : NSObject {
    int32_t _folderId;
    int32_t _count;
    NSString *_title;
}
@property (nonatomic, readonly) int32_t folderId;
@property (nonatomic, readonly) int32_t count;
@property (nonatomic, readonly, copy) NSString *title;
@end

/* the folders of a profile: reading them, and the changes the owner makes */
@interface ExteriaSession (GiftFolders)

/* the folders of the profile of a user or a channel, in the order the server keeps them */
- (void)loadGiftFoldersOfDialog:(ExteriaDialog *)dialog completion:(void (^)(NSArray *folders, NSString *errorName))completion;
/* one page of the gifts in a folder; folderId zero is the same as loadSavedGiftsOfDialog:offset:completion */
- (void)loadSavedGiftsOfDialog:(ExteriaDialog *)dialog folder:(int32_t)folderId offset:(NSString *)offset completion:(ExteriaSavedGiftsCompletion)completion;

/* for the own profile only: gifts are named by their messages */
- (void)createGiftFolderTitled:(NSString *)title withGifts:(NSArray *)gifts dialog:(ExteriaDialog *)dialog
                    completion:(void (^)(ExteriaGiftFolder *folder, NSString *errorName))completion;
- (void)renameGiftFolder:(ExteriaGiftFolder *)folder to:(NSString *)title dialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;
- (void)addGifts:(NSArray *)gifts toFolder:(ExteriaGiftFolder *)folder dialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;
- (void)removeGifts:(NSArray *)gifts fromFolder:(ExteriaGiftFolder *)folder dialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;
- (void)deleteGiftFolder:(ExteriaGiftFolder *)folder dialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *errorName))completion;

@end
