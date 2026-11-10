#import "VideoOverlayViewController.h"
#import "OverlayMetalView.h"
#import "OverlayAnalysis.h"
#import "OverlaySessionStore.h"
#import "OverlayAnnotationAdapter.h"
#import "OverlayTimelineMapper.h"
#import <AVFoundation/AVFoundation.h>

static double Seconds(CMTime t) { double s=CMTimeGetSeconds(t); return isfinite(s)?s:0; }
static CMTime Time(double seconds) { return CMTimeMakeWithSeconds(seconds,60000); }
static simd_double3x3 Translation(double x,double y) { simd_double3x3 m=matrix_identity_double3x3; m.columns[2]=(simd_double3){x,y,1}; return m; }
static simd_double3x3 CenterTransform(double scale,double angle) {
    simd_double3x3 m=matrix_identity_double3x3; double c=cos(angle)*scale,s=sin(angle)*scale;
    m.columns[0]=(simd_double3){c,s,0}; m.columns[1]=(simd_double3){-s,c,0};
    return simd_mul(simd_mul(Translation(.5,.5),m),Translation(-.5,-.5));
}

@interface OverlaySketch : UIView
@property NSMutableArray<NSDictionary *> *strokes;
@property CGRect videoRect;
@property double time;
@property BOOL enabled;
@property(copy) void (^changed)(void);
@end
@implementation OverlaySketch { NSMutableArray *_points; }
- (instancetype)initWithFrame:(CGRect)frame { if((self=[super initWithFrame:frame])) { self.backgroundColor=UIColor.clearColor; _strokes=[NSMutableArray array]; self.userInteractionEnabled=NO; } return self; }
- (NSArray *)point:(UITouch *)touch {
    CGPoint p=[touch locationInView:self]; CGRect r=self.videoRect;
    return @[@(MAX(0,MIN(1,(p.x-r.origin.x)/MAX(1,r.size.width)))),@(MAX(0,MIN(1,(p.y-r.origin.y)/MAX(1,r.size.height))))];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { if(!self.enabled||!CGRectContainsPoint(self.videoRect,[touches.anyObject locationInView:self])) return; _points=[NSMutableArray arrayWithObject:[self point:touches.anyObject]]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { if(_points) { [_points addObject:[self point:touches.anyObject]]; [self setNeedsDisplay]; } }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if(!_points) return; [_points addObject:[self point:touches.anyObject]];
    [self.strokes addObject:@{@"points":[_points copy],@"start":@(self.time),@"coordinateSystem":@"comparison-main-normalized"}]; _points=nil; [self setNeedsDisplay]; if(self.changed) self.changed();
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { _points=nil; [self setNeedsDisplay]; }
- (void)drawPoints:(NSArray *)points context:(CGContextRef)c {
    BOOL first=YES; for(NSArray *p in points) { CGPoint v=CGPointMake(self.videoRect.origin.x+[p[0] doubleValue]*self.videoRect.size.width,self.videoRect.origin.y+[p[1] doubleValue]*self.videoRect.size.height); if(first) CGContextMoveToPoint(c,v.x,v.y); else CGContextAddLineToPoint(c,v.x,v.y); first=NO; } CGContextStrokePath(c);
}
- (void)drawRect:(CGRect)rect {
    CGContextRef c=UIGraphicsGetCurrentContext(); CGContextClipToRect(c,self.videoRect); CGContextSetStrokeColorWithColor(c,UIColor.systemYellowColor.CGColor); CGContextSetLineWidth(c,3);
    for(NSDictionary *stroke in self.strokes) if(self.time+.03>=[stroke[@"start"] doubleValue]) [self drawPoints:stroke[@"points"] context:c];
    if(_points) [self drawPoints:_points context:c];
}
@end

@interface OverlayDisplayTarget : NSObject
@property(weak) id owner;
- (void)tick:(CADisplayLink *)link;
@end

@interface VideoOverlayViewController () <UIGestureRecognizerDelegate>
@property NSURL *mainURL;
@property NSURL *subURL;
@property AVPlayer *mainPlayer;
@property AVPlayer *subPlayer;
@property AVPlayerItemVideoOutput *mainOutput;
@property AVPlayerItemVideoOutput *subOutput;
@property AVAssetTrack *mainTrack;
@property AVAssetTrack *subTrack;
@property OverlayMetalView *metalView;
@property OverlaySketch *sketch;
@property OverlayAnnotationAdapter *mainAnnotations;
@property OverlayAnnotationAdapter *subAnnotations;
@property OverlaySessionStore *store;
@property OverlayAnalysis *analysis;
@property CADisplayLink *displayLink;
@property UILabel *statusLabel;
@property UILabel *timeLabel;
@property UILabel *titleLabel;
@property UISlider *mainSlider;
@property UISlider *subSlider;
@property UISlider *opacitySlider;
@property UISlider *speedSlider;
@property UISegmentedControl *blendControl;
@property UIButton *playButton;
@property UIButton *linkButton;
@property UIButton *analysisButton;
@property UIButton *modeButton;
@property UIButton *skeletonButton;
@property UIButton *drawingButton;
@property UIButton *sketchButton;
@property UIStackView *controls;
@property UIScrollView *scrollView;
@property NSLayoutConstraint *controlsHeight;
@property CIImage *mainImage;
@property CIImage *subImage;
@property NSArray<NSDictionary *> *frames;
@property NSDictionary *activeFrame;
@property NSMutableArray *manualHistory;
@property simd_double3x3 manualMatrix;
@property simd_double3x3 gestureMatrix;
@property double mainAnchor;
@property double subAnchor;
@property double mainDuration;
@property double subDuration;
@property double loopStart;
@property double loopEnd;
@property double requestedMain;
@property double requestedSub;
@property BOOL linked;
@property BOOL useAutomatic;
@property BOOL skeletonVisible;
@property BOOL drawingsVisible;
@property BOOL loopEnabled;
@property BOOL seeking;
@property BOOL playing;
@property BOOL prepared;
@property BOOL closed;
@property BOOL restored;
@property NSUInteger seekGeneration;
@property NSUInteger analysisGeneration;
@property double prepareDeadline;
@property double lastRenderTime;
@property double playbackScheduledUntil;
@property CGSize lastViewportSize;
@property CGFloat lastViewportScale;
@property NSInteger calibrationStep;
@property NSMutableArray<NSValue *> *subPoints;
@property NSMutableArray<NSValue *> *mainPoints;
@property CGPoint mainSubject;
@property CGPoint subSubject;
@property NSString *maskName;
@property CIImage *maskImage;
@property BOOL dirty;
@property UISegmentedControl *syncControl;
@property UILabel *courseLabel;
@property NSMutableArray<NSDictionary *> *courseAnchors;
@property OverlayTimelineMapper *courseMapper;
@property AVAsset *originalSubAsset;
@property BOOL courseMode;
@property BOOL switchingTimeline;
@property BOOL pendingRestoreCourse;
@property NSUInteger timelineGeneration;
@property NSDictionary *pendingCandidate;
@property BOOL restoringTimeline;
@property NSArray *restoredCourseFrames;
@property BOOL restoredCourseAutomatic;
@end

@implementation OverlayDisplayTarget
- (void)tick:(CADisplayLink *)link { [self.owner tick:link]; }
@end

@implementation VideoOverlayViewController
- (instancetype)initWithMainURL:(NSURL *)mainURL subURL:(NSURL *)subURL {
    if((self=[super init])) {
        _mainURL=mainURL; _subURL=subURL; _manualMatrix=matrix_identity_double3x3; _manualHistory=[NSMutableArray array];
        _courseAnchors=[NSMutableArray array];
        _linked=YES; _loopStart=NAN; _loopEnd=NAN; _mainSubject=CGPointMake(.5,.5); _subSubject=CGPointMake(.5,.5);
        self.modalPresentationStyle=UIModalPresentationFullScreen;
    } return self;
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; [b setTitle:title forState:UIControlStateNormal]; b.tintColor=UIColor.whiteColor;
    b.backgroundColor=[UIColor colorWithWhite:.16 alpha:1]; b.layer.cornerRadius=7; b.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    UIButtonConfiguration *config=[UIButtonConfiguration plainButtonConfiguration]; config.contentInsets=NSDirectionalEdgeInsetsMake(9,10,9,10); b.configuration=config; [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return b;
}
- (UIStackView *)row:(NSArray *)views {
    UIStackView *s=[[UIStackView alloc] initWithArrangedSubviews:views]; s.axis=UILayoutConstraintAxisHorizontal; s.spacing=8; s.alignment=UIStackViewAlignmentCenter; s.distribution=UIStackViewDistributionFill;
    for(UIView *v in views) [v setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal]; return s;
}
- (UISlider *)slider:(SEL)action min:(float)minimum max:(float)maximum value:(float)value {
    UISlider *s=[UISlider new]; s.minimumValue=minimum; s.maximumValue=maximum; s.value=value; [s addTarget:self action:action forControlEvents:UIControlEventValueChanged]; return s;
}
- (UILabel *)label:(NSString *)text { UILabel *l=[UILabel new]; l.text=text; l.textColor=UIColor.whiteColor; l.font=[UIFont systemFontOfSize:12]; return l; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=UIColor.blackColor;
    self.titleLabel=[self label:@"AI動画重ね合わせ比較"]; self.titleLabel.font=[UIFont boldSystemFontOfSize:17];
    UIStackView *header=[self row:@[[self button:@"閉じる" action:@selector(close)],self.titleLabel,[self button:@"保存" action:@selector(saveTapped)]]];
    self.statusLabel=[self label:@"動画を準備しています…"]; self.statusLabel.numberOfLines=2;
    self.metalView=[[OverlayMetalView alloc] initWithFrame:CGRectZero]; self.metalView.userInteractionEnabled=YES;
    self.sketch=[[OverlaySketch alloc] initWithFrame:CGRectZero]; [self.metalView addSubview:self.sketch];
    self.scrollView=[UIScrollView new]; self.scrollView.alwaysBounceVertical=YES;
    self.controls=[UIStackView new]; self.controls.axis=UILayoutConstraintAxisVertical; self.controls.spacing=9;
    [self.scrollView addSubview:self.controls];
    self.mainSlider=[self slider:@selector(positionChanged:) min:0 max:1 value:0]; self.mainSlider.accessibilityLabel=@"お手本動画の再生位置";
    self.subSlider=[self slider:@selector(positionChanged:) min:0 max:1 value:0]; self.subSlider.accessibilityLabel=@"練習動画の再生位置（同期解除時）";
    self.timeLabel=[self label:@"お手本 / 練習"]; self.timeLabel.numberOfLines=2;
    self.playButton=[self button:@"▶︎" action:@selector(togglePlay)]; self.playButton.accessibilityLabel=@"再生・一時停止";
    self.linkButton=[self button:@"同期解除" action:@selector(toggleLink)];
    self.analysisButton=[self button:@"自動解析" action:@selector(analyze)];
    self.modeButton=[self button:@"手動" action:@selector(toggleAutomatic)];
    self.skeletonButton=[self button:@"骨格" action:@selector(toggleSkeleton)];
    self.drawingButton=[self button:@"既存描画" action:@selector(toggleDrawings)];
    self.sketchButton=[self button:@"描く" action:@selector(toggleSketch)];
    self.opacitySlider=[self slider:@selector(appearanceChanged) min:0 max:1 value:.5]; self.opacitySlider.accessibilityLabel=@"練習動画の不透明度";
    self.speedSlider=[self slider:@selector(speedChanged) min:.1 max:2 value:1]; self.speedSlider.accessibilityLabel=@"再生速度";
    self.blendControl=[[UISegmentedControl alloc] initWithItems:@[@"半透明",@"選手切り抜き"]]; self.blendControl.selectedSegmentIndex=0; [self.blendControl addTarget:self action:@selector(appearanceChanged) forControlEvents:UIControlEventValueChanged];
    self.syncControl=[[UISegmentedControl alloc] initWithItems:@[@"実時間同期",@"コース位置同期"]]; self.syncControl.selectedSegmentIndex=0;
    [self.syncControl addTarget:self action:@selector(changeSyncMode:) forControlEvents:UIControlEventValueChanged];
    self.courseLabel=[self label:@"通過位置0組：同期解除→同じ目印の通過時刻で「位置点追加」（2組以上）"]; self.courseLabel.numberOfLines=2;
    NSArray *rows=@[self.timeLabel,self.syncControl,
        [self row:@[[self button:@"位置点追加" action:@selector(addCourseAnchor)],[self button:@"位置点一覧" action:@selector(showCourseAnchors)],[self button:@"自動候補" action:@selector(showCourseSuggestions)]]],self.courseLabel,[self row:@[[self label:@"お手本"],self.mainSlider]], [self row:@[[self label:@"練習"],self.subSlider]],
        [self row:@[[self button:@"−1f" action:@selector(backFrame)],self.playButton,[self button:@"＋1f" action:@selector(nextFrame)],self.linkButton,self.analysisButton,self.modeButton]],
        [self row:@[[self label:@"濃さ"],self.opacitySlider,self.blendControl]],
        [self row:@[[self label:@"速度"],self.speedSlider,[self button:@"A" action:@selector(setA)],[self button:@"B" action:@selector(setB)],[self button:@"AB解除" action:@selector(clearLoop)]]],
        [self row:@[[self button:@"4点補正" action:@selector(beginCalibration)],[self button:@"補正戻す" action:@selector(undoManual)],[self button:@"補正初期化" action:@selector(resetManual)],[self button:@"選手指定" action:@selector(beginSubjectSelection)]]],
        [self row:@[self.skeletonButton,self.drawingButton,self.sketchButton,[self button:@"描画戻す" action:@selector(undoSketch)]]],
        [self label:@"手動：ドラッグで移動・2本指で拡大/回転。同期解除→各動画を合わせ→同期確定。"]];
    for(UIView *row in rows) [self.controls addArrangedSubview:row];
    for(UIView *v in @[header,self.statusLabel,self.metalView,self.scrollView,self.controls]) v.translatesAutoresizingMaskIntoConstraints=NO;
    for(UIView *v in @[header,self.statusLabel,self.metalView,self.scrollView]) [self.view addSubview:v];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    self.controlsHeight=[self.scrollView.heightAnchor constraintEqualToConstant:280];
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:safe.topAnchor constant:4],[header.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:10],[header.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-10],
        [self.statusLabel.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:4],[self.statusLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],[self.statusLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],[self.statusLabel.heightAnchor constraintEqualToConstant:36],
        [self.metalView.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:4],[self.metalView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],[self.metalView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.metalView.bottomAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:-4],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:10],[self.scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-10],[self.scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-4],self.controlsHeight,
        [self.controls.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],[self.controls.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],[self.controls.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],[self.controls.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-10],[self.controls.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor]]];
    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    UIPinchGestureRecognizer *pinch=[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)];
    UIRotationGestureRecognizer *rotation=[[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(rotate:)];
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(calibrationTapped:)];
    for(UIGestureRecognizer *g in @[pan,pinch,rotation,tap]) { g.delegate=self; [self.metalView addGestureRecognizer:g]; }
    __weak typeof(self) weakSelf=self; self.sketch.changed=^{ weakSelf.dirty=YES; };
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resignActive) name:UIApplicationWillResignActiveNotification object:nil];
    self.prepareDeadline=CACurrentMediaTime()+20;
    [self prepareVideos];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat height=MIN(290,self.view.bounds.size.height*.43);
    if(fabs(self.controlsHeight.constant-height)>.5) self.controlsHeight.constant=height;
    if(!CGRectEqualToRect(self.sketch.frame,self.metalView.bounds)) self.sketch.frame=self.metalView.bounds;
    CGSize size=self.metalView.bounds.size; CGFloat scale=self.metalView.contentScaleFactor;
    // Updating the time/status labels can trigger layout even while paused. Only
    // invalidate the presented frame when the actual video viewport changes.
    if(!CGSizeEqualToSize(size,self.lastViewportSize)||scale!=self.lastViewportScale) {
        self.lastViewportSize=size; self.lastViewportScale=scale; self.lastRenderTime=0;
    }
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if(!self.displayLink&&!self.closed) { OverlayDisplayTarget *target=[OverlayDisplayTarget new]; target.owner=self; self.displayLink=[CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)]; self.displayLink.preferredFramesPerSecond=30; [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes]; }
}
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; if(!self.presentingViewController) [self shutdown]; }
- (void)prepareVideos {
    __weak typeof(self) weakSelf=self;
    NSURL *mainURL=self.mainURL,*subURL=self.subURL;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        AVURLAsset *m=[AVURLAsset URLAssetWithURL:mainURL options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@YES}];
        AVURLAsset *s=[AVURLAsset URLAssetWithURL:subURL options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@YES}];
        AVAssetTrack *mt=[m tracksWithMediaType:AVMediaTypeVideo].firstObject,*st=[s tracksWithMediaType:AVMediaTypeVideo].firstObject;
        double md=Seconds(m.duration),sd=Seconds(s.duration); NSError *error=nil;
        OverlaySessionStore *store=(mt&&st&&md>0&&sd>0)?[[OverlaySessionStore alloc] initWithMainURL:mainURL subURL:subURL error:&error]:nil;
        OverlayAnnotationAdapter *ma=[[OverlayAnnotationAdapter alloc] initWithVideoURL:mainURL],*sa=[[OverlayAnnotationAdapter alloc] initWithVideoURL:subURL];
        NSDictionary *saved=[store load];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self=weakSelf; if(!self||self.closed) return;
            if(!store||!mt||!st) { self.statusLabel.text=error.localizedDescription?:@"動画の映像トラックを読み込めません"; return; }
            self.store=store; self.originalSubAsset=s; self.mainTrack=mt; self.subTrack=st; self.mainDuration=md; self.subDuration=sd; self.mainAnnotations=ma; self.subAnnotations=sa;
            self.mainSlider.maximumValue=md; self.subSlider.maximumValue=sd;
            AVPlayerItem *mi=[AVPlayerItem playerItemWithAsset:m],*si=[AVPlayerItem playerItemWithAsset:s];
            NSDictionary *attrs=@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),(id)kCVPixelBufferMetalCompatibilityKey:@YES};
            self.mainOutput=[[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attrs]; self.subOutput=[[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attrs];
            [mi addOutput:self.mainOutput]; [si addOutput:self.subOutput];
            self.mainPlayer=[AVPlayer playerWithPlayerItem:mi]; self.subPlayer=[AVPlayer playerWithPlayerItem:si]; self.subPlayer.muted=YES;
            [self restore:saved]; self.restored=YES; self.prepareDeadline=CACurrentMediaTime()+15;
            if(!self.metalView.device) self.statusLabel.text=@"Metalを使用できないため、重ね合わせを表示できません";
        });
    });
}
- (void)restore:(NSDictionary *)state {
    if(!state) return;
    self.mainAnchor=MAX(0,MIN(self.mainDuration,[state[@"mainAnchor"] doubleValue])); self.subAnchor=MAX(0,MIN(self.subDuration,[state[@"subAnchor"] doubleValue]));
    self.manualMatrix=MTJOverlayMatrix(state[@"manualMatrix"]);
    self.opacitySlider.value=MAX(0,MIN(1,[state[@"opacity"] doubleValue])); self.speedSlider.value=MAX(.1,MIN(2,[state[@"speed"] doubleValue]));
    self.blendControl.selectedSegmentIndex=[state[@"cutout"] boolValue]?1:0;
    self.skeletonVisible=[state[@"skeleton"] boolValue]; self.drawingsVisible=[state[@"drawings"] boolValue];
    self.loopStart=[state[@"loopStart"] isKindOfClass:NSNumber.class]?[state[@"loopStart"] doubleValue]:NAN;
    self.loopEnd=[state[@"loopEnd"] isKindOfClass:NSNumber.class]?[state[@"loopEnd"] doubleValue]:NAN;
    self.loopEnabled=isfinite(self.loopStart)&&self.loopStart>=0&&isfinite(self.loopEnd)&&self.loopEnd>self.loopStart&&self.loopEnd<=self.mainDuration;
    NSArray *mp=state[@"mainSubject"],*sp=state[@"subSubject"];
    if(mp.count==2) self.mainSubject=CGPointMake([mp[0] doubleValue],[mp[1] doubleValue]); if(sp.count==2) self.subSubject=CGPointMake([sp[0] doubleValue],[sp[1] doubleValue]);
    if([state[@"frames"] isKindOfClass:NSArray.class]&&([state[@"engine"] isEqual:@"OpenCV-4.12.0-ORB-SIFT-LK-Vision-v3"]||[state[@"engine"] isEqual:@"OpenCV-4.12.0-ORB-SIFT-LK-Vision-v2"])) self.frames=state[@"frames"];
    self.useAutomatic=[state[@"automatic"] boolValue]&&self.frames.count>0;
    if([state[@"comparisonDrawings"] isKindOfClass:NSArray.class]) self.sketch.strokes=[state[@"comparisonDrawings"] mutableCopy];
    self.mainSlider.value=MAX([self mainLower],MIN([self mainUpper],[state[@"mainTime"] doubleValue]));
    self.subSlider.value=self.mainSlider.value-self.mainAnchor+self.subAnchor;
    if([state[@"courseAnchors"] isKindOfClass:NSArray.class]) self.courseAnchors=[state[@"courseAnchors"] mutableCopy];
    if([state[@"syncMode"] isEqual:@"coursePosition"]&&self.courseAnchors.count>=2) {
        OverlayTimelineMapper *restoredMapper=[[OverlayTimelineMapper alloc] initWithAnchors:self.courseAnchors mainDuration:self.mainDuration subDuration:self.subDuration error:nil];
        double m=[state[@"mainTime"] doubleValue];
        if(restoredMapper&&isfinite([restoredMapper subTimeForMainTime:m])) { self.pendingRestoreCourse=YES; self.mainSlider.value=m; self.subSlider.value=[restoredMapper subTimeForMainTime:m]; }
        // Restore the mode before using its cached registration pairs.
        self.restoredCourseFrames=self.frames; self.restoredCourseAutomatic=self.useAutomatic;
        self.frames=nil; self.useAutomatic=NO;
    }
    [self updateCourseLabel]; [self refreshButtons];
}
- (double)mappedSubTime:(double)main {
    return self.courseMode?[self.courseMapper subTimeForMainTime:main]:main-self.mainAnchor+self.subAnchor;
}
- (double)subSourceTime {
    double item=Seconds(self.subPlayer.currentTime);
    if(!self.courseMode) return item;
    double main=self.courseMapper.mainStart+item;
    // Composition timestamps are quantized to 1/60000 s; normalize only endpoint rounding.
    if(fabs(main-self.courseMapper.mainStart)<=1.0/60000) main=self.courseMapper.mainStart;
    if(fabs(main-self.courseMapper.mainEnd)<=1.0/60000) main=self.courseMapper.mainEnd;
    return [self.courseMapper subTimeForMainTime:main];
}
- (void)updateCourseLabel {
    self.courseLabel.text=[NSString stringWithFormat:@"通過位置%lu組：同期解除→同じ目印の通過時刻で「位置点追加」（2組以上）。候補は確認後に登録。",(unsigned long)self.courseAnchors.count];
}
- (BOOL)canEditCourseAnchors {
    if(!self.prepared||self.analysis||self.seeking||self.switchingTimeline||self.calibrationStep||self.courseMode) {
        self.statusLabel.text=@"通過位置の編集は実時間同期に戻り、解析・シーク完了後に行ってください"; return NO;
    }
    return YES;
}
- (BOOL)appendCourseAnchor:(NSDictionary *)anchor error:(NSError **)error {
    NSMutableArray *anchors=[self.courseAnchors mutableCopy]; [anchors addObject:anchor];
    [anchors sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) { return [a[@"mainTime"] compare:b[@"mainTime"]]; }];
    if(anchors.count>=2) {
        OverlayTimelineMapper *mapper=[[OverlayTimelineMapper alloc] initWithAnchors:anchors mainDuration:self.mainDuration subDuration:self.subDuration error:error];
        if(!mapper) return NO;
        anchors=[mapper.anchors mutableCopy];
    }
    self.courseAnchors=anchors; self.dirty=YES; [self updateCourseLabel]; return YES;
}
- (void)addCourseAnchor {
    if(![self canEditCourseAnchors]) return;
    if(self.linked) { self.statusLabel.text=@"先に「同期解除」を押し、同じ目印の通過時刻をお手本/練習で個別に合わせてください"; return; }
    [self pause]; double m=Seconds(self.mainPlayer.currentTime),s=[self subSourceTime];
    if(!isfinite(m)||!isfinite(s)) return;
    NSMutableDictionary *anchor=[@{@"mainTime":@(m),@"subTime":@(s),@"origin":@"manual",@"confirmed":@YES} mutableCopy];
    if(self.pendingCandidate&&fabs([self.pendingCandidate[@"mainTime"] doubleValue]-m)<.04&&fabs([self.pendingCandidate[@"subTime"] doubleValue]-s)<.04) {
        anchor=[self.pendingCandidate mutableCopy]; anchor[@"mainTime"]=@(m); anchor[@"subTime"]=@(s); anchor[@"confirmed"]=@YES;
    }
    NSError *error=nil;
    if([self appendCourseAnchor:anchor error:&error]) { self.pendingCandidate=nil; self.statusLabel.text=[NSString stringWithFormat:@"通過位置を登録：お手本 %.2f秒 / 練習 %.2f秒（%lu組）",m,s,(unsigned long)self.courseAnchors.count]; }
    else self.statusLabel.text=error.localizedDescription;
}
- (void)presentCourseSheet:(UIAlertController *)sheet {
    UIPopoverPresentationController *p=sheet.popoverPresentationController;
    if(p) { p.sourceView=self.syncControl; p.sourceRect=self.syncControl.bounds; }
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)showCourseAnchors {
    if(self.analysis||self.switchingTimeline||self.presentedViewController) return;
    [self pause];
    UIAlertController *list=[UIAlertController alertControllerWithTitle:@"登録した通過位置" message:@"同じコブ・目印・ランプ端などを、通過順に対応させます。最初から最後の位置点の間だけコース位置同期します。" preferredStyle:UIAlertControllerStyleActionSheet];
    for(NSUInteger i=0;i<self.courseAnchors.count;i++) {
        NSDictionary *anchor=self.courseAnchors[i];
        NSString *title=[NSString stringWithFormat:@"%lu：お手本 %.2f秒 / 練習 %.2f秒",(unsigned long)(i+1),[anchor[@"mainTime"] doubleValue],[anchor[@"subTime"] doubleValue]];
        [list addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self editCourseAnchor:anchor title:title]; }]];
    }
    [list addAction:[UIAlertAction actionWithTitle:@"閉じる" style:UIAlertActionStyleCancel handler:nil]]; [self presentCourseSheet:list];
}
- (void)editCourseAnchor:(NSDictionary *)anchor title:(NSString *)title {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:title message:@"表示して確認するか、実時間モードで削除して再登録できます。" preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"この位置を表示" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        if(self.courseMode) [self seekMain:[anchor[@"mainTime"] doubleValue] sub:[anchor[@"subTime"] doubleValue] play:NO];
        else { self.linked=NO; self.useAutomatic=NO; self.blendControl.selectedSegmentIndex=0; [self refreshButtons]; [self seekMain:[anchor[@"mainTime"] doubleValue] sub:[anchor[@"subTime"] doubleValue] play:NO]; }
    }]];
    if(!self.courseMode) [sheet addAction:[UIAlertAction actionWithTitle:@"この位置点を削除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self.courseAnchors removeObject:anchor]; self.dirty=YES; [self updateCourseLabel]; self.statusLabel.text=@"通過位置を削除しました";
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"閉じる" style:UIAlertActionStyleCancel handler:nil]];
    // Present after the selection sheet has completed its dismissal.
    UIViewController *presented=self.presentedViewController;
    if(presented) [presented dismissViewControllerAnimated:YES completion:^{ if(!self.closed) [self presentCourseSheet:sheet]; }];
    else [self presentCourseSheet:sheet];
}
- (void)showCourseSuggestions {
    if(![self canEditCourseAnchors]||self.presentedViewController) return;
    [self pause]; NSArray *candidates=[OverlayTimelineMapper suggestionsFromFrames:self.frames?:@[]];
    if(!candidates.count) { self.statusLabel.text=@"背景追跡と両足の検出が継続した区間から候補を作れません。自動解析するか、通過位置を手動登録してください"; return; }
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"通過位置の自動候補（未登録）" message:@"背景補正後の軌跡から推定しています。候補を表示し、同じコース位置か確認・時刻調整後に「位置点追加」を押してください。空中姿勢や水しぶきではずれる場合があります。" preferredStyle:UIAlertControllerStyleActionSheet];
    for(NSDictionary *candidate in [candidates subarrayWithRange:NSMakeRange(0,MIN(20,candidates.count))]) {
        NSString *title=[NSString stringWithFormat:@"お手本 %.2f秒 ↔ 練習 %.2f秒",[candidate[@"mainTime"] doubleValue],[candidate[@"subTime"] doubleValue]];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            self.pendingCandidate=candidate; self.linked=NO; self.useAutomatic=NO; self.blendControl.selectedSegmentIndex=0; [self refreshButtons];
            [self seekMain:[candidate[@"mainTime"] doubleValue] sub:[candidate[@"subTime"] doubleValue] play:NO];
            self.statusLabel.text=@"候補を表示中（未登録）。同じ目印の通過位置か確認・調整後、「位置点追加」で確定してください";
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"閉じる" style:UIAlertActionStyleCancel handler:nil]]; [self presentCourseSheet:sheet];
}
- (void)changeSyncMode:(UISegmentedControl *)control {
    BOOL desired=control.selectedSegmentIndex==1;
    if(desired==self.courseMode) return;
    if(!self.prepared||self.analysis||self.seeking||self.switchingTimeline||self.calibrationStep||!self.linked) {
        control.selectedSegmentIndex=self.courseMode?1:0;
        self.statusLabel.text=@"動画の準備・同期確定後に切り替えてください。通過位置の追加後も「同期確定」が必要です"; return;
    }
    NSError *error=nil;
    OverlayTimelineMapper *mapper=desired?[[OverlayTimelineMapper alloc] initWithAnchors:self.courseAnchors mainDuration:self.mainDuration subDuration:self.subDuration error:&error]:nil;
    double main=Seconds(self.mainPlayer.currentTime),sub=[self subSourceTime];
    double lower=desired?mapper.mainStart:MAX(0,self.mainAnchor-self.subAnchor),upper=desired?mapper.mainEnd:MIN(self.mainDuration,self.mainAnchor+self.subDuration-self.subAnchor);
    if((desired&&!mapper)||main<lower||main>upper) {
        control.selectedSegmentIndex=self.courseMode?1:0;
        self.statusLabel.text=error.localizedDescription?:@"現在のお手本時刻が同期区間の外です。位置点一覧から区間内の位置を表示してから切り替えてください"; self.restoringTimeline=NO; return;
    }
    [self pause]; if(self.sketch.enabled) [self toggleSketch];
    self.switchingTimeline=YES; NSUInteger generation=++self.timelineGeneration; [self refreshButtons]; self.statusLabel.text=@"同期タイムラインを準備しています…";
    AVPlayerItem *oldItem=self.subPlayer.currentItem; AVPlayerItemVideoOutput *oldOutput=self.subOutput;
    NSURL *url=self.subURL; AVAsset *original=self.originalSubAsset;
    __weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError *failure=nil; AVAsset *asset=desired?[mapper compositionForSubURL:url error:&failure]:original;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self=weakSelf; if(!self||self.closed||generation!=self.timelineGeneration) return;
            if(!asset) { self.switchingTimeline=NO; control.selectedSegmentIndex=self.courseMode?1:0; self.statusLabel.text=failure.localizedDescription; self.restoringTimeline=NO; [self refreshButtons]; return; }
            AVPlayerItem *item=[AVPlayerItem playerItemWithAsset:asset];
            if(desired) {
                // Give the retimed asset an explicit video-composition clock. Preserve
                // raw source orientation here; imageFromOutput applies preferredTransform.
                AVMutableVideoComposition *video=[AVMutableVideoComposition videoComposition];
                video.renderSize=self.subTrack.naturalSize; video.frameDuration=Time(1.0/30);
                AVCompositionTrack *track=[(AVComposition *)asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
                AVMutableVideoCompositionLayerInstruction *layer=[AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
                [layer setTransform:CGAffineTransformIdentity atTime:kCMTimeZero];
                AVMutableVideoCompositionInstruction *instruction=[AVMutableVideoCompositionInstruction videoCompositionInstruction];
                instruction.timeRange=CMTimeRangeMake(kCMTimeZero,asset.duration); instruction.layerInstructions=@[layer];
                video.instructions=@[instruction]; item.videoComposition=video;
            }
            self.subOutput=[[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),(id)kCVPixelBufferMetalCompatibilityKey:@YES}];
            [item addOutput:self.subOutput]; [self.subPlayer replaceCurrentItemWithPlayerItem:item];
            [self finishSyncMode:desired mapper:mapper main:main previousSub:sub oldItem:oldItem oldOutput:oldOutput generation:generation deadline:CACurrentMediaTime()+10];
        });
    });
}
- (void)finishSyncMode:(BOOL)desired mapper:(OverlayTimelineMapper *)mapper main:(double)main previousSub:(double)sub oldItem:(AVPlayerItem *)oldItem oldOutput:(AVPlayerItemVideoOutput *)oldOutput generation:(NSUInteger)generation deadline:(double)deadline {
    if(self.closed||generation!=self.timelineGeneration) return;
    AVPlayerItem *item=self.subPlayer.currentItem;
    if(item.status==AVPlayerItemStatusUnknown&&CACurrentMediaTime()<deadline) {
        __weak typeof(self) weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{ [weakSelf finishSyncMode:desired mapper:mapper main:main previousSub:sub oldItem:oldItem oldOutput:oldOutput generation:generation deadline:deadline]; }); return;
    }
    self.switchingTimeline=NO;
    if(item.status!=AVPlayerItemStatusReadyToPlay) {
        [item removeOutput:self.subOutput]; self.subOutput=oldOutput; [self.subPlayer replaceCurrentItemWithPlayerItem:oldItem]; self.syncControl.selectedSegmentIndex=self.courseMode?1:0;
        self.restoringTimeline=NO; [self refreshButtons]; [self seekMain:main sub:sub play:NO]; self.statusLabel.text=@"同期方式を切り替えられませんでした。元の方式に戻しました"; return;
    }
    [oldItem removeOutput:oldOutput]; self.courseMode=desired; self.courseMapper=mapper; self.linked=YES;
    self.frames=self.restoringTimeline?self.restoredCourseFrames:nil; self.useAutomatic=self.restoringTimeline&&self.restoredCourseAutomatic&&self.frames.count;
    self.restoringTimeline=NO; self.restoredCourseFrames=nil; self.activeFrame=nil; self.maskName=nil; self.maskImage=nil;
    if(self.loopEnabled&&(self.loopStart<[self mainLower]||self.loopEnd>[self mainUpper])) { self.loopEnabled=NO; self.loopStart=NAN; self.loopEnd=NAN; }
    self.syncControl.selectedSegmentIndex=desired?1:0; self.dirty=YES; [self refreshButtons];
    [self seekMain:main sub:[self mappedSubTime:main] play:NO];
    self.statusLabel.text=desired?@"コース位置同期に切替：お手本時刻を維持し、練習の時間進行を区間ごとに変更。必要なら自動解析してください":@"実時間同期に切替：お手本時刻を維持。必要なら自動解析してください";
}

