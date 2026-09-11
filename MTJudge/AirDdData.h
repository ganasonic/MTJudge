#import <Foundation/Foundation.h>

@interface AirDdData : NSObject

@property (nonatomic, copy) NSString *airname;
@property (nonatomic, assign) float dd_point_m;
@property (nonatomic, assign) float dd_point_f;

- (instancetype)initWithAirname:(NSString *)airname ddPointM:(float)dd_point_m ddPointF:(float)dd_point_f;

@end