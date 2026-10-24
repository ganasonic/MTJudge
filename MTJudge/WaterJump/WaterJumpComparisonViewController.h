#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 同一Recording Session IDのMain/Sub動画を並べて再生する画面。
@interface WaterJumpComparisonViewController : UIViewController
- (instancetype)initWithMainURL:(NSURL *)mainURL subURL:(NSURL *)subURL;
@property (nonatomic, copy, nullable) void (^closeHandler)(void);
@property (nonatomic) BOOL showsReceivedCameraNames;
- (void)pausePlayback;
- (void)togglePlayback;
- (void)startPlayback;
- (void)prepareForAutoplayReplacement;
@end

NS_ASSUME_NONNULL_END
