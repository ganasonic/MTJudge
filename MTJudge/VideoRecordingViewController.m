#import "VideoRecordingViewController.h"
#import "TagListViewController.h" // 追加
#import "TagSelectionViewController.h"
#import "FileSaver.h"
#import "WaterJump/RecordingController.h"
#import "WaterJump/WaterJumpCoordinator.h"
#import "WaterJump/WaterJumpSettingsViewController.h"
#import <AudioToolbox/AudioToolbox.h>
#import <Vision/Vision.h>
#import "SkeletonConnections.h"
#import <QuartzCore/QuartzCore.h>

// トラックの任意の位置へのタップと、そのままのドラッグに対応する。
@interface PlaybackSlider : UISlider
@end
@implementation PlaybackSlider
- (void)updateWithTouch:(UITouch *)touch {
    CGRect track = [self trackRectForBounds:self.bounds];
    CGRect first = [self thumbRectForBounds:self.bounds trackRect:track value:self.minimumValue];
    CGRect last = [self thumbRectForBounds:self.bounds trackRect:track value:self.maximumValue];
    CGFloat width = CGRectGetMidX(last) - CGRectGetMidX(first);
    CGFloat fraction = width != 0 ? ([touch locationInView:self].x - CGRectGetMidX(first)) / width : 0;
    self.value = self.minimumValue + MIN(1, MAX(0, fraction)) * (self.maximumValue - self.minimumValue);
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    self.highlighted = YES;
    [self sendActionsForControlEvents:UIControlEventEditingDidBegin];
    [self updateWithTouch:touch];
    return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self updateWithTouch:touch];
    return YES;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (touch) [self updateWithTouch:touch];
    self.highlighted = NO;
    [self sendActionsForControlEvents:UIControlEventEditingDidEnd];
}
- (void)cancelTrackingWithEvent:(UIEvent *)event {
    self.highlighted = NO;
    [self sendActionsForControlEvents:UIControlEventEditingDidEnd];
}
@end

@interface VideoRecordingViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UILabel *waterJumpStatus;
@property (nonatomic, strong) RecordingController *recordingController;
@property (nonatomic, strong) NSURL *pendingRecordingURL;
@property (nonatomic, strong) UIDocumentPickerViewController *downloadsPicker;
@property (nonatomic, copy) void (^downloadsReadyHandler)(void);
@property (nonatomic, strong) NSURL *latestRecordingURL;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *skeletonButton;
@property (nonatomic, strong) UIButton *tagButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIStackView *zoomPresetsRow;
@property (nonatomic, copy) NSArray<NSNumber *> *displayedZoomPresets;
@property (nonatomic, strong) UIButton *guideButton;
@property (nonatomic, strong) UIView *guideView;
@property (nonatomic, strong) CAShapeLayer *guideLayer;
@property (nonatomic, assign) BOOL guideEnabled;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIActivityIndicatorView *recordingActivity;
@property (nonatomic, strong) UIVisualEffectView *zoomControls;
@property (nonatomic, strong) UIButton *zoomInButton;
@property (nonatomic, strong) UIButton *zoomOutButton;
@property (nonatomic, strong) UILabel *zoomLabel;
@property (nonatomic, strong) UIPinchGestureRecognizer *zoomPinch;
@property (nonatomic, assign) CGFloat requestedZoom;
@property (nonatomic, assign) CGFloat pinchStartZoom;
@property (nonatomic, assign) NSUInteger zoomRequestGeneration;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) UIView *playbackView;
@property (nonatomic, assign) BOOL finishingRecording;
@property (nonatomic, strong) UIVisualEffectView *playbackControls;
@property (nonatomic, strong) NSLayoutConstraint *cameraControlsBottomConstraint;
@property (nonatomic, strong) PlaybackSlider *positionSlider;
@property (nonatomic, strong) PlaybackSlider *speedSlider;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) id playbackTimeObserver;
@property (nonatomic, assign) float playbackSpeed;
@property (nonatomic, assign) BOOL scrubbing;
@property (nonatomic, assign) BOOL seeking;
@property (nonatomic, assign) CMTime requestedSeekTime;
@end

@implementation VideoRecordingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.videoRecorder = [[VideoRecorder alloc] init];
    self.videoRecorder.delegate = self;
    self.recordingController = [[RecordingController alloc] initWithRecorder:self.videoRecorder];
    __weak typeof(self) weakCamera = self;
    self.recordingController.canStart = ^BOOL {
        typeof(self) camera = weakCamera;
        return camera && camera.view.window && !camera.player && !camera.pendingRecordingURL && !camera.presentedViewController && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    };
    self.recordingController.changed = ^{
        typeof(self) camera = weakCamera;
        camera.finishingRecording = [@[@"STOPPING", @"SAVING"] containsObject:camera.recordingController.state];
        [camera updateCameraControls];
        [[WaterJumpCoordinator shared] publish];
    };

    [WaterJumpCoordinator shared].recording = self.recordingController;
    [[WaterJumpCoordinator shared] applySettings];

    // カメラセッションの初期化中も白いStoryboard背景を表示しない。
    // セッション開始後にpreviewLayerが接続されるまで黒背景で待機する。
    self.previewView.backgroundColor = UIColor.blackColor;

    NSLog(@"videoRecorder is %@", self.videoRecorder ? @"not nil" : @"nil");
    NSLog(@"previewView is %@", self.previewView ? @"not nil" : @"nil");

    // 初期状態で描画を有効にする
    self.isSkeletonDrawingEnabled = NO;
    NSString *latestPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"LatestCameraRecordingPath"];
    if (latestPath && [[NSFileManager defaultManager] fileExistsAtPath:latestPath]) {
        self.latestRecordingURL = [NSURL fileURLWithPath:latestPath];
    }
    self.playbackSpeed = 1.0;
    self.requestedZoom = 1.0;
    [self setupCameraControls];
    UIButton *remote = [self cameraButtonWithAction:@selector(openWaterJump)];
    [self styleButton:remote title:@"ウォータージャンプ設定" symbol:@"antenna.radiowaves.left.and.right" color:UIColor.darkGrayColor];
    remote.accessibilityIdentifier = @"WJSettingsButton";
    remote.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:remote];
    self.waterJumpStatus = [UILabel new]; self.waterJumpStatus.translatesAutoresizingMaskIntoConstraints = NO;
    self.waterJumpStatus.accessibilityIdentifier = @"WJStatusLabel";
    self.waterJumpStatus.numberOfLines = 3; self.waterJumpStatus.font = [UIFont systemFontOfSize:11];
    self.waterJumpStatus.textColor = UIColor.whiteColor; self.waterJumpStatus.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];
    [self.view addSubview:self.waterJumpStatus];
    [NSLayoutConstraint activateConstraints:@[
        [remote.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [remote.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [self.waterJumpStatus.topAnchor constraintEqualToAnchor:remote.bottomAnchor constant:4],
        [self.waterJumpStatus.leadingAnchor constraintEqualToAnchor:remote.leadingAnchor],
        [self.waterJumpStatus.widthAnchor constraintEqualToConstant:160]
    ]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateWaterJumpStatus) name:WJStatusChanged object:nil];
    [self updateWaterJumpStatus];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackEnded:) name:UIApplicationDidEnterBackgroundNotification object:nil];

    dispatch_queue_t cameraQueue = dispatch_queue_create("com.MTJudge.cameraSetupQueue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(cameraQueue, ^{
        [self.videoRecorder setupCamera];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            AVCaptureVideoPreviewLayer *previewLayer = self.videoRecorder.previewLayer;
            previewLayer.frame = self.previewView.bounds;
            [self.previewView.layer addSublayer:previewLayer];

            self.drawingLayer = [CALayer layer];
            self.drawingLayer.frame = self.previewView.bounds;
            [self.previewView.layer addSublayer:self.drawingLayer];
            self.requestedZoom = self.videoRecorder.zoomFactor;
            [self updateCameraControls];
        });
    });
}

