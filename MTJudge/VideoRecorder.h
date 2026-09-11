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

// 撮影を開始するメソッド
- (void)startRecording;

// 撮影を停止するメソッド
- (void)stopRecording;

// カメラをセットアップするメソッド
- (void)setupCamera;

@end
