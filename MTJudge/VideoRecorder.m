#import "VideoRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreImage/CoreImage.h>
#import "SkeletonConnections.h"

// プライベートプロパティをここで宣言
@interface VideoRecorder () <AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (atomic, strong) AVCaptureDevice *cameraDevice;
@property (nonatomic, strong) dispatch_queue_t zoomQueue;
@property (nonatomic, strong) AVCaptureMovieFileOutput *movieFileOutput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *skeletonChanges;
@property (nonatomic, strong) AVAssetExportSession *skeletonExport;
@property (nonatomic, assign) BOOL isRecording; // isRecordingを読み書き可能に

@end

@implementation VideoRecorder
@synthesize skeletonDrawingEnabled = _skeletonDrawingEnabled;

// 初期化メソッド
- (instancetype)init {
    self = [super init];
    if (self) {
        // iOSアプリでカメラやマイクなどのメディアデバイスからデータを取得・録画するための準備 

        // AVCaptureSession: ビデオやオーディオのキャプチャ（取得）タスクを管理する中核的なオブジェクト
        // カメラからの映像入力、マイクからの音声入力、そしてそれらの出力を結びつける役割を担う
        _captureSession = [[AVCaptureSession alloc] init];
        _zoomQueue = dispatch_queue_create("com.MTJudge.cameraZoom", DISPATCH_QUEUE_SERIAL);
        // AVCaptureMovieFileOutput: ビデオとオーディオのデータをファイルに録画するための出力オブジェクト
        _movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
        _isRecording = NO;
    }
    return self;
}

#pragma mark - Camera Setup