- (void)openWaterJump {
    if (self.recordingController.busy) return;
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:[WaterJumpSettingsViewController new]] animated:YES completion:nil];
}
- (void)updateWaterJumpStatus {
    NSDictionary *status = [[WaterJumpCoordinator shared] status];
    self.waterJumpStatus.hidden = ![WaterJumpCoordinator shared].modeEnabled && ![[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"];
    [self updateCameraControls];
    self.waterJumpStatus.text = [NSString stringWithFormat:@"%@\n%@", status[@"state"], status[@"message"]];
}
#pragma mark - VideoRecorderDelegate
- (void)videoRecorderDidStart:(id)recorder { [self.recordingController didStart]; }

// ファイルの書き込み完了後、メインスレッドで保存先を選択する。
- (void)videoRecorder:(id)recorder didFinishRecordingToOutputFileURL:(NSURL *)outputFileURL error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.finishingRecording = NO;
        [self updateCameraControls];
        BOOL finishedSuccessfully = !error || [error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] boolValue];
        [self.recordingController finishedWithError:finishedSuccessfully ? nil : error];
        if (!finishedSuccessfully) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"録画できませんでした"
                                                                                   message:error.localizedDescription
                                                                            preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        if (self.recordingController.automaticRecording) {
            [[WaterJumpCoordinator shared] saveAutomatic:outputFileURL completion:^(NSURL *saved, NSError *saveError) {
                if (saved) {
                    self.latestRecordingURL = saved;
                    [[NSUserDefaults standardUserDefaults] setObject:saved.path forKey:@"LatestCameraRecordingPath"];
                    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"LatestCameraRecordingTags"];
                    [self.recordingController markSaved];
                } else {
                    self.latestRecordingURL = outputFileURL;
                    self.pendingRecordingURL = outputFileURL;
                    [self.recordingController finishedWithError:saveError];
                    [self presentRecordingReview];
                }
                [self updateCameraControls];
            }];
            return;
        }
        NSURL *directory = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        directory = [directory URLByAppendingPathComponent:@"CameraRecordings" isDirectory:YES];
        NSError *storageError = nil;
        [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&storageError];
        NSURL *localURL = [directory URLByAppendingPathComponent:outputFileURL.lastPathComponent];
        if (!storageError && [[NSFileManager defaultManager] moveItemAtURL:outputFileURL toURL:localURL error:&storageError]) {
            NSURL *previousURL = self.latestRecordingURL;
            [[NSUserDefaults standardUserDefaults] setObject:localURL.path forKey:@"LatestCameraRecordingPath"];
            if (previousURL && [previousURL.URLByDeletingLastPathComponent isEqual:directory] && ![previousURL isEqual:localURL]) {
                [[NSFileManager defaultManager] removeItemAtURL:previousURL error:NULL];
            }
        } else {
            localURL = outputFileURL;
            NSLog(@"Could not retain recording: %@", storageError);
        }
        // 保存先での移動・削除に影響されない再生用コピーを保持する。
        self.latestRecordingURL = localURL;
        self.pendingRecordingURL = localURL;
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"LatestCameraRecordingTags"];
        [self updateCameraControls];
        [self.recordingController markSaved];
        [self presentRecordingReview];
    });
}

