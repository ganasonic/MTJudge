#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 録画済み動画を非同期解析し、動画と同じ場所へ .pose.json を保存する。
@interface VideoPoseAnalysisManager : NSObject
+ (instancetype)sharedManager;
- (void)analyzeVideoURL:(NSURL *)url completion:(void (^)(NSURL * _Nullable resultURL, NSError * _Nullable error))completion;
- (nullable NSArray<NSDictionary *> *)loadFrameDataForVideoURL:(NSURL *)url;
@end

NS_ASSUME_NONNULL_END
