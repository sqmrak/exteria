#import <UIKit/UIKit.h>

/* the icon of a folder of the chat list, as exteraGram draws it on the tab: the folder names one of thirty pictures by an emoji (its emoticon), and a folder with none gets
   the one its rules suggest (every chat type left unread only, a single kind of chat, and a plain folder for the rest). the pictures are the ones of exteraGram, a white mask
   that takes the color it is asked for */
NSString *ExteriaFolderIconName(NSString *emoticon, uint32_t ruleFlags);
/* the picture at side points on a side, in color; nil for a name that has no picture */
UIImage *ExteriaFolderIconImage(NSString *name, CGFloat side, UIColor *color);