- (void)presentRecordingReview {
    if (!self.pendingRecordingURL || self.presentedViewController) return;
    TagSelectionViewController *review = [[TagSelectionViewController alloc] initWithVideoFileURL:self.pendingRecordingURL];
    review.selections = [[NSUserDefaults standardUserDefaults] arrayForKey:@"LatestCameraRecordingTags"] ?: @[];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:review];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    navigation.modalInPresentation = YES;
    __weak typeof(self) weakSelf = self;
    void (^finish)(NSArray *, BOOL) = ^(NSArray<NSDictionary<NSString *, NSString *> *> *selections, BOOL exportVideo) {
        typeof(self) self = weakSelf;
        if (!self) return;
        NSError *error = nil;
        if (selections.count) {
            NSMutableArray *names = [NSMutableArray array];
            NSCharacterSet *unsafe = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|\n\r"];
            for (NSDictionary *selection in selections) {
                NSString *name = [[selection[@"name"] componentsSeparatedByCharactersInSet:unsafe] componentsJoinedByString:@"-"];
                [names addObject:[name substringToIndex:MIN(name.length, 24)]];
            }
            NSString *suffix = NSUUID.UUID.UUIDString;
            NSString *prefix = [names componentsJoinedByString:@"_"];
            prefix = [prefix substringToIndex:MIN(prefix.length, 60)];
            NSURL *taggedURL = [[self.pendingRecordingURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@.mov", prefix, suffix]];
            if ([[NSFileManager defaultManager] moveItemAtURL:self.pendingRecordingURL toURL:taggedURL error:&error]) {
                self.pendingRecordingURL = taggedURL;
                self.latestRecordingURL = taggedURL;
                [[NSUserDefaults standardUserDefaults] setObject:taggedURL.path forKey:@"LatestCameraRecordingPath"];
                // カテゴリ名とタグIDも動画に関連付けてアプリ内に保持する。
                [[NSUserDefaults standardUserDefaults] setObject:selections forKey:@"LatestCameraRecordingTags"];
            }
        } else {
            NSURL *untaggedURL = [[self.pendingRecordingURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"mov"]];
            if ([[NSFileManager defaultManager] moveItemAtURL:self.pendingRecordingURL toURL:untaggedURL error:&error]) {
                self.pendingRecordingURL = untaggedURL;
                self.latestRecordingURL = untaggedURL;
                [[NSUserDefaults standardUserDefaults] setObject:untaggedURL.path forKey:@"LatestCameraRecordingPath"];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"LatestCameraRecordingTags"];
            }
        }
        if (error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"タグを保存できませんでした" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self.presentedViewController presentViewController:alert animated:YES completion:nil];
            return;
        }
        if (exportVideo) {
            [self dismissViewControllerAnimated:YES completion:^{ [self presentRecordingSavePicker]; }];
            return;
        }
        UIViewController *screen = self.presentedViewController;
        screen.view.userInteractionEnabled = NO;
        NSURL *sourceURL = self.pendingRecordingURL;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *saveError = nil;
            NSURL *savedURL = [[[FileSaver alloc] init] saveVideo:sourceURL selections:selections error:&saveError];
            dispatch_async(dispatch_get_main_queue(), ^{
                screen.view.userInteractionEnabled = YES;
                if (!savedURL) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存できませんでした" message:saveError.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"閉じる" style:UIAlertActionStyleCancel handler:nil]];
                    [alert addAction:[UIAlertAction actionWithTitle:@"保存先を再設定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                        [FileSaver forgetDownloadsDirectory];
                        [self chooseDownloadsDirectoryWithCompletion:nil];
                    }]];
                    [screen presentViewController:alert animated:YES completion:nil];
                    return;
                }
                // 外部フォルダの権限や移動に左右されず最新動画を再生できるよう、
                // アプリ内には直近の1本だけ再生用コピーを保持する。
                self.latestRecordingURL = sourceURL;
                self.pendingRecordingURL = nil;
                [self.recordingController markSaved];
                [[NSUserDefaults standardUserDefaults] setObject:sourceURL.path forKey:@"LatestCameraRecordingPath"];
                [self updateCameraControls];
                [self dismissViewControllerAnimated:YES completion:^{
                    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"動画を保存しました");
                }];
            });
        });
    };
    review.saveHandler = ^(NSArray *selections) {
        if ([FileSaver hasDownloadsDirectory]) {
            finish(selections, NO);
        } else {
            [weakSelf chooseDownloadsDirectoryWithCompletion:^{ finish(selections, NO); }];
        }
    };
    review.exportHandler = ^(NSArray *selections) { finish(selections, YES); };
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)chooseDownloadsDirectoryWithCompletion:(void (^)(void))completion {
    if (self.downloadsPicker) return;
    self.downloadsReadyHandler = completion;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.folder"] inMode:UIDocumentPickerModeOpen];
    picker.title = @"ダウンロードフォルダを選択";
    picker.allowsMultipleSelection = NO;
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    self.downloadsPicker = picker;
    [self.presentedViewController presentViewController:picker animated:YES completion:nil];
}

- (void)presentRecordingSavePicker {
    if (!self.pendingRecordingURL || self.presentedViewController) {
        return;
    }
    UIDocumentPickerViewController *picker;
    if (@available(iOS 14.0, *)) {
        picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[self.pendingRecordingURL] asCopy:YES];
    } else {
        picker = [[UIDocumentPickerViewController alloc] initWithURL:self.pendingRecordingURL inMode:UIDocumentPickerModeExportToService];
    }
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (controller == self.downloadsPicker) {
        NSError *error = nil;
        BOOL remembered = urls.count && [FileSaver rememberDownloadsDirectory:urls.firstObject error:&error];
        void (^ready)(void) = self.downloadsReadyHandler;
        self.downloadsReadyHandler = nil;
        self.downloadsPicker = nil;
        [controller dismissViewControllerAnimated:YES completion:^{
            if (remembered) {
                if (ready) ready();
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存先を登録できませんでした" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self.presentedViewController presentViewController:alert animated:YES completion:nil];
            }
        }];
        return;
    }
    if (urls.count == 0) {
        return;
    }
    self.pendingRecordingURL = nil;
    [self updateCameraControls];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (controller == self.downloadsPicker) {
        self.downloadsPicker = nil;
        self.downloadsReadyHandler = nil;
    }
    [self updateCameraControls];
}

// フレームごとに呼び出されるデリゲートメソッド
- (void)videoRecorder:(id)recorder didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    
    // カメラから送られてくるビデオフレーム（sampleBuffer）から、そのフレームのピクセルデータに
    // アクセスするためのオブジェクト（pixelBuffer）を取り出す
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) {
        return;
    }
    
    // Visionフレームワークを使って、ピクセルデータから人間の骨格を検出するリクエストを作成
    VNDetectHumanBodyPoseRequest *request = [[VNDetectHumanBodyPoseRequest alloc] init];
    /* 人体の姿勢（Human Body Pose）を検出するためのリクエストオブジェクトを初期化する。
    具体的には、画像や動画フレーム内に写っている人物の関節や骨格の位置を特定するためのタスクを定義している。
    VNDetectHumanBodyPoseRequest: 人物の体の姿勢を検出するリクエストを定義するクラス*/ 
    
    // ピクセルデータを使ってリクエストを実行するためのハンドラを作成
    // 画像データが含まれたCVPixelBufferを受け取り、それをVisionフレームワークが解析できる形式に変換するための処理ハンドラーを初期化している。
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer options:@{}];
    /* VNImageRequestHandler: Visionリクエストの処理を管理するクラス
       画像データや動画データなどのソースを指定し、そのデータに対してどのようなビジョンタスク（例: 顔認識、物体検出、姿勢推定など）
       を実行するかを設定するために使用される
     */
    
    NSError *error = nil;
    // Visionフレームワークの画像解析リクエストを実行
    [handler performRequests:@[request] error:&error];
    /* 配列で渡されたビジョンリクエスト（この場合はVNDetectHumanBodyPoseRequest）を実行するように指示している。
       これにより、指定された画像データに対して人体の姿勢検出が行われ、その結果がリクエストオブジェクトに格納される。
       error: リクエストの実行中に発生したエラー情報を格納するためのポインタ
    */
    
    // Visionフレームワークで検出された人体の骨格情報を画面に描画している
    /* 非同期処理を管理するGrand Central Dispatch (GCD) を利用して、ユーザーインターフェース (UI) の更新を
       メインスレッドに送っている。
       これは、UIの描画は常にメインスレッドで行うというiOSアプリ開発の基本原則に従うためのもの
    */
    dispatch_async(dispatch_get_main_queue(), ^{
        /* dispatch_async(dispatch_get_main_queue(), ^{ ... });: 
           これは、メインスレッド（UIの更新を担当するスレッド）で、非同期的に指定されたブロック内のコードを実行するための命令 
        */
        // 描画が有効な場合のみ処理を実行する（骨格の描画が有効に設定されているかを確認）
        if (self.isSkeletonDrawingEnabled) {
            // 画面上の既存の描画をクリア
            [self clearDrawing];
            // エラーがなく、リクエスト結果が存在する場合に骨格を描画
            if (!error && request.results.count > 0) {
                // 検出された各骨格に対して描画を実行
                /* 検出された各人物の骨格データ（VNHumanBodyPoseObservation）をループで処理 */
                for (VNHumanBodyPoseObservation *observation in request.results) {
                    // 骨格データから関節の位置を取得し、それを画面に線で結んで骨格を描画するカスタムメソッドを呼び出している
                    [self drawSkeletonFromObservation:observation];
                }
            }
        }
    });
}
#pragma mark - Drawing Methods

