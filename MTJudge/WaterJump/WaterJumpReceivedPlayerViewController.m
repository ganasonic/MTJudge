#import "WaterJumpReceivedPlayerViewController.h"
#import <Vision/Vision.h>
#import "../SkeletonConnections.h"
#import "../Analysis/VideoPoseAnalysisManager.h"
#import "../Analysis/TakeoffAnalysisConfig.h"
#import "../Analysis/TakeoffAngleAnalyzer.h"

@interface WaterJumpReceivedPlayerViewController ()
@property (nonatomic, assign) float wjSelectedSpeed;
@property (nonatomic, strong) UIView *speedControlContainer;
@property (nonatomic, weak) UIView *speedControlHost;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UILabel *speedValueLabel;
@property (nonatomic, strong) NSTimer *speedHideTimer;
@property (nonatomic, strong) UIView *featureControlContainer;
@property (nonatomic, strong) UIButton *loopStartButton;
@property (nonatomic, strong) UIButton *loopEndButton;
@property (nonatomic, strong) UIButton *loopButton;
@property (nonatomic, strong) UIButton *frameStepButton;
@property (nonatomic, strong) UIButton *mirrorButton;
@property (nonatomic, assign) CMTime loopStartTime;
@property (nonatomic, assign) CMTime loopEndTime;
@property (nonatomic, assign) BOOL loopEnabled;
@property (nonatomic, assign) BOOL mirroredPlayback;
@property (nonatomic, strong) id playbackTimeObserver;
@property (nonatomic, assign) NSInteger automaticLoopLimit;
@property (nonatomic, assign) NSInteger automaticLoopCount;
@property (nonatomic, strong) NSDate *automaticLoopDeadline;
@property (nonatomic, assign) BOOL handlingAutomaticLoop;
@property (nonatomic, strong) UILabel *analysisLabel;
@property (nonatomic, copy) NSArray<NSDictionary *> *analysisFrames;
@property (nonatomic, strong) TakeoffAnalysisConfig *takeoffConfig;
@property (nonatomic, strong) UIButton *takeoffButton;
@property (nonatomic, strong) UIButton *skeletonButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, assign) NSInteger takeoffSetupStep;
@property (nonatomic, strong) UILabel *ankleAnalysisLabel;
@property (nonatomic, strong) UILabel *kneeAnalysisLabel;
@property (nonatomic, strong) UILabel *hipAnalysisLabel;
@property (nonatomic, strong) UILabel *torsoAnalysisLabel;
@property (nonatomic, strong) CAShapeLayer *skeletonOverlayLayer;
@property (nonatomic, assign) BOOL skeletonVisible;
@property (nonatomic, copy) NSArray<NSURL *> *playlist;
@property (nonatomic, assign) NSInteger playlistIndex;
@property (nonatomic, strong) UIPanGestureRecognizer *playlistPanGesture;
@property (nonatomic, strong) UIPanGestureRecognizer *playlistOverlayPanGesture;
@property (nonatomic, assign) BOOL switchingPlaylist;
@end

@implementation WaterJumpReceivedPlayerViewController

