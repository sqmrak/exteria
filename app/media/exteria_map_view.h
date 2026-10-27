#import <UIKit/UIKit.h>
#include "exteria_geo.h"

@class ExteriaMapView;
@protocol ExteriaMapViewDelegate <NSObject>
- (void)mapView:(ExteriaMapView *)map didChangeCenter:(BOOL)finished;
@optional
- (void)mapView:(ExteriaMapView *)map didSelectPlace:(NSUInteger)index;
@end

@interface ExteriaMapView : UIView
@property (nonatomic, assign) id<ExteriaMapViewDelegate> delegate;
@property (nonatomic, assign) BOOL picking;
@property (nonatomic, assign) BOOL compact;
@property (nonatomic, assign) double zoom;
@property (nonatomic, readonly) double latitude;
@property (nonatomic, readonly) double longitude;
- (void)showLocation:(exteria_geo_point)point zoom:(double)zoom;
- (void)showUserLocation:(exteria_geo_point)point;
/* an array of exteria_geo_point values, at most sixteen markers */
- (void)showPlaces:(NSData *)points;
- (void)setCenterLatitude:(double)latitude longitude:(double)longitude zoom:(double)zoom;
- (void)cancelTiles;
@end