// 骨格を描画するメソッド
- (void)drawSkeletonFromObservation:(VNHumanBodyPoseObservation *)observation {

    // iOSやmacOSで図形を描画する際に使われるUIBezierPathオブジェクトを初期化し、その線の端の形状を設定している
    UIBezierPath *path = [UIBezierPath bezierPath];
    // lineCapStyleは、線の始点と終点のスタイルを決定するプロパティに丸型線端を設定
    path.lineCapStyle = kCGLineCapRound;//kCGLineCapRoundは線の端を丸くするスタイル（丸型線端）
    
    // 接続する関節のペアを定義
    /* VisionフレームワークのVNDetectHumanBodyPoseRequestで検出された人物の関節をつなぎ合わせ、
       骨格（スケルトン）を描画するための接続情報（骨）を定義
       関節のペア（bodyConnections）を二次元配列としてリストアップしています。
       各内部配列は、線で結びつけるべき2つの関節（Joint）を文字列で指定してる
       各配列は始点と終点の関節をセットで持っている
    */
    NSArray<NSArray<NSString *> *> *bodyConnections = SkeletonConnections();
    
    // 各関節ペアに対して線を描画
    /* 各関節ペア（bodyConnections）をループで処理して、関節間に線を引くための座標を計算し、
       その線をUIBezierPathオブジェクトに追加している
    */    
    for (NSArray<NSString *> *connection in bodyConnections) {
        // 各関節ペアの始点と終点の座標を取得
        /* observation: Visionフレームワークが提供するVNHumanBodyPoseObservationオブジェクト
           recognizedPointForJointName:error:: 指定された関節名に対応する認識されたポイント（関節の位置情報）を取得するメソッド
           connection.firstObject: 関節ペアの始点の関節名
           connection.lastObject: 関節ペアの終点の関節名
        */
        // それぞれの関節名に対応する認識されたポイント（関節の位置情報）を取得
        VNRecognizedPoint *startPoint = [observation recognizedPointForJointName:connection.firstObject error:nil];
        VNRecognizedPoint *endPoint = [observation recognizedPointForJointName:connection.lastObject error:nil];
        /* Visionフレームワークの姿勢検出結果から、特定の関節（ジョイント）の座標情報を取り出している
           VNRecognizedPoint: Visionフレームワークで認識されたポイント（関節の位置情報）を表すクラス
        */

        // 関節の信頼度が一定以上の場合にのみ線を描画
        if (startPoint.confidence > 0.1 && endPoint.confidence > 0.1) {
        /* startPoint.confidence > 0.1 && endPoint.confidence > 0.1:
           各関節の認識信頼度（confidence）が0.1より大きい場合にのみ、その関節間に線を引く条件を設定
            confidence: Visionフレームワークがその関節の位置をどれだけ正確に認識しているかを示す数値
        */       

            // 正しい座標変換の計算式
            // VisionのY座標をXに、VisionのX座標をYに割り当て

            /* Visionフレームワークが検出した正規化された関節の座標を、画面に描画するためのUIKit座標に変換し、それらの座標を使って線を描画している
                self.previewView.bounds.size.width: プレビュー表示領域の幅
                self.previewView.bounds.size.height: プレビュー表示領域の高さ
                Visionフレームワークは座標系が異なるため、Y座標とX座標を入れ替えて計算している
            */
            CGPoint start = CGPointMake(startPoint.location.y * self.previewView.bounds.size.width,
                                         startPoint.location.x * self.previewView.bounds.size.height);
            /* VisionのY座標を、プレビュー画面の幅に掛けることで、UIKitのX座標を計算している。これは、VisionのY軸がUIKitのX軸に相当するため */

            CGPoint end = CGPointMake(endPoint.location.y * self.previewView.bounds.size.width,
                                       endPoint.location.x * self.previewView.bounds.size.height);
            /* VisionのX座標を、プレビュー画面の高さに掛けることで、UIKitのY座標を計算している。これは、VisionのX軸がUIKitのY軸に相当するため */

            /* Visionフレームワークが返す座標（startPoint.locationとendPoint.location）は、
               正規化された（0.0から1.0の範囲）値であり、通常は左下を原点とし、Y軸が上向きになっている。
               しかし、iOSアプリの画面描画で使われるUIKitの座標系は、左上を原点とし、Y軸が下向きです。
            */

            // UIBezierPathオブジェクト（path）を使って、変換された座標を基に線を描画
            [path moveToPoint:start];// 始点（start）**の座標から線を引き始める
            [path addLineToPoint:end];// 始点から終点（end）までの直線を追加
        }
    }
    
    // 人体の骨格を描画するためのレイヤーを作成し、そのスタイルを設定している
    CAShapeLayer *lineLayer = [CAShapeLayer layer];
    /* CAShapeLayerは、UIBezierPathなどのパスを使って図形を描画するのに特化したレイヤー
       CALayerのサブクラスであり、パスに基づいて形状を描画するためのプロパティやメソッドを提供する
    */

    // 前のステップで作成された骨格の描画パス（UIBezierPath）を、このレイヤーのpathプロパティに設定している
    lineLayer.path = path.CGPath;//path.CGPathは、UIBezierPathの描画情報をCGPathという下位レベルの形式に変換
    lineLayer.strokeColor = [UIColor greenColor].CGColor;// 線の色を緑色に設定
    lineLayer.lineWidth = 3.0;// 線の太さを3ポイントに設定
    lineLayer.fillColor = [UIColor clearColor].CGColor;// 塗りつぶしの色を透明に設定
    
    // 描画レイヤー（drawingLayer）に骨格描画レイヤー（lineLayer）を追加
    [self.drawingLayer addSublayer:lineLayer];
}