- (instancetype)initWithVideoURL:(NSURL *)url {
    if ((self = [super init])) {
        _wjSelectedSpeed = 1.0f;
        _loopStartTime = kCMTimeInvalid;
        _loopEndTime = kCMTimeInvalid;
        self.player = [AVPlayer playerWithURL:url];
        self.videoGravity = AVLayerVideoGravityResizeAspect;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        // AVPlayerViewController標準の「…」メニューは表示せず、MTJudge独自の操作群を使う。
        self.showsPlaybackControls = NO;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // iPadの既定のページシート変換を避け、受信動画は常に画面全体へ表示する。
    self.modalPresentationStyle = UIModalPresentationFullScreen;
    self.modalPresentationCapturesStatusBarAppearance = YES;
    self.view.backgroundColor = UIColor.blackColor;
    [self buildSpeedControls];
    self.analysisLabel = [UILabel new];
    self.analysisLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.analysisLabel.numberOfLines = 0;
    self.analysisLabel.textColor = UIColor.whiteColor;
    self.analysisLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
    self.analysisLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:.55];
    self.analysisLabel.layer.cornerRadius = 8;
    self.analysisLabel.clipsToBounds = YES;
    self.analysisLabel.text = @"解析データなし";
    self.analysisLabel.hidden = YES;
    UIView *host = self.contentOverlayView ?: self.view;
    [host addSubview:self.analysisLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.analysisLabel.leadingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.leadingAnchor constant:16],
        [self.analysisLabel.topAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor constant:56],
        [self.analysisLabel.widthAnchor constraintGreaterThanOrEqualToConstant:150]
    ]];
    self.ankleAnalysisLabel = [self makePartAnalysisLabel];
    self.kneeAnalysisLabel = [self makePartAnalysisLabel];
    self.hipAnalysisLabel = [self makePartAnalysisLabel];
    self.torsoAnalysisLabel = [self makePartAnalysisLabel];
    for (UILabel *label in @[self.ankleAnalysisLabel, self.kneeAnalysisLabel, self.hipAnalysisLabel, self.torsoAnalysisLabel]) {
        [host addSubview:label];
        label.hidden = YES;
    }
    self.skeletonOverlayLayer = [CAShapeLayer layer];
    self.skeletonOverlayLayer.strokeColor = [UIColor colorWithRed:0.20 green:0.95 blue:1.0 alpha:.95].CGColor;
    self.skeletonOverlayLayer.fillColor = UIColor.clearColor.CGColor;
    self.skeletonOverlayLayer.lineWidth = 2.5;
    self.skeletonOverlayLayer.lineCap = kCALineCapRound;
    self.skeletonOverlayLayer.hidden = YES;
    self.skeletonVisible = NO;
    [host.layer addSublayer:self.skeletonOverlayLayer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [self installPlaylistGestures];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // contentOverlayViewがsafe areaだけのサイズになる環境でも、Player全体を覆う。
    self.contentOverlayView.frame = self.view.bounds;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self installPlaylistGestures];
    [self showSpeedControls];
    if (!self.playbackTimeObserver) {
        __weak typeof(self) weakSelf = self;
        self.playbackTimeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 30) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
            [weakSelf updateAnalysisForTime:time];
            if (weakSelf.loopEnabled && CMTIME_IS_VALID(weakSelf.loopStartTime) && CMTIME_IS_VALID(weakSelf.loopEndTime) && CMTimeCompare(weakSelf.loopEndTime, weakSelf.loopStartTime) > 0) {
                if (CMTimeCompare(time, weakSelf.loopEndTime) >= 0) {
                    AVPlayer *player = weakSelf.player; weakSelf.loopEnabled = NO;
                    [player seekToTime:weakSelf.loopStartTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) { dispatch_async(dispatch_get_main_queue(), ^{ if (finished && weakSelf.player == player) { weakSelf.loopEnabled = YES; player.rate = weakSelf.wjSelectedSpeed; } }); }];
                }
                return;
            }
            double duration = CMTimeGetSeconds(weakSelf.player.currentItem.duration);
            double current = CMTimeGetSeconds(time);
            if (weakSelf.automaticLoopLimit == 0 || !isfinite(duration) || duration <= 0 || !isfinite(current) || current < duration - 0.15) return;
            [weakSelf handleAutomaticLoopAtEnd];
        }];
    }
    [self resetAndPlay];
    [self loadAnalysisForCurrentVideo];
}

- (void)installPlaylistGestures {
    if (!self.playlistPanGesture) {
        self.playlistPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePlaylistPan:)];
        self.playlistPanGesture.cancelsTouchesInView = YES;
        self.playlistPanGesture.maximumNumberOfTouches = 1;
        [self.view addGestureRecognizer:self.playlistPanGesture];
    }
    if (self.contentOverlayView && !self.playlistOverlayPanGesture) {
        self.playlistOverlayPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePlaylistPan:)];
        self.playlistOverlayPanGesture.cancelsTouchesInView = YES;
        self.playlistOverlayPanGesture.maximumNumberOfTouches = 1;
        [self.contentOverlayView addGestureRecognizer:self.playlistOverlayPanGesture];
    }
}

- (void)playerDidReachEnd:(NSNotification *)notification {
    if (notification.object == self.player.currentItem) [self handleAutomaticLoopAtEnd];
}

- (void)loadAnalysisForCurrentVideo {
    if (!self.skeletonVisible) {
        self.analysisFrames = nil;
        self.analysisLabel.hidden = YES;
        self.skeletonOverlayLayer.hidden = YES;
        return;
    }
    NSURL *url = [(AVURLAsset *)self.player.currentItem.asset URL];
    if (!url) return;
    self.analysisFrames = [[VideoPoseAnalysisManager sharedManager] loadFrameDataForVideoURL:url];
    self.takeoffConfig = [TakeoffAnalysisConfig configForVideoURL:url];
    if (self.analysisFrames.count) { self.analysisLabel.hidden = NO; [self updateAnalysisForTime:self.player.currentTime]; return; }
    for (UILabel *label in @[self.ankleAnalysisLabel, self.kneeAnalysisLabel, self.hipAnalysisLabel, self.torsoAnalysisLabel]) label.hidden = YES;
    self.analysisLabel.hidden = YES;
    __weak typeof(self) weakSelf = self;
    [[VideoPoseAnalysisManager sharedManager] analyzeVideoURL:url completion:^(NSURL *resultURL, NSError *error) {
        if (!weakSelf || error) return;
        weakSelf.analysisFrames = [[VideoPoseAnalysisManager sharedManager] loadFrameDataForVideoURL:url];
        weakSelf.takeoffConfig = [TakeoffAnalysisConfig configForVideoURL:url];
        weakSelf.analysisLabel.hidden = weakSelf.analysisFrames.count == 0;
        if (!weakSelf.analysisFrames.count) for (UILabel *label in @[weakSelf.ankleAnalysisLabel, weakSelf.kneeAnalysisLabel, weakSelf.hipAnalysisLabel, weakSelf.torsoAnalysisLabel]) label.hidden = YES;
        [weakSelf updateAnalysisForTime:weakSelf.player.currentTime];
    }];
}

