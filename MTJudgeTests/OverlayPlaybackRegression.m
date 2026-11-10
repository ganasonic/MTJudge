// Targeted regression for the overlay freeze. Synthetic frames only; no recording,
// no XCUITest, no existing regression suites, and no user's video files.
#import <XCTest/XCTest.h>
#import <AVFoundation/AVFoundation.h>
#import "../MTJudge/Overlay/OverlayMetalView.h"
#import "../MTJudge/Overlay/VideoOverlayViewController.h"

@interface OverlayDrawSpy : OverlayMetalView
@property NSUInteger drawCount;
@end
@implementation OverlayDrawSpy
- (void)drawInMTKView:(MTKView *)view { self.drawCount++; [super drawInMTKView:view]; }
@end

@interface VideoOverlayViewController (PlaybackRegression)
- (void)shutdown;
@end

@interface OverlayPlaybackRegression : XCTestCase
@end
@implementation OverlayPlaybackRegression
- (UIWindow *)windowForController:(UIViewController *)controller {
    UIWindowScene *scene=nil;
    for(UIScene *candidate in UIApplication.sharedApplication.connectedScenes) if([candidate isKindOfClass:UIWindowScene.class]&&candidate.activationState==UISceneActivationStateForegroundActive) { scene=(UIWindowScene *)candidate; break; }
    UIWindow *window=scene?[[UIWindow alloc] initWithWindowScene:scene]:[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.frame=UIScreen.mainScreen.bounds; window.rootViewController=controller; [window makeKeyAndVisible]; [controller.view layoutIfNeeded]; return window;
}
- (void)testConsecutiveFramesUseMTKViewDrawCycleAndLeaveRunLoopResponsive {
    XCTestExpectation *done=[self expectationWithDescription:@"12 drawable presentations and UI callbacks"];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *controller=[UIViewController new];
        OverlayDrawSpy *view=[[OverlayDrawSpy alloc] initWithFrame:CGRectMake(0,0,320,240)]; [controller.view addSubview:view];
        UIWindow *window=[self windowForController:controller];
        __block NSUInteger attempts=0,submitted=0,callbacks=0;
        NSTimer *timer=[NSTimer scheduledTimerWithTimeInterval:1.0/30 repeats:YES block:^(NSTimer *timer) {
            CGFloat value=(attempts%2)?1:0;
            CIImage *image=[[CIImage imageWithColor:[CIColor colorWithRed:value green:0 blue:1-value alpha:1]] imageByCroppingToRect:CGRectMake(0,0,320,240)];
            if([view displayMain:image sub:nil matrix:matrix_identity_double3x3 mask:nil opacity:.5 mainAnnotation:nil subAnnotation:nil]) submitted++;
            attempts++; callbacks++;
            if(attempts==12) {
                [timer invalidate];
                XCTAssertGreaterThanOrEqual(view.drawCount,12u);
                XCTAssertGreaterThanOrEqual(submitted,8u);
                XCTAssertEqual(callbacks,12u);
                XCTAssertNil(view.renderError);
                window.hidden=YES; window.rootViewController=nil; [done fulfill];
            }
        }];
        [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    });
    [self waitForExpectations:@[done] timeout:10];
}
- (void)writeSyntheticMovie:(NSURL *)url {
    NSError *error=nil; AVAssetWriter *writer=[AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeQuickTimeMovie error:&error];
    XCTAssertNotNil(writer,@"%@",error);
    AVAssetWriterInput *input=[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{AVVideoCodecKey:AVVideoCodecTypeH264,AVVideoWidthKey:@160,AVVideoHeightKey:@120}];
    AVAssetWriterInputPixelBufferAdaptor *adaptor=[AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),(id)kCVPixelBufferWidthKey:@160,(id)kCVPixelBufferHeightKey:@120}];
    [writer addInput:input]; XCTAssertTrue([writer startWriting]); [writer startSessionAtSourceTime:kCMTimeZero];
    for(int frame=0;frame<90;frame++) {
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
        while(!input.readyForMoreMediaData&&writer.status==AVAssetWriterStatusWriting&&deadline.timeIntervalSinceNow>0) [NSThread sleepForTimeInterval:.001];
        XCTAssertTrue(input.readyForMoreMediaData); if(!input.readyForMoreMediaData) break;
        CVPixelBufferRef pixel=NULL; CVReturn result=CVPixelBufferPoolCreatePixelBuffer(NULL,adaptor.pixelBufferPool,&pixel); XCTAssertEqual(result,kCVReturnSuccess); if(!pixel) break;
        CVPixelBufferLockBaseAddress(pixel,0);
        size_t stride=CVPixelBufferGetBytesPerRow(pixel); uint8_t *bytes=CVPixelBufferGetBaseAddress(pixel);
        for(int y=0;y<120;y++) for(int x=0;x<160;x++) { uint8_t *p=bytes+y*stride+x*4; p[0]=(uint8_t)(frame*2);p[1]=(uint8_t)(x+frame);p[2]=(uint8_t)(y+frame);p[3]=255; }
        CVPixelBufferUnlockBaseAddress(pixel,0);
        XCTAssertTrue([adaptor appendPixelBuffer:pixel withPresentationTime:CMTimeMake(frame,30)]); CVPixelBufferRelease(pixel);
    }
    [input markAsFinished]; dispatch_semaphore_t finished=dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(finished); }];
    XCTAssertEqual(dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC)),0L);
    XCTAssertEqual(writer.status,AVAssetWriterStatusCompleted,@"%@",writer.error);
}
- (void)testPlaybackUpdatesFramesThenSeekAndAnalysisButtonRespond {
    XCTestExpectation *done=[self expectationWithDescription:@"moving video, paused seek and analysis response"];
    NSURL *root=[NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *main=[root URLByAppendingPathComponent:@"main.mov"],*sub=[root URLByAppendingPathComponent:@"sub.mov"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        [self writeSyntheticMovie:main]; XCTAssertTrue([NSFileManager.defaultManager copyItemAtURL:main toURL:sub error:nil]);
        dispatch_async(dispatch_get_main_queue(), ^{
            VideoOverlayViewController *controller=[[VideoOverlayViewController alloc] initWithMainURL:main subURL:sub];
            UIWindow *window=[self windowForController:controller];
            __block NSInteger phase=0; __block CIImage *previous=nil; __block NSUInteger updates=0; __block CFTimeInterval previousRender=0;
            NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:12];
            NSTimer *timer=[NSTimer scheduledTimerWithTimeInterval:.1 repeats:YES block:^(NSTimer *timer) {
                AVPlayer *player=[controller valueForKey:@"mainPlayer"];
                CIImage *image=[controller valueForKey:@"mainImage"];
                if(phase==0 && image && image!=previous) { updates++; previous=image; }
                double now=CMTimeGetSeconds(player.currentTime);
                if(phase==0 && updates>=4 && isfinite(now)&&now>.4) {
                    previousRender=[[controller valueForKey:@"lastRenderTime"] doubleValue];
                    UISlider *slider=[controller valueForKey:@"mainSlider"]; slider.value=.25; [slider sendActionsForControlEvents:UIControlEventValueChanged]; phase=1;
                } else if(phase==1 && ![[controller valueForKey:@"seeking"] boolValue] && fabs(now-.25)<.04 && [[controller valueForKey:@"lastRenderTime"] doubleValue]>previousRender) {
                    XCTAssertFalse([[controller valueForKey:@"playing"] boolValue]);
                    UIButton *button=[controller valueForKey:@"analysisButton"]; [button sendActionsForControlEvents:UIControlEventTouchUpInside];
#if !TARGET_OS_SIMULATOR
                    id job=[controller valueForKey:@"analysis"]; XCTAssertNotNil(job);
                    [button sendActionsForControlEvents:UIControlEventTouchUpInside]; XCTAssertTrue([[job valueForKey:@"cancelled"] boolValue]);
#endif
                    phase=2;
                }
                BOOL timedOut=deadline.timeIntervalSinceNow<=0;
                if(phase==2||timedOut) {
                    [timer invalidate]; XCTAssertEqual(phase,2,@"phase=%ld updates=%lu time=%.3f status=%@",(long)phase,(unsigned long)updates,now,[[controller valueForKey:@"statusLabel"] text]);
                    id store=[controller valueForKey:@"store"]; NSURL *directory=[store valueForKey:@"directory"],*cache=[store valueForKey:@"cacheDirectory"];
                    [controller shutdown]; window.hidden=YES; window.rootViewController=nil;
                    if(directory) [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
                    // A cancelled analysis owns its in-flight cache directory and cleans it itself.
                    (void)cache;
                    [NSFileManager.defaultManager removeItemAtURL:root error:nil]; [done fulfill];
                }
            }];
            [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
        });
    });
    [self waitForExpectations:@[done] timeout:25];
}
@end
