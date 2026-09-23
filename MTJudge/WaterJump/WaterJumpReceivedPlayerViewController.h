#import <AVKit/AVKit.h>

NS_ASSUME_NONNULL_BEGIN

/// iPadで自動転送された動画を全画面再生する専用プレイヤー。
/// 通常のMTJudge再生画面とは独立している。
@interface WaterJumpReceivedPlayerViewController : AVPlayerViewController
- (instancetype)initWithVideoURL:(NSURL *)url;
- (void)replaceVideoURL:(NSURL *)url;
@end

NS_ASSUME_NONNULL_END
