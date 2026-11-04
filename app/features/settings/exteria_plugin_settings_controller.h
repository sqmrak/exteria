#import "exteria_settings_kit.h"

/* the page of settings a plugin builds with create_settings(), drawn with the rows of the app. a Text with a sub page opens another of these */
@interface ExteriaPluginSettingsController : ExteriaSettingsPageController {
    NSString *_pluginId;
    NSArray *_items;
    BOOL _root;
}
/* items nil: the page asks the plugin, and asks again after every change, since a click may rebuild the list */
- (id)initWithPluginId:(NSString *)pluginId title:(NSString *)title items:(NSArray *)items;
@end