- (void)updateAnalysisForTime:(CMTime)time {
    if (!self.skeletonVisible || !self.analysisFrames.count) {
        self.skeletonOverlayLayer.hidden = YES;
        self.analysisLabel.hidden = YES;
        for (UILabel *label in @[self.ankleAnalysisLabel, self.kneeAnalysisLabel, self.hipAnalysisLabel, self.torsoAnalysisLabel]) label.hidden = YES;
        return;
    }
    double timestamp = CMTimeGetSeconds(time); NSDictionary *best = nil; double distance = DBL_MAX;
    for (NSDictionary *frame in self.analysisFrames) { double candidate = [frame[@"timestamp"] doubleValue]; double d = fabs(candidate - timestamp); if (d < distance) { distance = d; best = frame; } }
    if (!best || distance > .25) {
        self.skeletonOverlayLayer.hidden = YES;
        for (UILabel *label in @[self.ankleAnalysisLabel, self.kneeAnalysisLabel, self.hipAnalysisLabel, self.torsoAnalysisLabel]) label.hidden = YES;
        return;
    }
    [self drawSkeletonForFrame:best];
    NSDictionary *takeoff = self.takeoffConfig ? [TakeoffAngleAnalyzer resultForFrame:best config:self.takeoffConfig] : nil;
    if (takeoff) {
        NSString *ankle = takeoff[@"ankleAngle"] ? [NSString stringWithFormat:@"%.1f°", [takeoff[@"ankleAngle"] doubleValue]] : @"--";
        NSString *knee = takeoff[@"kneeAngle"] ? [NSString stringWithFormat:@"%.1f°", [takeoff[@"kneeAngle"] doubleValue]] : @"--";
        NSString *hip = takeoff[@"hipAngle"] ? [NSString stringWithFormat:@"%.1f°", [takeoff[@"hipAngle"] doubleValue]] : @"--";
        NSString *torso = takeoff[@"torsoRampAngle"] ? [NSString stringWithFormat:@"%.1f°", [takeoff[@"torsoRampAngle"] doubleValue]] : @"--";
        // 踏切解析時は4項目を左上にまとめず、対応する関節の右側へ表示する。
        self.analysisLabel.hidden = YES;
        NSString *side = [takeoff[@"analysisSide"] isEqualToString:@"RIGHT"] ? @"right" : @"left";
        NSDictionary *joints = best[@"joints"];
        NSDictionary *ankleJoint = joints[[NSString stringWithFormat:@"%@Ankle", side]];
        NSDictionary *kneeJoint = joints[[NSString stringWithFormat:@"%@Knee", side]];
        NSDictionary *hipJoint = joints[[NSString stringWithFormat:@"%@Hip", side]];
        NSDictionary *shoulderJoint = joints[[NSString stringWithFormat:@"%@Shoulder", side]];
        self.ankleAnalysisLabel.text = [NSString stringWithFormat:@"ANKLE %@", ankle];
        self.kneeAnalysisLabel.text = [NSString stringWithFormat:@"KNEE %@", knee];
        self.hipAnalysisLabel.text = [NSString stringWithFormat:@"HIP %@", hip];
        self.torsoAnalysisLabel.text = [NSString stringWithFormat:@"TORSO %@", torso];
        [self positionPartLabel:self.ankleAnalysisLabel besideJoint:ankleJoint host:self.contentOverlayView ?: self.view];
        [self positionPartLabel:self.kneeAnalysisLabel besideJoint:kneeJoint host:self.contentOverlayView ?: self.view];
        [self positionPartLabel:self.hipAnalysisLabel besideJoint:hipJoint host:self.contentOverlayView ?: self.view];
        [self positionPartLabel:self.torsoAnalysisLabel besideJoint:shoulderJoint host:self.contentOverlayView ?: self.view];
        return;
    }
    for (UILabel *label in @[self.ankleAnalysisLabel, self.kneeAnalysisLabel, self.hipAnalysisLabel, self.torsoAnalysisLabel]) label.hidden = YES;
    self.analysisLabel.hidden = NO;
    NSString *left = best[@"leftKneeAngle"] ? [NSString stringWithFormat:@"L %d°", (int)round([best[@"leftKneeAngle"] doubleValue])] : @"L --";
    NSString *right = best[@"rightKneeAngle"] ? [NSString stringWithFormat:@"R %d°", (int)round([best[@"rightKneeAngle"] doubleValue])] : @"R --";
    NSString *torso = best[@"torsoVerticalAngle"] ? [NSString stringWithFormat:@"%.1f°", [best[@"torsoVerticalAngle"] doubleValue]] : @"--";
    NSString *absorption = best[@"absorption"] ? [NSString stringWithFormat:@"%d%%", (int)round([best[@"absorption"] doubleValue])] : @"--";
    self.analysisLabel.text = [NSString stringWithFormat:@"KNEE\n%@  %@\nTORSO  %@\nABSORPTION  %@", left, right, torso, absorption];
}