- (double)mainLower { return self.courseMode?self.courseMapper.mainStart:MAX(0,self.mainAnchor-self.subAnchor); }
- (double)mainUpper { return self.courseMode?self.courseMapper.mainEnd:MIN(self.mainDuration,self.mainAnchor+self.subDuration-self.subAnchor); }
- (void)refreshButtons {
    [self.linkButton setTitle:self.linked?@"同期解除":@"同期確定" forState:UIControlStateNormal];
    [self.modeButton setTitle:self.useAutomatic?@"自動":@"手動" forState:UIControlStateNormal];
    self.modeButton.tintColor=self.useAutomatic?UIColor.systemGreenColor:UIColor.whiteColor;
    self.skeletonButton.tintColor=self.skeletonVisible?UIColor.systemGreenColor:UIColor.whiteColor;
    self.drawingButton.tintColor=self.drawingsVisible?UIColor.systemGreenColor:UIColor.whiteColor;
    self.sketchButton.tintColor=self.sketch.enabled?UIColor.systemYellowColor:UIColor.whiteColor;
    self.subSlider.enabled=!self.linked&&!self.analysis&&!self.switchingTimeline; self.mainSlider.enabled=!self.analysis&&!self.switchingTimeline;
    self.syncControl.enabled=!self.analysis&&!self.switchingTimeline; self.playButton.enabled=!self.switchingTimeline;
    self.linkButton.enabled=!self.analysis&&!self.switchingTimeline&&!self.courseMode; self.modeButton.enabled=!self.analysis&&!self.switchingTimeline;
    [self.analysisButton setTitle:self.analysis?@"解析中止":@"自動解析" forState:UIControlStateNormal];
}
- (void)pause {
    [self.mainPlayer pause]; [self.subPlayer pause]; self.playing=NO; [self.playButton setTitle:@"▶︎" forState:UIControlStateNormal];
}
- (void)seekMain:(double)main sub:(double)sub play:(BOOL)play {
    [self pause]; if(!self.prepared||self.closed||self.switchingTimeline) return;
    if(main<0||sub<0||main>self.mainDuration||sub>self.subDuration) return;
    double subItemTime=self.courseMode?[self.courseMapper mainTimeForSubTime:sub]-self.courseMapper.mainStart:sub;
    if(!isfinite(subItemTime)||subItemTime<0||(self.courseMode&&(main<[self mainLower]||main>[self mainUpper]))) return;
    NSUInteger generation=++self.seekGeneration; self.seeking=YES; self.requestedMain=main; self.requestedSub=sub;
    self.mainImage=nil; self.subImage=nil; self.lastRenderTime=0;
    dispatch_group_t group=dispatch_group_create(); __block BOOL finished=YES;
    for(NSUInteger i=0;i<2;i++) {
        AVPlayer *player=i?self.subPlayer:self.mainPlayer; double time=i?subItemTime:main; dispatch_group_enter(group);
        [player seekToTime:Time(time) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL ok) { dispatch_async(dispatch_get_main_queue(), ^{ finished=finished&&ok; dispatch_group_leave(group); }); }];
    }
    __weak typeof(self) weakSelf=self;
    dispatch_group_notify(group,dispatch_get_main_queue(), ^{
        typeof(self) self=weakSelf; if(!self||self.closed||generation!=self.seekGeneration) return;
        self.seeking=NO; if(!finished) { self.statusLabel.text=@"再生位置を移動できませんでした"; return; }
        if(self.pendingRestoreCourse) { self.pendingRestoreCourse=NO; self.restoringTimeline=YES; self.syncControl.selectedSegmentIndex=1; [self changeSyncMode:self.syncControl]; }
        else if(play) [self startPlaying];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
        typeof(self) self=weakSelf; if(self&&self.seeking&&generation==self.seekGeneration) { self.seekGeneration++; self.seeking=NO; [self pause]; self.statusLabel.text=@"動画の準備が完了しません。再生位置を選び直してください"; }
    });
}
- (void)startPlaying {
    if(self.analysis||self.seeking||self.calibrationStep||self.sketch.enabled||!self.prepared||self.switchingTimeline) return;
    double m=Seconds(self.mainPlayer.currentTime),s=Seconds(self.subPlayer.currentTime);
    CMTime host=CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()),Time(.1));
    self.mainPlayer.automaticallyWaitsToMinimizeStalling=NO; self.subPlayer.automaticallyWaitsToMinimizeStalling=NO;
    [self.mainPlayer setRate:self.speedSlider.value time:Time(m) atHostTime:host];
    [self.subPlayer setRate:self.speedSlider.value time:Time(s) atHostTime:host]; self.playing=YES; self.playbackScheduledUntil=CACurrentMediaTime()+.5; [self.playButton setTitle:@"❚❚" forState:UIControlStateNormal];
}
- (void)togglePlay {
    if(self.playing) { [self pause]; return; }
    if(self.analysis||!self.prepared||self.calibrationStep||self.switchingTimeline) return;
    if(self.sketch.enabled) [self toggleSketch];
    double m=Seconds(self.mainPlayer.currentTime),s=[self subSourceTime];
    if(self.linked) {
        if(m>=[self mainUpper]-.05) m=self.loopEnabled?self.loopStart:[self mainLower];
        s=[self mappedSubTime:m];
    } else if(m>=self.mainDuration-.05||s>=self.subDuration-.05) { m=0;s=0; }
    [self seekMain:m sub:s play:YES];
}
- (void)positionChanged:(UISlider *)slider {
    if(self.analysis||!self.prepared||self.calibrationStep||self.switchingTimeline) return;
    double m=self.mainSlider.value,s=self.subSlider.value;
    if(self.linked) { m=MAX([self mainLower],MIN([self mainUpper],m)); s=[self mappedSubTime:m]; }
    [self seekMain:m sub:s play:NO]; self.dirty=YES;
}
- (void)toggleLink {
    if(self.analysis||!self.prepared||self.calibrationStep||self.switchingTimeline||self.courseMode) return;
    [self pause]; self.linked=!self.linked;
    if(self.linked) {
        self.mainAnchor=Seconds(self.mainPlayer.currentTime); self.subAnchor=[self subSourceTime];
        self.frames=nil; self.useAutomatic=NO; self.activeFrame=nil; self.maskName=nil; self.loopEnabled=NO; self.loopStart=NAN; self.loopEnd=NAN;
        self.statusLabel.text=@"この2つの位置を基準に実時間同期します。必要なら自動解析してください";
    } else { self.useAutomatic=NO; self.blendControl.selectedSegmentIndex=0; self.statusLabel.text=@"2本の開始位置を個別に合わせて「同期確定」を押してください"; }
    self.dirty=YES; [self refreshButtons];
}
- (void)speedChanged { self.dirty=YES; if(self.playing) { [self pause]; [self startPlaying]; } }
- (void)appearanceChanged { self.dirty=YES; self.lastRenderTime=0; }
- (void)step:(NSInteger)direction {
    if(!self.prepared||self.analysis||self.calibrationStep||self.switchingTimeline) return;
    double fps=self.mainTrack.nominalFrameRate; double delta=direction/(fps>0?fps:30);
    double m=MAX(self.linked?[self mainLower]:0,MIN(self.linked?[self mainUpper]:self.mainDuration,Seconds(self.mainPlayer.currentTime)+delta));
    double s=self.linked?[self mappedSubTime:m]:MAX(0,MIN(self.subDuration,[self subSourceTime]+delta));
    [self seekMain:m sub:s play:NO];
}
- (void)backFrame { [self step:-1]; }
- (void)nextFrame { [self step:1]; }
- (void)setA { if(!self.prepared) return; self.loopStart=Seconds(self.mainPlayer.currentTime); self.loopEnd=NAN; self.loopEnabled=NO; self.dirty=YES; self.statusLabel.text=[NSString stringWithFormat:@"A: %.2f秒。B点を設定してください",self.loopStart]; }
- (void)setB {
    double b=Seconds(self.mainPlayer.currentTime);
    if(!self.linked||!isfinite(self.loopStart)||b<=self.loopStart) { self.statusLabel.text=@"同期を確定し、A点より後でB点を設定してください"; return; }
    self.loopEnd=b; self.loopEnabled=YES; self.dirty=YES; self.statusLabel.text=[NSString stringWithFormat:@"ABリピート: %.2f〜%.2f秒",self.loopStart,b];
    [self seekMain:self.loopStart sub:[self mappedSubTime:self.loopStart] play:YES];
}
- (void)clearLoop { self.loopEnabled=NO; self.loopStart=NAN; self.loopEnd=NAN; self.dirty=YES; self.statusLabel.text=@"ABリピートを解除しました"; }
- (void)analyze {
    if(self.analysis) { self.analysis.cancelled=YES; self.statusLabel.text=@"解析を中止しています…"; return; }
#if TARGET_OS_SIMULATOR
    self.statusLabel.text=@"自動背景合わせは接続したiPhone/iPad実機で利用できます。Simulatorでは手動比較を利用できます"; return;
#else
    if(!self.prepared||!self.linked||self.calibrationStep||self.seeking||self.switchingTimeline) { self.statusLabel.text=@"同期位置を確定し、動画の準備が終わってから解析してください"; return; }
    [self pause]; if(self.sketch.enabled) [self toggleSketch];
    double start=[self mainLower],duration=[self mainUpper]-start;
    if(duration<=0) { self.statusLabel.text=@"2動画に共通する区間がありません"; return; }
    self.analysis=[OverlayAnalysis new]; NSUInteger generation=++self.analysisGeneration;
    [self refreshButtons]; self.statusLabel.text=@"背景・人物を事前解析しています（最大30回/秒）…";
    __weak typeof(self) weakSelf=self;
    [self.analysis analyzeMain:self.mainURL sub:self.subURL mainStart:start subStart:[self mappedSubTime:start] duration:duration mainSubject:self.mainSubject subSubject:self.subSubject timeline:self.courseMode?self.courseMapper:nil cacheDirectory:self.store.cacheDirectory progress:^(double progress) {
        typeof(self) self=weakSelf; if(!self||self.closed||generation!=self.analysisGeneration) return;
        self.statusLabel.text=[NSString stringWithFormat:@"背景・人物を事前解析中 %ld%%（タップで中止）",(long)round(progress*100)];
    } completion:^(NSArray *frames,NSError *error) {
        typeof(self) self=weakSelf; if(!self||self.closed||generation!=self.analysisGeneration) return;
        self.analysis=nil;
        if(frames) {
            self.frames=frames; self.activeFrame=nil; self.maskName=nil;
            NSUInteger count=0; for(NSDictionary *f in frames) if([f[@"valid"] boolValue]) count++;
            if(count>0) { [self recordManual]; self.manualMatrix=matrix_identity_double3x3; }
            self.useAutomatic=count>0; self.dirty=YES;
            self.statusLabel.text=[NSString stringWithFormat:@"解析完了：背景一致 %lu/%lu。低信頼区間は非表示、手動へ切替可能",(unsigned long)count,(unsigned long)frames.count];
            [self saveQuietly];
        } else self.statusLabel.text=error.localizedDescription?:@"解析に失敗しました";
        [self refreshButtons]; self.lastRenderTime=0;
    }];
#endif
}
- (void)toggleAutomatic {
    if(self.analysis||self.calibrationStep) return;
    if(!self.useAutomatic&&!self.frames.count) { self.statusLabel.text=@"先に自動解析を実行してください。手動補正はすぐ使えます"; return; }
    [self pause]; [self recordManual];
    if(self.useAutomatic) {
        if([self.activeFrame[@"valid"] boolValue]) self.manualMatrix=simd_mul(self.manualMatrix,MTJOverlayMatrix(self.activeFrame[@"matrix"]));
        self.useAutomatic=NO;
    } else { self.manualMatrix=matrix_identity_double3x3; self.useAutomatic=YES; }
    self.dirty=YES; [self refreshButtons]; self.lastRenderTime=0;
}
- (void)recordManual {
    [self.manualHistory addObject:@{@"matrix":MTJOverlayMatrixArray(self.manualMatrix),@"automatic":@(self.useAutomatic)}];
    if(self.manualHistory.count>30) [self.manualHistory removeObjectAtIndex:0];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if(!self.prepared||self.analysis||self.seeking||self.sketch.enabled||self.switchingTimeline) return NO;
    if([g isKindOfClass:UITapGestureRecognizer.class]) return self.calibrationStep!=0;
    return !self.calibrationStep;
}
- (void)pan:(UIPanGestureRecognizer *)g {
    if(g.state==UIGestureRecognizerStateBegan) { [self pause]; [self recordManual]; self.gestureMatrix=self.manualMatrix; }
    CGPoint p=[g translationInView:self.metalView]; CGRect r=self.metalView.videoRect;
    self.manualMatrix=simd_mul(Translation(p.x/MAX(1,r.size.width),p.y/MAX(1,r.size.height)),self.gestureMatrix); self.dirty=YES; self.lastRenderTime=0;
}
- (void)pinch:(UIPinchGestureRecognizer *)g {
    if(g.state==UIGestureRecognizerStateBegan) { [self pause]; [self recordManual]; self.gestureMatrix=self.manualMatrix; }
    double scale=MAX(.2,MIN(5,g.scale));
    self.manualMatrix=simd_mul(CenterTransform(scale,0),self.gestureMatrix); self.dirty=YES; self.lastRenderTime=0;
}
- (void)rotate:(UIRotationGestureRecognizer *)g {
    if(g.state==UIGestureRecognizerStateBegan) { [self pause]; [self recordManual]; self.gestureMatrix=self.manualMatrix; }
    self.manualMatrix=simd_mul(CenterTransform(1,g.rotation),self.gestureMatrix); self.dirty=YES; self.lastRenderTime=0;
}
- (void)undoManual {
    if(self.calibrationStep) { self.calibrationStep=0; self.statusLabel.text=@"対応点/選手指定を中止しました"; self.lastRenderTime=0; return; }
    NSDictionary *last=self.manualHistory.lastObject; if(!last) return;
    self.manualMatrix=MTJOverlayMatrix(last[@"matrix"]); self.useAutomatic=[last[@"automatic"] boolValue]; [self.manualHistory removeLastObject]; self.dirty=YES; self.lastRenderTime=0; [self refreshButtons];
}
- (void)resetManual {
    if(self.analysis) return; self.calibrationStep=0; [self pause]; [self recordManual]; self.manualMatrix=matrix_identity_double3x3; self.useAutomatic=NO;
    self.dirty=YES; self.lastRenderTime=0; [self refreshButtons]; self.statusLabel.text=@"手動補正を初期化しました（自動解析結果は保持）";
}
- (void)beginCalibration {
    if(!self.prepared||self.analysis||self.seeking||self.switchingTimeline) return;
    [self pause]; if(self.sketch.enabled) [self toggleSketch]; self.calibrationStep=1;
    self.subPoints=[NSMutableArray array]; self.mainPoints=[NSMutableArray array]; self.lastRenderTime=0;
    self.statusLabel.text=@"4点補正：練習動画の背景目印1をタップ → お手本の同じ目印（計4組）。「補正戻す」で中止";
}
- (void)beginSubjectSelection {
    if(!self.prepared||self.analysis||self.seeking||self.switchingTimeline) return;
    [self pause]; if(self.sketch.enabled) [self toggleSketch]; self.calibrationStep=101; self.lastRenderTime=0;
    self.statusLabel.text=@"選手指定：練習動画の選手をタップ → お手本の選手をタップ。指定後に再解析します";
}
- (void)calibrationTapped:(UITapGestureRecognizer *)g {
    if(!self.calibrationStep) return;
    CGPoint p=[g locationInView:self.metalView]; CGRect r=self.metalView.videoRect; if(!CGRectContainsPoint(r,p)) return;
    p=CGPointMake((p.x-r.origin.x)/r.size.width,(p.y-r.origin.y)/r.size.height);
    if(self.calibrationStep>=101) {
        if(self.calibrationStep==101) { self.subSubject=p; self.calibrationStep=102; self.statusLabel.text=@"選手指定：お手本動画の選手をタップ"; }
        else { self.mainSubject=p; self.calibrationStep=0; self.frames=nil; self.useAutomatic=NO; self.maskName=nil; self.dirty=YES; [self refreshButtons]; self.statusLabel.text=@"選手を指定しました。「自動解析」で人物マスクを更新してください"; }
    } else {
        if(self.calibrationStep%2) [self.subPoints addObject:[NSValue valueWithCGPoint:p]]; else [self.mainPoints addObject:[NSValue valueWithCGPoint:p]];
        self.calibrationStep++;
        if(self.mainPoints.count==4) {
            NSArray *matrix=[OverlayRegistration matrixFromPoints:self.subPoints toPoints:self.mainPoints]; self.calibrationStep=0;
            if(matrix) { [self recordManual]; self.manualMatrix=MTJOverlayMatrix(matrix); self.useAutomatic=NO; self.dirty=YES; [self refreshButtons]; self.statusLabel.text=@"4点補正を適用しました。この補正は比較区間全体に適用されます"; }
            else self.statusLabel.text=@"4点が近い/一直線のため補正できません。広く離れた背景目印で再指定してください";
        } else self.statusLabel.text=[NSString stringWithFormat:@"4点補正：%@動画の背景目印%luをタップ（補正戻すで中止）",self.calibrationStep%2?@"練習":@"お手本",(unsigned long)(self.mainPoints.count+1)];
    }
    self.lastRenderTime=0;
}
- (void)toggleSkeleton {
    self.skeletonVisible=!self.skeletonVisible; self.dirty=YES; [self refreshButtons]; self.lastRenderTime=0;
    if(self.skeletonVisible&&!self.frames.count) self.statusLabel.text=@"骨格：既存解析を表示します。未解析動画は「自動解析」で取得できます";
}
- (void)toggleDrawings {
    self.drawingsVisible=!self.drawingsVisible; self.dirty=YES; [self refreshButtons]; self.lastRenderTime=0;
    if(self.drawingsVisible) self.statusLabel.text=@"既存描画を読取専用で表示。保存時の画面比情報がない旧描画は位置がずれる場合があります";
}
- (void)toggleSketch {
    if(self.analysis||self.calibrationStep) return; [self pause]; self.sketch.enabled=!self.sketch.enabled; self.sketch.userInteractionEnabled=self.sketch.enabled;
    [self refreshButtons]; if(self.sketch.enabled) self.statusLabel.text=@"比較画面に描画します。黄色線はお手本時刻に保存され、元動画の描画は変更しません";
}
- (void)undoSketch { if(self.sketch.strokes.count) { [self.sketch.strokes removeLastObject]; [self.sketch setNeedsDisplay]; self.dirty=YES; } }
- (NSDictionary *)frameForMain:(double)main sub:(double)sub {
    // Include every matching MAIN timestamp (VFR/low-fps assets can repeat it),
    // then choose the pair whose original SUB PTS also matches this synchronization.
    NSInteger low=0,high=(NSInteger)self.frames.count;
    while(low<high) { NSInteger mid=(low+high)/2; if([self.frames[mid][@"mainTime"] doubleValue]<main-.055) low=mid+1; else high=mid; }
    NSDictionary *best=nil; double error=.055;
    for(NSInteger i=low;i<(NSInteger)self.frames.count;i++) {
        NSDictionary *f=self.frames[i]; if([f[@"mainTime"] doubleValue]>main+.055) break;
        double d=MAX(fabs([f[@"mainTime"] doubleValue]-main),fabs([f[@"subTime"] doubleValue]-sub));
        if(d<error) { best=f; error=d; }
    } return best;
}

