#import <XCTest/XCTest.h>
#import "../MTJudge/WaterJump/RecordingController.h"
#import "../MTJudge/VideoRecorder.h"
@interface WJFakeRecorder : VideoRecorder
@property (nonatomic) NSInteger starts;
@property (nonatomic) NSInteger stops;
@property (nonatomic) BOOL available;
@end
@implementation WJFakeRecorder
- (BOOL)readyForRecording { return self.available; }
- (void)startRecording { self.starts++; }
- (void)stopRecording { self.stops++; }
@end
@interface RecordingControllerRegression : XCTestCase
@end
@implementation RecordingControllerRegression
- (void)testDuplicateCommandsAndSavingGate {
    WJFakeRecorder *recorder = [WJFakeRecorder new]; recorder.available = YES;
    RecordingController *controller = [[RecordingController alloc] initWithRecorder:recorder];
    controller.canStart = ^BOOL { return YES; };
    XCTAssertTrue([controller startAutomatic:NO error:nil]);
    XCTAssertFalse([controller startAutomatic:YES error:nil]);
    XCTAssertEqual(recorder.starts, 1);
    XCTAssertTrue([controller stop]); XCTAssertFalse([controller stop]); XCTAssertEqual(recorder.stops, 1);
    [controller finishedWithError:nil]; XCTAssertFalse([controller startAutomatic:NO error:nil]);
    [controller markSaved]; XCTAssertTrue([controller startAutomatic:YES error:nil]);
    [controller stop]; [controller finishedWithError:nil]; [controller markSaved];
}
- (void)testUnavailableCameraAndRejectedUI {
    WJFakeRecorder *recorder = [WJFakeRecorder new];
    RecordingController *controller = [[RecordingController alloc] initWithRecorder:recorder];
    XCTAssertFalse([controller startAutomatic:YES error:nil]);
    recorder.available = YES; controller.canStart = ^BOOL { return NO; };
    XCTAssertFalse([controller startAutomatic:YES error:nil]); XCTAssertEqual(recorder.starts, 0);
}
- (void)testAutomaticStopUsesCameraStartAndSurvivesNoRemote {
    WJFakeRecorder *recorder = [WJFakeRecorder new]; recorder.available = YES;
    RecordingController *controller = [[RecordingController alloc] initWithRecorder:recorder]; controller.duration = 10;
    XCTestExpectation *stopped = [self expectationWithDescription:@"iPhone-owned timer stops recording"];
    controller.changed = ^{ if ([controller.state isEqual:@"STOPPING"]) [stopped fulfill]; };
    XCTAssertTrue([controller startAutomatic:YES error:nil]); [controller didStart];
    [self waitForExpectationsWithTimeout:12 handler:nil];
    XCTAssertEqual(recorder.stops, 1); XCTAssertFalse([controller stop]); controller.changed = nil;
}
@end
