#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

@protocol VideoRecorderDelegate <NSObject>

// 撮影が完了したときに呼ばれるデリゲートメソッド
- (void)videoRecorder:(id)recorder didFinishRecordingToOutputFileURL:(NSURL *)outputFileURL error:(NSError *)error;

// 映像フレームをリアルタイムで受け取るためのデリゲートメソッド
- (void)videoRecorder:(id)recorder didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end

@interface VideoRecorder : NSObject

// デリゲートプロパティ
@property (nonatomic, weak) id<VideoRecorderDelegate> delegate;

// プレビューレイヤープロパティ (読み取り専用)
@property (nonatomic, strong, readonly) AVCaptureVideoPreviewLayer *previewLayer;

// 撮影中かどうかを返すプロパティ
@property (nonatomic, assign, readonly) BOOL isRecording;

// 表示の切り替えを録画時刻とともに記録する。
@property (atomic, assign) BOOL skeletonDrawingEnabled;

// カメラの実際のズーム倍率を変更する（プレビュー・録画の両方に反映）。
@property (nonatomic, readonly) CGFloat minimumZoomFactor;
@property (nonatomic, readonly) CGFloat maximumZoomFactor;
@property (nonatomic, readonly) CGFloat zoomFactor;
- (void)setZoomFactor:(CGFloat)factor completion:(void (^)(CGFloat actualFactor, NSError *error))completion;

// 撮影を開始するメソッド
- (void)startRecording;

// 撮影を停止するメソッド
- (void)stopRecording;

// カメラをセットアップするメソッド
- (void)setupCamera;

@end
