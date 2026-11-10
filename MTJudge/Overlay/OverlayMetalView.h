#import <MetalKit/MetalKit.h>
#import <CoreImage/CoreImage.h>
#import "OverlayRegistration.h"
NS_ASSUME_NONNULL_BEGIN
/// Core Image kernels execute on the Metal device and render directly into the drawable.
@interface OverlayMetalView : MTKView <MTKViewDelegate>
@property(nonatomic,readonly) CIContext *imageContext;
@property(nonatomic) CGRect videoRect;
@property(atomic,readonly,nullable) NSError *renderError;
- (BOOL)displayMain:(CIImage *)main sub:(nullable CIImage *)sub matrix:(simd_double3x3)matrix
              mask:(nullable CIImage *)mask opacity:(CGFloat)opacity
    mainAnnotation:(nullable CIImage *)mainAnnotation subAnnotation:(nullable CIImage *)subAnnotation;
@end
NS_ASSUME_NONNULL_END
