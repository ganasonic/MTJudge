#import "WaterJumpCoordinator.h"
#import "RecordingController.h"
#import "WatchRemoteController.h"
#import "WaterJumpReceivedPlayerViewController.h"
#import "WaterJumpComparisonViewController.h"
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
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSURL *> *> *receivedSessions;
@property (nonatomic, strong) WaterJumpComparisonViewController *comparisonPlayer;
@end
@implementation WaterJumpCoordinator
- (UIViewController *)activePresentationHost {
    UIViewController *root = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState == UISceneActivationStateUnattached) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) { root = window.rootViewController; break; }
            }
            if (!root) root = ((UIWindowScene *)scene).windows.firstObject.rootViewController;
            if (root) break;
        }
    }
    if (!root) root = UIApplication.sharedApplication.keyWindow.rootViewController;
    UIViewController *host = root;
    while (host.presentedViewController && !host.presentedViewController.isBeingDismissed) host = host.presentedViewController;
    return host;
}
- (void)presentComparisonMainURL:(NSURL *)mainURL subURL:(NSURL *)subURL {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"WJAutoPlayAfterTransfer"]) return;
    if (!mainURL || !subURL || [mainURL.path isEqualToString:subURL.path]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = self.receivedPlayer.presentingViewController ?: [self activePresentationHost];
        if (!presenter) return;
        self.comparisonPlayer = [[WaterJumpComparisonViewController alloc] initWithMainURL:mainURL subURL:subURL];
        void (^present)(void) = ^{
            [presenter presentViewController:self.comparisonPlayer animated:YES completion:^{ [self.comparisonPlayer startPlayback]; }];
        };
        if (self.receivedPlayer.presentingViewController) [self.receivedPlayer dismissViewControllerAnimated:NO completion:present];
        else if (presenter.presentedViewController && presenter.presentedViewController != self.comparisonPlayer) {
            [presenter dismissViewControllerAnimated:NO completion:present];
        } else present();
    });
}
+ (instancetype)shared { static id instance; static dispatch_once_t once; dispatch_once(&once, ^{ instance = [self new]; }); return instance; }
- (instancetype)init {
    if ((self = [super init])) {
        _message = @"";
        _receivedSessions = [NSMutableDictionary dictionary];
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
                [weakSelf handleReceivedURL:url];
            }; }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(background) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(foreground) name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"WJDuration":@20}];
    }
    return self;
}
- (void)handleReceivedURL:(NSURL *)url {
    // 受信待機中に本体録画が直前に完了している場合は、メタデータを介さず
    // その2本を直接比較画面へ渡す。旧版サイドカーの役割誤りで単独再生に
    // フォールバックする経路をここで遮断する。
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"] && [[NSUserDefaults standardUserDefaults] boolForKey:@"WJAutoPlayAfterTransfer"]) {
        NSString *localPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"LatestLocalCameraRecordingPath"];
        if (localPath.length && ![localPath isEqualToString:url.path] && [[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
            [self presentComparisonMainURL:[NSURL fileURLWithPath:localPath] subURL:url];
            return;
        }
    }
    NSURL *sidecar = [url URLByAppendingPathExtension:@"wj.json"];
    NSDictionary *info = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:sidecar] ?: [NSData data] options:0 error:nil];
    NSString *sessionID = info[@"sessionID"];
    NSString *role = info[@"cameraRole"];
    // iPadが受信待機中で直近のローカル録画を持っている場合、ここで届く動画は
    // リモート撮影用のサブ映像である。送信元の旧サイドカーがMAIN_CAMERAでも、
    // それをそのまま扱うと単独再生になってしまうため、受信側の構成を優先する。
    NSString *localPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"LatestLocalCameraRecordingPath"];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"] && localPath.length && ![localPath isEqualToString:url.path] && [[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
        role = @"SUB_CAMERA";
    }
    // 旧形式の転送メタデータでも、受信した動画はサブカメラ映像として
    // 現在のローカルメイン映像との比較対象にできるよう補完する。
    if (!sessionID.length) sessionID = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJSessionID"];
    if (sessionID.length && ![role isEqualToString:@"MAIN_CAMERA"] && ![role isEqualToString:@"SUB_CAMERA"]) role = @"SUB_CAMERA";
    if (sessionID.length && ( [role isEqualToString:@"MAIN_CAMERA"] || [role isEqualToString:@"SUB_CAMERA"] )) {
        NSMutableDictionary *session = self.receivedSessions[sessionID];
        if (!session) { session = [NSMutableDictionary dictionary]; self.receivedSessions[sessionID] = session; }
        session[role] = url;
        // iPad自身がメインカメラとして録画した場合、iPad側の動画は転送されない。
        // そのため、受信したSUB_CAMERAのSession IDとローカル保存動画のサイドカーを照合して比較再生へ参加させる。
        if ([role isEqualToString:@"SUB_CAMERA"] && !session[@"MAIN_CAMERA"]) {
            NSString *localPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"LatestLocalCameraRecordingPath"];
            NSURL *localURL = localPath.length ? [NSURL fileURLWithPath:localPath] : nil;
            NSURL *localSidecar = [localURL URLByAppendingPathExtension:@"wj.json"];
            NSDictionary *localInfo = localURL ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:localSidecar] ?: [NSData data] options:0 error:nil] : nil;
            if ([localInfo[@"sessionID"] isEqualToString:sessionID] && [localInfo[@"cameraRole"] isEqualToString:@"MAIN_CAMERA"]) session[@"MAIN_CAMERA"] = localURL;
            // 旧版サイドカーや保存直後の端末では役割情報が欠けることがある。
            // 本体の直近保存動画はこの受信セッションのメイン映像として扱い、
            // 片方だけの再生に落ちないようにする。
            if (!session[@"MAIN_CAMERA"] && localURL && [localURL.path isEqualToString:url.path] == NO && [[NSFileManager defaultManager] fileExistsAtPath:localURL.path]) {
                session[@"MAIN_CAMERA"] = localURL;
            }
            if (!session[@"MAIN_CAMERA"] && @available(iOS 13.0, *)) {
                double subCreated = [info[@"created"] doubleValue];
                for (NSURL *candidate in [ReceivedVideoManager videos]) {
                    NSDictionary *candidateInfo = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[candidate URLByAppendingPathExtension:@"wj.json"]] ?: [NSData data] options:0 error:nil];
                    if ([candidateInfo[@"sessionID"] isEqualToString:sessionID] && [candidateInfo[@"cameraRole"] isEqualToString:@"MAIN_CAMERA"]) { session[@"MAIN_CAMERA"] = candidate; break; }
                    double candidateCreated = [candidateInfo[@"created"] doubleValue];
                    if (!session[@"MAIN_CAMERA"] && [candidateInfo[@"cameraRole"] isEqualToString:@"MAIN_CAMERA"] && subCreated > 0 && candidateCreated > 0 && fabs(candidateCreated - subCreated) < 120.0) session[@"MAIN_CAMERA"] = candidate;
                }
                // セッションIDが欠落した旧動画でも、受信時刻に最も近いローカル動画を
                // メイン映像として採用する。転送先には通常この直前の1本しか新規保存されない。
                if (!session[@"MAIN_CAMERA"]) {
                    for (NSURL *candidate in [ReceivedVideoManager videos]) {
                        if ([candidate.path isEqualToString:url.path]) continue;
                        NSDate *date = [candidate resourceValuesForKeys:@[NSURLCreationDateKey] error:nil][NSURLCreationDateKey];
                        double candidateCreated = date ? date.timeIntervalSince1970 : 0;
                        if (subCreated > 0 && candidateCreated > 0 && fabs(candidateCreated - subCreated) < 180.0) { session[@"MAIN_CAMERA"] = candidate; break; }
                    }
                }
            }
        }
        NSURL *mainURL = session[@"MAIN_CAMERA"], *subURL = session[@"SUB_CAMERA"];
        if (mainURL && subURL) {
            if (![[NSUserDefaults standardUserDefaults] boolForKey:@"WJAutoPlayAfterTransfer"]) return;
            [self.receivedSessions removeObjectForKey:sessionID];
            dispatch_async(dispatch_get_main_queue(), ^{
                UIViewController *host = self.receivedPlayer.presentingViewController ?: [self activePresentationHost];
                if (!host) return;
                self.comparisonPlayer = [[WaterJumpComparisonViewController alloc] initWithMainURL:mainURL subURL:subURL];
                void (^presentComparison)(void) = ^{
                    if (!host.presentedViewController || host.presentedViewController.isBeingDismissed) {
                        [host presentViewController:self.comparisonPlayer animated:YES completion:^{ [self.comparisonPlayer startPlayback]; }];
                    }
                };
                if (self.receivedPlayer.presentingViewController) [self.receivedPlayer dismissViewControllerAnimated:NO completion:presentComparison];
                else presentComparison();
            });
            return;
        }
        if ([role isEqualToString:@"MAIN_CAMERA"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSDictionary *current = self.receivedSessions[sessionID];
                if (current[@"SUB_CAMERA"]) return;
                self.waitingReceivedURL = current[@"MAIN_CAMERA"] ?: url;
                // 先に届いたメイン動画は一旦表示するが、サブ動画が遅れて届いた場合に
                // 比較画面へ切り替えられるよう、セッション情報は短時間保持する。
                [self displayReceived];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    NSDictionary *stillWaiting = self.receivedSessions[sessionID];
                    if (stillWaiting && !stillWaiting[@"SUB_CAMERA"]) [self.receivedSessions removeObjectForKey:sessionID];
                });
            });
        }
        return;
    }
    self.waitingReceivedURL = url;
    [self displayReceived];
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
- (void)retransferVideoURL:(NSURL *)url { if (@available(iOS 13.0, *)) [self.transfer requeue:url]; }
- (void)displayReceived {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"WJAutoPlayAfterTransfer"]) {
        self.waitingReceivedURL = nil;
        return;
    }
    if (!self.waitingReceivedURL || self.recording.busy || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    UIViewController *host = [self activePresentationHost];
    if (!host) return;
    while (host.presentedViewController && host.presentedViewController != self.receivedPlayer) host = host.presentedViewController;
    if ([host isKindOfClass:UIAlertController.class] || host.isBeingDismissed) return;
    WaterJumpReceivedPlayerViewController *player = self.receivedPlayer;
    NSURL *url = self.waitingReceivedURL; self.waitingReceivedURL = nil;
    NSArray<NSURL *> *videos = @[];
    NSInteger currentIndex = 0;
    if (@available(iOS 13.0, *)) {
        videos = [ReceivedVideoManager videos];
        NSUInteger found = [videos indexOfObject:url];
        if (found != NSNotFound) currentIndex = (NSInteger)found;
    }
    if (player && player.presentingViewController) {
        [player setPlaylist:videos.count ? videos : @[url] currentIndex:currentIndex];
        [player replaceVideoURL:url];
    }
    else {
        player = [[WaterJumpReceivedPlayerViewController alloc] initWithVideoURL:url]; self.receivedPlayer = player;
        [player setPlaylist:videos.count ? videos : @[url] currentIndex:currentIndex];
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
- (void)saveAutomatic:(NSURL *)url completion:(void (^)(NSURL *, NSDictionary *, NSError *))completion {
    if (@available(iOS 13.0, *)) {
        self.message = @"保存中..."; [self publish];
        [ReceivedVideoManager saveAutomatic:url completion:^(NSURL *saved, NSDictionary *info, NSError *error) {
            if (saved) {
                self.message = @"保存完了";
                BOOL isSubCamera = [info[@"cameraRole"] isEqual:@"SUB_CAMERA"];
                if ([[NSUserDefaults standardUserDefaults] boolForKey:@"WJTransfer"] && (isSubCamera || ![[NSUserDefaults standardUserDefaults] boolForKey:@"WJTagBeforeTransfer"])) [self.transfer enqueue:saved metadata:info];
            } else self.message = [@"動画保存失敗: " stringByAppendingString:error.localizedDescription];
            if (saved) [[NSNotificationCenter defaultCenter] postNotificationName:@"WJVideoSaved" object:saved];
            completion(saved, info, error); [self publish];
        }];
    } else completion(nil, nil, [NSError errorWithDomain:@"MTJudge.WJ" code:1 userInfo:@{NSLocalizedDescriptionKey:@"自動保存にはiOS 13以降が必要です"}]);
}

- (void)enqueueAutomaticVideoURL:(NSURL *)url metadata:(NSDictionary *)metadata tags:(NSArray<NSDictionary *> *)tags {
    if (!url || !metadata || ![[NSUserDefaults standardUserDefaults] boolForKey:@"WJTransfer"]) return;
    NSMutableDictionary *info = [metadata mutableCopy];
    info[@"tags"] = tags ?: @[];
    // 遅延転送でも既存TransferQueueが参照するサイドカーを同じ動画名で更新する。
    NSURL *sidecar = [url URLByAppendingPathExtension:@"wj.json"];
    NSURL *tagSidecar = [url URLByAppendingPathExtension:@"tags.json"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:info options:0 error:nil];
    if (data) [data writeToURL:sidecar options:NSDataWritingAtomic error:nil];
    NSData *tagData = [NSJSONSerialization dataWithJSONObject:(tags ?: @[]) options:0 error:nil];
    if (tagData) [tagData writeToURL:tagSidecar options:NSDataWritingAtomic error:nil];
    [self.transfer enqueue:url metadata:info];
}

- (void)sendSubCameraCommand:(NSString *)command {
    NSString *raw = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJSubCameraURL"];
    if (raw.length == 0 || ![command isEqualToString:@"START"] && ![command isEqualToString:@"STOP"]) return;
    NSURLComponents *components = [NSURLComponents componentsWithString:raw];
    NSString *token = components.fragment;
    components.fragment = nil;
    NSString *base = components.URL.absoluteString;
    if (base.length == 0 || token.length == 0) return;
    NSURL *url = [NSURL URLWithString:[base stringByAppendingPathComponent:command.lowercaseString]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:token forHTTPHeaderField:@"X-MTJudge-Token"];
    NSString *sessionID = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJSessionID"];
    if (sessionID.length) [request setValue:sessionID forHTTPHeaderField:@"X-MTJudge-Session"];
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
#if DEBUG
        if (error) NSLog(@"[SubCamera] %@ failed: %@", command, error.localizedDescription);
        else NSLog(@"[SubCamera] %@ sent", command);
#endif
    }];
    [task resume];
}

