#import "WaterJumpComparisonViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "MTJudge-Swift.h"
#import "WaterJumpSettingsViewController.h"

static CGSize WJOrientedTrackSize(AVAssetTrack *track) {
    CGRect rect = CGRectApplyAffineTransform(CGRectMake(0, 0, fabs(track.naturalSize.width), fabs(track.naturalSize.height)), track.preferredTransform);
    return CGSizeMake(fabs(rect.size.width), fabs(rect.size.height));
}
static CGAffineTransform WJNormalizedTrackTransform(AVAssetTrack *track) {
    CGRect rect = CGRectApplyAffineTransform(CGRectMake(0, 0, fabs(track.naturalSize.width), fabs(track.naturalSize.height)), track.preferredTransform);
    CGAffineTransform t = track.preferredTransform; t.tx -= rect.origin.x; t.ty -= rect.origin.y; return t;
}

// Use display aspect ratios, never the source resolution, to allocate comparison panes.
static CGSize WJComparisonAspects(CGSize main, CGSize sub) {
    CGFloat a = main.width / MAX(main.height, 1), b = sub.width / MAX(sub.height, 1);
    if (a <= 0) a = 9.0 / 16.0;
    if (b <= 0) b = 9.0 / 16.0;
    if (a < 1 && b < 1) a = b = MAX(a, b);
    return CGSizeMake(a, b);
}
static void WJComparisonRects(CGRect area, CGSize aspects, BOOL sideBySide, CGRect *main, CGRect *sub) {
    if (sideBySide) {
        CGFloat width = area.size.width * aspects.width / (aspects.width + aspects.height);
        CGFloat minimumWidth = MIN(180, area.size.width / 2);
        width = MAX(minimumWidth, MIN(area.size.width - minimumWidth, width));
        *main = CGRectMake(area.origin.x, area.origin.y, width, area.size.height);
        *sub = CGRectMake(CGRectGetMaxX(*main), area.origin.y, area.size.width - width, area.size.height);
    } else {
        CGFloat height = area.size.height * aspects.height / (aspects.width + aspects.height);
        *main = CGRectMake(area.origin.x, area.origin.y, area.size.width, height);
        *sub = CGRectMake(area.origin.x, CGRectGetMaxY(*main), area.size.width, area.size.height - height);
    }
}
static void WJConfigureComparisonInstruction(AVMutableVideoCompositionLayerInstruction *instruction, AVAssetTrack *track, CGRect pane, CGFloat zoom, BOOL mirrored) {
    CGSize size = WJOrientedTrackSize(track);
    CGFloat scale = MIN(pane.size.width / MAX(size.width, 1), pane.size.height / MAX(size.height, 1)) * zoom;
    CGFloat width = size.width * scale, height = size.height * scale;
    CGAffineTransform t = CGAffineTransformConcat(WJNormalizedTrackTransform(track), CGAffineTransformMakeScale(mirrored ? -scale : scale, scale));
    t = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(CGRectGetMidX(pane) - width / 2 + (mirrored ? width : 0), CGRectGetMidY(pane) - height / 2));
    // Clip zoomed pixels to their own pane before the transform, just as on screen.
    CGRect crop = CGRectApplyAffineTransform(pane, CGAffineTransformInvert(t));
    crop = CGRectIntersection(crop, CGRectMake(0, 0, track.naturalSize.width, track.naturalSize.height));
    [instruction setCropRectangle:crop atTime:kCMTimeZero];
    [instruction setTransform:t atTime:kCMTimeZero];
}

// All linked times are measured relative to the two positions captured by Link.
// Never clamp the two anchors independently: only their shared interval is valid.
typedef struct { double lower; double upper; } WJSyncRange;
static WJSyncRange WJSharedSyncRange(double mainDuration, double subDuration, double mainAnchor, double subAnchor) {
    if (!isfinite(mainDuration) || !isfinite(subDuration) || !isfinite(mainAnchor) || !isfinite(subAnchor) || mainDuration <= 0 || subDuration <= 0 || mainAnchor < 0 || subAnchor < 0 || mainAnchor > mainDuration || subAnchor > subDuration) return (WJSyncRange){0, 0};
    return (WJSyncRange){-MIN(mainAnchor, subAnchor), MIN(mainDuration-mainAnchor, subDuration-subAnchor)};
}
@interface WJSyncPositionSlider : UISlider
@property(nonatomic) double syncFraction;
@property(nonatomic, strong) UIView *syncMarker;
@end
@implementation WJSyncPositionSlider
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) { _syncFraction = NAN; self.tintColor = UIColor.systemBlueColor; }
    return self;
}
- (void)setSyncFraction:(double)value { _syncFraction = value; [self setNeedsLayout]; }
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!self.syncMarker) {
        self.syncMarker = [UIView new]; self.syncMarker.backgroundColor = UIColor.systemYellowColor;
        self.syncMarker.userInteractionEnabled = NO; self.syncMarker.layer.cornerRadius = 1;
        [self addSubview:self.syncMarker];
    }
    self.syncMarker.hidden = !isfinite(self.syncFraction);
    if (self.syncMarker.hidden) return;
    CGRect track = [self trackRectForBounds:self.bounds];
    float value = self.minimumValue + (self.maximumValue-self.minimumValue) * MAX(0, MIN(1, self.syncFraction));
    CGRect thumb = [self thumbRectForBounds:self.bounds trackRect:track value:value];
    self.syncMarker.frame = CGRectMake(CGRectGetMidX(thumb)-1.5, CGRectGetMidY(track)-10, 3, 20);
    [self bringSubviewToFront:self.syncMarker];
}
@end

@interface WaterJumpComparisonViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSURL *mainURL;
@property (nonatomic, strong) NSURL *subURL;
@property (nonatomic, strong) AVPlayer *mainPlayer;
@property (nonatomic, strong) AVPlayer *subPlayer;
@property (nonatomic, strong) AVPlayerLayer *mainLayer;
@property (nonatomic, strong) AVPlayerLayer *subLayer;
@property (nonatomic, strong) CALayer *mainViewport;
@property (nonatomic, strong) CALayer *subViewport;
@property (nonatomic) CGSize comparisonAspects;
@property (nonatomic, strong) WJSyncPositionSlider *positionSlider;
@property (nonatomic, strong) WJSyncPositionSlider *mainPositionSlider;
@property (nonatomic, strong) WJSyncPositionSlider *subPositionSlider;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UILabel *speedValueLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UILabel *mainLabel;
@property (nonatomic, strong) UILabel *mainTimeLabel;
@property (nonatomic, strong) UILabel *subTimeLabel;
@property (nonatomic, strong) id subTimeObserver;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, assign) float speed;
@property (nonatomic, strong) id observer;
@property (nonatomic, strong) UIButton *aButton;
@property (nonatomic, strong) UIButton *bButton;
@property (nonatomic, strong) UIButton *loopButton;
@property (nonatomic, strong) UIButton *frameButton;
@property (nonatomic, strong) UIButton *mainMirrorButton;
@property (nonatomic, strong) UIButton *subMirrorButton;
@property (nonatomic, strong) UIButton *shareButton;
@property (nonatomic, strong) UIButton *exportButton;
@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, strong) UIButton *selectVideoButton;
@property (nonatomic, assign) CMTime loopStart;
@property (nonatomic, assign) CMTime loopEnd;
@property (nonatomic, assign) CMTime subLoopStart;
@property (nonatomic, assign) CMTime subLoopEnd;
@property (nonatomic, assign) BOOL loopEnabled;
@property (nonatomic, assign) BOOL loopSeekInProgress;
@property (nonatomic, assign) BOOL mainMirrored;
@property (nonatomic, assign) BOOL subMirrored;
@property (nonatomic, assign) CGFloat mainZoomScale;
@property (nonatomic, assign) CGFloat subZoomScale;
@property (nonatomic, assign) BOOL sideBySide;
@property (nonatomic, assign) BOOL linkedPlayback;
@property (nonatomic, strong) UIButton *linkButton;
@property (nonatomic, strong) UIButton *mainBackButton;
@property (nonatomic, strong) UIButton *mainPlayButton;
@property (nonatomic, strong) UIButton *mainForwardButton;
@property (nonatomic, strong) UIButton *subBackButton;
@property (nonatomic, strong) UIButton *subPlayButton;
@property (nonatomic, strong) UIButton *subForwardButton;
@property (nonatomic, strong) UIButton *syncPointButton;
@property (nonatomic, strong) UIButton *syncBackButton;
@property (nonatomic, strong) UIButton *syncForwardButton;
@property (nonatomic, assign) CMTime linkedMainAnchor;
@property (nonatomic, assign) CMTime linkedSubAnchor;
@property (nonatomic, assign) BOOL hasLinkedAnchors;
@property (nonatomic, strong) UILayoutGuide *bottomControlGuide;
@property (nonatomic, strong) UIStackView *sharedFeatureStack;
@property (nonatomic, assign) NSInteger automaticLoopLimit;
@property (nonatomic, assign) NSInteger automaticLoopCount;
@property (nonatomic, strong) NSDate *automaticLoopDeadline;
@property(nonatomic, strong) UISlider *unlinkedPositionSlider;
@property(nonatomic) BOOL resumeAfterUnlinkedSeek;
@property(nonatomic) NSUInteger unlinkedSeekGeneration;
@property(nonatomic) NSUInteger pairedSeekGeneration;
@property(nonatomic) BOOL pairedSeekInProgress;
@property(nonatomic) BOOL pairedWantsPlayback;
@property(nonatomic) CMTime pairedMainTarget;
@property(nonatomic) CMTime pairedSubTarget;
@property(nonatomic) CMTime requestedMainTime;
@property(nonatomic) CMTime requestedSubTime;
@end

