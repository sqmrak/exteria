#import "exteria_chat_extras_controller.h"

#import "exteria_chat_preview_view.h"
#import "exteria_chat_settings.h"
#import "exteria_name_color_controller.h"
#import "exteria_person.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

@interface ExteriaChatExtrasController () {
    ExteriaSession *_session;
    ExteriaWeakReference *_weak;
    /* the account itself, loaded for the name color row */
    ExteriaPerson *_me;
    /* the demo dialog at the top; it redraws itself when a setting under it changes */
    ExteriaChatPreviewView *_preview;
}
@end

@implementation ExteriaChatExtrasController

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"settings.exteria.chats", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_me release];
    [_preview release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self loadMe];
}

/* the page stays up when the theme changes; its rows are made again in the new colors */
- (void)themeDidChange {
    /* the dialog reads its colors when it is made */
    [_preview release];
    _preview = nil;
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaChatExtrasController alloc] initWithSession:_session] autorelease];
}

- (void)loadMe {
    ExteriaWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        ExteriaChatExtrasController *me = weak.target;
        if (!me) return;
        if (!items.count) {
            NSLog(@"exteria: the account did not load for the chat settings: %@", errorName);
            return;
        }
        [me->_me release];
        me->_me = [[items objectAtIndex:0] retain];
        [me rebuild];
    }];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[self lookSection]];
    /* the color of the name needs the account, which the screen waits for */
    if (_me) {
        ExteriaSettingsRow *color = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolPerson tone:ExteriaSettingsTonePurple title:NSLocalizedString(@"chatset.namecolor", nil)
                                                             subtitle:nil value:_me.name tap:^{
            ExteriaChatExtrasController *me = weak.target;
            if (!me || !me->_me) return;
            ExteriaNameColorController *colors = [[[ExteriaNameColorController alloc] initWithSession:me->_session person:me->_me] autorelease];
            colors.changedHandler = ^(NSInteger colorId) { (void)colorId; [(ExteriaChatExtrasController *)weak.target loadMe]; };
            [me.navigationController pushViewController:colors animated:YES];
        }];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:color]]];
    }
    [sections addObject:[self mediaSection]];
    [sections addObject:[self messagesSection]];
    [sections addObject:[self menuSection]];
    [sections addObject:[self confirmSection]];
    self.sections = sections;
    [self reloadSettings];
}

#pragma mark sections

static ExteriaSettingsRow *ExteriaFlagRow(NSString *titleKey, NSString *infoKey, ExteriaChatFlag flag) {
    return [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(titleKey, nil) subtitle:infoKey ? NSLocalizedString(infoKey, nil) : nil
                                               on:ExteriaChatFlagGet(flag) toggle:^(BOOL on) {
        ExteriaChatFlagSet(flag, on);
        /* the demo dialog shows some of these, so it hears of every change */
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatSettingsDidChangeNotification object:nil];
    }];
}


