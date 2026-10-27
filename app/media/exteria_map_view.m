#import "exteria_map_view.h"
#import "exteria_map_tiles.h"
#import "exteria_weak_reference.h"
#import "exteria_theme.h"
#import "exteria_symbol.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

@interface ExteriaMapPin : UIView
@end
@implementation ExteriaMapPin
- (void)drawRect:(CGRect)rect {
    (void)rect;
    [[UIColor colorWithRed:0.91 green:0.22 blue:0.34 alpha:1] setFill];
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(14,40)];
    [path addCurveToPoint:CGPointMake(1,15) controlPoint1:CGPointMake(12,31) controlPoint2:CGPointMake(1,25)];
    [path addArcWithCenter:CGPointMake(14,15) radius:13 startAngle:(CGFloat)M_PI endAngle:0 clockwise:YES];
    [path addCurveToPoint:CGPointMake(14,40) controlPoint1:CGPointMake(27,25) controlPoint2:CGPointMake(16,31)];
    [path fill];
    [[UIColor whiteColor] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(9,9,10,10)] fill];
}
@end

@interface ExteriaMapView () <UIGestureRecognizerDelegate> {
    NSMutableDictionary *_layers;
    NSMutableDictionary *_tickets;
    ExteriaWeakReference *_weak;
    ExteriaMapPin *_pin;
    CAShapeLayer *_accuracy;
    CAShapeLayer *_userDot;
    CAShapeLayer *_userAccuracy;
    UIButton *_credit;
    UIButton *_error;
    UILabel *_caption;
    NSData *_placeData;
    NSMutableArray *_places;
    exteria_geo_point _point;
    exteria_geo_point _userPoint;
    double _latitude, _longitude, _zoom;
    double _dragX, _dragY, _pinchX, _pinchY, _pinchZoom;
    BOOL _picking, _compact;
    id<ExteriaMapViewDelegate> _delegate;
}
@end