// 画面上の描画をすべてクリアするメソッド
- (void)clearDrawing {
    // drawingLayerのすべてのサブレイヤーを削除して、画面上の描画をクリア
    [self.drawingLayer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
}

#pragma mark - Action
// 骨格描画の有効/無効を切り替えるアクションメソッド
- (IBAction)toggleSkeletonDrawing:(id)sender {
    // 描画の状態を反転させる
    self.isSkeletonDrawingEnabled = !self.isSkeletonDrawingEnabled;
    self.videoRecorder.skeletonDrawingEnabled = self.isSkeletonDrawingEnabled;
    
    // 描画が無効になったら、画面上の線をすべて消去する
    if (!self.isSkeletonDrawingEnabled) {
        [self clearDrawing];
    }
    
    [self updateCameraControls];
}

// タグ管理画面に遷移するメソッドを追加
- (IBAction)manageTagsButtonTapped:(id)sender {
    if (self.pendingRecordingURL) {
        [self presentRecordingReview];
        return;
    }
    TagListViewController *tagListVC = [[TagListViewController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:tagListVC];
    [self presentViewController:navController animated:YES completion:nil];
}

- (IBAction)recordButtonTapped:(id)sender {
    if (self.finishingRecording || self.player) return;
    if (self.videoRecorder.isRecording) {
        self.finishingRecording = YES;
        [self.recordingController stop];
    } else {
        if (self.pendingRecordingURL) {
            [self presentRecordingSavePicker];
            return;
        }
        NSError *startError = nil;
        if (![self.recordingController startAutomatic:[WaterJumpCoordinator shared].modeEnabled error:&startError]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"録画を開始できません" message:startError.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
    }
    [self updateCameraControls];
}

- (UIButton *)cameraButtonWithAction:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.layer.cornerRadius = 14;
    button.layer.borderWidth = 1;
    button.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
    button.contentEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10);
    button.tintColor = UIColor.whiteColor;
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:44].active = YES;
    NSLayoutConstraint *width = [button.widthAnchor constraintEqualToConstant:44];
    width.priority = 999; // 非表示の保存ボタンはスタック内で折りたたむ。
    width.active = YES;
    return button;
}

- (void)styleButton:(UIButton *)button title:(NSString *)title symbol:(NSString *)symbol color:(UIColor *)color {
    [button setTitle:nil forState:UIControlStateNormal];
    if (@available(iOS 13.0, *)) {
        [button setImage:[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    }
    button.backgroundColor = [color colorWithAlphaComponent:0.22];
    button.accessibilityLabel = title;
    button.alpha = button.enabled ? 0.85 : 0.30;
}

- (void)setupCameraControls {
    self.guideView = [[UIView alloc] init];
    self.guideView.userInteractionEnabled = NO;
    self.guideView.translatesAutoresizingMaskIntoConstraints = NO;
    self.guideView.hidden = YES;
    [self.view addSubview:self.guideView];
    [NSLayoutConstraint activateConstraints:@[
        [self.guideView.leadingAnchor constraintEqualToAnchor:self.previewView.leadingAnchor],
        [self.guideView.trailingAnchor constraintEqualToAnchor:self.previewView.trailingAnchor],
        [self.guideView.topAnchor constraintEqualToAnchor:self.previewView.topAnchor],
        [self.guideView.bottomAnchor constraintEqualToAnchor:self.previewView.bottomAnchor]
    ]];
    self.guideLayer = [CAShapeLayer layer];
    self.guideLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.45].CGColor;
    self.guideLayer.fillColor = UIColor.clearColor.CGColor;
    self.guideLayer.lineWidth = 1.5;
    [self.guideView.layer addSublayer:self.guideLayer];
    self.playbackView = [[UIView alloc] init];
    self.playbackView.backgroundColor = UIColor.blackColor;
    self.playbackView.hidden = YES;
    self.playbackView.userInteractionEnabled = NO;
    self.playbackView.frame = self.previewView.bounds;
    self.playbackView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.previewView addSubview:self.playbackView];

    UIVisualEffectView *panel = [[UIVisualEffectView alloc] initWithEffect:nil];
    panel.backgroundColor = UIColor.clearColor;
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.layer.cornerRadius = 24;
    panel.clipsToBounds = YES;
    [self.view addSubview:panel];
    self.recordButton = [self cameraButtonWithAction:@selector(recordButtonTapped:)];
    self.recordingActivity = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.recordingActivity.translatesAutoresizingMaskIntoConstraints = NO;
    self.recordingActivity.hidesWhenStopped = YES;
    [self.recordButton addSubview:self.recordingActivity];
    [NSLayoutConstraint activateConstraints:@[
        [self.recordingActivity.centerXAnchor constraintEqualToAnchor:self.recordButton.centerXAnchor],
        [self.recordingActivity.centerYAnchor constraintEqualToAnchor:self.recordButton.centerYAnchor]
    ]];
    self.playButton = [self cameraButtonWithAction:@selector(togglePlayback:)];
    self.skeletonButton = [self cameraButtonWithAction:@selector(toggleSkeletonDrawing:)];
    self.tagButton = [self cameraButtonWithAction:@selector(manageTagsButtonTapped:)];
    self.guideButton = [self cameraButtonWithAction:@selector(toggleGuide:)];
    self.deleteButton = [self cameraButtonWithAction:@selector(deleteLatestRecording:)];
    self.saveButton = [self cameraButtonWithAction:@selector(presentRecordingSavePicker)];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.recordButton, self.playButton, self.skeletonButton, self.tagButton, self.guideButton, self.deleteButton, self.saveButton]];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 4;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [panel.contentView addSubview:stack];
    self.cameraControlsBottomConstraint = [panel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8];
    [NSLayoutConstraint activateConstraints:@[
        [panel.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        self.cameraControlsBottomConstraint,
        [stack.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor constant:8],
        [stack.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor constant:-8],
        [stack.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor constant:8],
        [stack.bottomAnchor constraintEqualToAnchor:panel.contentView.bottomAnchor constant:-8]
    ]];
    [self setupPlaybackControls];
    [self setupZoomControls];
    [self updateCameraControls];
}

