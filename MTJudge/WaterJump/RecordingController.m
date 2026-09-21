#import "RecordingController.h"
#import "../VideoRecorder.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>
@interface RecordingController ()
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) VideoRecorder *recorder;
@property (nonatomic, strong) AVAudioPlayer *cuePlayer;
@property (nonatomic, readwrite) NSString *state;
@property (nonatomic, readwrite) BOOL automaticRecording;
@end
@implementation RecordingController
- (NSData *)toneData:(double)frequency duration:(double)duration {
    const double sampleRate = 44100.0;
    NSUInteger samples = (NSUInteger)(sampleRate * duration);
    NSMutableData *data = [NSMutableData dataWithLength:44 + samples * 2];
    uint8_t *bytes = data.mutableBytes;
    memcpy(bytes, "RIFF", 4);
    uint32_t fileSize = (uint32_t)data.length - 8, fmtSize = 16, sampleData = (uint32_t)(samples * 2);
    uint16_t audioFormat = 1, channels = 1, bits = 16;
    uint32_t rate = (uint32_t)sampleRate, byteRate = rate * 2;
    uint16_t blockAlign = 2;
    memcpy(bytes + 4, &fileSize, 4); memcpy(bytes + 8, "WAVEfmt ", 8); memcpy(bytes + 16, &fmtSize, 4);
    memcpy(bytes + 20, &audioFormat, 2); memcpy(bytes + 22, &channels, 2); memcpy(bytes + 24, &rate, 4);
    memcpy(bytes + 28, &byteRate, 4); memcpy(bytes + 32, &blockAlign, 2); memcpy(bytes + 34, &bits, 2);
    memcpy(bytes + 36, "data", 4); memcpy(bytes + 40, &sampleData, 4);
    int16_t *pcm = (int16_t *)(bytes + 44);
    for (NSUInteger i = 0; i < samples; i++) {
        double t = (double)i / sampleRate;
        double envelope = MIN(1.0, t * 80.0) * MIN(1.0, (duration - t) * 30.0);
        pcm[i] = (int16_t)(sin(2.0 * M_PI * frequency * t) * envelope * 0.42 * INT16_MAX);
    }
    return data;
}

- (void)playCue:(BOOL)stopping {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *error = nil;
    [session setCategory:AVAudioSessionCategoryPlayAndRecord
                    mode:AVAudioSessionModeDefault
                 options:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionMixWithOthers
                   error:&error];
    [session setActive:YES error:&error];
    NSError *playerError = nil;
    NSData *tone = [self toneData:stopping ? 660.0 : 880.0 duration:0.13];
    self.cuePlayer = [[AVAudioPlayer alloc] initWithData:tone error:&playerError];
    self.cuePlayer.volume = 1.0;
    [self.cuePlayer prepareToPlay];
    [self.cuePlayer play];
}
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
    // 既存の本体録画と同じ開始音。リモコン開始でも撮影端末側で鳴らす。
    [self playCue:NO];
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
    // 自動停止・本体停止・リモコン停止を同じ終了音に統一する。
    [self playCue:YES];
    [self notify];
    return YES;
}
- (void)finishedWithError:(NSError *)error { [self.timer invalidate]; self.timer = nil; self.state = error ? @"ERROR" : @"SAVING"; [self notify]; }
- (void)markSaved { self.state = @"SAVED"; [self notify]; }
@end
