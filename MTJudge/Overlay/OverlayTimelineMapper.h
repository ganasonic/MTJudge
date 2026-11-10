#import <AVFoundation/AVFoundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Immutable, strictly monotonic time map. No extrapolation outside confirmed markers.
@interface OverlayTimelineMapper : NSObject
@property(nonatomic,readonly) NSArray<NSDictionary *> *anchors;
@property(nonatomic,readonly) double mainStart;
@property(nonatomic,readonly) double mainEnd;
- (nullable instancetype)initWithAnchors:(NSArray *)anchors mainDuration:(double)mainDuration subDuration:(double)subDuration error:(NSError **)error;
- (double)subTimeForMainTime:(double)mainTime;
- (double)mainTimeForSubTime:(double)subTime;
- (double)subRateForMainTime:(double)mainTime;
/// Maps SUB's original source intervals into a continuous MAIN-relative timeline.
/// There is no re-encoding, file write, or per-frame seek.
- (nullable AVMutableComposition *)compositionForSubURL:(NSURL *)url error:(NSError **)error;
/// Suggestions use tracked, stabilized course coordinates, not screen height.
/// They are never added to confirmed anchors automatically.
+ (NSArray<NSDictionary *> *)suggestionsFromFrames:(NSArray<NSDictionary *> *)frames;
@end
NS_ASSUME_NONNULL_END