- (void)updateCameraControls {
    BOOL recording = self.videoRecorder.isRecording;
    BOOL playing = self.player != nil;
    self.playbackControls.hidden = !playing;
    [self updateZoomControls];
    if (playing) [self.playbackControls.superview bringSubviewToFront:self.playbackControls];
    [self updateCameraControlsPosition];
    self.recordButton.enabled = !playing && !self.finishingRecording && !self.pendingRecordingURL && (recording || self.videoRecorder.readyForRecording);
    self.playButton.enabled = self.latestRecordingURL != nil && !recording && !self.finishingRecording;
    self.skeletonButton.enabled = !playing;
    self.tagButton.enabled = !recording && !playing && !self.finishingRecording;
    self.deleteButton.hidden = self.latestRecordingURL == nil;
    self.deleteButton.enabled = !recording && !self.finishingRecording && ![[WaterJumpCoordinator shared] protectsVideo:self.latestRecordingURL];
    [self styleButton:self.deleteButton title:@"再生用動画を削除" symbol:@"trash" color:UIColor.systemRedColor];
    self.saveButton.hidden = !self.pendingRecordingURL;
    self.saveButton.enabled = !playing;
    self.guideButton.hidden = self.pendingRecordingURL != nil;
    self.guideButton.enabled = !playing;
    self.guideView.hidden = !self.guideEnabled || playing;
    UIColor *neutral = [UIColor colorWithWhite:0.22 alpha:0.95];
    [self styleButton:self.recordButton title:recording ? @"録画停止" : @"録画開始" symbol:recording ? @"stop.fill" : @"record.circle" color:UIColor.systemRedColor];
    if (self.finishingRecording) {
        [self.recordButton setImage:nil forState:UIControlStateNormal];
        self.recordButton.accessibilityLabel = @"録画した動画を処理中";
        [self.recordingActivity startAnimating];
    } else {
        [self.recordingActivity stopAnimating];
    }
    [self styleButton:self.playButton title:playing ? @"再生停止" : @"最新動画を再生" symbol:playing ? @"stop.fill" : @"play.fill" color:UIColor.systemBlueColor];
    [self styleButton:self.skeletonButton title:self.isSkeletonDrawingEnabled ? @"骨格を非表示" : @"骨格を表示" symbol:@"figure.walk" color:self.isSkeletonDrawingEnabled ? [UIColor colorWithRed:0.08 green:0.45 blue:0.28 alpha:1] : neutral];
    self.skeletonButton.accessibilityValue = self.isSkeletonDrawingEnabled ? @"表示中" : @"非表示";
    [self styleButton:self.tagButton title:@"タグ設定" symbol:@"tag.fill" color:neutral];
    [self styleButton:self.guideButton title:self.guideEnabled ? @"十字ガイドを非表示" : @"十字ガイドを表示" symbol:@"scope" color:self.guideEnabled ? UIColor.systemBlueColor : neutral];
    self.guideButton.accessibilityValue = self.guideEnabled ? @"表示中" : @"非表示";
    [self styleButton:self.saveButton title:@"保存先を選択" symbol:@"square.and.arrow.down" color:neutral];
}

- (void)deleteLatestRecording:(id)sender {
    if (!self.latestRecordingURL || self.videoRecorder.isRecording || self.finishingRecording) return;
    NSURL *url = self.latestRecordingURL;
    if ([[WaterJumpCoordinator shared] protectsVideo:url]) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"再生用動画を削除しますか？" message:self.pendingRecordingURL ? @"未保存の動画を削除します。この操作は取り消せません。" : ([url.path containsString:@"/Documents/Recordings/"] ? @"この端末に保存した練習動画を削除します。この操作は取り消せません。転送済みの相手側動画は残ります。" : @"アプリ内の再生用動画を削除します。ダウンロードに保存済みの動画は残ります。") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"削除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self stopPlayback];
        NSError *error = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:url.path] && ![[NSFileManager defaultManager] removeItemAtURL:url error:&error]) {
            UIAlertController *failure = [UIAlertController alertControllerWithTitle:@"削除できませんでした" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [failure addAction:[UIAlertAction actionWithTitle:@"閉じる" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:failure animated:YES completion:nil];
            return;
        }
        [[NSFileManager defaultManager] removeItemAtPath:[url.path stringByAppendingString:@".tags.json"] error:nil];
        self.latestRecordingURL = nil;
        if ([self.pendingRecordingURL isEqual:url]) self.pendingRecordingURL = nil;
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"LatestCameraRecordingPath"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"LatestCameraRecordingTags"];
        [self updateCameraControls];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)toggleGuide:(id)sender {
    self.guideEnabled = !self.guideEnabled;
    [self updateGuideGeometry];
    [self updateCameraControls];
}

- (void)updateGuideGeometry {
    CGRect bounds = self.guideView.bounds;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(CGRectGetMidX(bounds), CGRectGetMinY(bounds))];
    [path addLineToPoint:CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds))];
    [path moveToPoint:CGPointMake(CGRectGetMinX(bounds), CGRectGetMidY(bounds))];
    [path addLineToPoint:CGPointMake(CGRectGetMaxX(bounds), CGRectGetMidY(bounds))];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.guideLayer.frame = bounds;
    self.guideLayer.path = path.CGPath;
    [CATransaction commit];
}

- (void)setupZoomControls {
    self.zoomPinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchCamera:)];
    [self.previewView addGestureRecognizer:self.zoomPinch];
    self.previewView.userInteractionEnabled = YES;
    self.zoomControls = [[UIVisualEffectView alloc] initWithEffect:nil];
    self.zoomControls.backgroundColor = [UIColor colorWithWhite:0 alpha:0.12];
    self.zoomControls.translatesAutoresizingMaskIntoConstraints = NO;
    self.zoomControls.layer.cornerRadius = 18;
    self.zoomControls.clipsToBounds = YES;
    [self.view addSubview:self.zoomControls];
    self.zoomOutButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.zoomInButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.zoomOutButton setImage:[UIImage systemImageNamed:@"minus.magnifyingglass"] forState:UIControlStateNormal];
    [self.zoomInButton setImage:[UIImage systemImageNamed:@"plus.magnifyingglass"] forState:UIControlStateNormal];
    self.zoomOutButton.accessibilityLabel = @"ズームアウト";
    self.zoomInButton.accessibilityLabel = @"ズームイン";
    [self.zoomOutButton addTarget:self action:@selector(zoomOut:) forControlEvents:UIControlEventTouchUpInside];
    [self.zoomInButton addTarget:self action:@selector(zoomIn:) forControlEvents:UIControlEventTouchUpInside];
    for (UIButton *button in @[self.zoomOutButton, self.zoomInButton]) {
        button.tintColor = UIColor.whiteColor;
        [button.widthAnchor constraintEqualToConstant:44].active = YES;
        [button.heightAnchor constraintEqualToConstant:44].active = YES;
    }
    self.zoomLabel = [[UILabel alloc] init];
    self.zoomLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    self.zoomLabel.textColor = UIColor.whiteColor;
    self.zoomLabel.textAlignment = NSTextAlignmentCenter;
    self.zoomLabel.accessibilityLabel = @"ズーム倍率";
    [self.zoomLabel.widthAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.zoomOutButton, self.zoomLabel, self.zoomInButton]];
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.zoomControls.contentView addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [self.zoomControls.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:56],
        [self.zoomControls.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [row.topAnchor constraintEqualToAnchor:self.zoomControls.contentView.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:self.zoomControls.contentView.bottomAnchor],
        [row.leadingAnchor constraintEqualToAnchor:self.zoomControls.contentView.leadingAnchor constant:4],
        [row.trailingAnchor constraintEqualToAnchor:self.zoomControls.contentView.trailingAnchor constant:-4]
    ]];
    [self updateZoomControls];
}

- (void)selectZoomPreset:(UIButton *)sender {
    [self changeCameraZoom:sender.tag / 10.0];
}