/* what the demo dialog at the top shows and what moves it: the size and the shape of stickers, the time on them, and the quotes of replies */
- (ExteriaSettingsSection *)lookSection {
    ExteriaWeakReference *weak = _weak;
    /* the classic table has no row that is a view of the owner's, so there the dialog is left out */
    if (!_preview && !ExteriaThemeIsClassic()) {
        _preview = [[ExteriaChatPreviewView alloc] initWithTalk:ExteriaChatPreviewTalkExteria];
        _preview.heightHandler = ^{ [(ExteriaChatExtrasController *)weak.target updateRowHeights]; };
    }
    ExteriaChatPreviewView *preview = _preview;
    NSMutableArray *rows = [NSMutableArray array];
    if (preview) [rows addObject:[ExteriaSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { return [preview heightForWidth:width]; }]];
    [rows addObject:[ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.stickersize", nil) format:@"%.0f%%" value:(float)ExteriaChatStickerScale()
                                                   minimum:EXTERIA_STICKER_SCALE_MIN maximum:EXTERIA_STICKER_SCALE_MAX change:^(float value) {
        [(ExteriaChatExtrasController *)weak.target stickerScaleMoved:value];
    }]];
    [rows addObject:ExteriaFlagRow(@"chatset.hidestickertime", nil, ExteriaChatFlagHideStickerTime)];
    static NSString *const shapes[] = {@"chatset.shape.none", @"chatset.shape.rounded", @"chatset.shape.bubble"};
    [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"chatset.stickershape", nil) value:NSLocalizedString(shapes[ExteriaChatStickerShape()], nil) tap:^{
        ExteriaChatExtrasController *me = weak.target;
        if (!me) return;
        NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(shapes[0], nil), NSLocalizedString(shapes[1], nil), NSLocalizedString(shapes[2], nil), nil];
        ExteriaSettingsChoose(me, NSLocalizedString(@"chatset.stickershape", nil), options, ^(NSUInteger index) {
            ExteriaChatSetStickerShape((ExteriaStickerShape)index);
            [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatSettingsDidChangeNotification object:nil];
            [(ExteriaChatExtrasController *)weak.target rebuild];
        });
    }]];
    [rows addObject:ExteriaFlagRow(@"chatset.replycolors", @"chatset.replycolors.info", ExteriaChatFlagReplyColors)];
    [rows addObject:ExteriaFlagRow(@"chatset.replybackground", nil, ExteriaChatFlagReplyBackground)];
    return [ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:rows];
}

/* playback beyond the original: the step of the seek, what pauses a voice or a round message when the app goes down, and the camera and the sound of videos */
- (ExteriaSettingsSection *)mediaSection {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"chatset.seek", nil)
                                               value:[NSString stringWithFormat:NSLocalizedString(@"chatset.seek.value", nil), (int)ExteriaChatSeekSeconds()] tap:^{
        ExteriaChatExtrasController *me = weak.target;
        if (!me) return;
        NSArray *options = [NSArray arrayWithObjects:@"5", @"10", @"15", @"30", nil];
        ExteriaSettingsChoose(me, NSLocalizedString(@"chatset.seek", nil), options, ^(NSUInteger index) {
            ExteriaChatSetSeekSeconds([[options objectAtIndex:index] integerValue]);
            [(ExteriaChatExtrasController *)weak.target rebuild];
        });
    }]];
    [rows addObject:ExteriaFlagRow(@"chatset.pausevoice", nil, ExteriaChatFlagPauseVoiceOnMinimize)];
    [rows addObject:ExteriaFlagRow(@"chatset.pauseround", nil, ExteriaChatFlagPauseRoundOnMinimize)];
    [rows addObject:ExteriaFlagRow(@"chatset.noautonext", nil, ExteriaChatFlagNoAutoNextVoice)];
    [rows addObject:ExteriaFlagRow(@"chatset.unmutevolume", @"chatset.unmutevolume.info", ExteriaChatFlagUnmuteWithVolume)];
    [rows addObject:ExteriaFlagRow(@"chatset.alwayshd", @"chatset.alwayshd.info", ExteriaChatFlagAlwaysHD)];
    [rows addObject:ExteriaFlagRow(@"chatset.hidecameratile", nil, ExteriaChatFlagHideCameraTile)];
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.media.header", nil) footer:nil rows:rows];
}

