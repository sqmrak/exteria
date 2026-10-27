#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_symbol.h"

/* a row of the contact list or the call log: avatar, a name, a line under it, and optionally a time and a symbol on the right */
/* the color of the tag of a member: violet for the owner, green for an admin draw them */
UIColor *ExteriaMemberTagColor(BOOL owner);

@interface ExteriaPersonCell : UITableViewCell

+ (CGFloat)rowHeight;
/* set just before configureWithName: for a person who took part in the development: the name gets the hammer */
@property (nonatomic, assign) NSUInteger developer;
/* set just before configureWithName: for a contact who has the account in the contacts too: two arrows stand at
   the end of the row */
@property (nonatomic, assign) BOOL mutual;
/* set just before configureWithName: for a trailing text that is a tag (the post of a member): it stands in a pill
   of this color show it */
@property (nonatomic, retain) UIColor *trailingTint;
- (void)configureWithName:(NSString *)name initials:(NSString *)initials seed:(NSUInteger)seed
                 subtitle:(NSString *)subtitle subtitleColor:(UIColor *)subtitleColor
                 trailing:(NSString *)trailing symbol:(ExteriaSymbol)symbol showsSymbol:(BOOL)showsSymbol
              nameColor:(UIColor *)nameColor photo:(ExteriaPhoto *)photo avatars:(ExteriaAvatarCache *)avatars;
/* the ghost avatar of a deleted account; every configure clears it, so a person row sets it after */
@property (nonatomic, assign) BOOL avatarDeleted;

@end