- (void)considerLocalMainRecordingURL:(NSURL *)url {
    if (!url) return;
    NSURL *sidecar = [url URLByAppendingPathExtension:@"wj.json"];
    NSDictionary *rawInfo = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:sidecar] ?: [NSData data] options:0 error:nil];
    NSMutableDictionary *info = [rawInfo mutableCopy] ?: [NSMutableDictionary dictionary];
    // 受信待機中のiPadで保存された動画は、旧サイドカーの役割が残っていても
    // 比較再生のメイン映像として扱う。
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"] && ![info[@"cameraRole"] isEqualToString:@"MAIN_CAMERA"]) {
        info[@"cameraRole"] = @"MAIN_CAMERA";
        NSData *data = [NSJSONSerialization dataWithJSONObject:info options:0 error:nil];
        if (data) [data writeToURL:sidecar options:NSDataWritingAtomic error:nil];
    }
    NSString *sessionID = info[@"sessionID"] ?: [[NSUserDefaults standardUserDefaults] stringForKey:@"WJSessionID"];
    if (!sessionID.length || ![info[@"cameraRole"] isEqualToString:@"MAIN_CAMERA"]) {
        if (![[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"]) return;
    }
    NSMutableDictionary *session = self.receivedSessions[sessionID];
    // 受信側とローカル側で旧セッションIDの形式が異なる場合も、待機中の
    // サブ動画が1本だけなら同じ撮影として結び付ける。
    if (!session) {
        for (NSString *key in self.receivedSessions) {
            NSMutableDictionary *candidate = self.receivedSessions[key];
            if (candidate[@"SUB_CAMERA"] && !candidate[@"MAIN_CAMERA"]) { session = candidate; sessionID = key; break; }
        }
    }
    NSURL *subURL = session[@"SUB_CAMERA"];
    if (!subURL) return;
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"WJAutoPlayAfterTransfer"]) return;
    [self.receivedSessions removeObjectForKey:sessionID];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *host = self.receivedPlayer.presentingViewController ?: [self activePresentationHost];
        if (!host) return;
        self.comparisonPlayer = [[WaterJumpComparisonViewController alloc] initWithMainURL:url subURL:subURL];
        void (^presentComparison)(void) = ^{
            [host presentViewController:self.comparisonPlayer animated:YES completion:^{ [self.comparisonPlayer startPlayback]; }];
        };
        if (self.receivedPlayer.presentingViewController) [self.receivedPlayer dismissViewControllerAnimated:NO completion:presentComparison];
        else presentComparison();
    });
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
