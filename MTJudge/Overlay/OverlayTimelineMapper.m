#import "OverlayTimelineMapper.h"

static NSError *TimelineError(NSString *message) { return [NSError errorWithDomain:@"MTJudge.OverlayTimeline" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
static BOOL Number(id n) { return [n isKindOfClass:NSNumber.class]&&isfinite([n doubleValue]); }
static CMTime PTS(double seconds) { return CMTimeMakeWithSeconds(seconds,60000); }
@implementation OverlayTimelineMapper
- (instancetype)initWithAnchors:(NSArray *)anchors mainDuration:(double)mainDuration subDuration:(double)subDuration error:(NSError **)error {
    if(!(self=[super init])) return nil;
    NSString *failure=nil;
    if(!isfinite(mainDuration)||!isfinite(subDuration)||mainDuration<=0||subDuration<=0) failure=@"原動画の長さが不正です";
    if(![anchors isKindOfClass:NSArray.class]||anchors.count<2) failure=@"同じ目印の通過位置を2組以上登録してください";
    NSMutableArray *validated=[NSMutableArray array]; double pm=-1,ps=-1;
    if(!failure) for(id anchor in anchors) {
        if(![anchor isKindOfClass:NSDictionary.class]||!Number(anchor[@"mainTime"])||!Number(anchor[@"subTime"])) { failure=@"通過位置の時刻が不正です"; break; }
        if(anchor[@"confirmed"]&&![anchor[@"confirmed"] boolValue]) { failure=@"自動候補は内容を確認してから登録してください"; break; }
        double m=[anchor[@"mainTime"] doubleValue],s=[anchor[@"subTime"] doubleValue];
        if(m<0||s<0||m>mainDuration||s>subDuration||m<=pm||s<=ps) { failure=@"2動画の通過順序が一致しません。重複・逆順・動画範囲外の位置を修正してください"; break; }
        if(pm>=0) {
            double rate=(s-ps)/(m-pm);
            if(m-pm<.04||s-ps<.04||rate<.1||rate>5) { failure=@"通過位置が近すぎるか、区間の速度差が大きすぎます（対応倍率0.1〜5）"; break; }
        }
        NSMutableDictionary *copy=[anchor mutableCopy];
        copy[@"coursePosition"]=@((double)validated.count/(anchors.count-1));
        copy[@"mainPTS"]=@{@"value":@(PTS(m).value),@"timescale":@60000}; copy[@"subPTS"]=@{@"value":@(PTS(s).value),@"timescale":@60000};
        [validated addObject:copy]; pm=m; ps=s;
    }
    if(failure) { if(error) *error=TimelineError(failure); return nil; }
    _anchors=[validated copy]; _mainStart=[_anchors.firstObject[@"mainTime"] doubleValue]; _mainEnd=[_anchors.lastObject[@"mainTime"] doubleValue]; return self;
}
- (NSInteger)segmentForTime:(double)time key:(NSString *)key {
    if(!isfinite(time)||time<[self.anchors.firstObject[key] doubleValue]-1e-7||time>[self.anchors.lastObject[key] doubleValue]+1e-7) return NSNotFound;
    for(NSUInteger i=1;i<self.anchors.count;i++) if(time<[self.anchors[i][key] doubleValue]-1e-8) return (NSInteger)i-1;
    return (NSInteger)self.anchors.count-2;
}
- (double)map:(double)time from:(NSString *)from to:(NSString *)to {
    NSInteger i=[self segmentForTime:time key:from]; if(i==NSNotFound) return NAN;
    NSDictionary *a=self.anchors[i],*b=self.anchors[i+1];
    double f=(time-[a[from] doubleValue])/([b[from] doubleValue]-[a[from] doubleValue]);
    return [a[to] doubleValue]+f*([b[to] doubleValue]-[a[to] doubleValue]);
}
- (double)subTimeForMainTime:(double)mainTime { return [self map:mainTime from:@"mainTime" to:@"subTime"]; }
- (double)mainTimeForSubTime:(double)subTime { return [self map:subTime from:@"subTime" to:@"mainTime"]; }
- (double)subRateForMainTime:(double)mainTime {
    NSInteger i=[self segmentForTime:mainTime key:@"mainTime"]; if(i==NSNotFound) return NAN;
    NSDictionary *a=self.anchors[i],*b=self.anchors[i+1];
    return ([b[@"subTime"] doubleValue]-[a[@"subTime"] doubleValue])/([b[@"mainTime"] doubleValue]-[a[@"mainTime"] doubleValue]);
}
- (AVMutableComposition *)compositionForSubURL:(NSURL *)url error:(NSError **)error {
    // AVAssetTrack.asset is weak; keep its owning asset alive through every insertion.
    AVAsset * __attribute__((objc_precise_lifetime)) asset=[AVAsset assetWithURL:url];
    AVAssetTrack *source=[asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if(!source) { if(error) *error=TimelineError(@"練習動画の映像を読み込めません"); return nil; }
    AVMutableComposition *composition=[AVMutableComposition composition];
    AVMutableCompositionTrack *track=[composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    track.preferredTransform=source.preferredTransform;
    for(NSUInteger i=1;i<self.anchors.count;i++) {
        NSDictionary *a=self.anchors[i-1],*b=self.anchors[i];
        CMTime from=PTS([a[@"subTime"] doubleValue]),to=PTS([b[@"subTime"] doubleValue]);
        CMTime at=CMTimeSubtract(PTS([a[@"mainTime"] doubleValue]),PTS(self.mainStart));
        CMTime length=CMTimeSubtract(PTS([b[@"mainTime"] doubleValue]),PTS([a[@"mainTime"] doubleValue]));
        CMTime sourceLength=CMTimeSubtract(to,from);
        if(![track insertTimeRange:CMTimeRangeMake(from,sourceLength) ofTrack:source atTime:at error:error]) return nil;
        [track scaleTimeRange:CMTimeRangeMake(at,sourceLength) toDuration:length];
    }
    return composition;
}

static BOOL CoursePoint(id value) { return [value isKindOfClass:NSArray.class]&&[value count]==2&&Number(value[0])&&Number(value[1]); }
static NSDictionary *Crossing(NSArray *points,NSString *pointKey,NSString *timeKey,double level,CGPoint origin,CGVector direction) {
    NSDictionary *previous=nil;
    for(NSDictionary *frame in points) {
        if(!CoursePoint(frame[pointKey])) { previous=nil; continue; }
        NSArray *p=frame[pointKey];
        double v=([p[0] doubleValue]-origin.x)*direction.dx+([p[1] doubleValue]-origin.y)*direction.dy;
        if(previous) {
            NSArray *q=previous[pointKey]; double u=([q[0] doubleValue]-origin.x)*direction.dx+([q[1] doubleValue]-origin.y)*direction.dy;
            double dt=[frame[timeKey] doubleValue]-[previous[timeKey] doubleValue];
            // Do not bridge missing observations, a camera tracking reset, or a backwards crossing.
            BOOL adjacent=!Number(frame[@"courseSampleIndex"])||!Number(previous[@"courseSampleIndex"])||[frame[@"courseSampleIndex"] integerValue]==[previous[@"courseSampleIndex"] integerValue]+1;
            if(adjacent&&dt>0&&dt<=.25&&v>u+.0001&&u<=level&&v>=level&&v-u<.15) {
                double f=(level-u)/(v-u);
                double x=[q[0] doubleValue]+f*([p[0] doubleValue]-[q[0] doubleValue]);
                double y=[q[1] doubleValue]+f*([p[1] doubleValue]-[q[1] doubleValue]);
                return @{@"time":@([previous[timeKey] doubleValue]+f*dt),@"perpendicular":@(-(x-origin.x)*direction.dy+(y-origin.y)*direction.dx)};
            }
        }
        previous=frame;
    }
    return nil;
}
+ (NSArray<NSDictionary *> *)suggestionsFromFrames:(NSArray<NSDictionary *> *)frames {
    NSMutableDictionary<NSNumber *,NSMutableArray *> *segments=[NSMutableDictionary dictionary];
    for(NSDictionary *frame in frames) if([frame[@"valid"] boolValue]&&Number(frame[@"courseSegment"])&&CoursePoint(frame[@"mainCoursePoint"])&&CoursePoint(frame[@"subCoursePoint"])) {
        NSNumber *key=frame[@"courseSegment"]; if(!segments[key]) segments[key]=[NSMutableArray array]; [segments[key] addObject:frame];
    }
    NSMutableArray *candidates=[NSMutableArray array];
    for(NSNumber *segment in [segments.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSArray *points=segments[segment]; if(points.count<8) continue;
        NSArray *first=points.firstObject[@"mainCoursePoint"],*last=points.lastObject[@"mainCoursePoint"];
        CGPoint origin=CGPointMake([first[0] doubleValue],[first[1] doubleValue]);
        CGVector d=CGVectorMake([last[0] doubleValue]-origin.x,[last[1] doubleValue]-origin.y); double length=hypot(d.dx,d.dy);
        if(length<.08) continue; d.dx/=length; d.dy/=length;
        double minM=DBL_MAX,maxM=-DBL_MAX,minS=DBL_MAX,maxS=-DBL_MAX;
        for(NSDictionary *f in points) for(NSString *role in @[@"main",@"sub"]) {
            NSArray *p=f[[role stringByAppendingString:@"CoursePoint"]]; double v=([p[0] doubleValue]-origin.x)*d.dx+([p[1] doubleValue]-origin.y)*d.dy;
            if([role isEqual:@"main"]) { minM=MIN(minM,v);maxM=MAX(maxM,v); } else { minS=MIN(minS,v);maxS=MAX(maxS,v); }
        }
        double lower=MAX(minM,minS),upper=MIN(maxM,maxS); if(upper-lower<.08) continue;
        for(int n=1;n<=3;n++) {
            double level=lower+(upper-lower)*n/4;
            NSDictionary *m=Crossing(points,@"mainCoursePoint",@"mainTime",level,origin,d),*s=Crossing(points,@"subCoursePoint",@"subTime",level,origin,d);
            if(!m||!s||fabs([m[@"perpendicular"] doubleValue]-[s[@"perpendicular"] doubleValue])>.12) continue;
            [candidates addObject:@{@"mainTime":m[@"time"],@"subTime":s[@"time"],@"origin":@"backgroundTrackedCandidate",@"confirmed":@NO,@"trackingSegment":segment,@"gatePosition":@(level),@"gateOrigin":@[@(origin.x),@(origin.y)],@"gateDirection":@[@(d.dx),@(d.dy)]}];
        }
    }
    [candidates sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) { return [a[@"mainTime"] compare:b[@"mainTime"]]; }];
    NSMutableArray *ordered=[NSMutableArray array]; double previousMain=-1,previousSub=-1;
    for(NSDictionary *candidate in candidates) {
        double m=[candidate[@"mainTime"] doubleValue],s=[candidate[@"subTime"] doubleValue];
        if(m>previousMain+.04&&s>previousSub+.04) { [ordered addObject:candidate];previousMain=m;previousSub=s; }
    }
    return ordered;
}
@end
