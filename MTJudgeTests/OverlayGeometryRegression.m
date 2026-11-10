// Focused, synthetic-image checks only. No camera, recording, UI tests or user's videos.
#import <XCTest/XCTest.h>
#import "../MTJudge/Overlay/OverlayRegistration.h"
#import "../MTJudge/Overlay/OverlaySessionStore.h"

@interface OverlayGeometryRegression : XCTestCase
@end
@implementation OverlayGeometryRegression
- (void)testManualHomographyAndSerialization {
    NSArray *corners=@[[NSValue valueWithCGPoint:CGPointMake(.1,.1)],[NSValue valueWithCGPoint:CGPointMake(.9,.1)],[NSValue valueWithCGPoint:CGPointMake(.9,.9)],[NSValue valueWithCGPoint:CGPointMake(.1,.9)]];
    simd_double3x3 expected=matrix_identity_double3x3;
    expected.columns[0]=(simd_double3){.9,.04,.07}; expected.columns[1]=(simd_double3){-.03,1.1,-.05}; expected.columns[2]=(simd_double3){.08,-.02,1};
    NSMutableArray *dest=[NSMutableArray array]; for(NSValue *p in corners) [dest addObject:[NSValue valueWithCGPoint:MTJOverlayProject(expected,p.CGPointValue)]];
    NSArray *array=[OverlayRegistration matrixFromPoints:corners toPoints:dest]; XCTAssertNotNil(array);
    simd_double3x3 actual=MTJOverlayMatrix(array);
    CGPoint p=MTJOverlayProject(actual,CGPointMake(.38,.64)),q=MTJOverlayProject(expected,CGPointMake(.38,.64));
    XCTAssertEqualWithAccuracy(p.x,q.x,1e-7); XCTAssertEqualWithAccuracy(p.y,q.y,1e-7);
    XCTAssertEqualObjects(MTJOverlayMatrixArray(actual),array);
}
- (void)testDegenerateManualPointsAreRejected {
    NSArray *line=@[[NSValue valueWithCGPoint:CGPointMake(0,0)],[NSValue valueWithCGPoint:CGPointMake(.3,.3)],[NSValue valueWithCGPoint:CGPointMake(.6,.6)],[NSValue valueWithCGPoint:CGPointMake(1,1)]];
    XCTAssertNil([OverlayRegistration matrixFromPoints:line toPoints:line]);
    simd_double3x3 invalid=matrix_identity_double3x3; invalid.columns[0].x=NAN; XCTAssertFalse(MTJOverlayMatrixIsValid(invalid));
}
- (UIImage *)texture {
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat]; format.scale=1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(400,300) format:format] imageWithActions:^(UIGraphicsImageRendererContext *r) {
        [UIColor.grayColor setFill]; UIRectFill(CGRectMake(0,0,400,300));
        uint32_t seed=20261110;
        for(int i=0;i<1400;i++) {
            seed=1664525*seed+1013904223; CGFloat x=(seed>>8)%390;
            seed=1664525*seed+1013904223; CGFloat y=(seed>>8)%290;
            seed=1664525*seed+1013904223; CGFloat gray=(seed%256)/255.0;
            [[UIColor colorWithWhite:gray alpha:1] setFill]; UIRectFill(CGRectMake(x,y,3+(seed%7),3+((seed>>5)%7)));
        }
    }];
}
- (void)testBackgroundRegistrationAndOpticalFlow {
#if !TARGET_OS_SIMULATOR
    UIImage *sub=[self texture]; UIGraphicsImageRendererFormat *f=[UIGraphicsImageRendererFormat defaultFormat]; f.scale=1;
    UIImage *main=[[[UIGraphicsImageRenderer alloc] initWithSize:sub.size format:f] imageWithActions:^(UIGraphicsImageRendererContext *r) { [UIColor.grayColor setFill]; UIRectFill(CGRectMake(0,0,400,300)); [sub drawAtPoint:CGPointMake(12,8)]; }];
    OverlayRegistration *registration=[OverlayRegistration new];
    for(NSDictionary *result in @[[registration registerMain:main.CGImage sub:sub.CGImage mainMask:nil subMask:nil],[registration trackFrom:sub.CGImage to:main.CGImage previousMask:nil currentMask:nil]]) {
        XCTAssertTrue([result[@"valid"] boolValue],@"%@",result);
        CGPoint center=MTJOverlayProject(MTJOverlayMatrix(result[@"matrix"]),CGPointMake(.5,.5));
        XCTAssertEqualWithAccuracy(center.x,.53,.008); XCTAssertEqualWithAccuracy(center.y,.5+8.0/300,.008);
    }
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:sub.size format:f];
    UIImage *blank=[renderer imageWithActions:^(UIGraphicsImageRendererContext *r) { [UIColor.whiteColor setFill]; UIRectFill(CGRectMake(0,0,400,300)); }];
    XCTAssertFalse([[registration registerMain:blank.CGImage sub:blank.CGImage mainMask:nil subMask:nil][@"valid"] boolValue]);
#endif
}
- (void)testSessionRoundTripCorruptionAndSameNameReplacement {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSURL *root=[fm.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    XCTAssertTrue([fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil]);
    NSURL *main=[root URLByAppendingPathComponent:@"main.mov"],*sub=[root URLByAppendingPathComponent:@"sub.mov"];
    [@"synthetic-main" writeToURL:main atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"synthetic-sub" writeToURL:sub atomically:YES encoding:NSUTF8StringEncoding error:nil];
    OverlaySessionStore *store=[[OverlaySessionStore alloc] initWithMainURL:main subURL:sub error:nil]; XCTAssertNotNil(store);
    NSDictionary *state=@{@"mainAnchor":@1,@"subAnchor":@2,@"mainTime":@3,@"opacity":@.5,@"speed":@1,@"manualMatrix":MTJOverlayMatrixArray(matrix_identity_double3x3),@"mainSubject":@[@.5,@.5],@"subSubject":@[@.5,@.5],@"frames":@[],@"comparisonDrawings":@[@{@"start":@2,@"points":@[@[@.1,@.2],@[@.4,@.5]]}]};
    XCTAssertTrue([store save:state error:nil]);
    NSDictionary *loaded=[store load]; XCTAssertNotNil(loaded); XCTAssertEqualObjects(loaded[@"comparisonDrawings"],state[@"comparisonDrawings"]);
    NSMutableDictionary *corrupt=[loaded mutableCopy]; corrupt[@"manualMatrix"]=@[@1,@0];
    NSData *json=[NSJSONSerialization dataWithJSONObject:corrupt options:0 error:nil]; [json writeToURL:[store.directory URLByAppendingPathComponent:@"session.json"] atomically:YES];
    XCTAssertNil([store load]);
    [@"replacement-with-same-name" writeToURL:sub atomically:YES encoding:NSUTF8StringEncoding error:nil];
    OverlaySessionStore *replacement=[[OverlaySessionStore alloc] initWithMainURL:main subURL:sub error:nil];
    XCTAssertNotEqualObjects(store.directory,replacement.directory); XCTAssertNil([replacement load]);
    // Only directories/files generated by this test are removed.
    for(NSURL *url in @[store.directory,store.cacheDirectory,replacement.directory,replacement.cacheDirectory,root]) [fm removeItemAtURL:url error:nil];
}
@end
