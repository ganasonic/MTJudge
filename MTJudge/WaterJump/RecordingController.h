#import <Foundation/Foundation.h>
@class VideoRecorder;
// Main-thread-only state gate shared by local, browser and Watch commands.
@interface RecordingController : NSObject
@property (nonatomic, readonly) NSString *state;
@property (nonatomic, readonly) BOOL busy;
@property (nonatomic, readonly) BOOL automaticRecording;
@property (nonatomic, copy) BOOL (^canStart)(void);
@property (nonatomic, copy) void (^changed)(void);
- (instancetype)initWithRecorder:(VideoRecorder *)recorder;
- (BOOL)startAutomatic:(BOOL)automatic error:(NSError **)error;
@property (nonatomic) NSTimeInterval duration;
- (void)didStart;
- (BOOL)stop;
- (void)finishedWithError:(NSError *)error;
- (void)markSaved;
@end