/* what a double tap does is a choice of ten, kept apart for the messages of others and our own */
- (ExteriaSettingsRow *)doubleTapRowOutgoing:(BOOL)outgoing {
    static NSString *const keys[ExteriaDoubleTapCount] = {
        @"chatset.dt.none", @"chatset.dt.reaction", @"chatset.dt.picker", @"chatset.dt.translate", @"chatset.dt.reply",
        @"chatset.dt.forward", @"chatset.dt.save", @"chatset.dt.repeat", @"chatset.dt.edit", @"chatset.dt.delete"};
    ExteriaWeakReference *weak = _weak;
    NSString *title = NSLocalizedString(outgoing ? @"chatset.doubletap.out" : @"chatset.doubletap.in", nil);
    return [ExteriaSettingsRow rowWithTitle:title value:NSLocalizedString(keys[ExteriaChatDoubleTap(outgoing)], nil) tap:^{
        ExteriaChatExtrasController *me = weak.target;
        if (!me) return;
        NSMutableArray *options = [NSMutableArray array];
        /* editing is only for our own messages */
        for (int action = 0; action < ExteriaDoubleTapCount; ++action) {
            if (action == ExteriaDoubleTapEdit && !outgoing) continue;
            [options addObject:NSLocalizedString(keys[action], nil)];
        }
        ExteriaSettingsChoose(me, title, options, ^(NSUInteger index) {
            int action = (int)index;
            if (!outgoing && action >= ExteriaDoubleTapEdit) ++action;
            ExteriaChatSetDoubleTap(outgoing, (ExteriaDoubleTapAction)action);
            [(ExteriaChatExtrasController *)weak.target rebuild];
        });
    }];
}

/* the emoji a double tap sends; the chat falls back to its first reaction when it does not offer the one chosen */
- (ExteriaSettingsRow *)quickReactionRow {
    static NSString *const choices[] = {@"\u2764", @"\U0001F44D", @"\U0001F44E", @"\U0001F525", @"\U0001F970", @"\U0001F44F", @"\U0001F601", @"\U0001F914",
                                        @"\U0001F622", @"\U0001F389", @"\U0001F92F", @"\U0001F631"};
    ExteriaWeakReference *weak = _weak;
    NSString *title = NSLocalizedString(@"chatset.quickreaction", nil);
    return [ExteriaSettingsRow rowWithTitle:title value:ExteriaChatQuickReaction() tap:^{
        ExteriaChatExtrasController *me = weak.target;
        if (!me) return;
        NSMutableArray *options = [NSMutableArray array];
        for (size_t i = 0; i < sizeof(choices) / sizeof(choices[0]); ++i) [options addObject:choices[i]];
        ExteriaSettingsChoose(me, title, options, ^(NSUInteger index) {
            ExteriaChatSetQuickReaction([options objectAtIndex:index]);
            [(ExteriaChatExtrasController *)weak.target rebuild];
        });
    }];
}

- (void)stickerScaleMoved:(float)value {
    NSInteger percent = (NSInteger)(value + 0.5f);
    if (percent == ExteriaChatStickerScale()) return;
    ExteriaChatSetStickerScale(percent);
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaChatSettingsDidChangeNotification object:nil];
}

/* how messages look and answer a tap */
- (ExteriaSettingsSection *)messagesSection {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:ExteriaFlagRow(@"chatset.mentioncomma", @"chatset.mentioncomma.info", ExteriaChatFlagCommaAfterMention)];
    [rows addObject:ExteriaFlagRow(@"chatset.editedicon", nil, ExteriaChatFlagEditedIcon)];
    [rows addObject:ExteriaFlagRow(@"chatset.notail", @"chatset.notail.info", ExteriaChatFlagRemoveTail)];
    [rows addObject:ExteriaFlagRow(@"chatset.pollresults", @"chatset.pollresults.info", ExteriaChatFlagPollResultsFirst)];
    [rows addObject:ExteriaFlagRow(@"chatset.forwarddate", nil, ExteriaChatFlagForwardDate)];
    [rows addObject:ExteriaFlagRow(@"chatset.hideshare", nil, ExteriaChatFlagHideShare)];
    [rows addObject:ExteriaFlagRow(@"chatset.hidesendas", @"chatset.hidesendas.info", ExteriaChatFlagHideSendAs)];
    [rows addObject:ExteriaFlagRow(@"chatset.noreactions.private", nil, ExteriaChatFlagHideReactionsPrivate)];
    [rows addObject:ExteriaFlagRow(@"chatset.noreactions.groups", nil, ExteriaChatFlagHideReactionsGroups)];
    [rows addObject:ExteriaFlagRow(@"chatset.noreactions.channels", nil, ExteriaChatFlagHideReactionsChannels)];
    [rows addObject:[self doubleTapRowOutgoing:NO]];
    [rows addObject:[self doubleTapRowOutgoing:YES]];
    [rows addObject:[self quickReactionRow]];
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.messages.header", nil) footer:NSLocalizedString(@"chatset.doubletap.info", nil) rows:rows];
}