- (void)drawSkeletonForFrame:(NSDictionary *)frame {
    UIView *host = self.contentOverlayView ?: self.view;
    NSDictionary *joints = frame[@"joints"];
    if (![joints isKindOfClass:NSDictionary.class] || host.bounds.size.width <= 0 || host.bounds.size.height <= 0) { self.skeletonOverlayLayer.hidden = YES; return; }
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSArray<NSString *> *connection in SkeletonConnections()) {
        NSDictionary *a = joints[connection.firstObject];
        NSDictionary *b = joints[connection.lastObject];
        if (![a isKindOfClass:NSDictionary.class] || ![b isKindOfClass:NSDictionary.class]) continue;
        if ([a[@"confidence"] doubleValue] <= .1 || [b[@"confidence"] doubleValue] <= .1) continue;
        CGPoint p1 = CGPointMake([a[@"x"] doubleValue] * host.bounds.size.width, (1.0 - [a[@"y"] doubleValue]) * host.bounds.size.height);
        CGPoint p2 = CGPointMake([b[@"x"] doubleValue] * host.bounds.size.width, (1.0 - [b[@"y"] doubleValue]) * host.bounds.size.height);
        [path moveToPoint:p1]; [path addLineToPoint:p2];
    }
    self.skeletonOverlayLayer.frame = host.bounds;
    self.skeletonOverlayLayer.path = path.CGPath;
    self.skeletonOverlayLayer.hidden = !self.skeletonVisible || path.isEmpty;
}

- (UILabel *)makePartAnalysisLabel {
    UILabel *label = [UILabel new];
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:.62];
    label.layer.cornerRadius = 5;
    label.clipsToBounds = YES;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 1;
    return label;
}

- (void)positionPartLabel:(UILabel *)label besideJoint:(NSDictionary *)joint host:(UIView *)host {
    if (![joint isKindOfClass:NSDictionary.class] || !joint[@"x"] || !joint[@"y"]) { label.hidden = YES; return; }
    CGFloat x = (CGFloat)[joint[@"x"] doubleValue] * host.bounds.size.width;
    CGFloat y = (CGFloat)(1.0 - [joint[@"y"] doubleValue]) * host.bounds.size.height;
    CGSize size = [label sizeThatFits:CGSizeMake(150, 28)];
    CGFloat left = MIN(MAX(x + 12.0, 8.0), MAX(8.0, host.bounds.size.width - size.width - 8.0));
    CGFloat top = MIN(MAX(y - size.height * .5, 8.0), MAX(8.0, host.bounds.size.height - size.height - 8.0));
    label.frame = CGRectMake(left, top, MAX(size.width + 10.0, 72.0), MAX(size.height, 24.0));
    label.hidden = NO;
}

- (void)handleAutomaticLoopAtEnd {
    if (self.handlingAutomaticLoop || self.automaticLoopLimit == 0) return;
    if (self.automaticLoopDeadline && [[NSDate date] compare:self.automaticLoopDeadline] != NSOrderedAscending) { self.automaticLoopLimit = 0; return; }
    if (self.automaticLoopLimit > 0 && self.automaticLoopCount >= self.automaticLoopLimit) { self.automaticLoopLimit = 0; return; }
    self.handlingAutomaticLoop = YES;
    self.automaticLoopCount += 1;
    __weak typeof(self) weakSelf = self;
    [self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.handlingAutomaticLoop = NO;
            if (finished) weakSelf.player.rate = weakSelf.wjSelectedSpeed;
        });
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [self.speedHideTimer invalidate];
    if (self.playbackTimeObserver) [self.player removeTimeObserver:self.playbackTimeObserver];
}

