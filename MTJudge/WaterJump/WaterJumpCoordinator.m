#import "WaterJumpCoordinator.h"
#import "RecordingController.h"
#import "WatchRemoteController.h"
#import "WaterJumpReceivedPlayerViewController.h"
#import "MTJudge-Swift.h"
#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
NSString * const WJStatusChanged = @"WJStatusChanged";
@interface WaterJumpCoordinator ()
@property (nonatomic, strong) RemoteRecordingServer *server;
@property (nonatomic, strong) WatchRemoteController *watch;
@property (nonatomic, strong) VideoTransferManager *transfer;
@property (nonatomic, strong) WaterJumpReceivedPlayerViewController *receivedPlayer;
@property (nonatomic, strong) NSURL *waitingReceivedURL;
@end
@implementation WaterJumpCoordinator
+ (instancetype)shared { static id instance; static dispatch_once_t once; dispatch_once(&once, ^{ instance = [self new]; }); return instance; }
- (instancetype)init {
    if ((self = [super init])) {
        _message = @"";
        _server = [RemoteRecordingServer new];
        __weak typeof(self) weakSelf = self;
        _server.command = ^NSDictionary *(NSString *command) { return [weakSelf command:command]; };
        _server.status = ^NSDictionary *{ return [weakSelf status]; };
        _server.changed = ^{ [weakSelf publish]; };
        _watch = [WatchRemoteController new];
        _watch.command = _server.command;
        _watch.status = _server.status;
        [_watch activate];
        if (@available(iOS 13.0, *)) { _transfer = [VideoTransferManager new]; _transfer.changed = ^{ [weakSelf publish]; };
            _transfer.received = ^(NSURL *url) {
                [[NSUserDefaults standardUserDefaults] setObject:url.path forKey:@"LatestCameraRecordingPath"];
                weakSelf.waitingReceivedURL = url; [weakSelf displayReceived];
            }; }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(background) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(foreground) name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"WJDuration":@20}];
    }
    return self;
}
- (void)background {
    [self.recording stop];
    // LINEやChromeへ切り替えた間も、Webリモコンの待受とURLを維持する。
    // iOSがプロセスを停止した場合だけ、foreground復帰時に同じ固定ポートで再開する。
    if (@available(iOS 13.0, *)) [self.transfer suspend];
    UIApplication.sharedApplication.idleTimerDisabled = NO;
}
- (void)foreground { [self applySettings]; [self displayReceived]; }
- (BOOL)protectsVideo:(NSURL *)url { if (!url) return NO; if (@available(iOS 13.0, *)) return [self.transfer protects:url]; return NO; }
- (BOOL)recordingBusy { return self.recording.busy; }
- (NSString *)pairingCode { if (@available(iOS 13.0, *)) return self.transfer.discovery.pairingCode; return @"iOS 13以降が必要です"; }
- (NSString *)peerDescription { if (@available(iOS 13.0, *)) return [NSString stringWithFormat:@"%@・%@", self.transfer.discovery.selectedName, self.transfer.discovery.peerAvailable ? @"検出済み（転送時に認証）" : @"未接続"]; return @"未対応"; }
- (NSArray *)discoveredPeers { if (@available(iOS 13.0, *)) return self.transfer.discovery.peers; return @[]; }
- (BOOL)registerPeer:(NSString *)name code:(NSString *)code { if (@available(iOS 13.0, *)) return [self.transfer.discovery registerPeer:name code:code]; return NO; }
- (void)retryTransfer { if (@available(iOS 13.0, *)) [self.transfer retry]; }
- (void)displayReceived {
    if (!self.waitingReceivedURL || self.recording.busy || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    UIViewController *host = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (host.presentedViewController && host.presentedViewController != self.receivedPlayer) host = host.presentedViewController;
    if ([host isKindOfClass:UIAlertController.class] || host.isBeingDismissed) return;
    WaterJumpReceivedPlayerViewController *player = self.receivedPlayer;
    NSURL *url = self.waitingReceivedURL; self.waitingReceivedURL = nil;
    if (player && player.presentingViewController) { [player replaceVideoURL:url]; }
    else {
        player = [[WaterJumpReceivedPlayerViewController alloc] initWithVideoURL:url]; self.receivedPlayer = player;
        player.modalPresentationStyle = UIModalPresentationFullScreen;
        player.modalPresentationCapturesStatusBarAppearance = YES;
        [host presentViewController:player animated:YES completion:nil];
    }
#if DEBUG
    NSLog(@"[iPad] latest video displayed: %@", url.lastPathComponent);
#endif
}
- (BOOL)modeEnabled { return [[NSUserDefaults standardUserDefaults] boolForKey:@"WJMode"]; }
- (NSString *)remoteAddress { return self.server.address; }
- (void)applySettings {
    BOOL active = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    BOOL enabled = active && self.modeEnabled && [[NSUserDefaults standardUserDefaults] boolForKey:@"WJWeb"];
    if (enabled) [self.server start]; else [self.server stop];
    self.recording.duration = [[NSUserDefaults standardUserDefaults] doubleForKey:@"WJDuration"];
    if (@available(iOS 13.0, *)) {
        self.transfer.enabled = active && [[NSUserDefaults standardUserDefaults] boolForKey:@"WJTransfer"];
        [self.transfer configureWithReceiving:active && [[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"] browsing:self.transfer.enabled];
    }
    [self publish];
    UIApplication.sharedApplication.idleTimerDisabled = self.modeEnabled || [[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"];
}
- (void)saveAutomatic:(NSURL *)url completion:(void (^)(NSURL *, NSError *))completion {
    if (@available(iOS 13.0, *)) {
        self.message = @"保存中..."; [self publish];
        [ReceivedVideoManager saveAutomatic:url completion:^(NSURL *saved, NSDictionary *info, NSError *error) {
            if (saved) {
                self.message = @"保存完了";
                if ([[NSUserDefaults standardUserDefaults] boolForKey:@"WJTransfer"]) [self.transfer enqueue:saved metadata:info];
            } else self.message = [@"動画保存失敗: " stringByAppendingString:error.localizedDescription];
            completion(saved, error); [self publish];
        }];
    } else completion(nil, [NSError errorWithDomain:@"MTJudge.WJ" code:1 userInfo:@{NSLocalizedDescriptionKey:@"自動保存にはiOS 13以降が必要です"}]);
}
- (NSDictionary *)status {
    BOOL ready = self.recording && !self.recording.busy && self.modeEnabled && self.recording.canStart && self.recording.canStart() && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    NSString *state = self.recording.state ?: @"IDLE";
    NSString *message = self.message;
    if (@available(iOS 13.0, *)) {
        if (!self.recording.busy && ![state isEqual:@"ERROR"] && ![self.transfer.state isEqual:@"IDLE"]) {
            state = self.transfer.state;
            if (self.transfer.message.length) message = self.transfer.message;
        }
    }
    if ([state isEqual:@"SAVED"] || [state isEqual:@"TRANSFERRED"]) state = @"COMPLETE";
    return @{@"state":state, @"recordingState":self.recording.state ?: @"IDLE", @"canStart":@(ready), @"message":self.server.errorMessage.length ? self.server.errorMessage : message};
}
- (NSDictionary *)command:(NSString *)command {
#if DEBUG
    NSLog(@"[Remote] %@ received", command);
#endif
    if (!self.modeEnabled || !self.recording || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return @{@"error":@"撮影端末でウォータージャンプモードをONにし、カメラ画面を開いてください。"};
    if ([command isEqual:@"START"]) {
        NSError *error = nil;
        if (![self.recording startAutomatic:YES error:&error]) return @{@"error":error.localizedDescription ?: @"録画中または保存中です。"};
    } else if ([command isEqual:@"STOP"]) [self.recording stop];
    else return @{@"error":@"不明なコマンドです。"};
    return [self status];
}
- (void)publish { [self.watch publish]; [[NSNotificationCenter defaultCenter] postNotificationName:WJStatusChanged object:self]; }
@end
