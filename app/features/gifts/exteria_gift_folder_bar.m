#import "exteria_gift_folder_bar.h"

#import "exteria_alert.h"
#import "exteria_filter_bar.h"
#import "exteria_weak_reference.h"

#define BAR_HEIGHT 48.0
/* the server refuses a title past this many characters; the field is cut here so the person sees it before the request fails */
#define TITLE_CHARACTERS_MAX 12

@interface ExteriaGiftFolderBar () <ExteriaFilterBarDelegate> {
    ExteriaSession *_session;
    ExteriaDialog *_dialog;
    BOOL _mine;
    NSArray *_folders;
    ExteriaGiftFolder *_selected;
    ExteriaFilterBar *_bar;
    BOOL _loaded;
    NSUInteger _generation;
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaGiftFolderBar

@synthesize delegate = _delegate;
@synthesize selectedFolder = _selected;
@synthesize folders = _folders;

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog mine:(BOOL)mine {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _session = [session retain];
    _dialog = [dialog retain];
    _mine = mine;
    _folders = [[NSArray alloc] init];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.clipsToBounds = YES;
    self.hidden = YES;
    return self;
}

- (void)dealloc {
    ++_generation;
    [_weak clear];
    [_weak release];
    _bar.delegate = nil;
    [_bar release];
    [_selected release];
    [_folders release];
    [_dialog release];
    [_session release];
    [super dealloc];
}

- (CGFloat)height {
    return _loaded && (_folders.count || _mine) ? BAR_HEIGHT : 0;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _bar.frame = self.bounds;
}

/* the chips: all gifts, a chip for each folder, and on our own profile the chip that makes one and the one that edits the chosen one */
- (void)rebuildChips {
    _bar.delegate = nil;
    [_bar removeFromSuperview];
    [_bar release];
    NSMutableArray *titles = [NSMutableArray arrayWithObject:NSLocalizedString(@"gifts.folder.all", nil)];
    for (ExteriaGiftFolder *folder in _folders) [titles addObject:folder.title];
    if (_mine) {
        [titles addObject:NSLocalizedString(@"gifts.folder.new", nil)];
        if (_selected) [titles addObject:NSLocalizedString(@"gifts.folder.edit", nil)];
    }
    _bar = [[ExteriaFilterBar alloc] initWithTitles:titles];
    _bar.delegate = self;
    _bar.selectedIndex = _selected ? (NSInteger)[_folders indexOfObject:_selected] + 1 : 0;
    [self addSubview:_bar];
    self.hidden = ![self height];
    [self setNeedsLayout];
}

- (void)reload {
    ++_generation;
    NSUInteger generation = _generation;
    ExteriaWeakReference *weak = _weak;
    [_session loadGiftFoldersOfDialog:_dialog completion:^(NSArray *folders, NSString *errorName) {
        ExteriaGiftFolderBar *bar = weak.target;
        if (!bar || generation != bar->_generation) return;
        if (!folders) {
            NSLog(@"exteria: the gift folders did not load: %@", errorName);
            return;
        }
        [bar takeFolders:folders];
    }];
}

- (void)takeFolders:(NSArray *)folders {
    ExteriaGiftFolder *previous = _selected;
    int32_t keep = previous.folderId;
    [_folders release];
    _folders = [folders retain];
    ExteriaGiftFolder *again = nil;
    for (ExteriaGiftFolder *folder in folders) if (folder.folderId == keep) again = folder;
    [_selected release];
    _selected = [again retain];
    BOOL wasLoaded = _loaded;
    _loaded = YES;
    [self rebuildChips];
    /* a chosen folder that is gone, or the first answer that finds none, puts the list back to all gifts */
    [_delegate giftFolderBarDidChange:self selectionChanged:previous != nil && again == nil && wasLoaded];
}

- (void)select:(ExteriaGiftFolder *)folder {
    if (folder == _selected) return;
    [_selected release];
    _selected = [folder retain];
    [self rebuildChips];
    [_delegate giftFolderBar:self didSelectFolder:_selected];
    [_delegate giftFolderBarDidChange:self selectionChanged:NO];
}

- (void)filterBar:(ExteriaFilterBar *)bar didSelectIndex:(NSInteger)index {
    NSInteger count = (NSInteger)_folders.count;
    if (index == 0) { [self select:nil]; return; }
    if (index <= count) { [self select:[_folders objectAtIndex:(NSUInteger)index - 1]]; return; }
    /* the chips that act leave the choice where it was */
    bar.selectedIndex = _selected ? (NSInteger)[_folders indexOfObject:_selected] + 1 : 0;
    if (index == count + 1) [self askNewFolder];
    else [self editSelected];
}

- (void)askNewFolder {
    ExteriaWeakReference *weak = _weak;
    ExteriaPromptText(NSLocalizedString(@"gifts.folder.new.title", nil), nil, @"", NSLocalizedString(@"gifts.folder.placeholder", nil), ^(NSString *text) {
        ExteriaGiftFolderBar *bar = weak.target;
        NSString *title = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!bar || !title.length) return;
        if (title.length > TITLE_CHARACTERS_MAX) title = [title substringToIndex:TITLE_CHARACTERS_MAX];
        [bar->_session createGiftFolderTitled:title withGifts:nil dialog:bar->_dialog completion:^(ExteriaGiftFolder *folder, NSString *errorName) {
            ExteriaGiftFolderBar *again = weak.target;
            if (!again) return;
            if (!folder) {
                NSLog(@"exteria: the gift folder was not made: %@", errorName);
                ExteriaShowNotice(nil, NSLocalizedString(@"gifts.folder.error", nil));
                return;
            }
            [again reload];
        }];
    });
}