- (void)updateZoomControls {
    BOOL available = !self.player && !self.finishingRecording && !self.pendingRecordingURL;
    CGFloat minimum = self.videoRecorder.minimumZoomFactor;
    CGFloat maximum = self.videoRecorder.maximumZoomFactor;
    self.zoomControls.hidden = !available;
    NSArray<NSNumber *> *presets = self.videoRecorder.zoomPresets;
    if (![self.displayedZoomPresets isEqual:presets]) {
        self.displayedZoomPresets = presets;
        [self.zoomPresetsRow removeFromSuperview];
        self.zoomPresetsRow = [[UIStackView alloc] init];
        self.zoomPresetsRow.spacing = 4;
        self.zoomPresetsRow.translatesAutoresizingMaskIntoConstraints = NO;
        for (NSNumber *value in presets) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tag = lround(value.doubleValue * 10);
            [button setTitle:[NSString stringWithFormat:@"%g", value.doubleValue] forState:UIControlStateNormal];
            button.accessibilityLabel = [NSString stringWithFormat:@"%g倍にズーム", value.doubleValue];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
            button.layer.cornerRadius = 20;
            [button.widthAnchor constraintEqualToConstant:40].active = YES;
            [button.heightAnchor constraintEqualToConstant:40].active = YES;
            [button addTarget:self action:@selector(selectZoomPreset:) forControlEvents:UIControlEventTouchUpInside];
            [self.zoomPresetsRow addArrangedSubview:button];
        }
        [self.view addSubview:self.zoomPresetsRow];
        [NSLayoutConstraint activateConstraints:@[
            [self.zoomPresetsRow.bottomAnchor constraintEqualToAnchor:self.zoomControls.topAnchor constant:-4],
            [self.zoomPresetsRow.trailingAnchor constraintEqualToAnchor:self.zoomControls.trailingAnchor]
        ]];
    }
    self.zoomPresetsRow.hidden = !available;
    for (UIButton *button in self.zoomPresetsRow.arrangedSubviews) {
        button.selected = fabs(self.requestedZoom - button.tag / 10.0) < 0.05;
        button.backgroundColor = button.selected ? [UIColor.systemBlueColor colorWithAlphaComponent:0.3] : [UIColor colorWithWhite:0 alpha:0.12];
        button.accessibilityValue = button.selected ? @"選択中" : nil;
    }
    self.zoomPinch.enabled = available && maximum > minimum;
    self.zoomOutButton.enabled = available && self.requestedZoom > minimum + 0.01;
    self.zoomInButton.enabled = available && self.requestedZoom < maximum - 0.01;
    self.zoomLabel.text = [NSString stringWithFormat:@"%.1f×", self.requestedZoom];
    self.zoomLabel.accessibilityValue = self.zoomLabel.text;
}

- (void)changeCameraZoom:(CGFloat)factor {
    if (!isfinite(factor) || self.player || self.finishingRecording || self.pendingRecordingURL) return;
    self.requestedZoom = MIN(self.videoRecorder.maximumZoomFactor, MAX(self.videoRecorder.minimumZoomFactor, factor));
    NSUInteger generation = ++self.zoomRequestGeneration;
    [self updateZoomControls];
    __weak typeof(self) weakSelf = self;
    [self.videoRecorder setZoomFactor:self.requestedZoom completion:^(CGFloat actual, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self || generation != self.zoomRequestGeneration) return;
        self.requestedZoom = actual;
        [self updateZoomControls];
        if (error && !self.presentedViewController) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ズームを変更できませんでした" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}
- (void)zoomIn:(id)sender { [self changeCameraZoom:self.requestedZoom + 0.5]; }
- (void)zoomOut:(id)sender { [self changeCameraZoom:self.requestedZoom - 0.5]; }
- (void)pinchCamera:(UIPinchGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) self.pinchStartZoom = self.requestedZoom;
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        [self changeCameraZoom:self.pinchStartZoom * gesture.scale];
    }
}

- (void)togglePlayback:(id)sender {
    if (self.player) {
        [self stopPlayback];
        return;
    }
    if (!self.latestRecordingURL || self.videoRecorder.isRecording || self.finishingRecording) return;
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:self.latestRecordingURL];
    self.player = [AVPlayer playerWithPlayerItem:item];
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.playerLayer.frame = self.playbackView.bounds;
    [self.playbackView.layer addSublayer:self.playerLayer];
    [self.previewView bringSubviewToFront:self.playbackView];
    self.playbackView.hidden = NO;
    self.drawingLayer.hidden = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];
    self.requestedSeekTime = kCMTimeInvalid;
    [self updatePlaybackProgress];
    __weak typeof(self) weakSelf = self;
    self.playbackTimeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 10) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        [weakSelf updatePlaybackProgress];
    }];
    self.player.rate = self.playbackSpeed;
    [self updateCameraControls];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == self.player.currentItem && [keyPath isEqualToString:@"status"]) {
        if (self.player.currentItem.status == AVPlayerItemStatusFailed) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (object == self.player.currentItem) [self playbackFailed:nil]; });
        }
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)playbackEnded:(NSNotification *)notification {
    if ([notification.name isEqualToString:AVPlayerItemDidPlayToEndTimeNotification] && (self.scrubbing || self.seeking)) return;
    [self stopPlayback];
}

- (void)playbackFailed:(NSNotification *)notification {
    [self stopPlayback];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"再生できませんでした" message:@"動画を読み込めませんでした。もう一度お試しください。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    if (!self.presentedViewController) [self presentViewController:alert animated:YES completion:nil];
}

- (void)stopPlayback {
    if (self.playbackTimeObserver) {
        [self.player removeTimeObserver:self.playbackTimeObserver];
        self.playbackTimeObserver = nil;
    }
    self.scrubbing = NO;
    self.seeking = NO;
    self.requestedSeekTime = kCMTimeInvalid;
    if (self.player) {
        [self.player.currentItem removeObserver:self forKeyPath:@"status"];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.player.currentItem];
    }
    [self.player pause];
    [self.playerLayer removeFromSuperlayer];
    self.playerLayer = nil;
    self.player = nil;
    self.playbackView.hidden = YES;
    self.drawingLayer.hidden = NO;
    [self updateCameraControls];
}

