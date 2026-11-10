#import "OverlayAnalysis.h"
#import "OverlayRegistration.h"
#import "OverlayTimelineMapper.h"
#import "../SkeletonConnections.h"
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>

static NSError *AnalysisError(NSString *message) { return [NSError errorWithDomain:@"MTJudge.Overlay" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
static NSDictionary *SubjectData(CGImageRef image, CGPoint target, CIContext *context) {
    VNGeneratePersonSegmentationRequest *seg=[VNGeneratePersonSegmentationRequest new];
    seg.qualityLevel=VNGeneratePersonSegmentationRequestQualityLevelBalanced; seg.outputPixelFormat=kCVPixelFormatType_OneComponent8;
    VNDetectHumanBodyPoseRequest *pose=[VNDetectHumanBodyPoseRequest new];
    VNDetectHumanRectanglesRequest *rectangles=[VNDetectHumanRectanglesRequest new];
    VNImageRequestHandler *handler=[[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
    NSError *error=nil; [handler performRequests:@[seg,pose,rectangles] error:&error];
    VNPixelBufferObservation *observation=seg.results.firstObject;
    CIImage *mask=observation?[CIImage imageWithCVPixelBuffer:observation.pixelBuffer]:nil;
    NSMutableDictionary *joints=[NSMutableDictionary dictionary];
    VNHumanBodyPoseObservation *selected=nil; double best=-DBL_MAX; CGRect chosen=CGRectNull;
    for(VNHumanBodyPoseObservation *body in pose.results) {
        NSDictionary *points=[body recognizedPointsForGroupKey:VNHumanBodyPoseObservationJointsGroupNameAll error:nil];
        CGRect rect=CGRectNull;
        for(VNRecognizedPoint *p in points.allValues) if(p.confidence>.15) {
            CGRect r=CGRectMake(p.location.x,1-p.location.y,.001,.001); rect=CGRectIsNull(rect)?r:CGRectUnion(rect,r);
        }
        if(CGRectIsNull(rect)) continue;
        double distance=hypot(CGRectGetMidX(rect)-target.x,CGRectGetMidY(rect)-target.y);
        double score=rect.size.width*rect.size.height-distance*.25;
        if(score>best) { best=score; selected=body; chosen=rect; }
    }
    if(selected) {
        NSDictionary *points=[selected recognizedPointsForGroupKey:VNHumanBodyPoseObservationJointsGroupNameAll error:nil];
        for(NSString *key in points) { VNRecognizedPoint *p=points[key]; if(p.confidence>.15) joints[key]=@{@"x":@(p.location.x),@"y":@(1-p.location.y),@"confidence":@(p.confidence)}; }
    }
    NSMutableDictionary *result=[@{@"joints":joints} mutableCopy];
    CGSize size=CGSizeMake(CGImageGetWidth(image),CGImageGetHeight(image));
    CGRect full=CGRectMake(0,0,size.width,size.height);
    CIImage *excluded=[[CIImage imageWithColor:CIColor.blackColor] imageByCroppingToRect:full];
    for(VNHumanObservation *human in rectangles.results) {
        CGRect box=CGRectInset(human.boundingBox,-.04,-.04);
        CGRect pixels=CGRectMake(box.origin.x*size.width,box.origin.y*size.height,box.size.width*size.width,box.size.height*size.height);
        CIImage *white=[[CIImage imageWithColor:CIColor.whiteColor] imageByCroppingToRect:pixels];
        excluded=[white imageByCompositingOverImage:excluded];
    }
    if(!CGRectIsNull(chosen)) result[@"subjectCenter"]=@[@(CGRectGetMidX(chosen)),@(CGRectGetMidY(chosen))];
    if(mask) {
        mask=[mask imageByApplyingTransform:CGAffineTransformMakeScale(size.width/mask.extent.size.width,size.height/mask.extent.size.height)];
        CIImage *combined=[mask imageByApplyingFilter:@"CIMaximumCompositing" withInputParameters:@{kCIInputBackgroundImageKey:excluded}];
        CGImageRef all=[context createCGImage:combined fromRect:full];
        if(all) { result[@"backgroundMask"]=(__bridge id)all; CGImageRelease(all); }
        if(!CGRectIsNull(chosen)) {
            // Keep board/poles near the selected body; all people remain excluded from registration.
            chosen=CGRectIntersection(CGRectMake(0,0,1,1),CGRectInset(chosen,-.10,-.10));
            CGRect crop=CGRectMake(chosen.origin.x*size.width,(1-CGRectGetMaxY(chosen))*size.height,chosen.size.width*size.width,chosen.size.height*size.height);
            CIImage *subject=[mask imageByCroppingToRect:crop];
            CIImage *black=[[CIImage imageWithColor:CIColor.blackColor] imageByCroppingToRect:CGRectMake(0,0,size.width,size.height)];
            subject=[subject imageByCompositingOverImage:black];
            CGImageRef cut=[context createCGImage:subject fromRect:black.extent];
            if(cut) { result[@"subjectMask"]=(__bridge id)cut; CGImageRelease(cut); }
        }
    } else if(rectangles.results.count) {
        CGImageRef all=[context createCGImage:excluded fromRect:full];
        if(all) { result[@"backgroundMask"]=(__bridge id)all; CGImageRelease(all); }
    }
    return result;
}
static CGPoint CourseContact(NSDictionary *joints) {
    NSDictionary *l=joints[VNHumanBodyPoseObservationJointNameLeftAnkle],*r=joints[VNHumanBodyPoseObservationJointNameRightAnkle];
    if([l[@"confidence"] doubleValue]<.3||[r[@"confidence"] doubleValue]<.3) return CGPointMake(NAN,NAN);
    return CGPointMake(([l[@"x"] doubleValue]+[r[@"x"] doubleValue])*.5,([l[@"y"] doubleValue]+[r[@"y"] doubleValue])*.5);
}

@implementation OverlayAnalysis
- (void)analyzeMain:(NSURL *)mainURL sub:(NSURL *)subURL mainStart:(double)mainStart subStart:(double)subStart duration:(double)duration mainSubject:(CGPoint)mainSubject subSubject:(CGPoint)subSubject cacheDirectory:(NSURL *)cacheDirectory progress:(void (^)(double))progress completion:(void (^)(NSArray<NSDictionary *> * _Nullable,NSError * _Nullable))completion {
    [self analyzeMain:mainURL sub:subURL mainStart:mainStart subStart:subStart duration:duration mainSubject:mainSubject subSubject:subSubject timeline:nil cacheDirectory:cacheDirectory progress:progress completion:completion];
}
- (void)analyzeMain:(NSURL *)mainURL sub:(NSURL *)subURL mainStart:(double)mainStart subStart:(double)subStart duration:(double)duration mainSubject:(CGPoint)mainSubject subSubject:(CGPoint)subSubject timeline:(OverlayTimelineMapper *)timeline cacheDirectory:(NSURL *)cacheDirectory progress:(void (^)(double))progress completion:(void (^)(NSArray<NSDictionary *> * _Nullable,NSError * _Nullable))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        @autoreleasepool {
            AVAssetImageGenerator *mg=[[AVAssetImageGenerator alloc] initWithAsset:[AVAsset assetWithURL:mainURL]];
            AVAssetImageGenerator *sg=[[AVAssetImageGenerator alloc] initWithAsset:[AVAsset assetWithURL:subURL]];
            for(AVAssetImageGenerator *g in @[mg,sg]) { g.appliesPreferredTrackTransform=YES; g.maximumSize=CGSizeMake(640,640); g.requestedTimeToleranceBefore=kCMTimeZero; g.requestedTimeToleranceAfter=kCMTimeZero; }
            CIContext *context=[CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}];
            OverlayRegistration *registration=[OverlayRegistration new]; NSMutableArray *frames=[NSMutableArray array];
            id previousMain=nil,previousSub=nil,previousMMask=nil,previousSMask=nil;
            simd_double3x3 previousH=matrix_identity_double3x3,mainToReference=matrix_identity_double3x3; BOOL previousValid=NO;
            id referenceMain=nil,referenceMask=nil; NSInteger courseSegment=0;
            NSError *failure=nil; NSInteger total=MAX(1,(NSInteger)ceil(duration*30));
            // Each run gets a namespace. Cancellation never overwrites masks used by a saved session.
            NSURL *run=[cacheDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
            [NSFileManager.defaultManager createDirectoryAtURL:run withIntermediateDirectories:YES attributes:nil error:&failure];
            if(failure) total=0;
            CGPoint currentMainSubject=mainSubject,currentSubSubject=subSubject;
            for(NSInteger i=0;i<total && !self.cancelled;i++) { @autoreleasepool {
                if(NSProcessInfo.processInfo.thermalState>=NSProcessInfoThermalStateSerious) { failure=AnalysisError(@"端末が高温のため解析を中止しました。冷却後に再試行してください"); break; }
                double delta=i/30.0; CMTime mt=kCMTimeInvalid,st=kCMTimeInvalid;
                CGImageRef m=[mg copyCGImageAtTime:CMTimeMakeWithSeconds(mainStart+delta,60000) actualTime:&mt error:&failure];
                double decodedMain=CMTimeGetSeconds(mt);
                double subTime=timeline?[timeline subTimeForMainTime:decodedMain]:subStart+decodedMain-mainStart;
                if(m&&!isfinite(subTime)) { CGImageRelease(m); continue; }
                CGImageRef s=m?[sg copyCGImageAtTime:CMTimeMakeWithSeconds(subTime,60000) actualTime:&st error:&failure]:nil;
                if(!m||!s) { if(m) CGImageRelease(m); if(s) CGImageRelease(s); break; }
                NSDictionary *md=SubjectData(m,currentMainSubject,context), *sd=SubjectData(s,currentSubSubject,context);
                NSArray *mc=md[@"subjectCenter"],*sc=sd[@"subjectCenter"];
                if(mc) currentMainSubject=CGPointMake([mc[0] doubleValue],[mc[1] doubleValue]);
                if(sc) currentSubSubject=CGPointMake([sc[0] doubleValue],[sc[1] doubleValue]);
                CGImageRef mm=(__bridge CGImageRef)md[@"backgroundMask"], sm=(__bridge CGImageRef)sd[@"backgroundMask"];
                NSDictionary *tm=previousMain?[registration trackFrom:(__bridge CGImageRef)previousMain to:m previousMask:(__bridge CGImageRef)previousMMask currentMask:mm]:nil;
                NSDictionary *fit=nil;
                if(previousValid && i%15!=0) {
                    NSDictionary *ts=[registration trackFrom:(__bridge CGImageRef)previousSub to:s previousMask:(__bridge CGImageRef)previousSMask currentMask:sm];
                    if([tm[@"valid"] boolValue]&&[ts[@"valid"] boolValue]) {
                        simd_double3x3 h=simd_mul(simd_mul(MTJOverlayMatrix(tm[@"matrix"]),previousH),simd_inverse(MTJOverlayMatrix(ts[@"matrix"])));
                        if(MTJOverlayMatrixIsValid(h)) fit=@{@"valid":@YES,@"matrix":MTJOverlayMatrixArray(h),@"method":@"LK/RANSAC",@"errorPixels":@(MAX([tm[@"errorPixels"] doubleValue],[ts[@"errorPixels"] doubleValue]))};
                    }
                }
                if(!fit) fit=[registration registerMain:m sub:s mainMask:mm subMask:sm];
                if(referenceMain && [tm[@"valid"] boolValue]) {
                    mainToReference=simd_mul(mainToReference,simd_inverse(MTJOverlayMatrix(tm[@"matrix"])));
                    if(i%15==0) {
                        NSDictionary *reanchor=[registration registerMain:(__bridge CGImageRef)referenceMain sub:m mainMask:(__bridge CGImageRef)referenceMask subMask:mm];
                        if([reanchor[@"valid"] boolValue]) mainToReference=MTJOverlayMatrix(reanchor[@"matrix"]);
                    }
                } else {
                    if(referenceMain) courseSegment++;
                    referenceMain=(__bridge id)m; referenceMask=md[@"backgroundMask"]; mainToReference=matrix_identity_double3x3;
                }
                NSMutableDictionary *frame=[fit mutableCopy];
                frame[@"mainTime"]=@(CMTimeGetSeconds(mt)); frame[@"subTime"]=@(CMTimeGetSeconds(st)); frame[@"courseSampleIndex"]=@(i);
                frame[@"mainPTS"]=@{@"value":@(mt.value),@"timescale":@(mt.timescale)};
                frame[@"subPTS"]=@{@"value":@(st.value),@"timescale":@(st.timescale)};
                frame[@"mainSize"]=@[@(CGImageGetWidth(m)),@(CGImageGetHeight(m))]; frame[@"subSize"]=@[@(CGImageGetWidth(s)),@(CGImageGetHeight(s))];
                frame[@"mainJoints"]=md[@"joints"]; frame[@"subJoints"]=sd[@"joints"];
                if([fit[@"valid"] boolValue]&&MTJOverlayMatrixIsValid(mainToReference)) {
                    CGPoint mp=CourseContact(md[@"joints"]),sp=CourseContact(sd[@"joints"]);
                    if(isfinite(mp.x)&&isfinite(sp.x)) {
                        mp=MTJOverlayProject(mainToReference,mp); sp=MTJOverlayProject(simd_mul(mainToReference,MTJOverlayMatrix(fit[@"matrix"])),sp);
                        if(isfinite(mp.x)&&isfinite(mp.y)&&isfinite(sp.x)&&isfinite(sp.y)) {
                            frame[@"mainCoursePoint"]=@[@(mp.x),@(mp.y)]; frame[@"subCoursePoint"]=@[@(sp.x),@(sp.y)]; frame[@"courseSegment"]=@(courseSegment);
                        }
                    }
                }

                for(NSString *role in @[@"main",@"sub"]) {
                    NSDictionary *data=[role isEqual:@"main"]?md:sd;
                    CGImageRef mask=(__bridge CGImageRef)data[@"subjectMask"];
                    if(mask) {
                        NSString *name=[NSString stringWithFormat:@"%@-%ld.png",role,(long)i]; NSURL *url=[run URLByAppendingPathComponent:name];
                        NSData *png=UIImagePNGRepresentation([UIImage imageWithCGImage:mask]); NSError *writeError=nil;
                        if(!png || ![png writeToURL:url options:NSDataWritingAtomic error:&writeError]) { failure=writeError?:AnalysisError(@"人物マスクを保存できません"); break; }
                        frame[[role stringByAppendingString:@"Mask"]]=[run.lastPathComponent stringByAppendingPathComponent:name];
                    }
                }
                previousValid=[fit[@"valid"] boolValue]; if(previousValid) previousH=MTJOverlayMatrix(fit[@"matrix"]);
                previousMain=(__bridge id)m; previousSub=(__bridge id)s; previousMMask=md[@"backgroundMask"]; previousSMask=sd[@"backgroundMask"];
                CGImageRelease(m); CGImageRelease(s); if(failure) break;
                [frames addObject:frame];
                dispatch_async(dispatch_get_main_queue(), ^{ if(!self.cancelled) progress((i+1)/(double)total); });
            } }
            if(self.cancelled||failure||!frames.count) {
                [NSFileManager.defaultManager removeItemAtURL:run error:nil];
                if(!failure) failure=AnalysisError(self.cancelled?@"解析を中止しました":@"解析できるフレームがありません");
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(failure?nil:frames,failure); });
        }
    });
}
@end
