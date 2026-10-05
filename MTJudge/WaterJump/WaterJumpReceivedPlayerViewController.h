#import <AVKit/AVKit.h>

NS_ASSUME_NONNULL_BEGIN

/// iPadで自動転送された動画を全画面再生する専用プレイヤー。
/// 通常のMTJudge再生画面とは独立している。
@interface WaterJumpReceivedPlayerViewController : AVPlayerViewController
/// ローカル撮影直後の再生など、閉じる／再生終了時の戻り先を呼び出し側で指定する。
@property (nonatomic, copy, nullable) void (^closeHandler)(void);
@property (nonatomic, copy, nullable) void (^playbackEndedHandler)(void);
- (instancetype)initWithVideoURL:(NSURL *)url;
- (void)replaceVideoURL:(NSURL *)url;
- (void)setPlaylist:(NSArray<NSURL *> *)playlist currentIndex:(NSInteger)index;
@end

NS_ASSUME_NONNULL_END
