#import "exteria_location_controller.h"
#import "exteria_bar_button.h"
#import "exteria_image_decoder.h"
#import "exteria_map_view.h"
#import "exteria_session_bots.h"
#import "exteria_theme.h"
#import "exteria_platform.h"
#import "exteria_weak_reference.h"
#import "exteria_symbol.h"
#import <CoreLocation/CoreLocation.h>
#import <QuartzCore/QuartzCore.h>

@interface ExteriaLocationController () <ExteriaMapViewDelegate,UITableViewDataSource,UITableViewDelegate,UISearchBarDelegate,CLLocationManagerDelegate,UIActionSheetDelegate> {
    ExteriaSession *_session;
    ExteriaDialog *_dialog;
    ExteriaWeakReference *_weak;
    ExteriaMapView *_map;
    UITableView *_table;
    UISearchBar *_search;
    UIButton *_position, *_plus, *_minus;
    /* the modern top bar, which replaces the system bar; the classic style keeps the system one */
    UIView *_header;
    UILabel *_headerTitle;
    ExteriaBarButton *_headerClose;
    UIButton *_headerAction;
    UIImage *_badgeSend, *_badgePlace, *_badgeIdle;
    /* the category pictures of the places the bot sent, as the badges of their rows, by the id of the result */
    NSMutableDictionary *_placeIcons;
    NSMutableSet *_placeIconAsks;
    UILabel *_details;
    CLLocationManager *_manager;
    CLLocation *_fix;
    ExteriaPerson *_bot;
    NSArray *_venues;
    ExteriaInlineResult *_selectedVenue;
    NSString *_searchError;
    exteria_geo_point _location;
    void (^_selection)(exteria_geo_point);
    void (^_closeHandler)(void);
    NSUInteger _generation;
    BOOL _hasPoint, _manual, _followFix, _loading, _closed, _botLoading, _searched, _searchOpen;
}
@end

/* how far the list card of the modern style rises over the foot of the map */
#define MODERN_CARD_RISE 16.0
#define MODERN_BAR_HEIGHT 44.0
#define MODERN_BUTTON 44.0