- (UILabel *)playbackLabel {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    label.textColor = UIColor.whiteColor;
    [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return label;
}

- (void)setupPlaybackControls {
    self.playbackControls = [[UIVisualEffectView alloc] initWithEffect:nil];
    self.playbackControls.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
    self.playbackControls.layer.cornerRadius = 16;
    self.playbackControls.clipsToBounds = YES;
    self.playbackControls.translatesAutoresizingMaskIntoConstraints = NO;
    self.playbackControls.hidden = YES;
    // タブバーと同じ親の最前面に配置し、画面下端まで重ねる。
    UIView *host = self.tabBarController ? self.tabBarController.view : self.view;
    [host addSubview:self.playbackControls];
    self.positionSlider = [[PlaybackSlider alloc] init];
    self.positionSlider.minimumValue = 0;
    self.positionSlider.maximumValue = 1;
    self.positionSlider.accessibilityLabel = @"再生位置";
    [self.positionSlider addTarget:self action:@selector(beginScrubbing) forControlEvents:UIControlEventEditingDidBegin];
    [self.positionSlider addTarget:self action:@selector(positionChanged:) forControlEvents:UIControlEventValueChanged];
    [self.positionSlider addTarget:self action:@selector(endScrubbing) forControlEvents:UIControlEventEditingDidEnd];
    self.elapsedLabel = [self playbackLabel];
    self.durationLabel = [self playbackLabel];
    UIStackView *position = [[UIStackView alloc] initWithArrangedSubviews:@[self.elapsedLabel, self.positionSlider, self.durationLabel]];
    self.speedSlider = [[PlaybackSlider alloc] init];
    self.speedSlider.minimumValue = 0.25;
    self.speedSlider.maximumValue = 2.0;
    self.speedSlider.value = self.playbackSpeed;
    self.speedSlider.accessibilityLabel = @"再生速度";
    [self.speedSlider addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    UILabel *slow = [self playbackLabel]; slow.text = @"0.25×";
    self.speedLabel = [self playbackLabel];
    self.speedLabel.text = @"1.00×";
    UILabel *fast = [self playbackLabel]; fast.text = @"2×";
    UIStackView *speed = [[UIStackView alloc] initWithArrangedSubviews:@[self.speedLabel, slow, self.speedSlider, fast]];
    for (UIStackView *row in @[position, speed]) {
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentCenter;
        row.spacing = 8;
    }
    [self.positionSlider.heightAnchor constraintEqualToConstant:44].active = YES;
    [self.speedSlider.heightAnchor constraintEqualToConstant:44].active = YES;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[position, speed]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.playbackControls.contentView addSubview:stack];
    NSLayoutConstraint *width = [self.playbackControls.widthAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.widthAnchor constant:-24];
    width.priority = 999;
    [NSLayoutConstraint activateConstraints:@[
        width, [self.playbackControls.widthAnchor constraintLessThanOrEqualToConstant:560],
        [self.playbackControls.centerXAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.centerXAnchor],
        [self.playbackControls.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.playbackControls.contentView.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:self.playbackControls.contentView.trailingAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:self.playbackControls.contentView.topAnchor constant:4],
        [stack.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:-4]
    ]];
}

- (NSString *)playbackTimeText:(double)seconds {
    if (!isfinite(seconds) || seconds < 0) return @"--:--";
    NSInteger total = (NSInteger)seconds;
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

- (void)updatePlaybackProgress {
    double duration = CMTimeGetSeconds(self.player.currentItem.duration);
    BOOL ready = self.player.currentItem.status == AVPlayerItemStatusReadyToPlay && isfinite(duration) && duration > 0;
    self.positionSlider.enabled = ready;
    self.speedSlider.enabled = ready;
    self.durationLabel.text = [self playbackTimeText:duration];
    if (!self.scrubbing && !self.seeking) {
        double elapsed = CMTimeGetSeconds(self.player.currentTime);
        self.positionSlider.value = ready && isfinite(elapsed) ? elapsed / duration : 0;
        self.elapsedLabel.text = [self playbackTimeText:elapsed];
    }
}

- (void)beginScrubbing {
    if (!self.player) return;
    self.scrubbing = YES;
    [self.player pause];
}

- (void)positionChanged:(UISlider *)slider {
    double duration = CMTimeGetSeconds(self.player.currentItem.duration);
    if (!isfinite(duration) || duration <= 0) return;
    self.requestedSeekTime = CMTimeMakeWithSeconds(duration * slider.value, 600);
    self.elapsedLabel.text = [self playbackTimeText:duration * slider.value];
    [self seekToRequestedPosition];
}

// ドラッグ中のシークは1件ずつ処理し、古い要求をためず最新位置へ追従する。
- (void)seekToRequestedPosition {
    if (!self.player || self.seeking || !CMTIME_IS_VALID(self.requestedSeekTime)) return;
    self.seeking = YES;
    AVPlayer *player = self.player;
    CMTime target = self.requestedSeekTime;
    __weak typeof(self) weakSelf = self;
    [player seekToTime:target toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self || self.player != player) return;
            self.seeking = NO;
            if (CMTimeCompare(target, self.requestedSeekTime) != 0) {
                [self seekToRequestedPosition];
            } else if (!self.scrubbing) {
                double duration = CMTimeGetSeconds(player.currentItem.duration);
                if (finished && CMTimeGetSeconds(target) >= duration) {
                    [self stopPlayback];
                } else {
                    player.rate = self.playbackSpeed;
                    [self updatePlaybackProgress];
                }
            }
        });
    }];
}

- (void)endScrubbing {
    self.scrubbing = NO;
    if (!self.seeking && self.player) [self seekToRequestedPosition];
}

- (void)speedChanged:(UISlider *)slider {
    self.playbackSpeed = roundf(slider.value * 100) / 100;
    self.speedLabel.text = [NSString stringWithFormat:@"%.2f×", self.playbackSpeed];
    self.speedSlider.accessibilityValue = self.speedLabel.text;
    if (!self.scrubbing && !self.seeking) self.player.rate = self.playbackSpeed;
}

- (void)updateCameraControlsPosition {
    CGFloat inset = 8;
    if (self.player && self.playbackControls.superview) {
        UIView *host = self.playbackControls.superview;
        CGRect safeFrame = [host convertRect:host.safeAreaLayoutGuide.layoutFrame toView:self.view];
        // 再生バー（96pt）と停止ボタンが重ならない位置へ移動する。
        CGFloat playbackTop = CGRectGetMaxY(safeFrame) - 96;
        inset = MAX(8, CGRectGetMaxY(self.view.safeAreaLayoutGuide.layoutFrame) - playbackTop + 8);
    }
    self.cameraControlsBottomConstraint.constant = -inset;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.videoRecorder.previewLayer.frame = self.previewView.bounds;
    self.drawingLayer.frame = self.previewView.bounds;
    self.playerLayer.frame = self.playbackView.bounds;
    [self updateGuideGeometry];
    [self updateCameraControlsPosition];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.recordingController.busy && !self.pendingRecordingURL) {
        NSString *path = [[NSUserDefaults standardUserDefaults] stringForKey:@"LatestCameraRecordingPath"];
        if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) self.latestRecordingURL = [NSURL fileURLWithPath:path];
        [self updateCameraControls];
    }
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopPlayback];
}

- (void)dealloc {
    [_playbackControls removeFromSuperview];
    if (_playbackTimeObserver) [_player removeTimeObserver:_playbackTimeObserver];
    if (_player) [_player.currentItem removeObserver:self forKeyPath:@"status"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
