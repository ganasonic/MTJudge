#import <Foundation/Foundation.h>
#import <Vision/Vision.h>

NS_ASSUME_NONNULL_BEGIN

/// Visionの人体姿勢観測を、再生Overlayで利用できるJSON互換の解析値へ変換する共通クラス。
@interface PoseAnalyzer : NSObject
+ (NSDictionary *)frameDataFromObservation:(VNHumanBodyPoseObservation *)observation timestamp:(double)timestamp;
+ (double)angleAtPoint:(CGPoint)point first:(CGPoint)first second:(CGPoint)second;
@end

NS_ASSUME_NONNULL_END
