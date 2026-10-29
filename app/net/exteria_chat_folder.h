#import <Foundation/Foundation.h>
#import "exteria_dialog.h"
#include "exteria_folders.h"

@interface ExteriaChatFolder : NSObject <NSCopying> {
    int32_t _folderId;
    NSString *_title;
    NSArray *_titleEntities;
    uint32_t _flags;
    NSData *_included;
    NSData *_excluded;
    NSData *_pinned;
    NSData *_original;
    BOOL _shared;
}
@property(nonatomic, assign) int32_t folderId;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, readonly, retain) NSArray *titleEntities;
@property(nonatomic, assign) uint32_t flags;
@property(nonatomic, copy) NSData *included;
@property(nonatomic, copy) NSData *excluded;
@property(nonatomic, copy) NSData *pinned;
@property(nonatomic, readonly) BOOL shared;
@property(nonatomic, readonly, retain) NSData *original;
+ (ExteriaChatFolder *)folderWithValue:(const exteria_tl_value *)value;
- (exteria_status)buildInArena:(exteria_arena *)arena value:(exteria_tl_value **)value;
- (ExteriaDialog *)dialogWithRow:(const exteria_dialog_row *)row;
- (BOOL)containsDialog:(ExteriaDialog *)dialog;
- (NSUInteger)pinIndexForDialog:(ExteriaDialog *)dialog;
@end
