#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 同一Recording Session IDのMain/Sub動画を並べて再生する画面。
@interface WaterJumpComparisonViewController : UIViewController
- (instancetype)initWithMainURL:(NSURL *)mainURL subURL:(NSURL *)subURL;
- (void)startPlayback;
@end

NS_ASSUME_NONNULL_END
