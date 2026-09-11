#import "VideoRecordingViewController.h"
#import "TagSelectionViewController.h"
#import "TagListViewController.h" // 追加
#import <AudioToolbox/AudioToolbox.h>
#import <Vision/Vision.h>
#import <QuartzCore/QuartzCore.h>

@implementation VideoRecordingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.videoRecorder = [[VideoRecorder alloc] init];
    self.videoRecorder.delegate = self;

    NSLog(@"videoRecorder is %@", self.videoRecorder ? @"not nil" : @"nil");
    NSLog(@"previewView is %@", self.previewView ? @"not nil" : @"nil");

    // 初期状態で描画を有効にする
    self.isSkeletonDrawingEnabled = NO;

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
        });
    });
}

#pragma mark - VideoRecorderDelegate

// 録画が正常に終了した場合、TagSelectionViewControllerを表示
- (void)videoRecorder:(id)recorder didFinishRecordingToOutputFileURL:(NSURL *)outputFileURL error:(NSError *)error {
    NSLog(@"didFinishRecordingToOutputFileAtURL @VideoRecordingViewController Video recording error: %@", error.localizedDescription);
    
    if(error){
        [self.recordButton setTitle:@"Error" forState:UIControlStateNormal];
        return;
    }
    // Main.storyboardからTagSelectionViewControllerを取得
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    TagSelectionViewController *tagVC = [storyboard instantiateViewControllerWithIdentifier:@"TagSelectionViewController"];
    // 録画したビデオのURLをTagSelectionViewControllerに渡す
    tagVC.videoFileURL = outputFileURL;

    // ナビゲーションコントローラーを介してTagSelectionViewControllerを表示
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:tagVC];
    [self presentViewController:navController animated:YES completion:nil];
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
    NSArray<NSArray<NSString *>*> *bodyConnections = @[
        // 胴体
        @[VNHumanBodyPoseObservationJointNameNeck, VNHumanBodyPoseObservationJointNameRightShoulder],
        @[VNHumanBodyPoseObservationJointNameNeck, VNHumanBodyPoseObservationJointNameLeftShoulder],
        @[VNHumanBodyPoseObservationJointNameRightShoulder, VNHumanBodyPoseObservationJointNameRightHip],
        @[VNHumanBodyPoseObservationJointNameLeftShoulder, VNHumanBodyPoseObservationJointNameLeftHip],
        @[VNHumanBodyPoseObservationJointNameRightHip, VNHumanBodyPoseObservationJointNameLeftHip],
        
        // 右腕
        @[VNHumanBodyPoseObservationJointNameRightShoulder, VNHumanBodyPoseObservationJointNameRightElbow],
        @[VNHumanBodyPoseObservationJointNameRightElbow, VNHumanBodyPoseObservationJointNameRightWrist],
        
        // 左腕
        @[VNHumanBodyPoseObservationJointNameLeftShoulder, VNHumanBodyPoseObservationJointNameLeftElbow],
        @[VNHumanBodyPoseObservationJointNameLeftElbow, VNHumanBodyPoseObservationJointNameLeftWrist],
        
        // 右足
        @[VNHumanBodyPoseObservationJointNameRightHip, VNHumanBodyPoseObservationJointNameRightKnee],
        @[VNHumanBodyPoseObservationJointNameRightKnee, VNHumanBodyPoseObservationJointNameRightAnkle],
        
        // 左足
        @[VNHumanBodyPoseObservationJointNameLeftHip, VNHumanBodyPoseObservationJointNameLeftKnee],
        @[VNHumanBodyPoseObservationJointNameLeftKnee, VNHumanBodyPoseObservationJointNameLeftAnkle]
    ];
    
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
    
    // 描画が無効になったら、画面上の線をすべて消去する
    if (!self.isSkeletonDrawingEnabled) {
        [self clearDrawing];
    }
    
    // ボタンのタイトルを更新する
    UIButton *button = (UIButton *)sender;
    if (self.isSkeletonDrawingEnabled) {
        [button setTitle:@"FrameOff" forState:UIControlStateNormal]; // ここを「FrmON」に変更
    } else {
        [button setTitle:@"Frame" forState:UIControlStateNormal]; // ここを「FrmOFF」に変更
    }
}

// タグ管理画面に遷移するメソッドを追加
- (IBAction)manageTagsButtonTapped:(id)sender {
    TagListViewController *tagListVC = [[TagListViewController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:tagListVC];
    [self presentViewController:navController animated:YES completion:nil];
}

- (IBAction)recordButtonTapped:(id)sender {
    NSLog(@"recordButtonTapped is called %@", [self.videoRecorder isRecording]?@"rec":@"stop");
    if ([self.videoRecorder isRecording]) {
        [self.videoRecorder stopRecording];
        AudioServicesPlaySystemSound(1306);
        [self.recordButton setTitle:@"Rec" forState:UIControlStateNormal];
    } else {
        [self.videoRecorder startRecording];
        AudioServicesPlaySystemSound(1305);
        [self.recordButton setTitle:@"Stop" forState:UIControlStateNormal];
    }
}

@end
