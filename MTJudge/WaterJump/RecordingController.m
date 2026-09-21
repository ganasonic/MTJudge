#import "RecordingController.h"
#import "../VideoRecorder.h"
@interface RecordingController ()
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) VideoRecorder *recorder;
@property (nonatomic, readwrite) NSString *state;
@property (nonatomic, readwrite) BOOL automaticRecording;
@end
@implementation RecordingController
- (instancetype)initWithRecorder:(VideoRecorder *)recorder {
    if ((self = [super init])) { _recorder = recorder; _state = @"READY"; _duration = 20; }
    return self;
}
- (BOOL)busy { return [@[@"RECORDING", @"STOPPING", @"SAVING"] containsObject:self.state]; }
- (void)notify {
#if DEBUG
    NSLog(@"[Recording] %@", self.state);
#endif
    if (self.changed) self.changed();
}
- (BOOL)startAutomatic:(BOOL)automatic error:(NSError **)error {
    NSAssert(NSThread.isMainThread, @"Recording state requires main thread");
    if (self.busy || (self.canStart && !self.canStart()) || !self.recorder.readyForRecording) {
        if (error) *error = [NSError errorWithDomain:@"MTJudge.Recording" code:1 userInfo:@{NSLocalizedDescriptionKey:@"カメラ画面を開き、保存・再生を終了してください。カメラの使用許可も確認してください。"}];
        return NO;
    }
    self.automaticRecording = automatic;
    self.state = @"RECORDING";
    [self.recorder startRecording];
    [self notify];
    return YES;
}
- (void)didStart {
    if (!self.automaticRecording || ![self.state isEqual:@"RECORDING"]) return;
    [self.timer invalidate];
    __weak typeof(self) weakSelf = self;
    NSTimeInterval duration = [@[@10,@15,@20,@30,@45,@60] containsObject:@(self.duration)] ? self.duration : 20;
    self.timer = [NSTimer timerWithTimeInterval:duration repeats:NO block:^(NSTimer *timer) { [weakSelf stop]; }];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
#if DEBUG
    NSLog(@"[Recording] auto stop timer = %.0f sec", duration);
#endif
}
- (BOOL)stop {
    NSAssert(NSThread.isMainThread, @"Recording state requires main thread");
    if (![self.state isEqual:@"RECORDING"]) return NO;
    [self.timer invalidate]; self.timer = nil;
    self.state = @"STOPPING";
    [self.recorder stopRecording];
    [self notify];
    return YES;
}
- (void)finishedWithError:(NSError *)error { [self.timer invalidate]; self.timer = nil; self.state = error ? @"ERROR" : @"SAVING"; [self notify]; }
- (void)markSaved { self.state = @"SAVED"; [self notify]; }
@end
