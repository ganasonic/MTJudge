#import <XCTest/XCTest.h>

@interface MTJudgeUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@property (nonatomic) BOOL startedRecording;
@end

@implementation MTJudgeUITests

- (void)setUp {
    [super setUp];
    self.continueAfterFailure = NO;
    self.app = [[XCUIApplication alloc] init];
    // NSArgumentDomain overrides are process-local. Never reset the user's defaults,
    // delete recordings, or change the production camera/transfer implementation.
    BOOL automatic = [self.name containsString:@"testWaterJumpAutomaticRecordingOnDevice"];
    self.app.launchArguments = @[@"-WJMode", automatic ? @"YES" : @"NO",
        @"-WJDuration", @"10", @"-WJTransfer", @"NO", @"-WJReceive", @"NO",
        @"-WJWeb", @"NO", @"-WJWatch", @"NO", @"-WJUseSubCamera", @"NO",
        @"-WJUseSubCamera2", @"NO", @"-WJAutoPlayAfterTransfer", @"NO",
        @"-WJCameraGroupID", @""];
    [self addUIInterruptionMonitorWithDescription:@"MTJudge media permissions" handler:^BOOL(XCUIElement *alert) {
        return [self acceptMediaPermission:alert];
    }];
    [self.app launch];
}

- (BOOL)acceptMediaPermission:(XCUIElement *)alert {
    NSString *text = alert.debugDescription.lowercaseString;
    BOOL media = NO;
    for (NSString *word in @[@"カメラ", @"マイク", @"ローカルネットワーク", @"camera", @"microphone", @"local network"])
        if ([text containsString:word]) media = YES;
    if (!media) return NO;
    for (NSString *label in @[@"許可", @"許可する", @"Allow", @"OK"])
        if (alert.buttons[label].exists) { [alert.buttons[label] tap]; return YES; }
    return NO;
}

- (void)capture:(NSString *)name {
    XCTAttachment *screen = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    screen.name = name;
    screen.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:screen];
}

- (void)tearDown {
    // Capture the failing state before cleanup; keep evidence on successful runs too.
    [self capture:self.name];
    XCTAttachment *hierarchy = [XCTAttachment attachmentWithString:self.app.debugDescription];
    hierarchy.name = @"UI hierarchy";
    hierarchy.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:hierarchy];
    if (self.startedRecording && self.app.buttons[@"録画停止"].isHittable) {
        [self.app.buttons[@"録画停止"] tap];
        NSPredicate *saved = [NSPredicate predicateWithFormat:@"label CONTAINS 'COMPLETE'"];
        XCTNSPredicateExpectation *completion = [[XCTNSPredicateExpectation alloc] initWithPredicate:saved object:self.app.staticTexts[@"WJStatusLabel"]];
        [XCTWaiter waitForExpectations:@[completion] timeout:60];
    }
    [self.app terminate];
    [super tearDown];
}

- (void)waitFor:(XCUIElement *)element predicate:(NSString *)format timeout:(NSTimeInterval)timeout {
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithFormat:format] object:element];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[expectation] timeout:timeout], XCTWaiterResultCompleted,
                   @"Expected %@: %@", format, element);
}

- (XCUIElement *)tabNamed:(NSString *)name {
    XCUIElement *tab = self.app.tabBars.buttons[name];
    // iPadOS floating tabs are exposed as nested Buttons, not a TabBar.
    return tab.exists ? tab : self.app.buttons[name].firstMatch;
}