@implementation WaterJumpComparisonViewController

- (instancetype)initWithMainURL:(NSURL *)mainURL subURL:(NSURL *)subURL {
    if ((self = [super init])) { _mainURL = mainURL; _subURL = subURL; [ReceivedVideoManager recordPlayback:subURL]; [ReceivedVideoManager recordPlayback:mainURL]; _speed = 1.0; _requestedMainTime = kCMTimeInvalid; _requestedSubTime = kCMTimeInvalid; self.modalPresentationStyle = UIModalPresentationFullScreen; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    UITapGestureRecognizer *controlsTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePlayback)];
    controlsTap.delegate = self; controlsTap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:controlsTap];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshFavorites) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshFavorites) name:@"WJVideoFavoritesChanged" object:nil];
    self.mainPlayer = [AVPlayer playerWithURL:self.mainURL];
    self.subPlayer = [AVPlayer playerWithURL:self.subURL];
    self.mainPlayer.automaticallyWaitsToMinimizeStalling = NO;
    self.subPlayer.automaticallyWaitsToMinimizeStalling = NO;
    self.mainZoomScale = 1.0; self.subZoomScale = 1.0;
    self.mainLayer = [AVPlayerLayer playerLayerWithPlayer:self.mainPlayer];
    self.subLayer = [AVPlayerLayer playerLayerWithPlayer:self.subPlayer];
    self.mainLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.subLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(comparisonPinched:)];
    [self.view addGestureRecognizer:pinch];
    self.mainLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.subLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.mainViewport = [CALayer layer]; self.subViewport = [CALayer layer];
    self.mainViewport.masksToBounds = YES; self.subViewport.masksToBounds = YES;
    [self.view.layer addSublayer:self.mainViewport]; [self.view.layer addSublayer:self.subViewport];
    [self.mainViewport addSublayer:self.mainLayer]; [self.subViewport addSublayer:self.subLayer];
    [self refreshComparisonAspects];
    self.mainLabel = [self label:@"MAIN"]; self.subLabel = [self label:@"SUB"];
    self.mainLabel.text = [self receivedTitle:@"MAIN" videoURL:self.mainURL];
    self.subLabel.text = [self receivedTitle:@"SUB" videoURL:self.subURL];
    self.mainLabel.adjustsFontSizeToFitWidth = YES; self.subLabel.adjustsFontSizeToFitWidth = YES;
    self.mainLabel.minimumScaleFactor = .65; self.subLabel.minimumScaleFactor = .65;
    [self.view addSubview:self.mainLabel]; [self.view addSubview:self.subLabel];
    self.mainTimeLabel = [self playbackCounterLabel]; self.subTimeLabel = [self playbackCounterLabel];
    self.mainTimeLabel.accessibilityLabel = @"MAIN 再生時間"; self.subTimeLabel.accessibilityLabel = @"SUB 再生時間";
    [self.view addSubview:self.mainTimeLabel]; [self.view addSubview:self.subTimeLabel];
    self.unlinkedPositionSlider = [UISlider new]; self.unlinkedPositionSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.unlinkedPositionSlider.minimumTrackTintColor = UIColor.systemGreenColor;
    self.unlinkedPositionSlider.thumbTintColor = UIColor.systemGreenColor;
    self.unlinkedPositionSlider.accessibilityLabel = @"同期設定前の2画面共通再生位置";
    [self.unlinkedPositionSlider addTarget:self action:@selector(unlinkedSeekBegan:) forControlEvents:UIControlEventTouchDown];
    [self.unlinkedPositionSlider addTarget:self action:@selector(unlinkedSeekChanged:) forControlEvents:UIControlEventValueChanged];
    [self.unlinkedPositionSlider addTarget:self action:@selector(unlinkedSeekEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.view addSubview:self.unlinkedPositionSlider];
    self.positionSlider = [WJSyncPositionSlider new]; self.positionSlider.minimumValue = 0; self.positionSlider.maximumValue = 1;
    [self.positionSlider addTarget:self action:@selector(positionChanged:) forControlEvents:UIControlEventValueChanged];
    self.mainPositionSlider = [WJSyncPositionSlider new]; self.mainPositionSlider.minimumValue = 0; self.mainPositionSlider.maximumValue = 1; [self.mainPositionSlider addTarget:self action:@selector(individualPositionChanged:) forControlEvents:UIControlEventValueChanged];
    self.subPositionSlider = [WJSyncPositionSlider new]; self.subPositionSlider.minimumValue = 0; self.subPositionSlider.maximumValue = 1; [self.subPositionSlider addTarget:self action:@selector(individualPositionChanged:) forControlEvents:UIControlEventValueChanged];
    self.speedSlider = [UISlider new]; self.speedSlider.minimumValue = .2; self.speedSlider.maximumValue = 1.0; self.speedSlider.value = 1.0;
    // 通常の再生画面と同じ、控えめな速度調整用カラーに統一する。
    self.speedSlider.minimumTrackTintColor = [UIColor colorWithWhite:0.82 alpha:0.75];
    self.speedSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.55 alpha:0.35];
    [self.speedSlider addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    self.speedValueLabel = [UILabel new];
    self.speedValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedValueLabel.text = @"1.00×";
    self.speedValueLabel.textColor = UIColor.whiteColor;
    self.speedValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    self.speedValueLabel.textAlignment = NSTextAlignmentCenter;
    self.playButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; self.playButton.tintColor = UIColor.whiteColor; [self.playButton addTarget:self action:@selector(togglePlay:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem]; [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal]; close.tintColor = UIColor.whiteColor; [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    self.shareButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.shareButton setImage:[UIImage systemImageNamed:@"square.and.arrow.up"] forState:UIControlStateNormal]; self.shareButton.tintColor = UIColor.whiteColor; [self.shareButton addTarget:self action:@selector(shareVideos:) forControlEvents:UIControlEventTouchUpInside];
    self.exportButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.exportButton setImage:[UIImage systemImageNamed:@"square.and.arrow.down"] forState:UIControlStateNormal]; self.exportButton.tintColor = UIColor.whiteColor; self.exportButton.accessibilityLabel = @"比較動画を書き出す"; [self.exportButton addTarget:self action:@selector(exportComparisonVideo:) forControlEvents:UIControlEventTouchUpInside];
    self.favoriteButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.favoriteButton setImage:[UIImage systemImageNamed:@"heart"] forState:UIControlStateNormal]; self.favoriteButton.tintColor = UIColor.whiteColor; [self.favoriteButton addTarget:self action:@selector(toggleFavorites:) forControlEvents:UIControlEventTouchUpInside];
    self.selectVideoButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.selectVideoButton setImage:[UIImage systemImageNamed:@"plus.rectangle.on.rectangle"] forState:UIControlStateNormal]; self.selectVideoButton.tintColor = UIColor.systemGreenColor; self.selectVideoButton.backgroundColor = [UIColor colorWithWhite:0 alpha:.25]; self.selectVideoButton.layer.cornerRadius = 7; self.selectVideoButton.accessibilityLabel = @"比較する動画を選択"; [self.selectVideoButton addTarget:self action:@selector(selectComparisonVideo:) forControlEvents:UIControlEventTouchUpInside];
    [self.selectVideoButton.widthAnchor constraintEqualToConstant:38].active = YES;
    [self.selectVideoButton.heightAnchor constraintEqualToConstant:36].active = YES;
    self.linkButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.linkButton setImage:[UIImage systemImageNamed:@"link"] forState:UIControlStateNormal]; self.linkButton.tintColor = UIColor.systemGreenColor; self.linkButton.backgroundColor = [UIColor colorWithWhite:0 alpha:.45]; self.linkButton.layer.cornerRadius = 18; self.linkButton.layer.borderWidth = 0; self.linkButton.accessibilityLabel = @"2画面シーク連動"; [self.linkButton addTarget:self action:@selector(toggleLink:) forControlEvents:UIControlEventTouchUpInside];
    self.mainBackButton = [self transportButton:@"backward.frame" action:@selector(individualTransport:) tag:1];
    self.mainPlayButton = [self transportButton:@"play.fill" action:@selector(individualTransport:) tag:2];
    self.mainForwardButton = [self transportButton:@"forward.frame" action:@selector(individualTransport:) tag:3];
    self.subBackButton = [self transportButton:@"backward.frame" action:@selector(individualTransport:) tag:4];
    self.subPlayButton = [self transportButton:@"play.fill" action:@selector(individualTransport:) tag:5];
    self.subForwardButton = [self transportButton:@"forward.frame" action:@selector(individualTransport:) tag:6];
    self.syncPointButton = [self transportButton:@"arrow.counterclockwise" action:@selector(returnToSyncPoint:) tag:7];
    self.syncBackButton = [self transportButton:@"backward.frame" action:@selector(syncFrameStep:) tag:8];
    self.syncForwardButton = [self transportButton:@"forward.frame" action:@selector(syncFrameStep:) tag:9];
    UIButton *layoutButton = [UIButton buttonWithType:UIButtonTypeSystem]; [layoutButton setImage:[UIImage systemImageNamed:@"rectangle.split.2x1"] forState:UIControlStateNormal]; layoutButton.tintColor = UIColor.whiteColor; [layoutButton addTarget:self action:@selector(toggleLayout:) forControlEvents:UIControlEventTouchUpInside];
    self.aButton = [self featureButton:@"A" action:@selector(setA:)];
    self.bButton = [self featureButton:@"B" action:@selector(setB:)];
    self.loopButton = [self featureButton:@"↻" action:@selector(toggleLoop:)];
    // A/Bと同じ固定幅で表示し、シンボルの内容余白で横に広がらないようにする。
    self.loopButton.contentEdgeInsets = UIEdgeInsetsZero;
    self.loopButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    [self.loopButton.widthAnchor constraintEqualToConstant:38].active = YES;
    [self.loopButton.heightAnchor constraintEqualToConstant:36].active = YES;
    self.frameButton = [self featureButton:@"▸|" action:@selector(stepFrame:)];
    self.mainMirrorButton = [self featureButton:@"M1" action:@selector(toggleMainMirror:)];
    self.subMirrorButton = [self featureButton:@"M2" action:@selector(toggleSubMirror:)];
    for (UIView *view in @[self.positionSlider, self.mainPositionSlider, self.subPositionSlider, self.speedSlider, self.speedValueLabel, self.playButton, close, self.shareButton, self.exportButton, self.favoriteButton, self.selectVideoButton, self.linkButton, self.mainBackButton, self.mainPlayButton, self.mainForwardButton, self.subBackButton, self.subPlayButton, self.subForwardButton, self.syncPointButton, self.syncBackButton, self.syncForwardButton, layoutButton, self.aButton, self.bButton, self.loopButton, self.mainMirrorButton, self.subMirrorButton]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:view]; }
    self.sharedFeatureStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.aButton, self.bButton, self.loopButton, self.syncPointButton]];
    self.sharedFeatureStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.sharedFeatureStack.axis = UILayoutConstraintAxisHorizontal;
    self.sharedFeatureStack.alignment = UIStackViewAlignmentCenter;
    self.sharedFeatureStack.distribution = UIStackViewDistributionEqualSpacing;
    self.sharedFeatureStack.spacing = 6.0;
    [self.view addSubview:self.sharedFeatureStack];
    self.frameButton.hidden = YES;
    [NSLayoutConstraint activateConstraints:@[[self.unlinkedPositionSlider.leadingAnchor constraintEqualToAnchor:self.positionSlider.leadingAnchor], [self.unlinkedPositionSlider.trailingAnchor constraintEqualToAnchor:self.positionSlider.trailingAnchor], [self.unlinkedPositionSlider.centerYAnchor constraintEqualToAnchor:self.positionSlider.centerYAnchor]]];
    self.positionSlider.accessibilityLabel = @"比較再生位置"; self.speedSlider.accessibilityLabel = @"比較再生速度";
    self.bottomControlGuide = [UILayoutGuide new];
    [self.view addLayoutGuide:self.bottomControlGuide];
    [NSLayoutConstraint activateConstraints:@[
        [self.positionSlider.leadingAnchor constraintEqualToAnchor:self.syncBackButton.trailingAnchor constant:8], [self.positionSlider.trailingAnchor constraintEqualToAnchor:self.syncForwardButton.leadingAnchor constant:-8], [self.positionSlider.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-48],
        [self.speedSlider.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12], [self.speedSlider.trailingAnchor constraintEqualToAnchor:self.speedValueLabel.leadingAnchor constant:-8], [self.speedSlider.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [self.speedValueLabel.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12], [self.speedValueLabel.centerYAnchor constraintEqualToAnchor:self.speedSlider.centerYAnchor], [self.speedValueLabel.widthAnchor constraintEqualToConstant:48],
        [self.playButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:10], [self.playButton.centerYAnchor constraintEqualToAnchor:self.positionSlider.centerYAnchor], [self.playButton.widthAnchor constraintEqualToConstant:38], [self.playButton.heightAnchor constraintEqualToConstant:36],
        [self.syncBackButton.leadingAnchor constraintEqualToAnchor:self.playButton.trailingAnchor constant:4], [self.syncBackButton.centerYAnchor constraintEqualToAnchor:self.positionSlider.centerYAnchor], [self.syncBackButton.widthAnchor constraintEqualToConstant:36], [self.syncBackButton.heightAnchor constraintEqualToConstant:36],
        [self.selectVideoButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12], [self.selectVideoButton.centerYAnchor constraintEqualToAnchor:self.sharedFeatureStack.centerYAnchor], [self.sharedFeatureStack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12], [self.sharedFeatureStack.trailingAnchor constraintEqualToAnchor:self.selectVideoButton.leadingAnchor constant:-12], [self.sharedFeatureStack.centerYAnchor constraintEqualToAnchor:self.speedSlider.topAnchor constant:-45], [self.sharedFeatureStack.heightAnchor constraintEqualToConstant:36],
        [self.syncForwardButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12], [self.syncForwardButton.centerYAnchor constraintEqualToAnchor:self.positionSlider.centerYAnchor], [self.syncForwardButton.widthAnchor constraintEqualToConstant:36], [self.syncForwardButton.heightAnchor constraintEqualToConstant:36],
        [close.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12], [close.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4], [close.widthAnchor constraintEqualToConstant:44], [close.heightAnchor constraintEqualToConstant:44],
        [self.favoriteButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12], [self.favoriteButton.topAnchor constraintEqualToAnchor:close.topAnchor], [self.favoriteButton.widthAnchor constraintEqualToConstant:44], [self.favoriteButton.heightAnchor constraintEqualToConstant:44],
        [self.shareButton.trailingAnchor constraintEqualToAnchor:self.favoriteButton.leadingAnchor constant:-4], [self.shareButton.topAnchor constraintEqualToAnchor:close.topAnchor], [self.shareButton.widthAnchor constraintEqualToConstant:44], [self.shareButton.heightAnchor constraintEqualToConstant:44],
        [self.exportButton.trailingAnchor constraintEqualToAnchor:self.shareButton.leadingAnchor constant:-4], [self.exportButton.topAnchor constraintEqualToAnchor:close.topAnchor], [self.exportButton.widthAnchor constraintEqualToConstant:44], [self.exportButton.heightAnchor constraintEqualToConstant:44],
        [layoutButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:62], [layoutButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4], [layoutButton.widthAnchor constraintEqualToConstant:44], [layoutButton.heightAnchor constraintEqualToConstant:44]
    ]];
    self.mainLabel.translatesAutoresizingMaskIntoConstraints = YES;
    self.subLabel.translatesAutoresizingMaskIntoConstraints = YES;
    self.linkButton.translatesAutoresizingMaskIntoConstraints = YES;
    self.mainPositionSlider.translatesAutoresizingMaskIntoConstraints = YES;
    self.subPositionSlider.translatesAutoresizingMaskIntoConstraints = YES;
    self.mainMirrorButton.translatesAutoresizingMaskIntoConstraints = YES;
    self.subMirrorButton.translatesAutoresizingMaskIntoConstraints = YES;
    for (UIView *view in @[self.mainBackButton, self.mainPlayButton, self.mainForwardButton, self.subBackButton, self.subPlayButton, self.subForwardButton]) view.translatesAutoresizingMaskIntoConstraints = YES;
    __weak typeof(self) weakSelf = self;
    self.observer = [self.mainPlayer addPeriodicTimeObserverForInterval:CMTimeMake(1, 10) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) { [weakSelf updatePosition]; }];
    self.subTimeObserver = [self.subPlayer addPeriodicTimeObserverForInterval:CMTimeMake(1, 10) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) { [weakSelf updatePlaybackCounters]; }];
    self.loopStart = kCMTimeInvalid; self.loopEnd = kCMTimeInvalid; self.subLoopStart = kCMTimeInvalid; self.subLoopEnd = kCMTimeInvalid; self.linkedMainAnchor = kCMTimeInvalid; self.linkedSubAnchor = kCMTimeInvalid; self.linkedPlayback = NO; self.sideBySide = YES; [self refreshComparisonFeatureButtons]; [self updateLinkControls];
}

