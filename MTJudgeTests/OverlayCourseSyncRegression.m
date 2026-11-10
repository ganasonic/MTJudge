// New focused Stage 4 checks. Synthetic input only. No XCUITest or recording.
#import <XCTest/XCTest.h>
#import "../MTJudge/Overlay/OverlayTimelineMapper.h"
#import "../MTJudge/Overlay/VideoOverlayViewController.h"
#import "../MTJudge/Overlay/OverlaySessionStore.h"
#import "../MTJudge/Overlay/OverlayMetalView.h"

@interface VideoOverlayViewController (CourseRegression)
- (void)shutdown;
- (void)pause;
- (void)seekMain:(double)main sub:(double)sub play:(BOOL)play;
- (double)subSourceTime;
- (void)changeSyncMode:(UISegmentedControl *)sender;
- (BOOL)appendCourseAnchor:(NSDictionary *)anchor error:(NSError **)error;
- (void)setA;
- (void)setB;
- (BOOL)saveQuietly;
@end
@interface OverlayCourseSyncRegression : XCTestCase
@end
@implementation OverlayCourseSyncRegression
- (NSArray *)anchors {
    return @[@{@"mainTime":@.25,@"subTime":@.5,@"confirmed":@YES},@{@"mainTime":@1,@"subTime":@2,@"confirmed":@YES},@{@"mainTime":@2.5,@"subTime":@3.5,@"confirmed":@YES}];
}
- (void)testPiecewiseMappingInverseBoundariesAndNoExtrapolation {
    OverlayTimelineMapper *map=[[OverlayTimelineMapper alloc] initWithAnchors:[self anchors] mainDuration:4 subDuration:4 error:nil]; XCTAssertNotNil(map);
    XCTAssertEqualWithAccuracy([map subTimeForMainTime:.25],.5,1e-8);
    XCTAssertEqualWithAccuracy([map subTimeForMainTime:.625],1.25,1e-8);
    XCTAssertEqualWithAccuracy([map subTimeForMainTime:1],2,1e-8);
    XCTAssertEqualWithAccuracy([map subTimeForMainTime:1.75],2.75,1e-8);
    XCTAssertEqualWithAccuracy([map subTimeForMainTime:2.5],3.5,1e-8);
    XCTAssertEqualWithAccuracy([map subRateForMainTime:.5],2,1e-8);
    XCTAssertEqualWithAccuracy([map subRateForMainTime:1.2],1,1e-8);
    for(double m=.25;m<=2.5;m+=.025) XCTAssertEqualWithAccuracy([map mainTimeForSubTime:[map subTimeForMainTime:m]],m,1e-7);
    XCTAssertTrue(isnan([map subTimeForMainTime:0])); XCTAssertTrue(isnan([map subTimeForMainTime:2.51])); XCTAssertTrue(isnan([map mainTimeForSubTime:3.6]));
}
- (void)testInvalidMarkersAreRejected {
    NSArray *cases=@[@[],@[@{@"mainTime":@1,@"subTime":@1}],@[@{@"mainTime":@0,@"subTime":@2},@{@"mainTime":@1,@"subTime":@1}],@[@{@"mainTime":@1,@"subTime":@0},@{@"mainTime":@1,@"subTime":@1}],@[@{@"mainTime":@0,@"subTime":@0},@{@"mainTime":@1,@"subTime":@8}],@[@{@"mainTime":@0,@"subTime":@0},@{@"mainTime":@5,@"subTime":@1}]];
    for(NSArray *anchors in cases) { NSError *error=nil; XCTAssertNil([[OverlayTimelineMapper alloc] initWithAnchors:anchors mainDuration:4 subDuration:4 error:&error]); XCTAssertNotNil(error); }
}
- (void)testSuggestionsRequireTrackedCoordinatesAndContinuousObservations {
    NSMutableArray *frames=[NSMutableArray array];
    for(int i=0;i<16;i++) [frames addObject:@{@"valid":@YES,@"courseSegment":@0,@"mainTime":@(i*.05),@"subTime":@(i*.05),@"mainCoursePoint":@[@(.1+i*.02),@.5],@"subCoursePoint":@[@(.06+i*.02),@.5]}];
    NSArray *suggestions=[OverlayTimelineMapper suggestionsFromFrames:frames]; XCTAssertGreaterThanOrEqual(suggestions.count,2u);
    for(NSDictionary *s in suggestions) { XCTAssertFalse([s[@"confirmed"] boolValue]); XCTAssertEqualWithAccuracy([s[@"subTime"] doubleValue]-[s[@"mainTime"] doubleValue],.1,1e-6); }
    NSMutableArray *gaps=[NSMutableArray array],*resets=[NSMutableArray array];
    for(NSUInteger i=0;i<frames.count;i++) {
        NSMutableDictionary *f=[frames[i] mutableCopy]; f[@"mainTime"]=@(i*2);f[@"subTime"]=@(i*2); [gaps addObject:f];
        f=[frames[i] mutableCopy]; f[@"courseSegment"]=@(i); [resets addObject:f];
    }
    XCTAssertEqual([OverlayTimelineMapper suggestionsFromFrames:gaps].count,0u);
    XCTAssertEqual([OverlayTimelineMapper suggestionsFromFrames:resets].count,0u);
    NSMutableArray *occluded=[NSMutableArray array];
    for(NSUInteger i=0;i<frames.count;i++) { NSMutableDictionary *f=[frames[i] mutableCopy];f[@"courseSampleIndex"]=@(i*2);[occluded addObject:f]; }
    XCTAssertEqual([OverlayTimelineMapper suggestionsFromFrames:occluded].count,0u);
    NSArray *missing=@[@{@"valid":@YES,@"mainTime":@1,@"subTime":@1,@"mainJoints":@{}}];
    XCTAssertEqual([OverlayTimelineMapper suggestionsFromFrames:missing].count,0u);
}
- (void)writeMovie:(NSURL *)url {
    NSError *error=nil; AVAssetWriter *writer=[AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeQuickTimeMovie error:&error]; XCTAssertNotNil(writer,@"%@",error);
    AVAssetWriterInput *input=[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{AVVideoCodecKey:AVVideoCodecTypeH264,AVVideoWidthKey:@160,AVVideoHeightKey:@120}];
    AVAssetWriterInputPixelBufferAdaptor *adaptor=[AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),(id)kCVPixelBufferWidthKey:@160,(id)kCVPixelBufferHeightKey:@120}];
    [writer addInput:input]; XCTAssertTrue([writer startWriting]); [writer startSessionAtSourceTime:kCMTimeZero];
    for(int i=0;i<120;i++) {
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5]; while(!input.readyForMoreMediaData&&writer.status==AVAssetWriterStatusWriting&&deadline.timeIntervalSinceNow>0) [NSThread sleepForTimeInterval:.001];
        XCTAssertTrue(input.readyForMoreMediaData); if(!input.readyForMoreMediaData) break;
        CVPixelBufferRef pixel=NULL; XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(NULL,adaptor.pixelBufferPool,&pixel),kCVReturnSuccess); if(!pixel) break;
        CVPixelBufferLockBaseAddress(pixel,0); uint8_t *bytes=CVPixelBufferGetBaseAddress(pixel); size_t stride=CVPixelBufferGetBytesPerRow(pixel);
        for(int y=0;y<120;y++) for(int x=0;x<160;x++) { uint8_t *p=bytes+y*stride+x*4;p[0]=(i*2)%256;p[1]=(x+i)%256;p[2]=(y+i)%256;p[3]=255; }
        CVPixelBufferUnlockBaseAddress(pixel,0); XCTAssertTrue([adaptor appendPixelBuffer:pixel withPresentationTime:CMTimeMake(i,30)]); CVPixelBufferRelease(pixel);
    }
    [input markAsFinished]; dispatch_semaphore_t completed=dispatch_semaphore_create(0); [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(completed); }];
    XCTAssertEqual(dispatch_semaphore_wait(completed,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC)),0L); XCTAssertEqual(writer.status,AVAssetWriterStatusCompleted,@"%@",writer.error);
}
- (UIWindow *)windowFor:(UIViewController *)controller {
    UIWindowScene *scene=nil; for(UIScene *s in UIApplication.sharedApplication.connectedScenes) if([s isKindOfClass:UIWindowScene.class]&&s.activationState==UISceneActivationStateForegroundActive) { scene=(UIWindowScene *)s; break; }
    UIWindow *w=scene?[[UIWindow alloc] initWithWindowScene:scene]:[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; w.frame=UIScreen.mainScreen.bounds; w.rootViewController=controller;[w makeKeyAndVisible];[controller.view layoutIfNeeded];return w;
}
- (void)testRetimedPlaybackSeekLoopModeSwitchAndSessionRestore {
    XCTestExpectation *done=[self expectationWithDescription:@"course composition, boundary playback, AB, switch and restore"];
    NSURL *root=[NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString]; [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *main=[root URLByAppendingPathComponent:@"main.mov"],*sub=[root URLByAppendingPathComponent:@"sub.mov"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        [self writeMovie:main]; XCTAssertTrue([NSFileManager.defaultManager copyItemAtURL:main toURL:sub error:nil]);
        OverlayTimelineMapper *mapper=[[OverlayTimelineMapper alloc] initWithAnchors:[self anchors] mainDuration:4 subDuration:4 error:nil];
        NSError *compositionError=nil; AVMutableComposition *composition=[mapper compositionForSubURL:sub error:&compositionError]; XCTAssertNotNil(composition,@"%@",compositionError); XCTAssertEqualWithAccuracy(CMTimeGetSeconds(composition.duration),2.25,.0001);
        NSArray<AVCompositionTrackSegment *> *segments=[composition tracksWithMediaType:AVMediaTypeVideo].firstObject.segments;
        XCTAssertEqual(segments.count,2u);
        if(segments.count==2) {
            XCTAssertEqualWithAccuracy(CMTimeGetSeconds(segments[0].timeMapping.source.start),.5,.0001);
            XCTAssertEqualWithAccuracy(CMTimeGetSeconds(segments[0].timeMapping.source.duration),1.5,.0001);
            XCTAssertEqualWithAccuracy(CMTimeGetSeconds(segments[0].timeMapping.target.duration),.75,.0001);
            XCTAssertEqualWithAccuracy(CMTimeGetSeconds(segments[1].timeMapping.target.start),.75,.0001);
            XCTAssertEqualWithAccuracy(CMTimeGetSeconds(segments[1].timeMapping.target.duration),1.5,.0001);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __block VideoOverlayViewController *controller=[[VideoOverlayViewController alloc] initWithMainURL:main subURL:sub];
            UIWindow *window=[self windowFor:controller];
            __block NSInteger phase=0; __block double preserved=0; __block BOOL rose=NO; __block NSUInteger imageChanges=0,courseImageChanges=0; __block id previous=nil,previousSubImage=nil;
            NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:20];
            NSTimer *timer=[NSTimer scheduledTimerWithTimeInterval:.05 repeats:YES block:^(NSTimer *timer) {
                AVPlayer *player=[controller valueForKey:@"mainPlayer"],*subPlayer=[controller valueForKey:@"subPlayer"];
                BOOL prepared=[[controller valueForKey:@"prepared"] boolValue],busy=[[controller valueForKey:@"seeking"] boolValue]||[[controller valueForKey:@"switchingTimeline"] boolValue];
                BOOL course=[[controller valueForKey:@"courseMode"] boolValue]; double m=CMTimeGetSeconds(player.currentTime);
                id subImage=[controller valueForKey:@"subImage"]; if(course&&subImage&&subImage!=previousSubImage) { courseImageChanges++;previousSubImage=subImage; }
                id image=[controller valueForKey:@"mainImage"]; if(image&&image!=previous) { imageChanges++;previous=image; }
                UISegmentedControl *mode=[controller valueForKey:@"syncControl"];
                if(phase==0&&prepared&&!busy&&imageChanges>=3&&m>.4) {
                    [controller pause]; preserved=CMTimeGetSeconds(player.currentTime);
                    for(NSDictionary *a in [self anchors]) XCTAssertTrue([controller appendCourseAnchor:a error:nil]);
                    mode.selectedSegmentIndex=1; [controller changeSyncMode:mode]; phase=1;
                } else if(phase==1&&course&&!busy) {
                    XCTAssertEqualWithAccuracy(m,preserved,.04); XCTAssertEqualWithAccuracy([controller subSourceTime],[mapper subTimeForMainTime:m],.04);
                    XCTAssertFalse(player.muted); XCTAssertTrue(subPlayer.muted);
                    XCTAssertTrue([subPlayer.currentItem.asset isKindOfClass:AVComposition.class]);
                    UIButton *play=[controller valueForKey:@"playButton"]; [play sendActionsForControlEvents:UIControlEventTouchUpInside]; phase=2;
                } else if(phase==2&&!busy&&m>1.12) {
                    XCTAssertGreaterThanOrEqual(courseImageChanges,3u);
                    XCTAssertEqualWithAccuracy([controller subSourceTime],[mapper subTimeForMainTime:m],.07);
                    XCTAssertEqualWithAccuracy(CMTimeGetSeconds(subPlayer.currentTime),m-.25,.05);
                    UISlider *slider=[controller valueForKey:@"mainSlider"];slider.value=1.5;[slider sendActionsForControlEvents:UIControlEventValueChanged]; phase=3;
                } else if(phase==3&&!busy&&fabs(m-1.5)<.025&&[[controller valueForKey:@"lastRenderTime"] doubleValue]>0) {
                    XCTAssertEqualWithAccuracy([controller subSourceTime],2.5,.025);
                    // The retimed SUB must actually show source frame ~75 (2.5 s),
                    // rather than merely report a mapped timestamp over frame ~45.
                    uint8_t rgba[4]={0}; CGColorSpaceRef rgb=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                    OverlayMetalView *metal=[controller valueForKey:@"metalView"];
                    [metal.imageContext render:[controller valueForKey:@"subImage"] toBitmap:rgba rowBytes:4 bounds:CGRectMake(80,60,1,1) format:kCIFormatRGBA8 colorSpace:rgb]; CGColorSpaceRelease(rgb);
                    XCTAssertEqualWithAccuracy(rgba[2],150,16);
                    [controller setA]; [controller seekMain:1.8 sub:2.8 play:NO]; phase=4;
                } else if(phase==4&&!busy&&fabs(m-1.8)<.025) {
                    [controller setB]; phase=5;
                } else if(phase==5&&!busy) {
                    if(m>1.7) rose=YES;
                    if(rose&&m<1.6) {
                        XCTAssertEqualWithAccuracy([controller subSourceTime],[mapper subTimeForMainTime:m],.06);
                        [controller pause];preserved=CMTimeGetSeconds(player.currentTime);mode.selectedSegmentIndex=0;[controller changeSyncMode:mode];phase=6;
                    }
                } else if(phase==6&&!busy&&!course) {
                    XCTAssertEqualWithAccuracy(m,preserved,.04);XCTAssertEqualWithAccuracy([controller subSourceTime],m,.04);
                    XCTAssertTrue([subPlayer.currentItem.asset isKindOfClass:AVURLAsset.class]);
                    mode.selectedSegmentIndex=1;[controller changeSyncMode:mode];phase=7;
                } else if(phase==7&&!busy&&course) {
                    XCTAssertTrue([controller saveQuietly]);
                    OverlaySessionStore *store=[controller valueForKey:@"store"];NSDictionary *saved=[store load];XCTAssertEqualObjects(saved[@"syncMode"],@"coursePosition");XCTAssertEqual([saved[@"courseAnchors"] count],3u);
                    preserved=m;[controller shutdown];
                    controller=[[VideoOverlayViewController alloc] initWithMainURL:main subURL:sub];window.rootViewController=controller;[controller.view layoutIfNeeded];phase=8;
                } else if(phase==8&&prepared&&!busy&&course) {
                    XCTAssertEqualWithAccuracy(m,preserved,.04);XCTAssertEqualWithAccuracy([controller subSourceTime],[mapper subTimeForMainTime:m],.04);phase=9;
                }
                BOOL timedOut=deadline.timeIntervalSinceNow<=0;
                if(phase==9||timedOut) {
                    [timer invalidate];XCTAssertEqual(phase,9,@"phase=%ld main=%.3f subItem=%.3f busy=%d render=%@ images=%d/%d status=%@",(long)phase,m,CMTimeGetSeconds(subPlayer.currentTime),busy,[controller valueForKey:@"lastRenderTime"],[controller valueForKey:@"mainImage"]!=nil,[controller valueForKey:@"subImage"]!=nil,[[controller valueForKey:@"statusLabel"] text]);
                    OverlaySessionStore *store=[controller valueForKey:@"store"];[controller shutdown];window.hidden=YES;window.rootViewController=nil;
                    if(store) { [NSFileManager.defaultManager removeItemAtURL:store.directory error:nil];[NSFileManager.defaultManager removeItemAtURL:store.cacheDirectory error:nil]; }
                    [NSFileManager.defaultManager removeItemAtURL:root error:nil];[done fulfill];
                }
            }];[NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
        });
    });
    [self waitForExpectations:@[done] timeout:35];
}
@end