- (void)openCamera {
    XCUIElement *camera = [self tabNamed:@"Camera"];
    for (NSUInteger page = 0; page < 3 && !camera.isHittable; page++) {
        XCUIElement *next = self.app.buttons[@"Next Page"].firstMatch;
        if (!next.isHittable) break;
        [next tap];
        camera = [self tabNamed:@"Camera"];
    }
    if (camera.exists && camera.isHittable) [camera tap];
    else {
        XCUIElement *more = self.app.tabBars.buttons[@"More"];
        if (!more.exists) more = self.app.tabBars.buttons[@"その他"];
        XCTAssertTrue(more.exists, @"Camera tab or More tab must exist");
        [more tap];
        XCUIElement *row = self.app.tables.staticTexts[@"Camera"].firstMatch;
        if (!row.isHittable) [self.app.tables.firstMatch swipeUp];
        XCTAssertTrue([row waitForExistenceWithTimeout:10]);
        [row tap];
    }
    XCUIApplication *system = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.apple.springboard"];
    for (NSUInteger attempt = 0; attempt < 3; attempt++) {
        XCUIElement *alert = system.alerts.firstMatch;
        if (![alert waitForExistenceWithTimeout:2]) break;
        if (![self acceptMediaPermission:alert]) break;
    }
    XCTAssertTrue([self.app.buttons[@"WJSettingsButton"] waitForExistenceWithTimeout:15]);
}

- (void)testLaunchShowsTabBar {
    XCUIElement *base = [self tabNamed:@"Base"];
    XCTAssertTrue([base waitForExistenceWithTimeout:15]);
    XCTAssertEqual(self.app.state, XCUIApplicationStateRunningForeground);
    XCTAssertTrue(base.isSelected);
    XCTAssertTrue([self tabNamed:@"Judging"].exists);
    XCTAssertTrue(self.app.staticTexts[@"Turn Base Point"].exists);
}

- (void)testTabSwitching {
    for (NSString *name in @[@"Judging", @"Speed", @"Base"]) {
        XCUIElement *tab = [self tabNamed:name];
        XCTAssertTrue([tab waitForExistenceWithTimeout:10]);
        [tab tap];
        [self waitFor:tab predicate:@"selected == YES" timeout:5];
        XCTAssertEqual(self.app.state, XCUIApplicationStateRunningForeground);
        [self capture:[@"Tab-" stringByAppendingString:name]];
    }
}

- (void)testCameraSettingsNavigation {
    [self openCamera];
    [self.app.buttons[@"WJSettingsButton"] tap];
    XCTAssertTrue([self.app.switches[@"WJMode"] waitForExistenceWithTimeout:10]);
    XCTAssertTrue(self.app.cells[@"WJDuration"].exists);
    [self capture:@"Camera-settings"];
    [self.app.buttons[@"WJDone"] tap];
    [self waitFor:self.app.buttons[@"WJSettingsButton"] predicate:@"hittable == YES" timeout:10];
    XCTAssertTrue(self.app.buttons[@"録画開始"].exists);
}

- (void)startCameraRecording {
    [self openCamera];
    XCUIElement *record = self.app.buttons[@"録画開始"];
    [self waitFor:record predicate:@"exists == YES AND enabled == YES AND hittable == YES" timeout:20];
    self.startedRecording = YES;
    [record tap];
    XCTAssertTrue([self.app.buttons[@"録画停止"] waitForExistenceWithTimeout:10]);
    [self waitFor:self.app.staticTexts[@"WJStatusLabel"] predicate:@"label CONTAINS 'RECORDING'" timeout:10];
    [self capture:@"Recording-started"];
}

- (void)verifyRecordingCompleted {
    [self waitFor:self.app.staticTexts[@"WJStatusLabel"] predicate:@"label CONTAINS 'COMPLETE'" timeout:60];
    [self waitFor:self.app.buttons[@"録画開始"] predicate:@"exists == YES AND enabled == YES" timeout:10];
    XCTAssertTrue(self.app.buttons[@"最新動画を再生"].enabled);
    XCTAssertFalse(self.app.buttons[@"録画停止"].exists);
    self.startedRecording = NO;
    [self capture:@"Recording-saved"];
}

- (void)testCameraManualRecordingStartStop {
    [self startCameraRecording];
    // Intentional capture interval, not a substitute for waiting for UI state.
    [NSThread sleepForTimeInterval:3];
    [self.app.buttons[@"録画停止"] tap];
    [self verifyRecordingCompleted];
}

- (void)testWaterJumpAutomaticRecordingOnDevice {
    [self startCameraRecording];
    [self verifyRecordingCompleted];
}
@end