- (CIImage *)imageFromOutput:(AVPlayerItemVideoOutput *)output player:(AVPlayer *)player track:(AVAssetTrack *)track previous:(CIImage *)previous {
    CMTime time=player.currentTime;
    if(previous && ![output hasNewPixelBufferForItemTime:time]) return previous;
    CVPixelBufferRef pixel=[output copyPixelBufferForItemTime:time itemTimeForDisplay:nil]; if(!pixel) return previous;
    CIImage *image=[CIImage imageWithCVPixelBuffer:pixel]; CVPixelBufferRelease(pixel);
    // UIKit's preferredTransform uses top-left coordinates; CIImage uses bottom-left.
    image=[image imageByApplyingTransform:CGAffineTransformMake(1,0,0,-1,0,image.extent.size.height)];
    image=[image imageByApplyingTransform:track.preferredTransform]; CGRect r=image.extent;
    image=[image imageByApplyingTransform:CGAffineTransformMakeTranslation(-r.origin.x,-r.origin.y)];
    image=[image imageByApplyingTransform:CGAffineTransformMake(1,0,0,-1,0,r.size.height)];
    CGFloat scale=MIN(1,1280.0/MAX(r.size.width,r.size.height)); return [image imageByApplyingTransform:CGAffineTransformMakeScale(scale,scale)];
}
- (void)tick:(CADisplayLink *)link {
    if(self.closed||self.switchingTimeline) return;
    if(!self.prepared) {
        if(!self.restored) return;
        if(self.mainPlayer.status==AVPlayerStatusFailed||self.subPlayer.status==AVPlayerStatusFailed) { self.statusLabel.text=self.mainPlayer.error.localizedDescription?:self.subPlayer.error.localizedDescription?:@"動画を再生できません"; return; }
        if(self.mainPlayer.status!=AVPlayerStatusReadyToPlay||self.subPlayer.status!=AVPlayerStatusReadyToPlay) {
            if(CACurrentMediaTime()>self.prepareDeadline) self.statusLabel.text=@"再生準備が完了しません。動画の状態を確認してください"; return;
        }
        self.prepared=YES; self.statusLabel.text=@"実時間同期。必要なら同期解除で開始位置を調整し、自動解析してください";
        [self seekMain:self.mainSlider.value sub:self.subSlider.value play:YES]; [self refreshButtons]; return;
    }
    if(self.seeking) return;
    double main=Seconds(self.mainPlayer.currentTime),sub=[self subSourceTime];
    if(!isfinite(sub)) { [self pause]; self.statusLabel.text=@"コース位置同期の有効区間外です。位置点一覧から区間内を選び直してください"; return; }
    if(self.playing) {
        if(self.loopEnabled&&main>=self.loopEnd) { [self seekMain:self.loopStart sub:[self mappedSubTime:self.loopStart] play:YES]; return; }
        if(main>=(self.linked?[self mainUpper]:self.mainDuration)-.015||sub>=self.subDuration-.015) { [self pause]; }
        else if(self.linked&&(self.courseMode?fabs(Seconds(self.subPlayer.currentTime)-(main-self.courseMapper.mainStart)):fabs(sub-([self mappedSubTime:main])))>.08) { [self seekMain:main sub:[self mappedSubTime:main] play:YES]; return; }
        // Pause both if either decoder stalls, rather than showing unrelated moments.
        else if(CACurrentMediaTime()>self.playbackScheduledUntil&&(self.mainPlayer.timeControlStatus==AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate||self.subPlayer.timeControlStatus==AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate)) { [self pause]; self.statusLabel.text=@"動画の読み込み待ちです。再生ボタンで再開してください"; }
    }
    if(!self.mainSlider.isTracking) self.mainSlider.value=main; if(!self.subSlider.isTracking) self.subSlider.value=sub;
    self.timeLabel.text=[NSString stringWithFormat:@"お手本 %.2f / %.2f秒　練習 %.2f / %.2f秒　%.2f×%@",main,self.mainDuration,sub,self.subDuration,self.speedSlider.value,self.loopEnabled?@"　AB":@""];
    if(self.courseMode) self.timeLabel.text=[self.timeLabel.text stringByAppendingFormat:@"　コース位置（練習時間 %.2f×）",self.speedSlider.value*[self.courseMapper subRateForMainTime:main]];
    self.mainImage=[self imageFromOutput:self.mainOutput player:self.mainPlayer track:self.mainTrack previous:self.mainImage];
    self.subImage=[self imageFromOutput:self.subOutput player:self.subPlayer track:self.subTrack previous:self.subImage];
    if(!self.mainImage||!self.subImage) return;
    if(!self.playing&&self.lastRenderTime>0) return;
    self.activeFrame=self.linked?[self frameForMain:main sub:sub]:nil;
    simd_double3x3 h=self.manualMatrix; BOOL valid=!self.useAutomatic;
    if(self.useAutomatic&&[self.activeFrame[@"valid"] boolValue]) { h=simd_mul(self.manualMatrix,MTJOverlayMatrix(self.activeFrame[@"matrix"])); valid=YES; }
    CIImage *mask=nil; BOOL cutout=self.blendControl.selectedSegmentIndex==1;
    if(cutout) {
        NSString *name=self.activeFrame[@"subMask"];
        if(![name isEqual:self.maskName]) { self.maskName=name; self.maskImage=name?[CIImage imageWithContentsOfURL:[self.store.cacheDirectory URLByAppendingPathComponent:name]]:nil; }
        mask=self.maskImage;
        if(!mask) valid=NO;
    }
    if(!self.analysis&&!self.calibrationStep&&(self.useAutomatic||cutout)) {
        if(!valid) self.statusLabel.text=cutout&&!mask?@"この時刻の選手マスクがありません。自動解析・選手指定、または半透明へ切替":@"この区間の背景合わせは低信頼です。「自動」を押して手動補正へ切替";
        else self.statusLabel.text=[NSString stringWithFormat:@"%@　%@%@",self.useAutomatic?self.activeFrame[@"method"]:@"手動補正",cutout?@"選手切り抜き":@"半透明",self.useAutomatic?@"（背景一致は近似）":@""];
    }
    CGSize maSize=CGSizeMake(self.mainImage.extent.size.width*.5,self.mainImage.extent.size.height*.5),saSize=CGSizeMake(self.subImage.extent.size.width*.5,self.subImage.extent.size.height*.5);
    CIImage *ma=[self.mainAnnotations imageAtTime:main size:maSize joints:self.activeFrame[@"mainJoints"]?:@{} skeleton:self.skeletonVisible drawings:self.drawingsVisible color:UIColor.systemGreenColor];
    CIImage *sa=valid?[self.subAnnotations imageAtTime:sub size:saSize joints:self.activeFrame[@"subJoints"]?:@{} skeleton:self.skeletonVisible drawings:self.drawingsVisible color:UIColor.systemPinkColor]:nil;
    if(self.calibrationStep) {
        BOOL showSub=(self.calibrationStep>=101?self.calibrationStep==101:self.calibrationStep%2==1);
        BOOL submitted=[self.metalView displayMain:showSub?self.subImage:self.mainImage sub:nil matrix:matrix_identity_double3x3 mask:nil opacity:0 mainAnnotation:nil subAnnotation:nil];
        self.lastRenderTime=submitted?CACurrentMediaTime():0;
        self.sketch.hidden=YES;
    } else {
        BOOL submitted=[self.metalView displayMain:self.mainImage sub:valid?self.subImage:nil matrix:h mask:mask opacity:self.opacitySlider.value mainAnnotation:ma subAnnotation:sa];
        self.lastRenderTime=submitted?CACurrentMediaTime():0;
        self.sketch.hidden=NO; self.sketch.videoRect=self.metalView.videoRect; self.sketch.time=main; [self.sketch setNeedsDisplay];
    }
    if(self.metalView.renderError) self.statusLabel.text=[NSString stringWithFormat:@"映像の描画に失敗しました：%@",self.metalView.renderError.localizedDescription];
}
- (NSDictionary *)sessionState {
    NSMutableDictionary *state=[@{@"mainAnchor":@(self.mainAnchor),@"subAnchor":@(self.subAnchor),@"mainTime":@(Seconds(self.mainPlayer.currentTime)),@"manualMatrix":MTJOverlayMatrixArray(self.manualMatrix),@"automatic":@(self.useAutomatic),@"opacity":@(self.opacitySlider.value),@"speed":@(self.speedSlider.value),@"cutout":@(self.blendControl.selectedSegmentIndex==1),@"skeleton":@(self.skeletonVisible),@"drawings":@(self.drawingsVisible),@"comparisonDrawings":self.sketch.strokes?:@[],@"mainSubject":@[@(self.mainSubject.x),@(self.mainSubject.y)],@"subSubject":@[@(self.subSubject.x),@(self.subSubject.y)],@"frames":self.frames?:@[],@"syncMode":self.courseMode?@"coursePosition":@"elapsedTime",@"courseAnchors":self.courseAnchors?:@[],@"mainDuration":@(self.mainDuration),@"subDuration":@(self.subDuration)} mutableCopy];
    state[@"mainAnchorPTS"]=@{@"value":@(Time(self.mainAnchor).value),@"timescale":@(Time(self.mainAnchor).timescale)};
    state[@"subAnchorPTS"]=@{@"value":@(Time(self.subAnchor).value),@"timescale":@(Time(self.subAnchor).timescale)};
    state[@"analysisSampleRate"]=@30;
    for(NSString *role in @[@"main",@"sub"]) {
        AVAssetTrack *track=[role isEqual:@"main"]?self.mainTrack:self.subTrack;
        CGAffineTransform t=track.preferredTransform;
        state[[role stringByAppendingString:@"Track"]]=@{@"naturalSize":@[@(track.naturalSize.width),@(track.naturalSize.height)],@"preferredTransform":@[@(t.a),@(t.b),@(t.c),@(t.d),@(t.tx),@(t.ty)],@"nominalFrameRate":@(track.nominalFrameRate)};
    }
    if(isfinite(self.loopStart)) state[@"loopStart"]=@(self.loopStart); if(isfinite(self.loopEnd)) state[@"loopEnd"]=@(self.loopEnd);
    return state;
}
- (BOOL)saveQuietly {
    if(!self.store||!self.prepared) return YES;
    NSError *error=nil; BOOL ok=[self.store save:[self sessionState] error:&error];
    if(ok) self.dirty=NO; else self.statusLabel.text=error.localizedDescription?:@"比較設定を保存できませんでした";
    return ok;
}
- (void)saveTapped { if([self saveQuietly]&&self.store) self.statusLabel.text=@"比較設定・補正行列・同期・描画を保存しました（元動画は変更していません）"; }
- (void)resignActive { [self pause]; if(self.analysis) { self.analysis.cancelled=YES; self.statusLabel.text=@"バックグラウンド移行により解析を中止します"; } if(self.dirty) [self saveQuietly]; }
- (void)didReceiveMemoryWarning { [super didReceiveMemoryWarning]; [self pause]; self.analysis.cancelled=YES; self.mainImage=nil; self.subImage=nil; self.maskImage=nil; self.maskName=nil; self.lastRenderTime=0; [self.metalView.imageContext clearCaches]; }
- (void)shutdown {
    if(self.closed) return; self.closed=YES; self.analysis.cancelled=YES; self.analysisGeneration++; self.seekGeneration++; self.timelineGeneration++;
    [self pause]; [self.displayLink invalidate]; self.displayLink=nil;
    [self.mainPlayer cancelPendingPrerolls]; [self.subPlayer cancelPendingPrerolls];
    [self.mainPlayer.currentItem cancelPendingSeeks]; [self.subPlayer.currentItem cancelPendingSeeks];
    [self.mainPlayer replaceCurrentItemWithPlayerItem:nil]; [self.subPlayer replaceCurrentItemWithPlayerItem:nil];
    self.mainImage=nil; self.subImage=nil; [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)close {
    [self pause];
    if(self.dirty&&![self saveQuietly]) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"比較設定を保存できません" message:self.statusLabel.text preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"戻る" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存せず閉じる" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [self shutdown]; [self dismissViewControllerAnimated:YES completion:nil]; }]]; [self presentViewController:alert animated:YES completion:nil]; return;
    }
    [self shutdown]; [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)dealloc { [self.displayLink invalidate]; self.analysis.cancelled=YES; [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
