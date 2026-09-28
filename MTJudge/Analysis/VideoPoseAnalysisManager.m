#import "VideoPoseAnalysisManager.h"
#import "PoseAnalyzer.h"
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>

@interface VideoPoseAnalysisManager ()
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation VideoPoseAnalysisManager
+ (instancetype)sharedManager { static VideoPoseAnalysisManager *manager; static dispatch_once_t once; dispatch_once(&once, ^{ manager = [self new]; }); return manager; }
- (instancetype)init { if ((self = [super init])) _queue = dispatch_queue_create("com.MTJudge.poseAnalysis", DISPATCH_QUEUE_SERIAL); return self; }
- (NSURL *)resultURLForVideo:(NSURL *)url { return [url URLByAppendingPathExtension:@"pose.json"]; }
- (NSArray<NSDictionary *> *)loadFrameDataForVideoURL:(NSURL *)url {
    NSData *data = [NSData dataWithContentsOfURL:[self resultURLForVideo:url]];
    NSArray *frames = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    return [frames isKindOfClass:NSArray.class] ? frames : nil;
}
- (void)analyzeVideoURL:(NSURL *)url completion:(void (^)(NSURL *, NSError *))completion {
    dispatch_async(self.queue, ^{
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
        NSArray<AVAssetTrack *> *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        AVAssetTrack *track = tracks.firstObject;
        double duration = CMTimeGetSeconds(asset.duration);
        if (!track || !isfinite(duration) || duration <= 0) { dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, [NSError errorWithDomain:@"MTJudge.Pose" code:1 userInfo:@{NSLocalizedDescriptionKey:@"動画の映像トラックを読み込めません。"}]); }); return; }
        float fps = track.nominalFrameRate > 0 ? track.nominalFrameRate : 30.0f;
        NSInteger count = MAX(1, (NSInteger)ceil(duration * fps));
        AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        generator.appliesPreferredTrackTransform = YES;
        generator.requestedTimeToleranceBefore = kCMTimeZero; generator.requestedTimeToleranceAfter = kCMTimeZero;
        NSMutableArray *frames = [NSMutableArray arrayWithCapacity:count];
        for (NSInteger index = 0; index < count; index++) {
            @autoreleasepool {
                double timestamp = MIN(duration, index / (double)fps);
                CMTime requested = CMTimeMakeWithSeconds(timestamp, 600); NSError *imageError = nil;
                CGImageRef image = [generator copyCGImageAtTime:requested actualTime:NULL error:&imageError];
                if (!image) continue;
                VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
                VNDetectHumanBodyPoseRequest *request = [VNDetectHumanBodyPoseRequest new];
                [handler performRequests:@[request] error:NULL];
                VNHumanBodyPoseObservation *observation = request.results.firstObject;
                if (observation) [frames addObject:[PoseAnalyzer frameDataFromObservation:observation timestamp:timestamp]];
                CGImageRelease(image);
            }
        }
        NSURL *resultURL = [self resultURLForVideo:url]; NSError *writeError = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:frames options:0 error:&writeError];
        if (json && [json writeToURL:resultURL options:NSDataWritingAtomic error:&writeError]) dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(resultURL, nil); });
        else dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, writeError); });
    });
}
@end
