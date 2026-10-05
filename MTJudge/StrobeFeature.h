#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MTJStrobeCompletion)(NSURL * _Nullable outputURL, NSError * _Nullable error);

@interface StrobeImageComposer : NSObject
+ (void)generateForVideoURL:(NSURL *)videoURL
                  startTime:(CMTime)startTime
                    endTime:(CMTime)endTime
       intervalMilliseconds:(NSInteger)intervalMilliseconds
                  completion:(MTJStrobeCompletion)completion;
+ (void)generateForVideoURL:(NSURL *)videoURL
                  startTime:(CMTime)startTime
                    endTime:(CMTime)endTime
       intervalMilliseconds:(NSInteger)intervalMilliseconds
                    progress:(void (^ _Nullable)(double progress))progress
                  completion:(MTJStrobeCompletion)completion;
@end

@interface StrobeConfigurationViewController : UIViewController
- (instancetype)initWithVideoURL:(NSURL *)videoURL completion:(void (^)(NSURL * _Nullable outputURL))completion;
@end

NS_ASSUME_NONNULL_END
