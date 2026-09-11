#import "AirDdData.h"

@implementation AirDdData

- (instancetype)initWithAirname:(NSString *)airname ddPointM:(float)dd_point_m ddPointF:(float)dd_point_f {
    self = [super init];
    if (self) {
        _airname = [airname copy];
        _dd_point_m = dd_point_m;
        _dd_point_f = dd_point_f;
    }
    return self;
}

@end