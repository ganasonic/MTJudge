#import <UIKit/UIKit.h>
#import <CoreImage/CoreImage.h>
NS_ASSUME_NONNULL_BEGIN
@interface OverlayAnnotationAdapter : NSObject
- (instancetype)initWithVideoURL:(NSURL *)url;
- (nullable CIImage *)imageAtTime:(double)time size:(CGSize)size joints:(NSDictionary *)joints
                       skeleton:(BOOL)skeleton drawings:(BOOL)drawings color:(UIColor *)color;
@end
NS_ASSUME_NONNULL_END