- (NSString *)receivedTitle:(NSString *)title videoURL:(NSURL *)url {
    if (!self.showsReceivedCameraNames) return title;
    NSData *data = [NSData dataWithContentsOfURL:[url URLByAppendingPathExtension:@"wj.json"]];
    id info = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    id value = [info isKindOfClass:NSDictionary.class] ? info[@"cameraName"] : nil;
    NSString *name = [value isKindOfClass:NSString.class] ? [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    return name.length ? [NSString stringWithFormat:@"%@ %@", title, name] : title;
}
- (UILabel *)playbackCounterLabel {
    UILabel *label = [self label:@"00:00.00/00:00.00"];
    label.translatesAutoresizingMaskIntoConstraints = YES;
    label.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter; label.adjustsFontSizeToFitWidth = YES; label.minimumScaleFactor = .65;
    label.userInteractionEnabled = NO;
    return label;
}
- (NSString *)formattedCounterTime:(double)seconds {
    if (!isfinite(seconds) || seconds < 0) seconds = 0;
    NSInteger minutes = (NSInteger)(seconds / 60.0);
    return [NSString stringWithFormat:@"%02ld:%05.2f", (long)minutes, seconds-minutes*60.0];
}
- (void)updatePlaybackCounters {
    NSArray<AVPlayer *> *players = @[self.mainPlayer,self.subPlayer];
    NSArray<UILabel *> *labels = @[self.mainTimeLabel,self.subTimeLabel];
    for (NSUInteger i=0; i<players.count; i++) {
        double duration = CMTimeGetSeconds(players[i].currentItem.duration);
        double current = CMTimeGetSeconds(players[i].currentTime);
        labels[i].text = [NSString stringWithFormat:@"%@/%@", [self formattedCounterTime:current], [self formattedCounterTime:duration]];
    }
}
- (UILabel *)label:(NSString *)text { UILabel *label = [UILabel new]; label.text = text; label.textColor = UIColor.whiteColor; label.backgroundColor = [UIColor colorWithWhite:0 alpha:.45]; label.translatesAutoresizingMaskIntoConstraints = NO; return label; }
- (UIButton *)featureButton:(NSString *)title action:(SEL)action { UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; NSDictionary *symbols = @{@"A": @"a.circle", @"B": @"b.circle", @"↻": @"repeat", @"▸|": @"forward.frame", @"M1": @"arrow.left.and.right.righttriangle.left.righttriangle.right", @"M2": @"arrow.left.and.right.righttriangle.left.righttriangle.right"}; NSString *symbol = symbols[title]; if (symbol) { [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal]; button.accessibilityLabel = title; } else { [button setTitle:title forState:UIControlStateNormal]; button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; } button.tintColor = UIColor.whiteColor; button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25]; button.layer.cornerRadius = 7; [button.widthAnchor constraintEqualToConstant:38].active = YES; [button.heightAnchor constraintEqualToConstant:36].active = YES; [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button; }
- (void)refreshComparisonFeatureButtons {
    UIColor *off = [UIColor colorWithWhite:0 alpha:0.25];
    self.aButton.backgroundColor = CMTIME_IS_VALID(self.loopStart) ? [UIColor.systemGreenColor colorWithAlphaComponent:.55] : off;
    self.bButton.backgroundColor = CMTIME_IS_VALID(self.loopEnd) ? [UIColor.systemGreenColor colorWithAlphaComponent:.55] : off;
    self.loopButton.backgroundColor = self.loopEnabled ? [UIColor.systemBlueColor colorWithAlphaComponent:.5] : off;
    // 通常再生画面と同じく、選択状態は背景色で示し、シンボル自体は固定する。
    [self.aButton setImage:[UIImage systemImageNamed:(CMTIME_IS_VALID(self.loopStart) ? @"a.circle.fill" : @"a.circle")] forState:UIControlStateNormal];
    [self.bButton setImage:[UIImage systemImageNamed:(CMTIME_IS_VALID(self.loopEnd) ? @"b.circle.fill" : @"b.circle")] forState:UIControlStateNormal];
    [self.loopButton setImage:[UIImage systemImageNamed:@"repeat"] forState:UIControlStateNormal];
}
- (void)updateIndividualTransportButtons { [self.mainPlayButton setImage:[UIImage systemImageNamed:(self.mainPlayer.rate > 0 ? @"pause.fill" : @"play.fill")] forState:UIControlStateNormal]; [self.subPlayButton setImage:[UIImage systemImageNamed:(self.subPlayer.rate > 0 ? @"pause.fill" : @"play.fill")] forState:UIControlStateNormal]; }
- (UIButton *)transportButton:(NSString *)symbol action:(SEL)action tag:(NSInteger)tag { UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal]; button.tintColor = UIColor.whiteColor; button.backgroundColor = [UIColor colorWithWhite:0 alpha:.45]; button.layer.cornerRadius = 6; button.tag = tag; [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button; }
- (void)updateLinkControls { self.unlinkedPositionSlider.hidden = self.linkedPlayback; for (UIView *view in @[self.positionSlider, self.speedSlider, self.speedValueLabel, self.playButton, self.syncBackButton, self.syncForwardButton, self.sharedFeatureStack]) view.hidden = !self.linkedPlayback; self.mainPositionSlider.hidden = self.linkedPlayback; self.subPositionSlider.hidden = self.linkedPlayback; self.mainTimeLabel.hidden = self.linkedPlayback; self.subTimeLabel.hidden = self.linkedPlayback; for (UIView *view in @[self.mainBackButton, self.mainPlayButton, self.mainForwardButton, self.subBackButton, self.subPlayButton, self.subForwardButton, self.mainMirrorButton, self.subMirrorButton]) view.hidden = self.linkedPlayback; self.selectVideoButton.hidden = NO; [self updateSyncMarkers]; self.syncPointButton.enabled = self.linkedPlayback; self.syncPointButton.alpha = self.linkedPlayback ? 1.0 : .35; self.linkButton.tintColor = [UIColor.systemGreenColor colorWithAlphaComponent:self.linkedPlayback ? 1.0 : .3]; [self.linkButton setImage:[UIImage systemImageNamed:@"link"] forState:UIControlStateNormal]; self.linkButton.accessibilityValue = self.linkedPlayback ? @"選択中：2画面を連動" : @"未選択：個別操作"; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }
- (BOOL)shouldAutorotate { return YES; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self refreshFavorites];
    [self setNeedsUpdateOfSupportedInterfaceOrientations];
    [UIViewController attemptRotationToDeviceOrientation];
}
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    if (size.width > size.height) self.sideBySide = YES;
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.view setNeedsLayout]; [self.view layoutIfNeeded];
    } completion:nil];
}
- (void)refreshComparisonAspects {
    AVAssetTrack *main = [self.mainPlayer.currentItem.asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    AVAssetTrack *sub = [self.subPlayer.currentItem.asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    self.comparisonAspects = WJComparisonAspects(WJOrientedTrackSize(main), WJOrientedTrackSize(sub));
    [self.view setNeedsLayout];
}
- (void)layoutPlayerLayer:(AVPlayerLayer *)layer inViewport:(CALayer *)viewport rect:(CGRect)rect zoom:(CGFloat)zoom mirrored:(BOOL)mirrored {
    viewport.frame = rect;
    layer.bounds = CGRectMake(0, 0, rect.size.width, rect.size.height);
    layer.position = CGPointMake(rect.size.width / 2, rect.size.height / 2);
    layer.affineTransform = CGAffineTransformMakeScale(mirrored ? -zoom : zoom, zoom);
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat top = CGRectGetMinY(safe) + 48, bottom = CGRectGetMaxY(safe) - 112;
    CGRect area = CGRectMake(safe.origin.x, top, safe.size.width, MAX(1, bottom - top));
    CGRect mainRect, subRect;
    WJComparisonRects(area, self.comparisonAspects, self.sideBySide, &mainRect, &subRect);
    CGFloat boundaryX = CGRectGetMaxX(mainRect), boundaryY = self.sideBySide ? CGRectGetMidY(area) : CGRectGetMaxY(mainRect);
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    [self layoutPlayerLayer:self.mainLayer inViewport:self.mainViewport rect:mainRect zoom:self.mainZoomScale mirrored:self.mainMirrored];
    [self layoutPlayerLayer:self.subLayer inViewport:self.subViewport rect:subRect zoom:self.subZoomScale mirrored:self.subMirrored];
    [CATransaction commit];
 [self.mainLabel sizeToFit]; [self.subLabel sizeToFit]; CGFloat labelX = 12.0; self.mainLabel.frame = CGRectMake(mainRect.origin.x + labelX, mainRect.origin.y + 8.0, MIN(self.mainLabel.bounds.size.width,MAX(1,mainRect.size.width-24)), self.mainLabel.bounds.size.height); self.subLabel.frame = CGRectMake(subRect.origin.x + labelX, subRect.origin.y + 8.0, MIN(self.subLabel.bounds.size.width,MAX(1,subRect.size.width-24)), self.subLabel.bounds.size.height); self.linkButton.frame = CGRectMake((self.sideBySide ? boundaryX : self.view.bounds.size.width / 2.0) - 24.0, boundaryY - 24.0, 48.0, 48.0); CGFloat sliderHeight = 32.0, sliderYMain = CGRectGetMaxY(mainRect) - sliderHeight - 42.0, sliderYSub = CGRectGetMaxY(subRect) - sliderHeight - 42.0; self.mainPositionSlider.frame = CGRectMake(mainRect.origin.x + 24, sliderYMain, MAX(1, mainRect.size.width - 48), sliderHeight); self.subPositionSlider.frame = CGRectMake(subRect.origin.x + 24, sliderYSub, MAX(1, subRect.size.width - 48), sliderHeight); self.mainTimeLabel.frame = CGRectMake(CGRectGetMinX(self.mainPositionSlider.frame), CGRectGetMaxY(self.mainPositionSlider.frame)+2, CGRectGetWidth(self.mainPositionSlider.frame), 22);
    self.subTimeLabel.frame = CGRectMake(CGRectGetMinX(self.subPositionSlider.frame), CGRectGetMaxY(self.subPositionSlider.frame)+2, CGRectGetWidth(self.subPositionSlider.frame), 22);
    [self layoutTransportButton:self.mainBackButton play:self.mainPlayButton forward:self.mainForwardButton inRect:mainRect sliderY:sliderYMain]; [self layoutTransportButton:self.subBackButton play:self.subPlayButton forward:self.subForwardButton inRect:subRect sliderY:sliderYSub]; CGFloat mirrorSize = 36.0; self.mainMirrorButton.frame = CGRectMake(CGRectGetMaxX(self.mainForwardButton.frame) + 6.0, self.mainForwardButton.frame.origin.y, mirrorSize, mirrorSize); self.subMirrorButton.frame = CGRectMake(CGRectGetMaxX(self.subForwardButton.frame) + 6.0, self.subForwardButton.frame.origin.y, mirrorSize, mirrorSize); [self.view bringSubviewToFront:self.linkButton]; [self.view bringSubviewToFront:self.syncBackButton]; [self.view bringSubviewToFront:self.playButton]; [self.view bringSubviewToFront:self.syncForwardButton]; [self.view bringSubviewToFront:self.mainMirrorButton]; [self.view bringSubviewToFront:self.subMirrorButton]; [self.view bringSubviewToFront:self.mainPositionSlider]; [self.view bringSubviewToFront:self.subPositionSlider]; [self updateSyncMarkers]; }
- (void)layoutTransportButton:(UIButton *)back play:(UIButton *)play forward:(UIButton *)forward inRect:(CGRect)rect sliderY:(CGFloat)sliderY { CGFloat size = 36.0, gap = 6.0, total = size * 4 + gap * 3; CGFloat x = CGRectGetMidX(rect) - total / 2.0; CGFloat y = sliderY - size - 4.0; back.frame = CGRectMake(x, y, size, size); play.frame = CGRectMake(x + size + gap, y, size, size); forward.frame = CGRectMake(x + (size + gap) * 2, y, size, size); }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (![gesture isKindOfClass:UITapGestureRecognizer.class]) return YES;
    for (UIView *view = touch.view; view && view != self.view; view = view.superview) {
        if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UIScrollView.class]) return NO;
    }
    return [touch locationInView:self.view].y >= CGRectGetMaxY(UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets))-112;
}
- (void)togglePlayback {
    double duration = CMTimeGetSeconds(self.mainPlayer.currentItem.duration), current = CMTimeGetSeconds(self.mainPlayer.currentTime);
    if (!self.linkedPlayback && !self.pairedSeekInProgress && self.mainPlayer.rate == 0 && self.subPlayer.rate == 0 && isfinite(duration) && duration > 0 && isfinite(current) && current >= duration-.05) {
        [self seekPairMain:kCMTimeZero sub:kCMTimeZero play:YES];
        return;
    }
    [self togglePlay:nil];
}
- (void)togglePlay:(id)sender {
    BOOL playing = self.mainPlayer.rate > 0 || self.subPlayer.rate > 0 || (self.pairedSeekInProgress && self.pairedWantsPlayback);
    if (playing) { [self pausePlayback]; }
    else if (self.linkedPlayback && self.hasLinkedAnchors) {
        WJSyncRange range = [self sharedSyncRange];
        double relative = self.pairedSeekInProgress ? CMTimeGetSeconds(self.pairedMainTarget)-CMTimeGetSeconds(self.linkedMainAnchor) : CMTimeGetSeconds(self.mainPlayer.currentTime)-CMTimeGetSeconds(self.linkedMainAnchor);
        if (relative >= range.upper-.01) relative = range.lower;
        [self seekLinkedRelative:relative play:YES];
    } else { self.mainPlayer.rate = self.speed; self.subPlayer.rate = self.speed; }
    [self.playButton setImage:[UIImage systemImageNamed:playing ? @"play.fill" : @"pause.fill"] forState:UIControlStateNormal];
    [self updateIndividualTransportButtons];
}

