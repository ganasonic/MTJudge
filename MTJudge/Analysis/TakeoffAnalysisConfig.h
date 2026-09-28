#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TakeoffAnalysisSide) {
    TakeoffAnalysisSideAuto = 0,
    TakeoffAnalysisSideLeft = 1,
    TakeoffAnalysisSideRight = 2
};

/// 動画ごとの踏切解析設定。動画本体には書き込まずUserDefaultsへ保存する。
@interface TakeoffAnalysisConfig : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *videoIdentifier;
@property (nonatomic, assign) CGPoint rampPointA;
@property (nonatomic, assign) CGPoint rampPointB;
@property (nonatomic, assign) CGPoint lipPoint;
@property (nonatomic, assign) CMTime takeoffStartTime;
@property (nonatomic, assign) CMTime lipExitTime;
@property (nonatomic, assign) TakeoffAnalysisSide analysisSide;
@property (nonatomic, assign) BOOL enabled;
+ (instancetype)configForVideoURL:(NSURL *)url;
- (void)save;
@end

NS_ASSUME_NONNULL_END