- (void)buildSpeedControls {
    // AVPlayerViewControllerの標準プレイヤーより前面に表示されるoverlayへ追加する。
    // self.view直下ではOSの標準コントロールに隠れる場合がある。
    UIView *host = self.contentOverlayView ?: self.view;
    self.speedControlHost = host;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(playerTapped:)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];
    if (self.contentOverlayView) {
        UITapGestureRecognizer *overlayTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(playerTapped:)];
        overlayTap.cancelsTouchesInView = NO;
        [self.contentOverlayView addGestureRecognizer:overlayTap];
    }
    self.speedControlContainer = [[UIView alloc] init];
    self.speedControlContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedControlContainer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    self.speedControlContainer.layer.cornerRadius = 12;
    self.speedControlContainer.hidden = YES;
    [host addSubview:self.speedControlContainer];
    self.speedSlider = [UISlider new];
    self.speedSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedSlider.minimumValue = 0.25;
    self.speedSlider.maximumValue = 1.0;
    self.speedSlider.value = 1.0;
    self.speedSlider.minimumTrackTintColor = UIColor.whiteColor;
    self.speedSlider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.35];
    self.speedSlider.accessibilityLabel = @"再生速度";
    [self.speedSlider addTarget:self action:@selector(speedSliderChanged:) forControlEvents:UIControlEventValueChanged];
    self.speedValueLabel = [UILabel new];
    self.speedValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedValueLabel.textColor = UIColor.whiteColor;
    self.speedValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    self.speedValueLabel.text = @"1.00×";
    [self.speedControlContainer addSubview:self.speedSlider];
    [self.speedControlContainer addSubview:self.speedValueLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.speedControlContainer.centerXAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.centerXAnchor],
        [self.speedControlContainer.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:-24],
        [self.speedControlContainer.widthAnchor constraintEqualToConstant:300],
        [self.speedControlContainer.heightAnchor constraintEqualToConstant:50],
        [self.speedSlider.leadingAnchor constraintEqualToAnchor:self.speedControlContainer.leadingAnchor constant:12],
        [self.speedSlider.centerYAnchor constraintEqualToAnchor:self.speedControlContainer.centerYAnchor],
        [self.speedSlider.trailingAnchor constraintEqualToAnchor:self.speedValueLabel.leadingAnchor constant:-8],
        [self.speedValueLabel.trailingAnchor constraintEqualToAnchor:self.speedControlContainer.trailingAnchor constant:-12],
        [self.speedValueLabel.centerYAnchor constraintEqualToAnchor:self.speedControlContainer.centerYAnchor],
        [self.speedValueLabel.widthAnchor constraintEqualToConstant:42]
    ]];
    self.featureControlContainer = [[UIView alloc] init];
    self.featureControlContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.featureControlContainer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    self.featureControlContainer.layer.cornerRadius = 12;
    self.featureControlContainer.hidden = YES;
    [host addSubview:self.featureControlContainer];
    self.loopStartButton = [self featureButtonWithSymbol:@"a.circle" action:@selector(setLoopStart:) label:@"A点を設定"];
    self.loopEndButton = [self featureButtonWithSymbol:@"b.circle" action:@selector(setLoopEnd:) label:@"B点を設定"];
    self.loopButton = [self featureButtonWithSymbol:@"repeat" action:@selector(toggleLoop:) label:@"A-Bリピート"];
    self.frameStepButton = [self featureButtonWithSymbol:@"forward.frame" action:@selector(stepOneFrame:) label:@"1フレーム進む"];
    self.mirrorButton = [self featureButtonWithSymbol:@"arrow.left.and.right.righttriangle.left.righttriangle.right" action:@selector(toggleMirror:) label:@"左右反転"];
    self.takeoffButton = [self featureButtonWithSymbol:@"figure.skiing.downhill" action:@selector(toggleTakeoffSetup:) label:@"Takeoff解析設定"];
    self.takeoffButton.enabled = NO;
    self.takeoffButton.alpha = .4;
    self.skeletonButton = [self featureButtonWithSymbol:@"figure.stand" action:@selector(toggleSkeleton:) label:@"骨格線表示"];
    self.deleteButton = [self featureButtonWithSymbol:@"trash" action:@selector(deleteCurrentVideo:) label:@"再生中の動画を削除"];
    self.deleteButton.tintColor = UIColor.systemRedColor;
    UIStackView *featureStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.loopStartButton, self.loopEndButton, self.loopButton, self.frameStepButton, self.mirrorButton, self.skeletonButton, self.takeoffButton, self.deleteButton]];
    featureStack.translatesAutoresizingMaskIntoConstraints = NO;
    featureStack.axis = UILayoutConstraintAxisHorizontal;
    featureStack.alignment = UIStackViewAlignmentCenter;
    featureStack.distribution = UIStackViewDistributionEqualSpacing;
    featureStack.spacing = 5;
    [self.featureControlContainer addSubview:featureStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.featureControlContainer.centerXAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.centerXAnchor],
        [self.featureControlContainer.bottomAnchor constraintEqualToAnchor:self.speedControlContainer.topAnchor constant:-8],
        [self.featureControlContainer.widthAnchor constraintEqualToConstant:410],
        [self.featureControlContainer.heightAnchor constraintEqualToConstant:44],
        [featureStack.leadingAnchor constraintEqualToAnchor:self.featureControlContainer.leadingAnchor constant:8],
        [featureStack.trailingAnchor constraintEqualToAnchor:self.featureControlContainer.trailingAnchor constant:-8],
        [featureStack.topAnchor constraintEqualToAnchor:self.featureControlContainer.topAnchor constant:4],
        [featureStack.bottomAnchor constraintEqualToAnchor:self.featureControlContainer.bottomAnchor constant:-4]
    ]];
}