- (void)startPlayback {
    NSTimeInterval mainStart = [ReceivedVideoManager recordingStartTime:self.mainURL];
    NSTimeInterval subStart = [ReceivedVideoManager recordingStartTime:self.subURL];
    double mainSeconds = 0, subSeconds = 0;
    if (isfinite(mainStart) && isfinite(subStart) && mainStart > 0 && subStart > 0) {
        double common = MAX(mainStart,subStart);
        double mainOffset = common-mainStart, subOffset = common-subStart;
        double mainDuration = CMTimeGetSeconds(self.mainPlayer.currentItem.asset.duration), subDuration = CMTimeGetSeconds(self.subPlayer.currentItem.asset.duration);
        if (isfinite(mainDuration) && isfinite(subDuration) && mainOffset < mainDuration && subOffset < subDuration) { mainSeconds = mainOffset; subSeconds = subOffset; }
    }
    CMTime mainTime = CMTimeMakeWithSeconds(mainSeconds,1000000), subTime = CMTimeMakeWithSeconds(subSeconds,1000000);
    [self configureAutomaticLoop]; [self seekPairMain:mainTime sub:subTime play:YES];
}
- (void)unlinkedSeekBegan:(UISlider *)slider { self.pairedSeekGeneration += 1; self.pairedSeekInProgress = NO; self.pairedWantsPlayback = NO; self.unlinkedSeekGeneration += 1; self.resumeAfterUnlinkedSeek = YES; [self.mainPlayer pause]; [self.subPlayer pause]; }
- (void)unlinkedSeekChanged:(UISlider *)slider {
    if (self.linkedPlayback) return;
    double duration = MIN(CMTimeGetSeconds(self.mainPlayer.currentItem.duration), CMTimeGetSeconds(self.subPlayer.currentItem.duration));
    if (!isfinite(duration) || duration <= 0) return;
    CMTime time = CMTimeMakeWithSeconds(duration * slider.value, 600);
    [self.mainPlayer seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    [self.subPlayer seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    [self updateIndividualTransportButtons];
}
- (void)unlinkedSeekEnded:(UISlider *)slider {
    double duration = MIN(CMTimeGetSeconds(self.mainPlayer.currentItem.duration), CMTimeGetSeconds(self.subPlayer.currentItem.duration));
    if (self.linkedPlayback || !isfinite(duration) || duration <= 0) return;
    BOOL resume = self.resumeAfterUnlinkedSeek; self.resumeAfterUnlinkedSeek = NO;
    NSUInteger generation = self.unlinkedSeekGeneration;
    CMTime time = CMTimeMakeWithSeconds(duration * slider.value, 600);
    dispatch_group_t seeks = dispatch_group_create(); __block BOOL finishedAll = YES;
    for (AVPlayer *player in @[self.mainPlayer, self.subPlayer]) {
        dispatch_group_enter(seeks);
        [player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
            dispatch_async(dispatch_get_main_queue(), ^{ finishedAll = finishedAll && finished; dispatch_group_leave(seeks); });
        }];
    }
    dispatch_group_notify(seeks, dispatch_get_main_queue(), ^{
        if (resume && finishedAll && generation == self.unlinkedSeekGeneration && !self.linkedPlayback && self.view.window) { self.mainPlayer.rate = self.speed; self.subPlayer.rate = self.speed; }
        [self updateIndividualTransportButtons];
    });
}
- (void)positionChanged:(UISlider *)slider {
    [self pausePlayback];
    if (self.linkedPlayback && self.hasLinkedAnchors) [self seekLinkedElapsed:[self linkedDurationSeconds] * slider.value];
}

- (void)individualPositionChanged:(UISlider *)slider {
    [self pausePlayback];
    AVPlayer *player = slider == self.mainPositionSlider ? self.mainPlayer : self.subPlayer;
    double duration = CMTimeGetSeconds(player.currentItem.duration);
    if (isfinite(duration) && duration > 0) [self seekIndividualPlayer:player time:CMTimeMakeWithSeconds(duration * slider.value, 600)];
}

- (void)toggleLink:(id)sender {
    self.unlinkedSeekGeneration += 1; self.resumeAfterUnlinkedSeek = NO;
    if (!self.linkedPlayback) {
        BOOL playing = self.mainPlayer.rate > 0 || self.subPlayer.rate > 0;
        [self.mainPlayer pause]; [self.subPlayer pause];
        self.linkedMainAnchor = CMTIME_IS_NUMERIC(self.requestedMainTime) ? self.requestedMainTime : self.mainPlayer.currentTime;
        self.linkedSubAnchor = CMTIME_IS_NUMERIC(self.requestedSubTime) ? self.requestedSubTime : self.subPlayer.currentTime;
        self.hasLinkedAnchors = CMTIME_IS_NUMERIC(self.linkedMainAnchor) && CMTIME_IS_NUMERIC(self.linkedSubAnchor);
        self.linkedPlayback = self.hasLinkedAnchors;
        self.requestedMainTime = kCMTimeInvalid; self.requestedSubTime = kCMTimeInvalid;
        if (self.linkedPlayback) [self seekLinkedRelative:0 play:playing];
    } else {
        self.linkedPlayback = NO; self.pairedWantsPlayback = NO;
        self.pairedSeekGeneration += 1; self.pairedSeekInProgress = NO;
    }
    [self updateLinkControls]; [self updatePosition]; [self.view setNeedsLayout];
}

- (void)toggleLayout:(id)sender { self.sideBySide = !self.sideBySide; [self.view setNeedsLayout]; }
- (void)speedChanged:(UISlider *)slider {
    self.speed = roundf(slider.value * 100) / 100; self.speedValueLabel.text = [NSString stringWithFormat:@"%.2f×", self.speed];
    if (self.linkedPlayback && (self.mainPlayer.rate > 0 || (self.pairedSeekInProgress && self.pairedWantsPlayback))) {
        double relative = (self.pairedSeekInProgress ? CMTimeGetSeconds(self.pairedMainTarget) : CMTimeGetSeconds(self.mainPlayer.currentTime)) - CMTimeGetSeconds(self.linkedMainAnchor);
        [self seekLinkedRelative:relative play:YES];
    } else if (!self.linkedPlayback) { BOOL playing = self.mainPlayer.rate > 0; self.mainPlayer.rate = playing ? self.speed : 0; self.subPlayer.rate = playing ? self.speed : 0; }
}

- (void)updatePosition { [self updatePlaybackCounters]; [self updateSyncMarkers]; double commonDuration = MIN(CMTimeGetSeconds(self.mainPlayer.currentItem.duration), CMTimeGetSeconds(self.subPlayer.currentItem.duration)); if (!self.unlinkedPositionSlider.isTracking && isfinite(commonDuration) && commonDuration > 0) self.unlinkedPositionSlider.value = MIN(1, MAX(0, CMTimeGetSeconds(self.mainPlayer.currentTime) / commonDuration)); [self updateIndividualTransportButtons]; double duration = CMTimeGetSeconds(self.mainPlayer.currentItem.duration); double current = CMTimeGetSeconds(self.mainPlayer.currentTime); double subDuration = CMTimeGetSeconds(self.subPlayer.currentItem.duration); double subCurrent = CMTimeGetSeconds(self.subPlayer.currentTime); if (self.linkedPlayback && self.hasLinkedAnchors) { double linkedDuration = [self linkedDurationSeconds]; WJSyncRange range = [self sharedSyncRange]; double linkedStart = CMTimeGetSeconds(self.linkedMainAnchor) + range.lower; double elapsed = MAX(0, CMTimeGetSeconds(self.mainPlayer.currentTime) - linkedStart); if (linkedDuration > 0 && !self.positionSlider.isTracking && !self.pairedSeekInProgress) self.positionSlider.value = MIN(1, elapsed / linkedDuration); if (!self.pairedSeekInProgress && self.mainPlayer.rate > 0 && linkedDuration > 0 && elapsed >= linkedDuration - .001) { [self seekLinkedRelative:range.upper play:NO]; } } else if (isfinite(duration) && duration > 0 && isfinite(current)) { self.positionSlider.value = current / duration; } if (!self.mainPositionSlider.isTracking && !CMTIME_IS_NUMERIC(self.requestedMainTime) && isfinite(duration) && duration > 0 && isfinite(current)) self.mainPositionSlider.value = current / duration; if (!self.subPositionSlider.isTracking && !CMTIME_IS_NUMERIC(self.requestedSubTime) && isfinite(subDuration) && subDuration > 0 && isfinite(subCurrent)) self.subPositionSlider.value = subCurrent / subDuration; if (!self.pairedSeekInProgress && !self.loopSeekInProgress && self.loopEnabled && CMTIME_IS_VALID(self.loopEnd) && current >= CMTimeGetSeconds(self.loopEnd)) { self.loopSeekInProgress = YES; if (self.linkedPlayback && self.hasLinkedAnchors) { [self seekLinkedRelative:CMTimeGetSeconds(self.loopStart)-CMTimeGetSeconds(self.linkedMainAnchor) play:YES]; } else { [self seekPairMain:self.loopStart sub:self.loopStart play:YES]; }  [self updateIndividualTransportButtons]; return; } if (self.linkedPlayback) return; if (self.automaticLoopLimit == 0 || !isfinite(duration) || duration <= 0 || !isfinite(current) || current < duration - .15) return; if (self.automaticLoopDeadline && [[NSDate date] compare:self.automaticLoopDeadline] != NSOrderedAscending) { self.automaticLoopLimit = 0; return; } if (self.automaticLoopLimit > 0 && self.automaticLoopCount >= self.automaticLoopLimit) { self.automaticLoopLimit = 0; return; } self.automaticLoopCount += 1; [self seekPairMain:kCMTimeZero sub:kCMTimeZero play:YES]; }
- (void)configureAutomaticLoop { NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults; self.automaticLoopLimit = 0; self.automaticLoopCount = 1; self.automaticLoopDeadline = nil; if (![defaults boolForKey:@"WJLoopPlayback"]) return; NSInteger count = [defaults integerForKey:@"WJLoopCount"]; if (count == 0) count = 3; if (count > 0) self.automaticLoopLimit = count; else { self.automaticLoopLimit = -1; NSInteger seconds = [defaults integerForKey:@"WJLoopDuration"]; if (seconds > 0) self.automaticLoopDeadline = [NSDate dateWithTimeIntervalSinceNow:seconds]; } }
- (WJSyncRange)sharedSyncRange {
    if (!self.hasLinkedAnchors) return (WJSyncRange){0,0};
    return WJSharedSyncRange(CMTimeGetSeconds(self.mainPlayer.currentItem.duration), CMTimeGetSeconds(self.subPlayer.currentItem.duration), CMTimeGetSeconds(self.linkedMainAnchor), CMTimeGetSeconds(self.linkedSubAnchor));
}
- (double)linkedDurationSeconds { WJSyncRange range = [self sharedSyncRange]; return MAX(0, range.upper-range.lower); }
- (void)seekPairMain:(CMTime)mainTime sub:(CMTime)subTime play:(BOOL)play {
    NSUInteger generation = ++self.pairedSeekGeneration;
    self.pairedSeekInProgress = YES; self.pairedWantsPlayback = play;
    self.pairedMainTarget = mainTime; self.pairedSubTarget = subTime;
    [self.mainPlayer pause]; [self.subPlayer pause];
    [self.playButton setImage:[UIImage systemImageNamed:play ? @"pause.fill" : @"play.fill"] forState:UIControlStateNormal];
    dispatch_group_t seeks = dispatch_group_create(); __block BOOL completed = YES;
    __weak typeof(self) weakSelf = self;
    for (AVPlayer *player in @[self.mainPlayer,self.subPlayer]) {
        dispatch_group_enter(seeks);
        [player seekToTime:player == self.mainPlayer ? mainTime : subTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
            dispatch_async(dispatch_get_main_queue(), ^{ completed = completed && finished; dispatch_group_leave(seeks); });
        }];
    }
    dispatch_group_notify(seeks, dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (!self || generation != self.pairedSeekGeneration) return;
        [self finishPairedSeekForGeneration:generation completed:completed deadline:CACurrentMediaTime()+15.0];
    });
}
- (void)finishPairedSeekForGeneration:(NSUInteger)generation completed:(BOOL)completed deadline:(CFTimeInterval)deadline {
    if (generation != self.pairedSeekGeneration) return;
    BOOL wantsPlayback = completed && self.pairedWantsPlayback && self.view.window;
    BOOL ready = self.mainPlayer.status == AVPlayerStatusReadyToPlay && self.subPlayer.status == AVPlayerStatusReadyToPlay;
    BOOL failed = self.mainPlayer.status == AVPlayerStatusFailed || self.subPlayer.status == AVPlayerStatusFailed;
    // A successful seek does not guarantee AVPlayer itself is ready for a
    // host-clock playback request. Keep both paused until both players are ready.
    if (wantsPlayback && !ready && !failed && CACurrentMediaTime() < deadline) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.05*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf finishPairedSeekForGeneration:generation completed:completed deadline:deadline];
        });
        return;
    }
    self.pairedSeekInProgress = NO; self.loopSeekInProgress = NO;
    if (wantsPlayback && ready) {
#if DEBUG
            NSLog(@"[Comparison] synchronized start ready main=%ld sub=%ld targets=%.6f/%.6f", (long)self.mainPlayer.status, (long)self.subPlayer.status, CMTimeGetSeconds(self.pairedMainTarget), CMTimeGetSeconds(self.pairedSubTarget));
#endif
            CMTime hostTime = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTimeMakeWithSeconds(.1, 1000000000));
            self.mainPlayer.automaticallyWaitsToMinimizeStalling = NO;
            self.subPlayer.automaticallyWaitsToMinimizeStalling = NO;
            [self.mainPlayer setRate:self.speed time:self.pairedMainTarget atHostTime:hostTime];
            [self.subPlayer setRate:self.speed time:self.pairedSubTarget atHostTime:hostTime];
    } else {
        self.pairedWantsPlayback = NO;
        [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
        if (wantsPlayback && !self.presentedViewController) {
            NSError *error = self.mainPlayer.error ?: self.subPlayer.error;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"動画を再生できませんでした" message:error.localizedDescription ?: @"動画の再生準備が完了しませんでした。再生ボタンで再試行してください。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
    [self updatePosition];
}
- (void)seekLinkedRelative:(double)relative play:(BOOL)play {
    WJSyncRange range = [self sharedSyncRange];
    if (!isfinite(relative) || range.upper <= range.lower) return;
    relative = MAX(range.lower, MIN(range.upper, relative));
    CMTime offset = CMTimeMakeWithSeconds(relative,600);
    [self seekPairMain:CMTimeAdd(self.linkedMainAnchor,offset) sub:CMTimeAdd(self.linkedSubAnchor,offset) play:play];
}
- (void)seekIndividualPlayer:(AVPlayer *)player time:(CMTime)time {
    double duration = CMTimeGetSeconds(player.currentItem.duration);
    if (!isfinite(duration) || duration <= 0 || !CMTIME_IS_NUMERIC(time)) return;
    time = CMTimeMakeWithSeconds(MAX(0, MIN(duration, CMTimeGetSeconds(time))),600);
    BOOL main = player == self.mainPlayer;
    if (main) self.requestedMainTime = time; else self.requestedSubTime = time;
    [player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CMTime requested = main ? self.requestedMainTime : self.requestedSubTime;
            if (CMTIME_IS_NUMERIC(requested) && CMTimeCompare(requested,time) == 0) {
                if (main) self.requestedMainTime = kCMTimeInvalid; else self.requestedSubTime = kCMTimeInvalid;
                [self updatePosition];
            }
        });
    }];
}
- (void)updateSyncMarkers {
    WJSyncRange range = [self sharedSyncRange]; double duration = range.upper-range.lower;
    self.positionSlider.syncFraction = self.hasLinkedAnchors ? (duration > 0 ? -range.lower/duration : 0) : NAN;
    double mainDuration = CMTimeGetSeconds(self.mainPlayer.currentItem.duration), subDuration = CMTimeGetSeconds(self.subPlayer.currentItem.duration);
    self.mainPositionSlider.syncFraction = self.hasLinkedAnchors && isfinite(mainDuration) && mainDuration > 0 ? CMTimeGetSeconds(self.linkedMainAnchor)/mainDuration : NAN;
    self.subPositionSlider.syncFraction = self.hasLinkedAnchors && isfinite(subDuration) && subDuration > 0 ? CMTimeGetSeconds(self.linkedSubAnchor)/subDuration : NAN;
}