/* a round badge with a white pin, the icon of a row of the modern list */
static UIImage *ExteriaLocationBadge(ExteriaSymbol symbol, UIColor *fill) {
    CGFloat side=40;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side,side),NO,0);
    CGContextRef context=UIGraphicsGetCurrentContext();
    [fill setFill];
    CGContextFillEllipseInRect(context,CGRectMake(0,0,side,side));
    UIImage *glyph=ExteriaSymbolImage(symbol,20,[UIColor whiteColor]);
    [glyph drawInRect:CGRectMake((side-glyph.size.width)/2,(side-glyph.size.height)/2,glyph.size.width,glyph.size.height)];
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* the disc of a place row: the category picture the bot sent, or nothing yet */
static UIImage *ExteriaLocationPlaceBadge(UIImage *icon) {
    CGFloat side=40;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side,side),NO,0);
    CGContextRef context=UIGraphicsGetCurrentContext();
    [ExteriaColorField() setFill];
    CGContextFillEllipseInRect(context,CGRectMake(0,0,side,side));
    if (icon && icon.size.width>0 && icon.size.height>0) {
        CGFloat fit=MIN(28/icon.size.width,28/icon.size.height);
        CGSize size=CGSizeMake(icon.size.width*fit,icon.size.height*fit);
        [icon drawInRect:CGRectMake((side-size.width)/2,(side-size.height)/2,size.width,size.height)];
    }
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@implementation ExteriaLocationController
@synthesize closeHandler=_closeHandler;
- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog location:(exteria_geo_point)location
             selection:(void (^)(exteria_geo_point))selection {
    self=[super init];
    if (!self) return nil;
    _session=[session retain]; _dialog=[dialog retain]; _location=location; _selection=[selection copy];
    _weak=[[ExteriaWeakReference referenceTo:self] retain]; _hasPoint=location.valid; _followFix=selection!=nil;
    if ([self respondsToSelector:NSSelectorFromString(@"setEdgesForExtendedLayout:")])
        [self setValue:[NSNumber numberWithUnsignedInteger:0] forKey:@"edgesForExtendedLayout"];
    if ([self respondsToSelector:NSSelectorFromString(@"setAutomaticallyAdjustsScrollViewInsets:")])
        [self setValue:[NSNumber numberWithBool:NO] forKey:@"automaticallyAdjustsScrollViewInsets"];
    self.title=NSLocalizedString(selection ? @"map.send.title" : @"preview.location",nil);
    return self;
}
- (void)dealloc {
    [self cancel];
    [_session release]; [_dialog release]; [_weak release]; [_map release]; [_table release]; [_search release];
    [_position release]; [_plus release]; [_minus release]; [_details release];
    [_header release]; [_headerTitle release]; [_headerClose release]; [_headerAction release];
    [_badgeSend release]; [_badgePlace release]; [_badgeIdle release]; [_placeIcons release]; [_placeIconAsks release];
    [_fix release]; [_bot release]; [_venues release]; [_selectedVenue release]; [_searchError release]; [_selection release]; [_closeHandler release];
    [super dealloc];
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button=[[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    button.titleLabel.font=ExteriaFontMedium(15); button.backgroundColor=ExteriaColorCard();
    button.layer.cornerRadius=20; button.accessibilityLabel=title;
    if (!ExteriaThemeIsClassic()) {
        /* a round button that floats over the map, as the buttons of the map in the original client do */
        button.layer.cornerRadius=22; button.layer.shadowColor=[UIColor blackColor].CGColor; button.layer.shadowOpacity=0.28f;
        button.layer.shadowRadius=4; button.layer.shadowOffset=CGSizeMake(0,2);
    }
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_map addSubview:button];
    return button;
}
- (void)loadView {
    UIView *root=[[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    root.backgroundColor=ExteriaColorScreen(); self.view=root;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resignedActive) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(becameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    BOOL classic=ExteriaThemeIsClassic();
    if (classic) {
        self.navigationItem.leftBarButtonItem=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(close)] autorelease];
        if (!_selection) self.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(showActions)] autorelease];
        else self.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch target:self action:@selector(toggleSearch)] autorelease];
    } else {
        _header=[[UIView alloc] init]; _header.backgroundColor=ExteriaColorBar();
        _headerTitle=[[UILabel alloc] init]; _headerTitle.backgroundColor=[UIColor clearColor]; _headerTitle.font=ExteriaFontSemibold(17);
        _headerTitle.textColor=ExteriaColorTitle(); _headerTitle.textAlignment=ExteriaTextAlignmentCenter; _headerTitle.text=self.title;
        [_header addSubview:_headerTitle];
        _headerClose=[[ExteriaBarButton alloc] init]; _headerClose.title=NSLocalizedString(@"attach.cancel",nil);
        [_headerClose addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
        [_header addSubview:_headerClose];
        _headerAction=[[UIButton buttonWithType:UIButtonTypeCustom] retain];
        [_headerAction setImage:ExteriaSymbolImage(_selection ? ExteriaSymbolMagnifier : ExteriaSymbolEllipsisVertical,22,ExteriaColorAccent()) forState:UIControlStateNormal];
        _headerAction.accessibilityLabel=NSLocalizedString(_selection ? @"map.search" : @"profile.more",nil);
        [_headerAction addTarget:self action:_selection ? @selector(toggleSearch) : @selector(showActions) forControlEvents:UIControlEventTouchUpInside];
        [_header addSubview:_headerAction];
        _badgeSend=[ExteriaLocationBadge(ExteriaSymbolMapPin,ExteriaColorAccent()) retain];
        /* a place stands on a plain disc until its own picture comes; the pin is the sign of the chosen point alone */
        _badgePlace=[ExteriaLocationPlaceBadge(nil) retain];
        _badgeIdle=[ExteriaLocationBadge(ExteriaSymbolMapPin,ExteriaColorMuted()) retain];
    }
    _map=[[ExteriaMapView alloc] initWithFrame:CGRectZero]; _map.picking=_selection!=nil; _map.delegate=self;
    if (_location.valid) [_map showLocation:_location zoom:15];
    [root addSubview:_map];
    _position=[self button:NSLocalizedString(@"map.my_position",nil) action:@selector(locate)];
    [_position setTitle:nil forState:UIControlStateNormal];
    [_position setImage:ExteriaSymbolImage(ExteriaSymbolMapPin,24,ExteriaColorAccent()) forState:UIControlStateNormal];
    _plus=[self button:@"+" action:@selector(zoomIn)]; _minus=[self button:@"−" action:@selector(zoomOut)];
    /* the map zooms by pinch and double tap in the modern style, as it does in the original client */
    _plus.hidden=_minus.hidden=!classic;
    if (_selection) {
        _search=[[UISearchBar alloc] init]; _search.delegate=self;
        _search.placeholder=NSLocalizedString(@"map.search",nil);
        _search.showsCancelButton=YES; _search.hidden=YES;
        _search.barStyle=ExteriaThemeIsDark() ? UIBarStyleBlack : UIBarStyleDefault;
        [root addSubview:_search];
        _table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _table.dataSource=self; _table.delegate=self;
        _table.backgroundColor=classic ? ExteriaColorScreen() : ExteriaColorCard(); _table.separatorColor=ExteriaColorHairline();
        if (!classic) {
            /* a card that rises over the foot of the map, with a spacer that keeps the first row under its round corners */
            _table.layer.cornerRadius=16; _table.clipsToBounds=YES; _table.showsVerticalScrollIndicator=NO;
            UIView *spacer=[[[UIView alloc] initWithFrame:CGRectMake(0,0,10,MODERN_CARD_RISE+4)] autorelease]; spacer.backgroundColor=ExteriaColorCard();
            _table.tableHeaderView=spacer;
        }
        [root addSubview:_table];
    } else {
        _details=[[UILabel alloc] init]; _details.font=ExteriaFontRegular(15); _details.textColor=ExteriaColorTitle();
        _details.backgroundColor=ExteriaColorCard(); _details.numberOfLines=3;
        NSString *title=[NSString stringWithUTF8String:_location.title],*address=[NSString stringWithUTF8String:_location.address];
        _details.text=[NSString stringWithFormat:@"%@%@%.6f, %.6f", title.length ? [title stringByAppendingString:@"\n"] : @"",
            address.length ? [address stringByAppendingString:@"\n"] : @"",_location.latitude,_location.longitude];
        [root addSubview:_details];
    }
    if (_header) [root addSubview:_header];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_header) [self.navigationController setNavigationBarHidden:YES animated:animated];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_selection && !_closed) { [self locate]; [self loadBot]; }
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopLocating]; [_map cancelTiles];
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return ExteriaAllowsOrientation(orientation); }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size=self.view.bounds.size;
    BOOL modern=_header!=nil;
    CGFloat top=0;
    if (modern) {
        UIEdgeInsets insets=ExteriaLayoutInsets(self);
        top=insets.top+MODERN_BAR_HEIGHT;
        _header.frame=CGRectMake(0,0,size.width,top);
        CGFloat barY=insets.top;
        _headerClose.frame=CGRectMake(MAX(insets.left,0)+4,barY,88,MODERN_BAR_HEIGHT);
        _headerAction.frame=CGRectMake(size.width-MAX(insets.right,0)-MODERN_BAR_HEIGHT-4,barY,MODERN_BAR_HEIGHT,MODERN_BAR_HEIGHT);
        _headerTitle.frame=CGRectMake(100,barY,MAX(0,size.width-200),MODERN_BAR_HEIGHT);
    }
    CGFloat searchHeight=_selection && _searchOpen ? 44 : 0;
    BOOL searching=_search.text.length>0;
    CGFloat room=size.height-top;
    CGFloat mapHeight=_selection ? (searching ? 0 : MAX(130,floor((room-searchHeight)*0.52))) : MAX(0,room-94);
    CGFloat rise=modern ? MODERN_CARD_RISE : 0;
    _search.frame=CGRectMake(0,top,size.width,searchHeight);
    _map.hidden=searching; _map.frame=CGRectMake(0,top+searchHeight,size.width,mapHeight);
    /* the card of the modern list covers the foot of the map, so the map is as tall as the list lets it be seen */
    _table.frame=CGRectMake(0,top+searchHeight+mapHeight-(searching ? 0 : rise),size.width,MAX(0,room-searchHeight-mapHeight+(searching ? 0 : rise)));
    _details.frame=CGRectMake(12,top+mapHeight,size.width-24,94);
    if (modern) {
        _position.frame=CGRectMake(MAX(0,size.width-MODERN_BUTTON-12),MAX(12,mapHeight-rise-MODERN_BUTTON-12),MODERN_BUTTON,MODERN_BUTTON);
        return;
    }
    _position.frame=CGRectMake(MAX(0,size.width-52),MAX(12,mapHeight-68),40,40);
    _plus.frame=CGRectMake(12,12,40,40); _minus.frame=CGRectMake(12,56,40,40);
}
- (void)alert:(NSString *)message {
    id alert=[[NSClassFromString(@"UIAlertView") alloc] initWithTitle:nil message:message delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok",nil) otherButtonTitles:nil];
    [alert show]; [alert release];
}
- (void)stopLocating {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(locationTimedOut) object:nil];
    _manager.delegate=nil; [_manager stopUpdatingLocation]; [_manager release]; _manager=nil;
}
- (void)locate {
    if (_closed) return;
    CLAuthorizationStatus status=[CLLocationManager authorizationStatus];
    if (![CLLocationManager locationServicesEnabled] || status==kCLAuthorizationStatusDenied || status==kCLAuthorizationStatusRestricted) {
        [self alert:NSLocalizedString(@"attach.location.denied",nil)]; return;
    }
    /* a manager that waits for the answer to the prompt stays as it is, or a second one would ask again */
    if (_manager && status==kCLAuthorizationStatusNotDetermined) return;
    [self stopLocating]; _followFix=YES;
    _manager=[[CLLocationManager alloc] init]; _manager.delegate=self;
    _manager.desiredAccuracy=kCLLocationAccuracyHundredMeters;
    SEL ask=NSSelectorFromString(@"requestWhenInUseAuthorization");
    if ([_manager respondsToSelector:ask]) [_manager performSelector:ask];
    [_manager startUpdatingLocation];
    [self performSelector:@selector(locationTimedOut) withObject:nil afterDelay:15];
}
- (void)locationTimedOut {
    /* the time a person takes to answer the prompt is not the time a fix takes */
    if (!_closed && _manager && [CLLocationManager authorizationStatus]==kCLAuthorizationStatusNotDetermined) {
        [self performSelector:@selector(locationTimedOut) withObject:nil afterDelay:15];
        return;
    }
    [self stopLocating];
    if (!_closed) [self alert:NSLocalizedString(@"attach.location.failed",nil)];
}
- (void)handleFix:(CLLocation *)fix {
    if (_closed || !fix || !exteria_geo_valid(fix.coordinate.latitude,fix.coordinate.longitude) ||
        fix.horizontalAccuracy<0 || fix.horizontalAccuracy>1500 || fabs([fix.timestamp timeIntervalSinceNow])>30) return;
    [_fix release]; _fix=[fix retain];
    exteria_geo_point user;
    memset(&user,0,sizeof(user)); user.valid=1;
    user.latitude=fix.coordinate.latitude; user.longitude=fix.coordinate.longitude; user.accuracy=fix.horizontalAccuracy;
    [_map showUserLocation:user];
    if (_followFix) {
        [_selectedVenue release]; _selectedVenue=nil;
        [_map setCenterLatitude:fix.coordinate.latitude longitude:fix.coordinate.longitude zoom:15];
        _hasPoint=YES; _manual=NO;
        [_table reloadData];
        if (_selection && !_searched) [self requestPlaces];
    }
    [self stopLocating];
}
- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)fix fromLocation:(CLLocation *)old {
    (void)old; if (manager==_manager) [self handleFix:fix];
}
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations { if (manager==_manager) [self handleFix:[locations lastObject]]; }
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if (manager!=_manager || error.code==kCLErrorLocationUnknown) return;
    [self stopLocating];
    if (!_closed) [self alert:NSLocalizedString(error.code==kCLErrorDenied ? @"attach.location.denied" : @"attach.location.failed",nil)];
}
- (void)mapView:(ExteriaMapView *)map didChangeCenter:(BOOL)finished {
    (void)map;
    _followFix=NO;
    if (!_selection) return;
    [_selectedVenue release]; _selectedVenue=nil;
    _manual=YES; _followFix=NO; _hasPoint=YES; _loading=NO; ++_generation;
    UITableViewCell *cell=[_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    cell.textLabel.text=NSLocalizedString(@"map.send_selected",nil);
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%.6f, %.6f",_map.latitude,_map.longitude];
    if (finished) [_table reloadData];
}
- (void)mapView:(ExteriaMapView *)map didSelectPlace:(NSUInteger)index {
    if (_closed || !_selection || index>=_venues.count) return;
    [_selectedVenue release]; _selectedVenue=[[_venues objectAtIndex:index] retain];
    [map showLocation:_selectedVenue.media.location zoom:map.zoom];
    _hasPoint=YES; _manual=YES; _followFix=NO; [_table reloadData];
}
- (void)loadBot {
    if (!_session || !_dialog || _bot || _botLoading || _closed) return;
    _botLoading=YES;
    ExteriaWeakReference *weak=_weak;
    [_session loadVenueSearchBot:^(ExteriaPerson *bot,NSString *error) {
        ExteriaLocationController *screen=weak.target;
        if (!screen || screen->_closed) return;
        screen->_botLoading=NO;
        [screen->_bot release]; screen->_bot=[bot retain];
        [screen->_searchError release]; screen->_searchError=[error copy];
        if (error) NSLog(@"exteria: venue bot lookup failed: %@",error);
        [screen->_table reloadData];
        if (bot && (screen->_hasPoint || screen->_search.text.length)) [screen requestPlaces];
    }];
}
/* direct venue image URLs would bypass the selected network route */
- (void)loadIconOfResult:(ExteriaInlineResult *)result {
    if (_closed || !result.resultId || !result.thumb.proxied || [_placeIconAsks containsObject:result.resultId] || _placeIconAsks.count>=64) return;
    if (!_placeIconAsks) _placeIconAsks=[[NSMutableSet alloc] init];
    [_placeIconAsks addObject:result.resultId];
    NSString *identifier=[[result.resultId copy] autorelease];
    ExteriaWeakReference *weak=_weak;
    [_session loadWebFile:result.thumb completion:^(NSData *data,NSString *errorName) {
        ExteriaLocationController *screen=weak.target;
        if (!screen || screen->_closed) return;
        UIImage *picture=data.length<=256*1024 ? ExteriaDecodeImage(data,64) : nil;
        if (!picture) {
            if (errorName) NSLog(@"exteria: place picture not loaded: %@",errorName);
            return;
        }
        if (!screen->_placeIcons) screen->_placeIcons=[[NSMutableDictionary alloc] init];
        [screen->_placeIcons setObject:ExteriaLocationPlaceBadge(picture) forKey:identifier];
        [screen->_table reloadData];
    }];
}
- (void)searchPlaces {
    if (_closed || (!_hasPoint && !_search.text.length)) return;
    [_search resignFirstResponder];
    [self requestPlaces];
}
- (void)requestPlaces {
    if (_closed || (!_hasPoint && !_search.text.length)) return;
    if (!_bot) { [self loadBot]; return; }
    _searched=YES; _loading=YES;
    [_searchError release]; _searchError=nil; [_table reloadData];
    NSUInteger generation=++_generation;
    ExteriaWeakReference *weak=_weak;
    [_session searchVenues:_search.text ? _search.text : @"" latitude:_map.latitude longitude:_map.longitude bot:_bot inDialog:_dialog
        completion:^(ExteriaInlinePage *page,NSString *error) {
        ExteriaLocationController *screen=weak.target;
        if (!screen || screen->_closed || generation!=screen->_generation) return;
        screen->_loading=NO;
        NSMutableArray *venues=[NSMutableArray array];
        for (ExteriaInlineResult *result in page.results) if (result.kind==EXTERIA_INLINE_LOCATION && result.media.location.valid) [venues addObject:result];
        [screen->_venues release]; screen->_venues=[venues copy];
        NSMutableData *points=[NSMutableData data];
        for (NSUInteger i=0;i<MIN((NSUInteger)16,venues.count);++i) {
            exteria_geo_point point=[(ExteriaInlineResult *)[venues objectAtIndex:i] media].location;
            [points appendBytes:&point length:sizeof(point)];
        }
        [screen->_map showPlaces:points];
        [screen->_searchError release]; screen->_searchError=[error copy];
        if (error) NSLog(@"exteria: venue search failed: %@",error);
        [screen->_table reloadData];
    }];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    (void)searchBar; (void)text;
    ++_generation; _loading=NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(requestPlaces) object:nil];
    [self.view setNeedsLayout];
    [_venues release]; _venues=nil; [_map showPlaces:nil]; [_table reloadData];
    [self performSelector:@selector(requestPlaces) withObject:nil afterDelay:0.35];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; [self requestPlaces]; }