- (void)editSelected {
    ExteriaGiftFolder *folder = [[_selected retain] autorelease];
    if (!folder) return;
    ExteriaWeakReference *weak = _weak;
    NSArray *choices = [NSArray arrayWithObjects:NSLocalizedString(@"gifts.folder.rename", nil), NSLocalizedString(@"gifts.folder.delete", nil), nil];
    ExteriaChoose(folder.title, choices, 1, ^(NSInteger index) {
        ExteriaGiftFolderBar *bar = weak.target;
        if (!bar) return;
        if (index == 0) [bar askRename:folder];
        else [bar confirmDelete:folder];
    });
}

- (void)askRename:(ExteriaGiftFolder *)folder {
    ExteriaWeakReference *weak = _weak;
    ExteriaPromptText(NSLocalizedString(@"gifts.folder.rename", nil), nil, folder.title, NSLocalizedString(@"gifts.folder.placeholder", nil), ^(NSString *text) {
        ExteriaGiftFolderBar *bar = weak.target;
        NSString *title = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!bar || !title.length || [title isEqualToString:folder.title]) return;
        if (title.length > TITLE_CHARACTERS_MAX) title = [title substringToIndex:TITLE_CHARACTERS_MAX];
        [bar->_session renameGiftFolder:folder to:title dialog:bar->_dialog completion:^(NSString *errorName) {
            ExteriaGiftFolderBar *again = weak.target;
            if (!again) return;
            if (errorName) {
                NSLog(@"exteria: the gift folder was not renamed: %@", errorName);
                ExteriaShowNotice(nil, NSLocalizedString(@"gifts.folder.error", nil));
                return;
            }
            [again reload];
        }];
    });
}

- (void)confirmDelete:(ExteriaGiftFolder *)folder {
    ExteriaWeakReference *weak = _weak;
    ExteriaConfirm(folder.title, NSLocalizedString(@"gifts.folder.delete.ask", nil), NSLocalizedString(@"gifts.folder.delete", nil), ^{
        ExteriaGiftFolderBar *bar = weak.target;
        if (!bar) return;
        [bar->_session deleteGiftFolder:folder dialog:bar->_dialog completion:^(NSString *errorName) {
            ExteriaGiftFolderBar *again = weak.target;
            if (!again) return;
            if (errorName) {
                NSLog(@"exteria: the gift folder was not deleted: %@", errorName);
                ExteriaShowNotice(nil, NSLocalizedString(@"gifts.folder.error", nil));
                return;
            }
            [again reload];
        }];
    });
}

@end