// カメラとマイクのセットアップ
- (void)setupCamera {

    // キャプチャセッションの設定を開始
    [_captureSession beginConfiguration];
    
    // 既存の入力と出力を削除
    for (AVCaptureInput *input in _captureSession.inputs) {
        [_captureSession removeInput:input];
    }
    for (AVCaptureOutput *output in _captureSession.outputs) {
        [_captureSession removeOutput:output];
    }
    
    // カメラとマイクのデバイスを取得し、セッションに追加

    // defaultDeviceWithMediaType: は、指定されたメディアタイプ（ここではAVMediaTypeVideo、つまりビデオ）に対応するデフォルトのキャプチャデバイスを取得
    AVCaptureDevice *videoDevice = nil;
    if (@available(iOS 13.0, *)) {
        for (AVCaptureDeviceType type in @[AVCaptureDeviceTypeBuiltInTripleCamera, AVCaptureDeviceTypeBuiltInDualWideCamera, AVCaptureDeviceTypeBuiltInDualCamera]) {
            videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:type mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
            if (videoDevice) break;
        }
    }
    if (!videoDevice) videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    // 取得したvideoDevice（背面カメラ）を使って、新しいビデオ入力オブジェクトを作成している
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
    // セッションにビデオ入力を追加
    if ([_captureSession canAddInput:videoInput]) {//追加できるかどうかをチェック
        [_captureSession addInput:videoInput];//ビデオ入力をキャプチャセッションに追加
    }
    
    // defaultDeviceWithMediaType: は、指定されたメディアタイプ（ここではAVMediaTypeAudio、つまり音声）に対応するデフォルトのキャプチャデバイスを取得
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    // 取得したaudioDevice（内蔵マイク）を使って、新しいオーディオ入力オブジェクトを作成している
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
    // セッションにオーディオ入力を追加
    if ([_captureSession canAddInput:audioInput]) {//追加できるかどうかをチェック
        [_captureSession addInput:audioInput];//オーディオ入力をキャプチャセッションに追加
    }

    // 録画用の出力をセッションに追加
    if ([_captureSession canAddOutput:_movieFileOutput]) {//追加できるかどうかをチェック
        [_captureSession addOutput:_movieFileOutput];//録画用の出力をキャプチャセッションに追加
    }

    // 映像フレームをリアルタイムで出力する設定
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    // カメラからの映像データを特定のフォーマットに設定するための辞書を作成している。
    // 具体的には、ピクセルフォーマットを32BGRAという形式に設定している
    NSDictionary *rgbOutputSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
    // 映像データの出力形式を、事前に定義されたrgbOutputSettings（32BGRAピクセルフォーマット）に設定している。
    // これにより、カメラから送られてくる映像フレームが、この特定のフォーマットに変換されてから、
    // 次の処理（例：Visionフレームワークでの解析）に渡されるようになる
    self.videoDataOutput.videoSettings = rgbOutputSettings;
    // フレームの処理が間に合わなかった場合に、そのフレームを破棄するかどうかを制御するプロパティ
    // NOに設定することで、フレームが遅延しても破棄せず、すべてのフレームを処理するようにしている
    self.videoDataOutput.alwaysDiscardsLateVideoFrames = NO;
    
    // 映像フレームを処理するための専用のキューを作成
    // カメラから取得した映像フレームを、バックグラウンドの専用キューで処理するための設定を行っている
    /* dispatch_queue_createは、Grand Central Dispatch (GCD) を使って新しいディスパッチキューを作成 */
    dispatch_queue_t videoQueue = dispatch_queue_create("com.MTJudge.videoQueue", DISPATCH_QUEUE_SERIAL);
    /* videoQueueという名前のこのキューは、シリアル（DISPATCH_QUEUE_SERIAL）に設定されています。
       シリアルキューは、タスクを一度に1つずつ、順番に実行することを保証します。
       これは、映像フレームの処理順序を保つために重要です
    */

    /* AVCaptureVideoDataOutputオブジェクト（self.videoDataOutput）にデリゲートを設定
       することで、カメラから新しい映像フレームが取得されるたびに、
       指定されたキュー（videoQueue）でデリゲートメソッドが呼び出されるようになる
    */
    [self.videoDataOutput setSampleBufferDelegate:self queue:videoQueue];

    // セッションに映像データの出力を追加
    if ([_captureSession canAddOutput:self.videoDataOutput]) {//追加できるかどうかをチェック
        [_captureSession addOutput:self.videoDataOutput];//映像データの出力をキャプチャセッションに追加
    }

    // プレビューレイヤーのセットアップ
    // AVCaptureVideoPreviewLayer: カメラからの映像をリアルタイムで表示するためのレイヤー
    _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_captureSession];

    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    /* videoGravityは、レイヤーの境界内にコンテンツ（映像）がどのように表示されるかを決定するプロパティ
       AVLayerVideoGravityResizeAspectFillに設定することで、映像がレイヤーの境界を完全に覆うように拡大・縮小される
       ただし、映像のアスペクト比（縦横比）は維持されるため、レイヤーの一部が映像で覆われない場合がある
    */

    // videoOrientationは、映像の表示方向を設定するプロパティ
    // AVCaptureVideoOrientationPortraitに設定することで、映像が縦向き（ポートレートモード）で表示されるようになる
    _previewLayer.connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    
    // カメラのキャプチャセッションを有効化し、データストリームを開始
    /* beginConfigurationとcommitConfigurationのペアは、セッションの構成を一時的にロックして、
       複数の設定変更を一括で行うために使用されます。これにより、設定変更中のパフォーマンス低下を防ぎ、
       変更がすべて同時に適用されることが保証されます。このコードは、設定が完了したことをセッションに通知しています。
    */
    [_captureSession commitConfiguration];// 冒頭の beginConfiguration に対応
    // 設定が確定されたキャプチャセッションを開始
    [self.captureSession startRunning];
    self.cameraDevice = videoInput ? videoDevice : nil;
    if ([videoDevice lockForConfiguration:nil]) {
        videoDevice.videoZoomFactor = MIN(videoDevice.maxAvailableVideoZoomFactor, MAX(videoDevice.minAvailableVideoZoomFactor, 1.0 / [self zoomDisplayMultiplier]));
        [videoDevice unlockForConfiguration];
    }

    NSLog(@"Camera setup complete. Session running: %d", self.captureSession.isRunning);
}

