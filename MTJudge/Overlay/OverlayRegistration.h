#import <UIKit/UIKit.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN
/// All matrices map normalized, oriented, top-left-origin SUB coordinates to MAIN.
FOUNDATION_EXPORT NSArray<NSNumber *> *MTJOverlayMatrixArray(simd_double3x3 matrix);
FOUNDATION_EXPORT simd_double3x3 MTJOverlayMatrix(NSArray * _Nullable values);
FOUNDATION_EXPORT CGPoint MTJOverlayProject(simd_double3x3 matrix, CGPoint point);
FOUNDATION_EXPORT BOOL MTJOverlayMatrixIsValid(simd_double3x3 matrix);

@interface OverlayRegistration : NSObject
- (NSDictionary *)registerMain:(CGImageRef)main sub:(CGImageRef)sub
                     mainMask:(nullable CGImageRef)mainMask subMask:(nullable CGImageRef)subMask;
/// Forward/backward checked LK, returning previous -> current normalized coordinates.
- (NSDictionary *)trackFrom:(CGImageRef)previous to:(CGImageRef)current
              previousMask:(nullable CGImageRef)previousMask currentMask:(nullable CGImageRef)currentMask;
+ (nullable NSArray<NSNumber *> *)matrixFromPoints:(NSArray<NSValue *> *)subPoints
                                        toPoints:(NSArray<NSValue *> *)mainPoints;
@end
NS_ASSUME_NONNULL_END