@implementation ExteriaMapView
@synthesize delegate = _delegate, picking = _picking, compact = _compact;
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.clipsToBounds = YES;
    self.backgroundColor = ExteriaColorField();
    _zoom = 2;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _layers = [[NSMutableDictionary alloc] init];
    _tickets = [[NSMutableDictionary alloc] init];
    _places = [[NSMutableArray alloc] init];
    _accuracy = [[CAShapeLayer layer] retain];
    _accuracy.fillColor = [UIColor colorWithRed:0.15 green:0.5 blue:1 alpha:0.15].CGColor;
    _accuracy.strokeColor = [UIColor colorWithRed:0.15 green:0.5 blue:1 alpha:0.5].CGColor;
    _accuracy.lineWidth = 1;
    [self.layer addSublayer:_accuracy];
    _userAccuracy=[[CAShapeLayer layer] retain];
    _userAccuracy.fillColor=_accuracy.fillColor; _userAccuracy.strokeColor=_accuracy.strokeColor;
    [self.layer addSublayer:_userAccuracy];
    _userDot=[[CAShapeLayer layer] retain];
    _userDot.fillColor=[UIColor colorWithRed:0.15 green:0.5 blue:1 alpha:1].CGColor;
    _userDot.strokeColor=[UIColor whiteColor].CGColor; _userDot.lineWidth=2;
    [self.layer addSublayer:_userDot];
    _pin = [[ExteriaMapPin alloc] initWithFrame:CGRectMake(0,0,28,40)];
    _pin.backgroundColor = [UIColor clearColor];
    _pin.userInteractionEnabled = NO;
    [self addSubview:_pin];
    _credit = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _credit.titleLabel.font = ExteriaFontRegular(10);
    [_credit setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
    _credit.backgroundColor = [UIColor colorWithWhite:1 alpha:0.9];
    [_credit addTarget:self action:@selector(creditTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_credit];
    _error = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _error.titleLabel.font = ExteriaFontMedium(12);
    [_error setTitle:NSLocalizedString(@"map.unavailable",nil) forState:UIControlStateNormal];
    [_error setTitleColor:ExteriaColorTitle() forState:UIControlStateNormal];
    _error.backgroundColor = ExteriaColorCard(); _error.layer.cornerRadius = 8; _error.hidden = YES;
    [_error addTarget:self action:@selector(retry) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_error];
    _caption = [[UILabel alloc] init];
    _caption.font = ExteriaFontMedium(12); _caption.textColor = ExteriaColorTitle();
    _caption.backgroundColor = ExteriaColorCard(); _caption.numberOfLines = 2;
    [self addSubview:_caption];
    UIPanGestureRecognizer *pan = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)] autorelease];
    pan.maximumNumberOfTouches = 1; pan.delegate = self; [self addGestureRecognizer:pan];
    UIPinchGestureRecognizer *pinch = [[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinched:)] autorelease];
    [self addGestureRecognizer:pinch];
    UITapGestureRecognizer *doubleTap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(zoomIn)] autorelease];
    doubleTap.numberOfTapsRequired = 2; [self addGestureRecognizer:doubleTap];
    return self;
}
- (void)dealloc {
    [_weak clear]; [self cancelTiles]; [_weak release]; [_layers release]; [_tickets release];
    [_pin release]; [_accuracy release]; [_userDot release]; [_userAccuracy release]; [_credit release]; [_error release]; [_caption release];
    [_placeData release]; [_places release];
    [super dealloc];
}
- (double)latitude { return _latitude; }
- (double)longitude { return _longitude; }
- (double)zoom { return _zoom; }
- (void)setZoom:(double)zoom { [self setCenterLatitude:_latitude longitude:_longitude zoom:zoom]; }
- (void)setCompact:(BOOL)compact { _compact = compact; [self setNeedsLayout]; }
- (void)setPicking:(BOOL)picking { _picking = picking; [self setNeedsLayout]; }
- (void)showLocation:(exteria_geo_point)point zoom:(double)zoom {
    _point = point;
    if (point.valid) [self setCenterLatitude:point.latitude longitude:point.longitude zoom:zoom];
    [self setNeedsLayout];
}
- (void)showUserLocation:(exteria_geo_point)point { _userPoint=point; [self setNeedsLayout]; }
- (void)showPlaces:(NSData *)points {
    for (UIView *view in _places) [view removeFromSuperview];
    [_places removeAllObjects]; [_placeData release]; _placeData=nil;
    if (points.length%sizeof(exteria_geo_point) || points.length>16*sizeof(exteria_geo_point)) return;
    _placeData=[points copy];
    const uint8_t *locations=_placeData.bytes;
    for (NSUInteger i=0;i<_placeData.length/sizeof(exteria_geo_point);++i) {
        exteria_geo_point point;
        memcpy(&point,locations+i*sizeof(point),sizeof(point));
        if (!point.valid || !exteria_geo_valid(point.latitude,point.longitude)) continue;
        UIButton *pin=[UIButton buttonWithType:UIButtonTypeCustom]; pin.tag=(NSInteger)i;
        [pin setImage:ExteriaSymbolImage(ExteriaSymbolMapPin,22,ExteriaColorAccent()) forState:UIControlStateNormal];
        pin.backgroundColor=ExteriaColorCard(); pin.layer.cornerRadius=16;
        if (memchr(point.title,0,sizeof(point.title))) pin.accessibilityLabel=[NSString stringWithUTF8String:point.title];
        [pin addTarget:self action:@selector(placeTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self insertSubview:pin belowSubview:_pin]; [_places addObject:pin];
    }
    [self setNeedsLayout];
}
- (void)placeTapped:(UIButton *)pin {
    if ([_delegate respondsToSelector:@selector(mapView:didSelectPlace:)]) [_delegate mapView:self didSelectPlace:(NSUInteger)pin.tag];
}
- (void)setCenterLatitude:(double)latitude longitude:(double)longitude zoom:(double)zoom {
    if (!exteria_geo_valid(latitude,longitude) || !isfinite(zoom)) return;
    _latitude = latitude; _longitude = longitude; _zoom = MAX(0,MIN(EXTERIA_MAP_MAX_ZOOM,zoom));
    [self setNeedsLayout];
}
- (void)cancelTiles {
    for (ExteriaMapTileTicket *ticket in [_tickets allValues]) [ticket cancel];
    [_tickets removeAllObjects];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self cancelTiles];
    else [self setNeedsLayout];
}
- (void)retry {
    [self cancelTiles];
    for (CALayer *layer in [_layers allValues]) [layer removeFromSuperlayer];
    [_layers removeAllObjects]; _error.hidden = YES; [self setNeedsLayout];
}
- (void)creditTapped { [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://www.openstreetmap.org/copyright"]]; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    if (size.width <= 0 || size.height <= 0) return;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    exteria_map_tile tiles[EXTERIA_MAP_MAX_TILES];
    size_t count = 0;
    NSMutableSet *visible = [NSMutableSet set];
    double centerX=0,centerY=0;
    exteria_map_project(_latitude,_longitude,&centerX,&centerY);
    if (self.window && !self.hidden && exteria_map_tiles(_latitude,_longitude,_zoom,size.width,size.height,tiles,EXTERIA_MAP_MAX_TILES,&count) == EXTERIA_OK) {
        for (size_t i=0;i<count;++i) {
            exteria_map_tile tile=tiles[i];
            long column = lround(tile.left/tile.side + centerX*(1u<<tile.zoom) - size.width/(2*tile.side));
            NSString *key=[NSString stringWithFormat:@"%u:%u:%u:%ld",tile.zoom,tile.x,tile.y,column];
            [visible addObject:key];
            CALayer *layer=[_layers objectForKey:key];
            if (!layer) {
                layer=[CALayer layer]; layer.contentsGravity=kCAGravityResize;
                [self.layer insertSublayer:layer atIndex:0]; [_layers setObject:layer forKey:key];
            }
            layer.frame=CGRectMake((CGFloat)floor(tile.left),(CGFloat)floor(tile.top),(CGFloat)ceil(tile.side)+1,(CGFloat)ceil(tile.side)+1);
            if (!layer.contents && ![_tickets objectForKey:key]) {
                ExteriaWeakReference *weak=_weak;
                ExteriaMapTileTicket *ticket=[[ExteriaMapTiles sharedTiles] loadTile:tile completion:^(UIImage *image,NSString *failure) {
                    ExteriaMapView *map=weak.target;
                    if (!map || [map->_layers objectForKey:key] != layer) return;
                    [CATransaction begin]; [CATransaction setDisableActions:YES];
                    if (image) layer.contents=(id)image.CGImage;
                    if (failure) map->_error.hidden=NO;
                    [CATransaction commit];
                }];
                [_tickets setObject:ticket forKey:key];
            }
        }
    }
    for (NSString *key in [_layers allKeys]) {
        if ([visible containsObject:key]) continue;
        [[_tickets objectForKey:key] cancel]; [_tickets removeObjectForKey:key];
        [[_layers objectForKey:key] removeFromSuperlayer]; [_layers removeObjectForKey:key];
    }
    double px=centerX,py=centerY;
    if (!_picking && _point.valid) exteria_map_project(_point.latitude,_point.longitude,&px,&py);
    double delta=px-centerX; delta-=floor(delta+0.5);
    double world=256*pow(2,_zoom);
    const uint8_t *places=_placeData.bytes;
    for (UIButton *pin in _places) {
        exteria_geo_point place;
        memcpy(&place,places+(NSUInteger)pin.tag*sizeof(place),sizeof(place));
        double x=0,y=0;
        exteria_map_project(place.latitude,place.longitude,&x,&y);
        double dx=x-centerX; dx-=floor(dx+0.5);
        pin.frame=CGRectMake((CGFloat)(size.width/2+dx*world)-16,(CGFloat)(size.height/2+(y-centerY)*world)-32,32,32);
    }
    CGPoint marker=CGPointMake((CGFloat)(size.width/2+delta*world),(CGFloat)(size.height/2+(py-centerY)*world));
    _pin.hidden=!_picking && !_point.valid;
    _pin.frame=CGRectMake(marker.x-14,marker.y-40,28,40);
    _accuracy.hidden=_picking || !_point.valid || _point.accuracy<=0;
    if (!_accuracy.hidden) {
        double meters=40075016.68557849*cos(_point.latitude*M_PI/180)/world;
        CGFloat radius=(CGFloat)MIN(MAX(size.width,size.height)*2,_point.accuracy/MAX(0.001,meters));
        _accuracy.path=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(marker.x-radius,marker.y-radius,radius*2,radius*2)].CGPath;
    }
    _userDot.hidden=!_userPoint.valid; _userAccuracy.hidden=!_userPoint.valid;
    if (_userPoint.valid) {
        double ux=0,uy=0;
        exteria_map_project(_userPoint.latitude,_userPoint.longitude,&ux,&uy);
        double dx=ux-centerX; dx-=floor(dx+0.5);
        CGPoint user=CGPointMake((CGFloat)(size.width/2+dx*world),(CGFloat)(size.height/2+(uy-centerY)*world));
        _userDot.path=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(user.x-6,user.y-6,12,12)].CGPath;
        double meters=40075016.68557849*cos(_userPoint.latitude*M_PI/180)/world;
        CGFloat radius=(CGFloat)MIN(MAX(size.width,size.height)*2,_userPoint.accuracy/MAX(0.001,meters));
        _userAccuracy.path=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(user.x-radius,user.y-radius,2*radius,2*radius)].CGPath;
    }
    [_credit setTitle:@"© OpenStreetMap contributors" forState:UIControlStateNormal];
    _credit.frame=CGRectMake(0,_compact ? 0 : size.height-18,MIN(size.width,190),18);
    _error.frame=CGRectMake(MAX(0,(size.width-220)/2),MAX(18,size.height/2+12),MIN(220,size.width),30);
    NSString *title=[NSString stringWithUTF8String:_point.title];
    NSString *address=[NSString stringWithUTF8String:_point.address];
    _caption.hidden=!_compact || !title.length;
    _caption.text=address.length ? [NSString stringWithFormat:@"%@\n%@",title,address] : title;
    _caption.frame=CGRectMake(6,MAX(0,size.height-44),MAX(0,size.width-12),40);
    [CATransaction commit];
}
- (void)panned:(UIPanGestureRecognizer *)pan {
    if (pan.state==UIGestureRecognizerStateBegan) exteria_map_project(_latitude,_longitude,&_dragX,&_dragY);
    if (pan.state==UIGestureRecognizerStateChanged || pan.state==UIGestureRecognizerStateEnded) {
        CGPoint delta=[pan translationInView:self];
        double world=256*pow(2,_zoom),lat=0,lon=0;
        exteria_map_unproject(_dragX-delta.x/world,_dragY-delta.y/world,&lat,&lon);
        [self setCenterLatitude:lat longitude:lon zoom:_zoom];
        [_delegate mapView:self didChangeCenter:pan.state==UIGestureRecognizerStateEnded];
    }
}
- (void)pinched:(UIPinchGestureRecognizer *)pinch {
    CGPoint anchor=[pinch locationInView:self];
    if (pinch.state==UIGestureRecognizerStateBegan) {
        _pinchZoom=_zoom;
        exteria_map_project(_latitude,_longitude,&_pinchX,&_pinchY);
        double world=256*pow(2,_zoom);
        _pinchX+=(anchor.x-self.bounds.size.width/2)/world;
        _pinchY+=(anchor.y-self.bounds.size.height/2)/world;
    }
    if ((pinch.state==UIGestureRecognizerStateChanged || pinch.state==UIGestureRecognizerStateEnded) && pinch.scale>0) {
        double zoom=MAX(0,MIN(19,_pinchZoom+log2(pinch.scale))),world=256*pow(2,zoom),lat=0,lon=0;
        exteria_map_unproject(_pinchX-(anchor.x-self.bounds.size.width/2)/world,_pinchY-(anchor.y-self.bounds.size.height/2)/world,&lat,&lon);
        [self setCenterLatitude:lat longitude:lon zoom:zoom];
        [_delegate mapView:self didChangeCenter:pinch.state==UIGestureRecognizerStateEnded];
    }
}
- (void)zoomIn { self.zoom=_zoom+1; }
@end