- (UIButton *)featureButtonWithSymbol:(NSString *)symbol action:(SEL)action label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = UIColor.whiteColor;
    button.accessibilityLabel = label;
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];
    button.layer.cornerRadius = 7;
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintEqualToConstant:44].active = YES;
    [button.heightAnchor constraintEqualToConstant:36].active = YES;
    return button;
}

- (void)replaceVideoURL:(NSURL *)url {
    if (!url || ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
        self.wjSelectedSpeed = 1.0f;
        self.loopStartTime = kCMTimeInvalid;
        self.loopEndTime = kCMTimeInvalid;
        self.loopEnabled = NO;
        self.automaticLoopLimit = 0;
        self.automaticLoopCount = 0;
        self.automaticLoopDeadline = nil;
        self.skeletonVisible = NO;
        self.skeletonOverlayLayer.hidden = YES;
        self.takeoffButton.enabled = NO;
        self.takeoffButton.alpha = .4;
        [self.player replaceCurrentItemWithPlayerItem:item];
        self.mirroredPlayback = NO;
        self.skeletonVisible = NO;
        self.skeletonOverlayLayer.hidden = YES;
        [self applyMirrorToPlayerLayers];
        [self updateSpeedSlider];
        [self refreshFeatureButtons];
        [self resetAndPlay];
        [self loadAnalysisForCurrentVideo];
    });
}

- (void)setPlaylist:(NSArray<NSURL *> *)playlist currentIndex:(NSInteger)index {
    self.playlist = [playlist copy];
    self.playlistIndex = MAX(0, MIN(index, (NSInteger)self.playlist.count - 1));
}

- (void)handlePlaylistPan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || self.switchingPlaylist || self.playlist.count < 2) return;
    CGPoint translation = [gesture translationInView:gesture.view];
    if (fabs(translation.x) < 60.0 || fabs(translation.x) < fabs(translation.y) * 1.15) return;
    NSInteger next = self.playlistIndex + (translation.x < 0 ? 1 : -1);
    if (next < 0 || next >= (NSInteger)self.playlist.count) return;
    NSURL *url = self.playlist[next];
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path]) return;
    self.switchingPlaylist = YES;
    self.playlistIndex = next;
    [self replaceVideoURL:url];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ self.switchingPlaylist = NO; });
}

- (void)resetAndPlay {
    if (!self.player) return;
    [self configureAutomaticLoop];
    self.player.rate = 0.0f;
    [self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finished && self.player.currentItem.status != AVPlayerItemStatusFailed) {
                self.player.rate = self.wjSelectedSpeed;
            }
        });
    }];
}

- (void)configureAutomaticLoop {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    self.automaticLoopLimit = 0;
    self.automaticLoopCount = 1;
    self.automaticLoopDeadline = nil;
    if (![defaults boolForKey:@"WJLoopPlayback"]) return;
    NSInteger count = [defaults integerForKey:@"WJLoopCount"]; if (count == 0) count = 3;
    if (count > 0) self.automaticLoopLimit = count;
    else if (count < 0) {
        NSInteger seconds = [defaults integerForKey:@"WJLoopDuration"];
        if (seconds > 0) self.automaticLoopDeadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
        self.automaticLoopLimit = -1;
    }
}