- (void)seekLinkedElapsed:(double)elapsed { WJSyncRange range = [self sharedSyncRange]; [self seekLinkedRelative:range.lower+elapsed play:NO]; }

- (void)seekBoth:(CMTime)time {
    if (self.linkedPlayback && self.hasLinkedAnchors) { [self seekLinkedRelative:CMTimeGetSeconds(time)-CMTimeGetSeconds(self.linkedMainAnchor) play:NO]; return; }
    [self seekPairMain:time sub:time play:NO];
}

- (void)returnToSyncPoint:(id)sender {
    if (!self.linkedPlayback || !self.hasLinkedAnchors) return;
    WJSyncRange range = [self sharedSyncRange];
    [self seekLinkedRelative:MAX(range.lower,-2.0) play:YES];
}

- (void)syncFrameStep:(UIButton *)sender {
    if (!self.linkedPlayback || !self.hasLinkedAnchors) return;
    double relative = (self.pairedSeekInProgress ? CMTimeGetSeconds(self.pairedMainTarget) : CMTimeGetSeconds(self.mainPlayer.currentTime)) - CMTimeGetSeconds(self.linkedMainAnchor);
    double delta = CMTimeGetSeconds([self frameDurationForPlayer:self.mainPlayer]);
    [self pausePlayback]; [self seekLinkedRelative:relative + (sender.tag == 8 ? -delta : delta) play:NO];
}

