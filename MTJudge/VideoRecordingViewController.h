#import <UIKit/UIKit.h>
#import "VideoRecorder.h"
#import <Vision/Vision.h> // 追加
#import <AVFoundation/AVFoundation.h> // 追加
#import <QuartzCore/QuartzCore.h> // 追加

@interface VideoRecordingViewController : UIViewController <VideoRecorderDelegate>

@property (nonatomic, strong) IBOutlet UIView *previewView;
@property (nonatomic, strong) IBOutlet UIButton *recordButton;
@property (nonatomic, strong) VideoRecorder *videoRecorder;
// 描画用のレイヤーを追加
@property (nonatomic, strong) CALayer *drawingLayer;
// 骨格描画の状態を管理するプロパティを追加
@property (assign, nonatomic) BOOL isSkeletonDrawingEnabled;

- (IBAction)recordButtonTapped:(id)sender;
// ストーリーボードでボタンと紐付けるメソッドを追加
- (IBAction)toggleSkeletonDrawing:(id)sender;

@end