#pragma mark - Camera Zoom

- (CGFloat)zoomDisplayMultiplier {
    if (@available(iOS 18.0, *)) return self.cameraDevice ? self.cameraDevice.displayVideoZoomFactorMultiplier : 1;
    if (@available(iOS 13.0, *)) {
        if ([self.cameraDevice.deviceType isEqual:AVCaptureDeviceTypeBuiltInTripleCamera] || [self.cameraDevice.deviceType isEqual:AVCaptureDeviceTypeBuiltInDualWideCamera])
            return 1.0 / self.cameraDevice.virtualDeviceSwitchOverVideoZoomFactors.firstObject.doubleValue;
    }
    return 1;
}

- (NSArray<NSNumber *> *)zoomPresets {
    AVCaptureDevice *device = self.cameraDevice;
    if (!device) return @[];
    CGFloat multiplier = [self zoomDisplayMultiplier];
    NSMutableArray<NSNumber *> *raw = [NSMutableArray arrayWithObject:@(1.0 / multiplier)];
    if (@available(iOS 13.0, *)) [raw addObjectsFromArray:device.virtualDeviceSwitchOverVideoZoomFactors];
    if (@available(iOS 16.0, *)) [raw addObjectsFromArray:device.activeFormat.secondaryNativeResolutionZoomFactors];
    NSMutableSet<NSNumber *> *values = [NSMutableSet set];
    for (NSNumber *factor in raw) {
        CGFloat value = round(factor.doubleValue * multiplier * 10) / 10;
        if (value >= 1 && value <= self.maximumZoomFactor && value >= self.minimumZoomFactor) [values addObject:@(value)];
    }
    return [[values allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

- (CGFloat)minimumZoomFactor {
    return self.cameraDevice ? self.cameraDevice.minAvailableVideoZoomFactor * [self zoomDisplayMultiplier] : 1;
}
- (CGFloat)maximumZoomFactor {
    AVCaptureDevice *device = self.cameraDevice;
    return device ? MIN(device.maxAvailableVideoZoomFactor, device.activeFormat.videoMaxZoomFactor) * [self zoomDisplayMultiplier] : 1;
}
- (CGFloat)zoomFactor {
    return self.cameraDevice ? self.cameraDevice.videoZoomFactor * [self zoomDisplayMultiplier] : 1;
}
- (void)setZoomFactor:(CGFloat)factor completion:(void (^)(CGFloat, NSError *))completion {
    dispatch_async(self.zoomQueue, ^{
        AVCaptureDevice *device = self.cameraDevice;
        NSError *error = nil;
        if (device && isfinite(factor) && [device lockForConfiguration:&error]) {
            CGFloat minimum = device.minAvailableVideoZoomFactor;
            CGFloat maximum = MIN(device.maxAvailableVideoZoomFactor, device.activeFormat.videoMaxZoomFactor);
            [device cancelVideoZoomRamp];
            device.videoZoomFactor = MIN(maximum, MAX(minimum, factor / [self zoomDisplayMultiplier]));
            [device unlockForConfiguration];
        }
        CGFloat actual = device ? device.videoZoomFactor * [self zoomDisplayMultiplier] : 1;
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(actual, error); });
    });
}

#pragma mark - Recording Control

// 録画の開始
- (void)startRecording {
    NSLog(@"startRecording @VideoRecorder");
    @synchronized (self) {
        _isRecording = YES;
        self.skeletonChanges = [NSMutableArray arrayWithObject:@{@"time": @0, @"enabled": @(_skeletonDrawingEnabled)}];
    }
    
    // 録画の設定
    AVCaptureConnection *movieConnection = [_movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
    // AVCaptureConnectionオブジェクト（movieConnection）を使って、録画の映像の向きを縦向き（ポートレートモード）に設定
    if (movieConnection) {
        movieConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    
    // 録画ファイルの保存先URLを一時ディレクトリに設定
    // NSTemporaryDirectory()は、一時ファイルを保存するためのディレクトリのパスを取得する関数
    // ここでは、一意のファイル 名を生成するために、UUID（Universally Unique Identifier）を使用しています
    // 生成されたファイル名に.mov拡張子を付けて、一時ディレクトリのパスと結合しています
    NSString *outputPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mov", [[NSUUID UUID] UUIDString]]];
    // 動画を保存する場所（ファイルパス）を表す**NSURL**オブジェクトを作成している
    NSURL *outputURL = [NSURL fileURLWithPath:outputPath];
    
    // 既に同じパスにファイルが存在する場合は削除
    if ([[NSFileManager defaultManager] fileExistsAtPath:outputURL.path]) {
        NSError *error = nil;
        // [NSFileManager defaultManager]: これは、iOS/macOSのファイルシステムを
        // 管理するための**NSFileManager**クラスの共有インスタンスを取得しています。
        // このクラスは、ファイルの作成、移動、コピー、削除などの操作を行うための主要なツール   。
        // removeItemAtURL:error: メソッドは、指定されたURLにあるファイルまたはディレクトリを削除する
        if (![[NSFileManager defaultManager] removeItemAtURL:outputURL error:&error]) {
            NSLog(@"Failed to remove existing file: %@", error.localizedDescription);
        }
    }

    // 録画の開始
    [_movieFileOutput startRecordingToOutputFileURL:outputURL recordingDelegate:self];
}

// 録画の停止
- (void)stopRecording {
    NSLog(@"stopRecording @VideoRecorder");
    _isRecording = NO;

    // 録画の停止
    if ([_movieFileOutput isRecording]) {
        [_movieFileOutput stopRecording];
    }
}

#pragma mark - AVCaptureFileOutputRecordingDelegate

// 録画が完了したときに呼ばれるデリゲートメソッド
- (void)captureOutput:(AVCaptureFileOutput *)output didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error {
    _isRecording = NO;
    BOOL successful = !error || [error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] boolValue];
    if (!successful) {
        [self notifyRecordingFinished:outputFileURL error:error];
        return;
    }
    NSArray<NSDictionary *> *changes;
    @synchronized (self) { changes = [self.skeletonChanges copy]; }
    BOOL needsSkeleton = NO;
    for (NSDictionary *change in changes) needsSkeleton |= [change[@"enabled"] boolValue];
    if (!needsSkeleton) {
        [self notifyRecordingFinished:outputFileURL error:nil];
        return;
    }
    [self exportSkeletonInVideo:outputFileURL changes:changes];
}

- (BOOL)skeletonDrawingEnabled {
    @synchronized (self) { return _skeletonDrawingEnabled; }
}

- (void)setSkeletonDrawingEnabled:(BOOL)enabled {
    @synchronized (self) {
        _skeletonDrawingEnabled = enabled;
        if (_isRecording) {
            double seconds = CMTimeGetSeconds(self.movieFileOutput.recordedDuration);
            if (!isfinite(seconds) || seconds < 0) seconds = 0;
            [self.skeletonChanges addObject:@{@"time": @(seconds), @"enabled": @(enabled)}];
        }
    }
}

- (void)notifyRecordingFinished:(NSURL *)url error:(NSError *)error {
    [self.delegate videoRecorder:self didFinishRecordingToOutputFileURL:url error:error];
}

// 元の音声を保持し、表示が有効だった区間の映像に骨格線を焼き込む。
- (void)exportSkeletonInVideo:(NSURL *)sourceURL changes:(NSArray<NSDictionary *> *)changes {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    AVVideoComposition *composition = [AVVideoComposition videoCompositionWithAsset:asset applyingCIFiltersWithHandler:^(AVAsynchronousCIImageFilteringRequest *request) {
        @autoreleasepool {
            double time = CMTimeGetSeconds(request.compositionTime);
            BOOL enabled = NO;
            for (NSDictionary *change in changes) {
                if ([change[@"time"] doubleValue] > time) break;
                enabled = [change[@"enabled"] boolValue];
            }
            CIImage *source = request.sourceImage;
            if (!enabled) {
                [request finishWithImage:source context:nil];
                return;
            }
            CGRect extent = source.extent;
            CIImage *image = [source imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x, -extent.origin.y)];
            VNDetectHumanBodyPoseRequest *pose = [[VNDetectHumanBodyPoseRequest alloc] init];
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCIImage:image options:@{}];
            NSError *error = nil;
            if (![handler performRequests:@[pose] error:&error]) {
                [request finishWithError:error];
                return;
            }
            size_t width = (size_t)CGRectGetWidth(extent);
            size_t height = (size_t)CGRectGetHeight(extent);
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space, kCGImageAlphaPremultipliedLast);
            CGColorSpaceRelease(space);
            if (!context) {
                [request finishWithError:[NSError errorWithDomain:@"MTJudge.Skeleton" code:1 userInfo:@{NSLocalizedDescriptionKey: @"骨格線の描画に必要なメモリを確保できませんでした。"}]];
                return;
            }
            CGContextSetRGBStrokeColor(context, 0, 1, 0, 1);
            CGContextSetLineWidth(context, MAX(3, width / 180.0));
            CGContextSetLineCap(context, kCGLineCapRound);
            for (VNHumanBodyPoseObservation *observation in pose.results) {
                for (NSArray<NSString *> *connection in SkeletonConnections()) {
                    VNRecognizedPoint *start = [observation recognizedPointForJointName:connection.firstObject error:NULL];
                    VNRecognizedPoint *end = [observation recognizedPointForJointName:connection.lastObject error:NULL];
                    if (start.confidence > 0.1 && end.confidence > 0.1) {
                        CGContextMoveToPoint(context, start.location.x * width, start.location.y * height);
                        CGContextAddLineToPoint(context, end.location.x * width, end.location.y * height);
                    }
                }
            }
            CGContextStrokePath(context);
            CGImageRef overlayImage = CGBitmapContextCreateImage(context);
            CGContextRelease(context);
            CIImage *overlay = [[CIImage imageWithCGImage:overlayImage] imageByApplyingTransform:CGAffineTransformMakeTranslation(extent.origin.x, extent.origin.y)];
            CGImageRelease(overlayImage);
            [request finishWithImage:[[overlay imageByCompositingOverImage:source] imageByCroppingToRect:extent] context:nil];
        }
    }];
    NSURL *destination = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"mov"]]];
    self.skeletonExport = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetHighestQuality];
    if (!self.skeletonExport) {
        [self notifyRecordingFinished:sourceURL error:[NSError errorWithDomain:@"MTJudge.Skeleton" code:2 userInfo:@{NSLocalizedDescriptionKey: @"骨格付き動画の作成を開始できませんでした。"}]];
        return;
    }
    self.skeletonExport.outputURL = destination;
    self.skeletonExport.outputFileType = AVFileTypeQuickTimeMovie;
    self.skeletonExport.videoComposition = composition;
    AVAssetExportSession *export = self.skeletonExport;
    [export exportAsynchronouslyWithCompletionHandler:^{
        if (export.status == AVAssetExportSessionStatusCompleted) {
            [[NSFileManager defaultManager] removeItemAtURL:sourceURL error:NULL];
            [self notifyRecordingFinished:destination error:nil];
        } else {
            NSError *error = export.error ?: [NSError errorWithDomain:@"MTJudge.Skeleton" code:3 userInfo:@{NSLocalizedDescriptionKey: @"骨格付き動画を作成できませんでした。"}];
            [self notifyRecordingFinished:sourceURL error:error];
        }
        self.skeletonExport = nil;
    }];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

// 映像フレームが取得されるたびに呼ばれるデリゲートメソッド
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // 映像フレームをViewControllerに渡す
    //NSLog(@"Received a sample buffer in VideoRecorder.");
    if ([self.delegate respondsToSelector:@selector(videoRecorder:didOutputSampleBuffer:)]) {
        [self.delegate videoRecorder:self didOutputSampleBuffer:sampleBuffer];
    }
}
@end