- (void)playerTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    if (self.takeoffSetupStep > 0 && self.takeoffSetupStep <= 5) {
        CGPoint point = [gesture locationInView:self.view];
        CGFloat width = MAX(self.view.bounds.size.width, 1.0), height = MAX(self.view.bounds.size.height, 1.0);
        CGPoint normalized = CGPointMake(MAX(0, MIN(1, point.x / width)), MAX(0, MIN(1, point.y / height)));
        if (self.takeoffSetupStep == 1) self.takeoffConfig.rampPointA = normalized;
        else if (self.takeoffSetupStep == 2) self.takeoffConfig.rampPointB = normalized;
        else if (self.takeoffSetupStep == 3) self.takeoffConfig.lipPoint = normalized;
        else if (self.takeoffSetupStep == 4) self.takeoffConfig.takeoffStartTime = self.player.currentTime;
        else if (self.takeoffSetupStep == 5) { self.takeoffConfig.lipExitTime = self.player.currentTime; self.takeoffConfig.enabled = YES; [self.takeoffConfig save]; self.takeoffSetupStep = 0; self.takeoffButton.backgroundColor = [UIColor colorWithWhite:0 alpha:.25]; [self updateAnalysisForTime:self.player.currentTime]; }
        if (self.takeoffSetupStep > 0) { self.takeoffSetupStep += 1; self.analysisLabel.hidden = NO; self.analysisLabel.text = [self takeoffSetupInstruction]; }
        [self showSpeedControls];
        return;
    }
    [self showSpeedControls];
}

- (NSString *)takeoffSetupInstruction { NSArray *steps = @[@"TAKEOFF設定\n動画上でRamp始点をタップ", @"TAKEOFF設定\n動画上でRamp終点をタップ", @"TAKEOFF設定\n動画上でLip位置をタップ", @"TAKEOFF設定\nサッツ開始フレームでタップ", @"TAKEOFF設定\nリップ離脱フレームでタップ"]; return steps[MAX(0, MIN(self.takeoffSetupStep - 1, (NSInteger)steps.count - 1))]; }
- (void)toggleTakeoffSetup:(id)sender {
    if (!self.skeletonVisible) return;
    if (self.takeoffSetupStep > 0) { self.takeoffSetupStep = 0; self.analysisLabel.hidden = self.analysisFrames.count == 0; self.takeoffButton.backgroundColor = [UIColor colorWithWhite:0 alpha:.25]; return; }
    NSURL *url = [(AVURLAsset *)self.player.currentItem.asset URL];
    self.takeoffConfig = [TakeoffAnalysisConfig configForVideoURL:url];
    self.takeoffSetupStep = 1;
    self.takeoffButton.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:.55];
    self.analysisLabel.hidden = NO; self.analysisLabel.text = [self takeoffSetupInstruction];
    [self showSpeedControls];
}

- (void)showSpeedControls {
    self.speedControlContainer.hidden = NO;
    self.featureControlContainer.hidden = NO;
    [self.speedControlHost bringSubviewToFront:self.speedControlContainer];
    [self.speedHideTimer invalidate];
    self.speedHideTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(hideSpeedControls) userInfo:nil repeats:NO];
}

- (void)hideSpeedControls { self.speedControlContainer.hidden = YES; self.featureControlContainer.hidden = YES; }

- (void)speedSliderChanged:(UISlider *)slider {
    [self showSpeedControls];
    self.wjSelectedSpeed = roundf(slider.value * 100.0f) / 100.0f;
    slider.value = self.wjSelectedSpeed;
    self.speedValueLabel.text = [NSString stringWithFormat:@"%.2f×", self.wjSelectedSpeed];
    slider.accessibilityValue = self.speedValueLabel.text;
    AVPlayerItem *item = self.player.currentItem;
    if (!item) return;
    double duration = CMTimeGetSeconds(item.duration);
    double current = CMTimeGetSeconds(self.player.currentTime);
    BOOL atEnd = isfinite(duration) && duration > 0 && isfinite(current) && current >= duration - 0.05;
    if (atEnd) {
        [self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
            if (finished) dispatch_async(dispatch_get_main_queue(), ^{ self.player.rate = self.wjSelectedSpeed; });
        }];
    } else {
        // 一時停止中でも速度ボタンを押せば、その速度で再開する。
        self.player.rate = self.wjSelectedSpeed;
    }
}

- (void)updateSpeedSlider {
    self.speedSlider.value = self.wjSelectedSpeed;
    self.speedValueLabel.text = [NSString stringWithFormat:@"%.2f×", self.wjSelectedSpeed];
}

- (void)refreshFeatureButtons {
    self.loopStartButton.accessibilityValue = CMTIME_IS_VALID(self.loopStartTime) ? [NSString stringWithFormat:@"A %.2f秒", CMTimeGetSeconds(self.loopStartTime)] : @"未設定";
    self.loopEndButton.accessibilityValue = CMTIME_IS_VALID(self.loopEndTime) ? [NSString stringWithFormat:@"B %.2f秒", CMTimeGetSeconds(self.loopEndTime)] : @"未設定";
    self.loopButton.backgroundColor = self.loopEnabled ? [UIColor.systemBlueColor colorWithAlphaComponent:0.5] : [UIColor colorWithWhite:0 alpha:0.25];
    self.mirrorButton.backgroundColor = self.mirroredPlayback ? [UIColor.systemBlueColor colorWithAlphaComponent:0.5] : [UIColor colorWithWhite:0 alpha:0.25];
    self.skeletonButton.backgroundColor = self.skeletonVisible ? [UIColor.systemBlueColor colorWithAlphaComponent:0.5] : [UIColor colorWithWhite:0 alpha:0.25];
}