/* the entries the menu of a message may add */
- (ExteriaSettingsSection *)menuSection {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:ExteriaFlagRow(@"chatset.menu.save", nil, ExteriaChatFlagMenuSave)];
    [rows addObject:ExteriaFlagRow(@"chatset.menu.repeat", nil, ExteriaChatFlagMenuRepeat)];
    [rows addObject:ExteriaFlagRow(@"chatset.menu.details", nil, ExteriaChatFlagMenuDetails)];
    [rows addObject:ExteriaFlagRow(@"chatset.menu.bookmark", nil, ExteriaChatFlagMenuBookmark)];
    [rows addObject:ExteriaFlagRow(@"chatset.menu.copyphoto", nil, ExteriaChatFlagMenuCopyPhoto)];
    [rows addObject:ExteriaFlagRow(@"chatset.menu.noquote", nil, ExteriaChatFlagMenuNoQuote)];
    [rows addObject:ExteriaFlagRow(@"chatset.menu.history", nil, ExteriaChatFlagMenuHistory)];
    [rows addObject:ExteriaFlagRow(@"chatset.menu.report", nil, ExteriaChatFlagMenuReport)];
    [rows addObject:ExteriaFlagRow(@"chatset.menu.remind", nil, ExteriaChatFlagMenuRemind)];
    [rows addObject:ExteriaFlagRow(@"chatset.menu.replyprivate", nil, ExteriaChatFlagMenuReplyPrivate)];
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.menu.header", nil) footer:NSLocalizedString(@"chatset.menu.header.info", nil) rows:rows];
}

/* the questions asked before something that cannot be taken back, and what happens to a link */
- (ExteriaSettingsSection *)confirmSection {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:ExteriaFlagRow(@"chatset.askcall", nil, ExteriaChatFlagAskCall)];
    [rows addObject:ExteriaFlagRow(@"chatset.askrepeat", nil, ExteriaChatFlagAskRepeat)];
    [rows addObject:ExteriaFlagRow(@"chatset.askrecording", nil, ExteriaChatFlagAskRecording)];
    [rows addObject:ExteriaFlagRow(@"chatset.askbotcommand", nil, ExteriaChatFlagAskBotCommand)];
    static NSString *const keys[] = {@"chatset.linkask.never", @"chatset.linkask.hidden", @"chatset.linkask.always"};
    [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"chatset.linkask", nil) value:NSLocalizedString(keys[ExteriaChatLinkConfirm()], nil) tap:^{
        ExteriaChatExtrasController *me = weak.target;
        if (!me) return;
        NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(keys[0], nil), NSLocalizedString(keys[1], nil), NSLocalizedString(keys[2], nil), nil];
        ExteriaSettingsChoose(me, NSLocalizedString(@"chatset.linkask", nil), options, ^(NSUInteger index) {
            ExteriaChatSetLinkConfirm((ExteriaLinkConfirm)index);
            [(ExteriaChatExtrasController *)weak.target rebuild];
        });
    }]];
    [rows addObject:ExteriaFlagRow(@"chatset.nolinkpreview", @"chatset.nolinkpreview.info", ExteriaChatFlagNoLinkPreview)];
    [rows addObject:ExteriaFlagRow(@"chatset.deleteforme", @"chatset.deleteforme.info", ExteriaChatFlagDeleteForMe)];
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.confirm.header", nil) footer:nil rows:rows];
}

@end
