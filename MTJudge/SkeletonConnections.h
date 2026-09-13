#import <Vision/Vision.h>

static inline NSArray<NSArray<NSString *> *> *SkeletonConnections(void) {
    return @[
        // 胴体
        @[VNHumanBodyPoseObservationJointNameNeck, VNHumanBodyPoseObservationJointNameRightShoulder],
        @[VNHumanBodyPoseObservationJointNameNeck, VNHumanBodyPoseObservationJointNameLeftShoulder],
        @[VNHumanBodyPoseObservationJointNameRightShoulder, VNHumanBodyPoseObservationJointNameRightHip],
        @[VNHumanBodyPoseObservationJointNameLeftShoulder, VNHumanBodyPoseObservationJointNameLeftHip],
        @[VNHumanBodyPoseObservationJointNameRightHip, VNHumanBodyPoseObservationJointNameLeftHip],
        
        // 右腕
        @[VNHumanBodyPoseObservationJointNameRightShoulder, VNHumanBodyPoseObservationJointNameRightElbow],
        @[VNHumanBodyPoseObservationJointNameRightElbow, VNHumanBodyPoseObservationJointNameRightWrist],
        
        // 左腕
        @[VNHumanBodyPoseObservationJointNameLeftShoulder, VNHumanBodyPoseObservationJointNameLeftElbow],
        @[VNHumanBodyPoseObservationJointNameLeftElbow, VNHumanBodyPoseObservationJointNameLeftWrist],
        
        // 右足
        @[VNHumanBodyPoseObservationJointNameRightHip, VNHumanBodyPoseObservationJointNameRightKnee],
        @[VNHumanBodyPoseObservationJointNameRightKnee, VNHumanBodyPoseObservationJointNameRightAnkle],
        
        // 左足
        @[VNHumanBodyPoseObservationJointNameLeftHip, VNHumanBodyPoseObservationJointNameLeftKnee],
        @[VNHumanBodyPoseObservationJointNameLeftKnee, VNHumanBodyPoseObservationJointNameLeftAnkle]
    ];
}
