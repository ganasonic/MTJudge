#import "TakeoffAngleAnalyzer.h"
#import "PoseAnalyzer.h"

static BOOL ReadPoint(NSDictionary *joints, NSString *name, CGPoint *point, double *confidence) {
    NSDictionary *value = joints[name]; if (![value isKindOfClass:NSDictionary.class]) return NO;
    double c = [value[@"confidence"] doubleValue]; if (c <= .1) return NO;
    if (point) *point = CGPointMake([value[@"x"] doubleValue], [value[@"y"] doubleValue]); if (confidence) *confidence = c; return YES;
}
static double VectorAngle(CGPoint a, CGPoint b) { double denominator = hypot(a.x, a.y) * hypot(b.x, b.y); if (denominator <= DBL_EPSILON) return NAN; return acos(MAX(-1.0, MIN(1.0, (a.x*b.x + a.y*b.y) / denominator))) * 180.0 / M_PI; }
static CGPoint Sub(CGPoint a, CGPoint b) { return CGPointMake(a.x-b.x, a.y-b.y); }

@implementation TakeoffAngleAnalyzer
+ (NSDictionary *)resultForFrame:(NSDictionary *)frame config:(TakeoffAnalysisConfig *)config {
    if (!config.enabled || !CMTIME_IS_VALID(config.takeoffStartTime) || !CMTIME_IS_VALID(config.lipExitTime)) return nil;
    double timestamp = [frame[@"timestamp"] doubleValue]; if (timestamp < CMTimeGetSeconds(config.takeoffStartTime) || timestamp > CMTimeGetSeconds(config.lipExitTime)) return nil;
    NSDictionary *joints = frame[@"joints"]; CGPoint hip, knee, ankle, shoulder; BOOL left = ReadPoint(joints, VNHumanBodyPoseObservationJointNameLeftHip, &hip, NULL) && ReadPoint(joints, VNHumanBodyPoseObservationJointNameLeftKnee, &knee, NULL) && ReadPoint(joints, VNHumanBodyPoseObservationJointNameLeftAnkle, &ankle, NULL) && ReadPoint(joints, VNHumanBodyPoseObservationJointNameLeftShoulder, &shoulder, NULL); CGPoint rHip, rKnee, rAnkle, rShoulder; BOOL right = ReadPoint(joints, VNHumanBodyPoseObservationJointNameRightHip, &rHip, NULL) && ReadPoint(joints, VNHumanBodyPoseObservationJointNameRightKnee, &rKnee, NULL) && ReadPoint(joints, VNHumanBodyPoseObservationJointNameRightAnkle, &rAnkle, NULL) && ReadPoint(joints, VNHumanBodyPoseObservationJointNameRightShoulder, &rShoulder, NULL);
    if (config.analysisSide == TakeoffAnalysisSideLeft) right = NO; else if (config.analysisSide == TakeoffAnalysisSideRight) left = NO; else if (left && right) { left = ([frame[@"joints"][VNHumanBodyPoseObservationJointNameLeftKnee][@"confidence"] doubleValue] >= [frame[@"joints"][VNHumanBodyPoseObservationJointNameRightKnee][@"confidence"] doubleValue]); right = !left; }
    if (!left && !right) return nil; if (!left) { hip=rHip; knee=rKnee; ankle=rAnkle; shoulder=rShoulder; }
    CGPoint ramp = Sub(config.rampPointB, config.rampPointA); CGPoint lower = Sub(knee, ankle); CGPoint thigh = Sub(hip, knee); CGPoint torso = Sub(shoulder, hip); double ankleAngle = VectorAngle(ramp, lower); double kneeAngle = [PoseAnalyzer angleAtPoint:knee first:ankle second:hip]; double hipAngle = [PoseAnalyzer angleAtPoint:hip first:knee second:shoulder]; double torsoAngle = VectorAngle(ramp, torso);
    NSMutableDictionary *result = [@{ @"timestamp": @(timestamp), @"analysisSide": left ? @"LEFT" : @"RIGHT" } mutableCopy]; if (isfinite(ankleAngle)) result[@"ankleAngle"] = @(ankleAngle); if (isfinite(kneeAngle)) result[@"kneeAngle"] = @(kneeAngle); if (isfinite(hipAngle)) result[@"hipAngle"] = @(hipAngle); if (isfinite(torsoAngle)) result[@"torsoRampAngle"] = @(torsoAngle); return result;
}
@end
