#import <Foundation/Foundation.h>
#import "TakeoffAnalysisConfig.h"

NS_ASSUME_NONNULL_BEGIN

/// 保存済みPoseFrameDataとRamp設定から、踏切区間の4角度を算出する純粋な計算クラス。
@interface TakeoffAngleAnalyzer : NSObject
+ (nullable NSDictionary *)resultForFrame:(NSDictionary *)frame config:(TakeoffAnalysisConfig *)config;
@end

NS_ASSUME_NONNULL_END