- (void)setA:(id)sender { self.loopStart = self.mainPlayer.currentTime; self.subLoopStart = self.subPlayer.currentTime; self.loopEnd = kCMTimeInvalid; self.subLoopEnd = kCMTimeInvalid; self.loopEnabled = NO; [self refreshComparisonFeatureButtons]; }
- (void)setB:(id)sender { CMTime now = self.mainPlayer.currentTime; if (!CMTIME_IS_VALID(self.loopStart) || CMTimeCompare(now, self.loopStart) <= 0) return; self.loopEnd = now; self.subLoopEnd = self.subPlayer.currentTime; self.loopEnabled = YES; [self refreshComparisonFeatureButtons]; if (self.linkedPlayback && self.hasLinkedAnchors) { [self seekLinkedRelative:CMTimeGetSeconds(self.loopStart)-CMTimeGetSeconds(self.linkedMainAnchor) play:YES]; } else { [self seekPairMain:self.loopStart sub:self.loopStart play:YES]; } }
- (void)toggleLoop:(id)sender {
    // A/B区間が設定済みなら、リピート解除時に区間設定も同時に解除する。
    // 通常再生画面と同じく、A/Bの色・選択状態も初期状態へ戻す。
    if (CMTIME_IS_VALID(self.loopStart) && CMTIME_IS_VALID(self.loopEnd)) {
        self.loopEnabled = NO;
        self.loopStart = kCMTimeInvalid;
        self.loopEnd = kCMTimeInvalid;
        self.subLoopStart = kCMTimeInvalid;
        self.subLoopEnd = kCMTimeInvalid;
    } else {
        self.loopEnabled = !self.loopEnabled;
    }
    [self refreshComparisonFeatureButtons];
}
- (CMTime)frameDurationForPlayer:(AVPlayer *)player { AVAssetTrack *track = [[player.currentItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject]; CMTime d = track.minFrameDuration; if (CMTIME_IS_VALID(d) && d.value > 0) return d; float fps = track.nominalFrameRate; return CMTimeMakeWithSeconds(fps > 0 ? 1.0 / fps : 1.0 / 30.0, 600); }
- (void)stepFrame:(id)sender { [self.mainPlayer pause]; [self.subPlayer pause]; CMTime step = [self frameDurationForPlayer:self.mainPlayer]; [self seekBoth:CMTimeAdd(self.mainPlayer.currentTime, step)]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; }
- (void)individualTransport:(UIButton *)sender { AVPlayer *player = sender.tag <= 3 ? self.mainPlayer : self.subPlayer; BOOL isPlay = (sender.tag == 2 || sender.tag == 5); if (isPlay) { if (player.rate > 0) { [player pause]; [sender setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; } else { player.rate = self.speed; [sender setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal]; } return; } [player pause]; CMTime current = player.currentTime; CMTime delta = [self frameDurationForPlayer:player]; if (sender.tag == 1 || sender.tag == 4) delta = CMTimeMake(-delta.value, delta.timescale); CMTime target = CMTimeAdd(current, delta); if (CMTIME_COMPARE_INLINE(target, <, kCMTimeZero)) target = kCMTimeZero; [self seekIndividualPlayer:player time:target]; UIButton *play = sender.tag <= 3 ? self.mainPlayButton : self.subPlayButton; [play setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; }
- (void)toggleMainMirror:(id)sender { self.mainMirrored = !self.mainMirrored; [self.view setNeedsLayout]; [self.mainMirrorButton setImage:[UIImage systemImageNamed:(self.mainMirrored ? @"arrow.left.and.right.righttriangle.left.righttriangle.right.fill" : @"arrow.left.and.right.righttriangle.left.righttriangle.right")] forState:UIControlStateNormal]; }
- (void)toggleSubMirror:(id)sender { self.subMirrored = !self.subMirrored; [self.view setNeedsLayout]; [self.subMirrorButton setImage:[UIImage systemImageNamed:(self.subMirrored ? @"arrow.left.and.right.righttriangle.left.righttriangle.right.fill" : @"arrow.left.and.right.righttriangle.left.righttriangle.right")] forState:UIControlStateNormal]; }
- (void)selectComparisonVideo:(id)sender {
    __weak typeof(self) weakSelf = self;
    UIViewController *library = [WaterJumpSettingsViewController videoLibraryViewControllerForComparisonWithMainURL:self.mainURL selection:^(NSURL *url) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self pausePlayback]; self.pairedSeekGeneration += 1; self.pairedSeekInProgress = NO;
        self.requestedMainTime = kCMTimeInvalid; self.requestedSubTime = kCMTimeInvalid;
        self.subURL = url;
        self.showsReceivedCameraNames = NO;
        self.mainLabel.text = @"MAIN"; self.subLabel.text = @"SUB";
        [self.subPlayer replaceCurrentItemWithPlayerItem:[AVPlayerItem playerItemWithURL:url]];
        self.subZoomScale = 1.0;
        [self refreshComparisonAspects];
        [self refreshFavorites];
        self.hasLinkedAnchors = NO; self.linkedPlayback = NO; self.linkedMainAnchor = kCMTimeInvalid; self.linkedSubAnchor = kCMTimeInvalid;
        self.loopStart = kCMTimeInvalid; self.loopEnd = kCMTimeInvalid; self.subLoopStart = kCMTimeInvalid; self.subLoopEnd = kCMTimeInvalid; self.loopEnabled = NO;
        [self refreshComparisonFeatureButtons]; [self updateLinkControls]; [self updatePosition];
    }];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:library];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:navigation animated:YES completion:nil];
}
- (void)comparisonPinched:(UIPinchGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.view];
    BOOL mainArea = CGRectContainsPoint(self.mainViewport.frame, point);
    CGFloat *scale = mainArea ? &_mainZoomScale : &_subZoomScale;
    *scale = MIN(3.0, MAX(1.0, *scale * gesture.scale));
    gesture.scale = 1.0;
    CGAffineTransform transform = CGAffineTransformMakeScale(mainArea ? (self.mainMirrored ? -*scale : *scale) : (self.subMirrored ? -*scale : *scale), *scale);
    if (mainArea) self.mainLayer.affineTransform = transform; else self.subLayer.affineTransform = transform;
}
- (void)pausePlayback { self.pairedWantsPlayback = NO; [self.mainPlayer pause]; [self.subPlayer pause]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; [self updateIndividualTransportButtons]; }

