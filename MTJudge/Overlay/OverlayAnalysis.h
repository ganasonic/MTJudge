#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
@class OverlayTimelineMapper;
NS_ASSUME_NONNULL_BEGIN
@interface OverlayAnalysis : NSObject
@property(atomic) BOOL cancelled;
- (void)analyzeMain:(NSURL *)mainURL sub:(NSURL *)subURL
         mainStart:(double)mainStart subStart:(double)subStart duration:(double)duration
       mainSubject:(CGPoint)mainSubject subSubject:(CGPoint)subSubject
    cacheDirectory:(NSURL *)cacheDirectory
          progress:(void (^)(double fraction))progress
        completion:(void (^)(NSArray<NSDictionary *> * _Nullable frames, NSError * _Nullable error))completion;
- (void)analyzeMain:(NSURL *)mainURL sub:(NSURL *)subURL
         mainStart:(double)mainStart subStart:(double)subStart duration:(double)duration
       mainSubject:(CGPoint)mainSubject subSubject:(CGPoint)subSubject
          timeline:(nullable OverlayTimelineMapper *)timeline
    cacheDirectory:(NSURL *)cacheDirectory
          progress:(void (^)(double fraction))progress
        completion:(void (^)(NSArray<NSDictionary *> * _Nullable frames, NSError * _Nullable error))completion;
@end
NS_ASSUME_NONNULL_END
