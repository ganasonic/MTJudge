#import "PoseAnalyzer.h"

static double ClampAngle(double value) { return MAX(0.0, MIN(180.0, value)); }
static NSDictionary *PointValue(VNRecognizedPoint *point) {
    return @{ @"x": @(point.location.x), @"y": @(point.location.y), @"confidence": @(point.confidence) };
}

@implementation PoseAnalyzer

+ (double)angleAtPoint:(CGPoint)point first:(CGPoint)first second:(CGPoint)second {
    double ax = first.x - point.x, ay = first.y - point.y;
    double bx = second.x - point.x, by = second.y - point.y;
    double denominator = hypot(ax, ay) * hypot(bx, by);
    if (denominator <= DBL_EPSILON) return NAN;
    return ClampAngle(acos(MAX(-1.0, MIN(1.0, (ax * bx + ay * by) / denominator))) * 180.0 / M_PI);
}

+ (NSDictionary *)frameDataFromObservation:(VNHumanBodyPoseObservation *)observation timestamp:(double)timestamp {
    NSArray<NSString *> *names = @[
        VNHumanBodyPoseObservationJointNameLeftShoulder, VNHumanBodyPoseObservationJointNameRightShoulder,
        VNHumanBodyPoseObservationJointNameLeftHip, VNHumanBodyPoseObservationJointNameRightHip,
        VNHumanBodyPoseObservationJointNameLeftKnee, VNHumanBodyPoseObservationJointNameRightKnee,
        VNHumanBodyPoseObservationJointNameLeftAnkle, VNHumanBodyPoseObservationJointNameRightAnkle
    ];
    NSMutableDictionary *joints = [NSMutableDictionary dictionary];
    for (NSString *name in names) {
        VNRecognizedPoint *point = [observation recognizedPointForJointName:name error:NULL];
        if (point && point.confidence > 0.1) joints[name] = PointValue(point);
    }
    VNRecognizedPoint *lh = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameLeftHip error:NULL];
    VNRecognizedPoint *rh = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameRightHip error:NULL];
    VNRecognizedPoint *ls = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameLeftShoulder error:NULL];
    VNRecognizedPoint *rs = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameRightShoulder error:NULL];
    VNRecognizedPoint *lk = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameLeftKnee error:NULL];
    VNRecognizedPoint *rk = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameRightKnee error:NULL];
    VNRecognizedPoint *la = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameLeftAnkle error:NULL];
    VNRecognizedPoint *ra = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameRightAnkle error:NULL];
    BOOL leftValid = lk.confidence > .1 && lh.confidence > .1 && la.confidence > .1;
    BOOL rightValid = rk.confidence > .1 && rh.confidence > .1 && ra.confidence > .1;
    double leftKnee = leftValid ? [self angleAtPoint:CGPointMake(lk.location.x, lk.location.y) first:CGPointMake(lh.location.x, lh.location.y) second:CGPointMake(la.location.x, la.location.y)] : NAN;
    double rightKnee = rightValid ? [self angleAtPoint:CGPointMake(rk.location.x, rk.location.y) first:CGPointMake(rh.location.x, rh.location.y) second:CGPointMake(ra.location.x, ra.location.y)] : NAN;
    BOOL torsoValid = ls.confidence > .1 && rs.confidence > .1 && lh.confidence > .1 && rh.confidence > .1;
    double torso = NAN;
    if (torsoValid) {
        CGPoint hips = CGPointMake((lh.location.x + rh.location.x) / 2.0, (lh.location.y + rh.location.y) / 2.0);
        CGPoint shoulders = CGPointMake((ls.location.x + rs.location.x) / 2.0, (ls.location.y + rs.location.y) / 2.0);
        torso = ClampAngle(atan2(fabs(shoulders.x - hips.x), fabs(shoulders.y - hips.y)) * 180.0 / M_PI);
    }
    double averageKnee = (leftValid && rightValid) ? (leftKnee + rightKnee) / 2.0 : (leftValid ? leftKnee : (rightValid ? rightKnee : NAN));
    double absorption = isfinite(averageKnee) ? MAX(0.0, MIN(100.0, (180.0 - averageKnee) / 90.0 * 100.0)) : NAN;
    NSMutableDictionary *result = [@{ @"timestamp": @(timestamp), @"joints": joints } mutableCopy];
    if (isfinite(leftKnee)) result[@"leftKneeAngle"] = @(leftKnee);
    if (isfinite(rightKnee)) result[@"rightKneeAngle"] = @(rightKnee);
    if (isfinite(torso)) result[@"torsoVerticalAngle"] = @(torso);
    if (isfinite(absorption)) result[@"absorption"] = @(absorption);
    return result;
}
@end
