#import <Foundation/Foundation.h>

@class ExteriaPerson;

/* the contacts of the account laid out it: by name, in sections of one letter each, or by when they were last
   seen, those that are online first, in one section; main thread only */
@interface ExteriaContactList : NSObject

/* the people as the session gave them */
@property (nonatomic, retain) NSArray *people;
@property (nonatomic, assign) BOOL sortByName;
@property (nonatomic, copy) NSString *query;

/* one entry per section: the letter of a section by name, nil for the single section by time */
@property (nonatomic, readonly) NSArray *titles;
@property (nonatomic, readonly) NSArray *sections;
/* how many people show, after the search */
@property (nonatomic, readonly) NSUInteger count;

- (ExteriaPerson *)personAtIndexPath:(NSIndexPath *)path;

+ (BOOL)storedSortByName;
+ (void)storeSortByName:(BOOL)byName;

@end