- (void)toggleSkeleton:(id)sender {
    self.skeletonVisible = !self.skeletonVisible;
    self.skeletonOverlayLayer.hidden = !self.skeletonVisible;
    self.takeoffButton.enabled = self.skeletonVisible;
    self.takeoffButton.alpha = self.skeletonVisible ? 1.0 : .4;
    if (!self.skeletonVisible) {
        self.takeoffSetupStep = 0;
        self.analysisLabel.hidden = YES;
        for (UILabel *label in @[self.ankleAnalysisLabel, self.kneeAnalysisLabel, self.hipAnalysisLabel, self.torsoAnalysisLabel]) label.hidden = YES;
    }
    [self refreshFeatureButtons];
    if (self.skeletonVisible) [self loadAnalysisForCurrentVideo];
    [self showSpeedControls];
}

- (void)deleteCurrentVideo:(id)sender {
    NSURL *url = [(AVURLAsset *)self.player.currentItem.asset URL];
    if (!url || ![url.pathExtension.lowercaseString isEqualToString:@"mov"]) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"動画を削除しますか？" message:url.lastPathComponent preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"削除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSFileManager *files = NSFileManager.defaultManager;
        NSError *error = nil;
        for (NSURL *target in @[url, [url URLByAppendingPathExtension:@"wj.json"], [url URLByAppendingPathExtension:@"tags.json"], [url URLByAppendingPathExtension:@"pose.json"]]) {
            if ([files fileExistsAtPath:target.path] && ![files removeItemAtURL:target error:&error]) break;
        }
        if (error) {
            UIAlertController *failure = [UIAlertController alertControllerWithTitle:@"削除できません" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [failure addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:failure animated:YES completion:nil];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"WJVideoDeleted" object:url];
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setLoopStart:(id)sender {
    self.loopStartTime = self.player.currentTime;
    if (CMTIME_IS_VALID(self.loopEndTime) && CMTimeCompare(self.loopEndTime, self.loopStartTime) <= 0) {
        self.loopEndTime = kCMTimeInvalid;
        self.loopEnabled = NO;
    }
    [self refreshFeatureButtons];
}

- (void)setLoopEnd:(id)sender {
    if (!CMTIME_IS_VALID(self.loopStartTime)) return;
    CMTime current = self.player.currentTime;
    if (CMTimeCompare(current, self.loopStartTime) <= 0) { self.loopEnabled = NO; [self refreshFeatureButtons]; return; }
    self.loopEndTime = current;
    self.loopEnabled = YES;
    [self refreshFeatureButtons];
}

- (void)toggleLoop:(id)sender {
    if (!CMTIME_IS_VALID(self.loopStartTime) || !CMTIME_IS_VALID(self.loopEndTime) || CMTimeCompare(self.loopEndTime, self.loopStartTime) <= 0) self.loopEnabled = NO;
    else self.loopEnabled = !self.loopEnabled;
    [self refreshFeatureButtons];
}

- (CMTime)videoFrameDuration {
    AVAssetTrack *track = [self.player.currentItem.asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    CMTime duration = track.minFrameDuration;
    if (CMTIME_IS_VALID(duration) && duration.value > 0) return duration;
    float fps = track.nominalFrameRate;
    if (fps <= 0) fps = 30.0f;
    return CMTimeMakeWithSeconds(1.0 / fps, 600);
}

- (void)stepOneFrame:(id)sender {
    [self.player pause];
    CMTime next = CMTimeAdd(self.player.currentTime, [self videoFrameDuration]);
    CMTime duration = self.player.currentItem.duration;
    if (CMTIME_IS_VALID(duration) && CMTimeCompare(next, duration) > 0) next = duration;
    [self.player seekToTime:next toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil];
}

- (void)applyMirrorToPlayerLayers {
    AVPlayerLayer *videoLayer = [self findPlayerLayerInLayer:self.view.layer];
    videoLayer.affineTransform = self.mirroredPlayback ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
}

- (AVPlayerLayer *)findPlayerLayerInLayer:(CALayer *)layer {
    if ([layer isKindOfClass:[AVPlayerLayer class]]) return (AVPlayerLayer *)layer;
    for (CALayer *child in layer.sublayers) {
        AVPlayerLayer *found = [self findPlayerLayerInLayer:child];
        if (found) return found;
    }
    return nil;
}

- (void)toggleMirror:(id)sender {
    self.mirroredPlayback = !self.mirroredPlayback;
    [self applyMirrorToPlayerLayers];
    [self refreshFeatureButtons];
}

@end