- (void)close { self.pairedSeekGeneration += 1; self.pairedWantsPlayback = NO; [self.mainPlayer pause]; [self.subPlayer pause]; self.loopEnabled = NO; self.loopSeekInProgress = NO; if (self.observer) { [self.mainPlayer removeTimeObserver:self.observer]; self.observer = nil; } UIWindowScene *scene = self.view.window.windowScene;
    if (self.parentViewController) { void (^handler)(void) = self.closeHandler; self.closeHandler = nil; [self willMoveToParentViewController:nil]; [self.view removeFromSuperview]; [self removeFromParentViewController]; if (handler) handler(); return; }
    UIViewController *presenter = self.presentingViewController;
    [self dismissViewControllerAnimated:YES completion:^{
        [presenter setNeedsUpdateOfSupportedInterfaceOrientations];
        [scene requestGeometryUpdateWithPreferences:[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait] errorHandler:^(NSError *error) { NSLog(@"Comparison portrait restore: %@", error); }];
    }]; }
- (void)shareVideos:(id)sender { UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[self.mainURL, self.subURL] applicationActivities:nil]; if (activity.popoverPresentationController) { activity.popoverPresentationController.sourceView = sender; activity.popoverPresentationController.sourceRect = [sender bounds]; } [self presentViewController:activity animated:YES completion:nil]; }
- (void)exportComparisonVideo:(id)sender {
    AVAsset *mainAsset = [AVAsset assetWithURL:self.mainURL], *subAsset = [AVAsset assetWithURL:self.subURL];
    AVAssetTrack *mainTrack = [mainAsset tracksWithMediaType:AVMediaTypeVideo].firstObject, *subTrack = [subAsset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!mainTrack || !subTrack) return;
    // リンクを有効にした時点のMAIN/SUB位置をそれぞれの基準にする。
    // 書き出しはリンクポイントの2秒前から開始し、短い方の終端で終了する。
    BOOL useLinkedRange = self.hasLinkedAnchors && CMTIME_IS_VALID(self.linkedMainAnchor) && CMTIME_IS_VALID(self.linkedSubAnchor);
    WJSyncRange range = [self sharedSyncRange];
    double preroll = MAX(range.lower, -2.0);
    double mainStartSeconds = useLinkedRange ? CMTimeGetSeconds(self.linkedMainAnchor) + preroll : 0.0;
    double subStartSeconds = useLinkedRange ? CMTimeGetSeconds(self.linkedSubAnchor) + preroll : 0.0;
    double mainDurationSeconds = CMTimeGetSeconds(mainAsset.duration), subDurationSeconds = CMTimeGetSeconds(subAsset.duration);
    double outputDurationSeconds = useLinkedRange ? MIN(MAX(0.0, mainDurationSeconds - mainStartSeconds), MAX(0.0, subDurationSeconds - subStartSeconds)) : MIN(mainDurationSeconds, subDurationSeconds);
    if (!isfinite(outputDurationSeconds) || outputDurationSeconds <= 0) { [self showExportError:[NSError errorWithDomain:@"MTJudge.Export" code:3 userInfo:@{NSLocalizedDescriptionKey:@"同期位置から書き出せる区間がありません。"}]]; return; }
    CMTime mainStart = CMTimeMakeWithSeconds(mainStartSeconds, 600), subStart = CMTimeMakeWithSeconds(subStartSeconds, 600), duration = CMTimeMakeWithSeconds(outputDurationSeconds, 600);
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *mainComp = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *subComp = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVAssetTrack *mainAudioTrack = [mainAsset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    AVAssetTrack *subAudioTrack = [subAsset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    AVMutableCompositionTrack *mainAudioComp = mainAudioTrack ? [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid] : nil;
    AVMutableCompositionTrack *subAudioComp = subAudioTrack ? [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid] : nil;
    NSError *error = nil;
    [mainComp insertTimeRange:CMTimeRangeMake(mainStart, duration) ofTrack:mainTrack atTime:kCMTimeZero error:&error];
    [subComp insertTimeRange:CMTimeRangeMake(subStart, duration) ofTrack:subTrack atTime:kCMTimeZero error:&error];
    if (mainAudioComp) [mainAudioComp insertTimeRange:CMTimeRangeMake(mainStart, duration) ofTrack:mainAudioTrack atTime:kCMTimeZero error:&error];
    if (subAudioComp) [subAudioComp insertTimeRange:CMTimeRangeMake(subStart, duration) ofTrack:subAudioTrack atTime:kCMTimeZero error:&error];
    if (error) { [self showExportError:error]; return; }
    CGSize mainSize = WJOrientedTrackSize(mainTrack);
    CGSize subSize = WJOrientedTrackSize(subTrack);
    CGSize aspects = WJComparisonAspects(mainSize, subSize);
    // Normalize resolution before arranging the panes (e.g. 1080p vs 4K portrait).
    CGFloat height = MIN(1920, MAX(mainSize.height, subSize.height));
    CGFloat width = MIN(1920, MAX(mainSize.width, subSize.width));
    CGSize render = self.sideBySide ? CGSizeMake(height * (aspects.width + aspects.height), height) : CGSizeMake(width, width / aspects.width + width / aspects.height);
    CGFloat limit = MIN(1, 3840 / MAX(render.width, render.height));
    render = CGSizeMake(MAX(2, ceil(render.width * limit / 2) * 2), MAX(2, ceil(render.height * limit / 2) * 2));
    CGRect mainPane, subPane;
    WJComparisonRects((CGRect){CGPointZero, render}, aspects, self.sideBySide, &mainPane, &subPane);
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
    videoComposition.renderSize = render; videoComposition.frameDuration = CMTimeMake(1, 30);
    AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction]; instruction.timeRange = CMTimeRangeMake(kCMTimeZero, duration);
    AVMutableVideoCompositionLayerInstruction *mainInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:mainComp];
    AVMutableVideoCompositionLayerInstruction *subInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:subComp];
    WJConfigureComparisonInstruction(mainInstruction, mainTrack, mainPane, self.mainZoomScale, self.mainMirrored);
    WJConfigureComparisonInstruction(subInstruction, subTrack, subPane, self.subZoomScale, self.subMirrored);
    instruction.layerInstructions = @[mainInstruction, subInstruction]; videoComposition.instructions = @[instruction];
    NSMutableArray *audioParameters = [NSMutableArray array];
    if (mainAudioComp) { AVMutableAudioMixInputParameters *p = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:mainAudioComp]; [p setVolume:subAudioComp ? 0.5 : 1.0 atTime:kCMTimeZero]; [audioParameters addObject:p]; }
    if (subAudioComp) { AVMutableAudioMixInputParameters *p = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:subAudioComp]; [p setVolume:mainAudioComp ? 0.5 : 1.0 atTime:kCMTimeZero]; [audioParameters addObject:p]; }
    NSString *name = [NSString stringWithFormat:@"MTJCompare_%@.MOV", [self exportTimestamp]];
    NSURL *output = [[self exportDirectoryURL] URLByAppendingPathComponent:name];
    [[NSFileManager defaultManager] removeItemAtURL:output error:nil];
    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetHighestQuality]; session.outputURL = output; session.outputFileType = AVFileTypeQuickTimeMovie; session.videoComposition = videoComposition; if (audioParameters.count) { AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix]; audioMix.inputParameters = audioParameters; session.audioMix = audioMix; } session.shouldOptimizeForNetworkUse = NO;
    self.exportButton.enabled = NO;
    [session exportAsynchronouslyWithCompletionHandler:^{ dispatch_async(dispatch_get_main_queue(), ^{ self.exportButton.enabled = YES; if (session.status == AVAssetExportSessionStatusCompleted) [self presentExportedFile:output from:self.exportButton]; else [self showExportError:session.error ?: [NSError errorWithDomain:@"MTJudge.Export" code:1 userInfo:@{NSLocalizedDescriptionKey:@"比較動画を書き出せませんでした。"}]]; }); }];
}
- (NSString *)exportTimestamp { NSDateFormatter *f = [NSDateFormatter new]; f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; f.dateFormat = @"yyyyMMddHHmmssSSS"; return [f stringFromDate:[NSDate date]]; }
- (NSURL *)exportDirectoryURL { NSURL *u = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject]; u = [u URLByAppendingPathComponent:@"Recordings" isDirectory:YES]; [[NSFileManager defaultManager] createDirectoryAtURL:u withIntermediateDirectories:YES attributes:nil error:nil]; return u; }
- (void)presentExportedFile:(NSURL *)url from:(UIView *)source { UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil]; if (activity.popoverPresentationController) { activity.popoverPresentationController.sourceView = source; activity.popoverPresentationController.sourceRect = source.bounds; } [self presentViewController:activity animated:YES completion:nil]; }
- (void)showExportError:(NSError *)error { UIAlertController *a = [UIAlertController alertControllerWithTitle:@"書き出し失敗" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)refreshFavorites {
    BOOL selected = [ReceivedVideoManager isFavoriteVideo:self.mainURL] && [ReceivedVideoManager isFavoriteVideo:self.subURL];
    [self.favoriteButton setImage:[UIImage systemImageNamed:(selected ? @"heart.fill" : @"heart")] forState:UIControlStateNormal];
    self.favoriteButton.tintColor = selected ? UIColor.systemPinkColor : UIColor.whiteColor;
}
- (void)toggleFavorites:(id)sender {
    BOOL selected = [ReceivedVideoManager isFavoriteVideo:self.mainURL] && [ReceivedVideoManager isFavoriteVideo:self.subURL];
    [ReceivedVideoManager setFavoriteVideo:self.mainURL favorite:!selected];
    [ReceivedVideoManager setFavoriteVideo:self.subURL favorite:!selected];
    [self refreshFavorites];
}
- (void)prepareForAutoplayReplacement {
    self.pairedSeekGeneration += 1; self.pairedWantsPlayback = NO;
    [self.mainPlayer pause]; [self.subPlayer pause];
    self.loopEnabled = NO; self.loopSeekInProgress = NO;
    self.automaticLoopLimit = 0;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.observer) { [self.mainPlayer removeTimeObserver:self.observer]; self.observer = nil; }
    if (self.subTimeObserver) { [self.subPlayer removeTimeObserver:self.subTimeObserver]; self.subTimeObserver = nil; }
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; if (self.observer) [self.mainPlayer removeTimeObserver:self.observer]; if (self.subTimeObserver) [self.subPlayer removeTimeObserver:self.subTimeObserver]; }
@end
