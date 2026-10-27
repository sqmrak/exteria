#import <UIKit/UIKit.h>

#import "exteria_bot.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"

/* one row of the panel above the field: a command a bot offers or a result of an inline query */
@interface ExteriaSuggestion : NSObject {
    NSString *_title;
    NSString *_subtitle;
    ExteriaMedia *_media;
    ExteriaWebFile *_webFile;
    id _payload;
}
- (id)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle media:(ExteriaMedia *)media webFile:(ExteriaWebFile *)webFile payload:(id)payload;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *subtitle;
/* the picture the server holds, or the one the bot hosts; both nil for a row without a picture */
@property (nonatomic, readonly, retain) ExteriaMedia *media;
@property (nonatomic, readonly, retain) ExteriaWebFile *webFile;
@property (nonatomic, readonly, retain) id payload;
@end

/* the list over the chat that follows what is typed: the commands of a bot after a slash, the answers of a bot
   after its name */
@interface ExteriaSuggestionPanel : UIView <UITableViewDataSource, UITableViewDelegate> {
    ExteriaSession *_session;
    ExteriaMediaCache *_media;
    UITableView *_table;
    UIActivityIndicatorView *_spinner;
    UILabel *_empty;
    NSMutableArray *_items;
    BOOL _gallery;
    NSString *_headerTitle;
    void (^_pickHandler)(ExteriaSuggestion *suggestion);
    void (^_headerHandler)(void);
    void (^_moreHandler)(void);
}

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media;

@property (nonatomic, copy) void (^pickHandler)(ExteriaSuggestion *suggestion);
/* asked for when the list is scrolled to its end; the owner appends the next page */
@property (nonatomic, copy) void (^moreHandler)(void);

/* replaces the rows */
- (void)setSuggestions:(NSArray *)items gallery:(BOOL)gallery;
- (void)appendSuggestions:(NSArray *)items;
/* a row above the others, such as the bot's own button to continue elsewhere; nil title removes it */
- (void)setHeaderTitle:(NSString *)title handler:(void (^)(void))handler;
/* a spinner while the first answer is awaited, and a line when there is none */
- (void)setLoading:(BOOL)loading;
- (void)setEmptyText:(NSString *)text;
@property (nonatomic, readonly) NSUInteger count;
/* the height the rows want for a width, up to maxHeight */
- (CGFloat)preferredHeightForWidth:(CGFloat)width maxHeight:(CGFloat)maxHeight;

@end
