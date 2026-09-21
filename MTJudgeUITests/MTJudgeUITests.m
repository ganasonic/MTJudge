//
//  MTJudgeUITests.m
//  MTJudgeUITests
//
//  Created by Yasunori Nagashima on 2019/04/16.
//  Copyright © 2019 Yasunori Nagashima. All rights reserved.
//

#import <XCTest/XCTest.h>

@interface MTJudgeUITests : XCTestCase

@end

@implementation MTJudgeUITests

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.

    // In UI tests it is usually best to stop immediately when a failure occurs.
    self.continueAfterFailure = NO;

    // UI tests must launch the application that they test. Doing this in setup will make sure it happens for each test method.
    [[[XCUIApplication alloc] init] launch];

    // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testWaterJumpAutomaticRecordingOnDevice {
    XCUIApplication *app = [[XCUIApplication alloc] init];
    [self addUIInterruptionMonitorWithDescription:@"Camera permissions" handler:^BOOL(XCUIElement *alert) {
        for (NSString *name in @[@"許可", @"Allow", @"OK"]) if (alert.buttons[name].exists) { [alert.buttons[name] tap]; return YES; }
        return NO;
    }];
    XCUIElement *cameraTab = app.tabBars.buttons[@"Camera"];
    if (cameraTab.exists) [cameraTab tap];
    else {
        [app.tabBars.buttons.allElementsBoundByIndex.lastObject tap];
        XCUIElement *camera = app.tables.staticTexts[@"Camera"].firstMatch;
        XCTAssertTrue([camera waitForExistenceWithTimeout:10]); [camera tap];
    }
    XCUIElement *settings = app.buttons[@"WJSettingsButton"];
    XCTAssertTrue([settings waitForExistenceWithTimeout:10]); [settings tap];
    XCUIElement *mode = app.switches[@"WJMode"], *transfer = app.switches[@"WJTransfer"];
    if ([transfer.value isEqual:@"1"]) [transfer tap];
    if (![mode.value isEqual:@"1"]) [mode tap];
    [app.cells[@"WJDuration"] tap]; [app.alerts.buttons[@"10秒"] tap];
    [app.buttons[@"WJDone"] tap];
    XCUIElement *record = app.buttons[@"録画開始"];
    NSPredicate *enabled = [NSPredicate predicateWithFormat:@"exists == YES AND enabled == YES"];
    XCTestExpectation *ready = [self expectationForPredicate:enabled evaluatedWithObject:record handler:nil];
    [self waitForExpectations:@[ready] timeout:15];
    [record tap];
    XCTAssertTrue([app.buttons[@"録画停止"] waitForExistenceWithTimeout:5]);
    XCUIElement *status = app.staticTexts[@"WJStatusLabel"];
    NSPredicate *saved = [NSPredicate predicateWithFormat:@"label CONTAINS 'COMPLETE'"];
    XCTestExpectation *completed = [self expectationForPredicate:saved evaluatedWithObject:status handler:nil];
    [self waitForExpectations:@[completed] timeout:60];
    XCTAssertTrue(app.buttons[@"最新動画を再生"].enabled);
    [app.buttons[@"最新動画を再生"] tap]; XCTAssertTrue([app.buttons[@"再生停止"] waitForExistenceWithTimeout:5]);
    [app.buttons[@"再生停止"] tap];
    // Leave default 20 seconds and normal mode; retain the recorded test clip.
    [settings tap]; [app.cells[@"WJDuration"] tap]; [app.alerts.buttons[@"20秒"] tap];
    if ([app.switches[@"WJMode"].value isEqual:@"1"]) [app.switches[@"WJMode"] tap];
    [app.buttons[@"WJDone"] tap];
}

- (void)testExample {
    // Use recording to get started writing UI tests.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
}

@end