- (void)toggleSearch {
    if (_searchOpen) { [self searchBarCancelButtonClicked:_search]; return; }
    _searchOpen=YES; _search.hidden=NO; [self.view setNeedsLayout]; [_search becomeFirstResponder];
}
- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder]; searchBar.text=@""; searchBar.hidden=YES; _searchOpen=NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(requestPlaces) object:nil];
    ++_generation; _loading=NO; [_venues release]; _venues=nil; [_map showPlaces:nil];
    [self.view setNeedsLayout]; [_table reloadData];
    if (_hasPoint) [self requestPlaces];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; return section==0 ? 1 : (NSInteger)MAX((NSUInteger)1,_venues.count);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; return section==1 && !_header ? NSLocalizedString(@"map.nearby",nil) : nil;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (!_header || section!=1) return nil;
    UIView *bar=[[[UIView alloc] initWithFrame:CGRectMake(0,0,320,34)] autorelease];
    bar.backgroundColor=ExteriaColorCard();
    UILabel *label=[[[UILabel alloc] initWithFrame:CGRectMake(16,8,288,22)] autorelease];
    label.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    label.backgroundColor=[UIColor clearColor]; label.font=ExteriaFontSemibold(14); label.textColor=ExteriaColorAccent();
    label.text=NSLocalizedString(@"map.nearby",nil);
    [bar addSubview:label];
    return bar;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (!_header) return section==1 ? 24 : 0.01f;
    return section==1 ? 34 : 0.01f;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    /* the modern list carries no credit line under the places */
    if (_header || section!=1 || !_venues.count) return nil;
    exteria_geo_point point=[(ExteriaInlineResult *)[_venues objectAtIndex:0] media].location;
    return !strcmp(point.provider,"foursquare") ? NSLocalizedString(@"map.foursquare",nil) : nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path { (void)tableView; (void)path; return 64; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"place"];
    if (!cell) cell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"place"] autorelease];
    cell.backgroundColor=ExteriaColorCard(); cell.textLabel.textColor=ExteriaColorTitle();
    cell.textLabel.font=ExteriaFontMedium(15); cell.detailTextLabel.font=ExteriaFontRegular(12);
    cell.detailTextLabel.textColor=ExteriaColorSecondary(); cell.detailTextLabel.numberOfLines=2;
    cell.accessoryType=UITableViewCellAccessoryNone; cell.imageView.image=nil; cell.detailTextLabel.text=nil;
    cell.selectionStyle=UITableViewCellSelectionStyleBlue;
    if (_header) {
        /* the rows of the modern list are set in from the badge, as the lists of the app are */
        cell.textLabel.font=ExteriaFontSemibold(16);
        SEL inset=NSSelectorFromString(@"setSeparatorInset:");
        if ([cell respondsToSelector:inset]) [cell setValue:[NSValue valueWithUIEdgeInsets:UIEdgeInsetsMake(0,68,0,0)] forKey:@"separatorInset"];
    }
    if (path.section==0) {
        cell.textLabel.text=NSLocalizedString(!_hasPoint ? @"map.choose_point" : (_manual ? @"map.send_selected" : @"map.send_current"),nil);
        if (_selectedVenue) cell.textLabel.text=NSLocalizedString(@"map.send_place",nil);
        cell.textLabel.textColor=_hasPoint ? ExteriaColorAccent() : ExteriaColorSecondary();
        cell.imageView.image=_header ? (_hasPoint ? _badgeSend : _badgeIdle) : ExteriaSymbolImage(ExteriaSymbolSendArrow,24,_hasPoint ? ExteriaColorAccent() : ExteriaColorSecondary());
        if (_hasPoint) cell.detailTextLabel.text=[NSString stringWithFormat:@"%.6f, %.6f%@",_map.latitude,_map.longitude,
            !_manual && _fix ? [NSString stringWithFormat:@" · ±%.0f m",_fix.horizontalAccuracy] : @""];
        if (_selectedVenue) cell.detailTextLabel.text=[NSString stringWithUTF8String:_selectedVenue.media.location.title];
    } else if (_venues.count) {
        ExteriaInlineResult *result=[_venues objectAtIndex:(NSUInteger)path.row];
        exteria_geo_point point=result.media.location;
        cell.textLabel.text=result.title.length ? result.title : [NSString stringWithUTF8String:point.title];
        cell.detailTextLabel.text=result.subtitle.length ? result.subtitle : [NSString stringWithUTF8String:point.address];
        UIImage *placeIcon=[_placeIcons objectForKey:result.resultId];
        if (!placeIcon) [self loadIconOfResult:result];
        cell.imageView.image=placeIcon ? placeIcon : (_header ? _badgePlace : ExteriaSymbolImage(ExteriaSymbolMapPin,24,ExteriaColorAccent()));
        cell.accessoryType=_header ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text=NSLocalizedString(_loading || _botLoading ? @"map.loading" : (_searchError ? @"map.places_failed" : @"map.no_places"),nil);
        cell.detailTextLabel.text=_searchError ? NSLocalizedString(@"map.retry_places",nil) : nil;
        cell.textLabel.textColor=ExteriaColorSecondary();
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (_closed) return;
    if (path.section==1 && !_venues.count) { [self searchPlaces]; return; }
    if ((!_hasPoint && path.section==0) || !_selection) return;
    exteria_geo_point point;
    memset(&point,0,sizeof(point));
    if (path.section==1) point=[(ExteriaInlineResult *)[_venues objectAtIndex:(NSUInteger)path.row] media].location;
    else if (_selectedVenue) point=_selectedVenue.media.location;
    else { point.valid=1; point.latitude=_map.latitude; point.longitude=_map.longitude; point.accuracy=!_manual && _fix ? MIN(1500,_fix.horizontalAccuracy) : 0; }
    if (!point.valid) return;
    [self cancel]; _selection(point);
}
- (void)zoomIn { _map.zoom=_map.zoom+1; }
- (void)zoomOut { _map.zoom=_map.zoom-1; }
- (void)showActions {
    UIActionSheet *sheet=[[[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:NSLocalizedString(@"attach.cancel",nil)
        destructiveButtonTitle:nil otherButtonTitles:NSLocalizedString(@"map.copy_coordinates",nil),NSLocalizedString(@"map.copy_link",nil),NSLocalizedString(@"map.open_osm",nil),nil] autorelease];
    sheet.tag=2; [sheet showInView:self.view];
}
- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index==sheet.cancelButtonIndex || _closed) return;
    NSString *link=[NSString stringWithFormat:@"https://www.openstreetmap.org/?mlat=%.6f&mlon=%.6f#map=15/%.6f/%.6f",
        _location.latitude,_location.longitude,_location.latitude,_location.longitude];
    if (index==0) [UIPasteboard generalPasteboard].string=[NSString stringWithFormat:@"%.6f, %.6f",_location.latitude,_location.longitude];
    else if (index==1) [UIPasteboard generalPasteboard].string=link;
    else if (index==2) [[UIApplication sharedApplication] openURL:[NSURL URLWithString:link]];
}
- (void)cancel {
    if (_closed) return;
    _closed=YES; ++_generation; [_weak clear];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self]; [self stopLocating]; [_map cancelTiles];
    _map.delegate=nil; _search.delegate=nil;
}
- (void)resignedActive {
    [_map cancelTiles];
    /* the permission prompt of the system takes the app out of the active state; letting the manager go then closes the prompt, and coming back asks again, which made it blink in a loop */
    if ([CLLocationManager authorizationStatus]==kCLAuthorizationStatusNotDetermined) return;
    [self stopLocating];
}
- (void)becameActive {
    if (_closed || !self.view.window) return;
    [_map setNeedsLayout];
    if (_followFix && !_fix) [self locate];
}
- (void)close { [self cancel]; [self dismissViewControllerAnimated:YES completion:^{ if (_closeHandler) _closeHandler(); }]; }
@end
