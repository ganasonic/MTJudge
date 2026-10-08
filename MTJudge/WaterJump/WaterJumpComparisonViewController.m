#import "WaterJumpComparisonViewController.h"
#import <AVFoundation/AVFoundation.h>

static CGSize WJOrientedTrackSize(AVAssetTrack *track) {
    CGRect rect = CGRectApplyAffineTransform(CGRectMake(0, 0, fabs(track.naturalSize.width), fabs(track.naturalSize.height)), track.preferredTransform);
    return CGSizeMake(fabs(rect.size.width), fabs(rect.size.height));
}
static CGAffineTransform WJNormalizedTrackTransform(AVAssetTrack *track) {
    CGRect rect = CGRectApplyAffineTransform(CGRectMake(0, 0, fabs(track.naturalSize.width), fabs(track.naturalSize.height)), track.preferredTransform);
    CGAffineTransform t = track.preferredTransform; t.tx -= rect.origin.x; t.ty -= rect.origin.y; return t;
}

@interface WaterJumpComparisonViewController ()
@property (nonatomic, strong) NSURL *mainURL;
@property (nonatomic, strong) NSURL *subURL;
@property (nonatomic, strong) AVPlayer *mainPlayer;
@property (nonatomic, strong) AVPlayer *subPlayer;
@property (nonatomic, strong) AVPlayerLayer *mainLayer;
@property (nonatomic, strong) AVPlayerLayer *subLayer;
@property (nonatomic, strong) UISlider *positionSlider;
@property (nonatomic, strong) UISlider *mainPositionSlider;
@property (nonatomic, strong) UISlider *subPositionSlider;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UILabel *mainLabel;
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
@property (nonatomic, assign) CMTime loopStart;
@property (nonatomic, assign) CMTime loopEnd;
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
@property (nonatomic, assign) NSInteger automaticLoopLimit;
@property (nonatomic, assign) NSInteger automaticLoopCount;
@property (nonatomic, strong) NSDate *automaticLoopDeadline;
@end

@implementation WaterJumpComparisonViewController

- (instancetype)initWithMainURL:(NSURL *)mainURL subURL:(NSURL *)subURL {
    if ((self = [super init])) { _mainURL = mainURL; _subURL = subURL; _speed = 1.0; self.modalPresentationStyle = UIModalPresentationFullScreen; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.mainPlayer = [AVPlayer playerWithURL:self.mainURL];
    self.subPlayer = [AVPlayer playerWithURL:self.subURL];
    self.mainZoomScale = 1.0; self.subZoomScale = 1.0;
    self.mainLayer = [AVPlayerLayer playerLayerWithPlayer:self.mainPlayer];
    self.subLayer = [AVPlayerLayer playerLayerWithPlayer:self.subPlayer];
    self.mainLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.subLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(comparisonPinched:)];
    [self.view addGestureRecognizer:pinch];
    self.mainLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.subLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.view.layer addSublayer:self.mainLayer]; [self.view.layer addSublayer:self.subLayer];
    self.mainLabel = [self label:@"MAIN"]; self.subLabel = [self label:@"SUB"];
    [self.view addSubview:self.mainLabel]; [self.view addSubview:self.subLabel];
    self.positionSlider = [UISlider new]; self.positionSlider.minimumValue = 0; self.positionSlider.maximumValue = 1;
    [self.positionSlider addTarget:self action:@selector(positionChanged:) forControlEvents:UIControlEventValueChanged];
    self.mainPositionSlider = [UISlider new]; self.mainPositionSlider.minimumValue = 0; self.mainPositionSlider.maximumValue = 1; [self.mainPositionSlider addTarget:self action:@selector(individualPositionChanged:) forControlEvents:UIControlEventValueChanged];
    self.subPositionSlider = [UISlider new]; self.subPositionSlider.minimumValue = 0; self.subPositionSlider.maximumValue = 1; [self.subPositionSlider addTarget:self action:@selector(individualPositionChanged:) forControlEvents:UIControlEventValueChanged];
    self.speedSlider = [UISlider new]; self.speedSlider.minimumValue = .2; self.speedSlider.maximumValue = 1.0; self.speedSlider.value = 1.0;
    [self.speedSlider addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    self.playButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; self.playButton.tintColor = UIColor.whiteColor; [self.playButton addTarget:self action:@selector(togglePlay:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem]; [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal]; close.tintColor = UIColor.whiteColor; [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    self.shareButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.shareButton setImage:[UIImage systemImageNamed:@"square.and.arrow.up"] forState:UIControlStateNormal]; self.shareButton.tintColor = UIColor.whiteColor; [self.shareButton addTarget:self action:@selector(shareVideos:) forControlEvents:UIControlEventTouchUpInside];
    self.exportButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.exportButton setImage:[UIImage systemImageNamed:@"square.and.arrow.down"] forState:UIControlStateNormal]; self.exportButton.tintColor = UIColor.whiteColor; self.exportButton.accessibilityLabel = @"比較動画を書き出す"; [self.exportButton addTarget:self action:@selector(exportComparisonVideo:) forControlEvents:UIControlEventTouchUpInside];
    self.favoriteButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.favoriteButton setImage:[UIImage systemImageNamed:@"heart"] forState:UIControlStateNormal]; self.favoriteButton.tintColor = UIColor.whiteColor; [self.favoriteButton addTarget:self action:@selector(toggleFavorites:) forControlEvents:UIControlEventTouchUpInside];
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
    self.frameButton = [self featureButton:@"▸|" action:@selector(stepFrame:)];
    self.mainMirrorButton = [self featureButton:@"M1" action:@selector(toggleMainMirror:)];
    self.subMirrorButton = [self featureButton:@"M2" action:@selector(toggleSubMirror:)];
    for (UIView *view in @[self.positionSlider, self.mainPositionSlider, self.subPositionSlider, self.speedSlider, self.playButton, close, self.shareButton, self.exportButton, self.favoriteButton, self.linkButton, self.mainBackButton, self.mainPlayButton, self.mainForwardButton, self.subBackButton, self.subPlayButton, self.subForwardButton, self.syncPointButton, self.syncBackButton, self.syncForwardButton, layoutButton, self.aButton, self.bButton, self.loopButton, self.mainMirrorButton, self.subMirrorButton]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:view]; }
    self.frameButton.hidden = YES;
    self.positionSlider.accessibilityLabel = @"比較再生位置"; self.speedSlider.accessibilityLabel = @"比較再生速度";
    self.bottomControlGuide = [UILayoutGuide new];
    [self.view addLayoutGuide:self.bottomControlGuide];
    [NSLayoutConstraint activateConstraints:@[
        [self.positionSlider.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24], [self.positionSlider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24], [self.positionSlider.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-78],
        [self.speedSlider.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor], [self.speedSlider.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.6], [self.speedSlider.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-36],
        [self.loopButton.trailingAnchor constraintEqualToAnchor:self.syncPointButton.leadingAnchor constant:-6], [self.loopButton.centerYAnchor constraintEqualToAnchor:self.syncPointButton.centerYAnchor],
        [self.bButton.trailingAnchor constraintEqualToAnchor:self.loopButton.leadingAnchor constant:-6], [self.bButton.centerYAnchor constraintEqualToAnchor:self.loopButton.centerYAnchor],
        [self.aButton.trailingAnchor constraintEqualToAnchor:self.bButton.leadingAnchor constant:-6], [self.aButton.centerYAnchor constraintEqualToAnchor:self.bButton.centerYAnchor],
        [self.bottomControlGuide.leadingAnchor constraintEqualToAnchor:self.aButton.leadingAnchor], [self.bottomControlGuide.trailingAnchor constraintEqualToAnchor:self.syncForwardButton.trailingAnchor], [self.bottomControlGuide.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor], [self.bottomControlGuide.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:4], [self.bottomControlGuide.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-4],
        [self.playButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4], [self.playButton.widthAnchor constraintEqualToConstant:44], [self.playButton.heightAnchor constraintEqualToConstant:36],
        [self.syncBackButton.trailingAnchor constraintEqualToAnchor:self.playButton.leadingAnchor constant:-8], [self.syncBackButton.centerYAnchor constraintEqualToAnchor:self.playButton.centerYAnchor], [self.syncBackButton.widthAnchor constraintEqualToConstant:36], [self.syncBackButton.heightAnchor constraintEqualToConstant:36],
        [self.syncPointButton.trailingAnchor constraintEqualToAnchor:self.syncBackButton.leadingAnchor constant:-6], [self.syncPointButton.centerYAnchor constraintEqualToAnchor:self.playButton.centerYAnchor], [self.syncPointButton.widthAnchor constraintEqualToConstant:36], [self.syncPointButton.heightAnchor constraintEqualToConstant:36],
        [self.syncForwardButton.leadingAnchor constraintEqualToAnchor:self.playButton.trailingAnchor constant:8], [self.syncForwardButton.centerYAnchor constraintEqualToAnchor:self.playButton.centerYAnchor], [self.syncForwardButton.widthAnchor constraintEqualToConstant:36], [self.syncForwardButton.heightAnchor constraintEqualToConstant:36],
        [close.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12], [close.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4], [close.widthAnchor constraintEqualToConstant:44], [close.heightAnchor constraintEqualToConstant:44],
        [self.favoriteButton.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-4], [self.favoriteButton.topAnchor constraintEqualToAnchor:close.topAnchor], [self.favoriteButton.widthAnchor constraintEqualToConstant:44], [self.favoriteButton.heightAnchor constraintEqualToConstant:44],
        [self.shareButton.trailingAnchor constraintEqualToAnchor:self.favoriteButton.leadingAnchor constant:-4], [self.shareButton.topAnchor constraintEqualToAnchor:close.topAnchor], [self.shareButton.widthAnchor constraintEqualToConstant:44], [self.shareButton.heightAnchor constraintEqualToConstant:44],
        [self.exportButton.trailingAnchor constraintEqualToAnchor:self.shareButton.leadingAnchor constant:-4], [self.exportButton.topAnchor constraintEqualToAnchor:close.topAnchor], [self.exportButton.widthAnchor constraintEqualToConstant:44], [self.exportButton.heightAnchor constraintEqualToConstant:44],
        [layoutButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12], [layoutButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4], [layoutButton.widthAnchor constraintEqualToConstant:44], [layoutButton.heightAnchor constraintEqualToConstant:44]
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
    self.loopStart = kCMTimeInvalid; self.loopEnd = kCMTimeInvalid; self.linkedMainAnchor = kCMTimeInvalid; self.linkedSubAnchor = kCMTimeInvalid; self.linkedPlayback = NO; self.sideBySide = YES; [self updateLinkControls];
}

- (UILabel *)label:(NSString *)text { UILabel *label = [UILabel new]; label.text = text; label.textColor = UIColor.whiteColor; label.backgroundColor = [UIColor colorWithWhite:0 alpha:.45]; label.translatesAutoresizingMaskIntoConstraints = NO; return label; }
- (UIButton *)featureButton:(NSString *)title action:(SEL)action { UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; NSDictionary *symbols = @{@"A": @"a.circle", @"B": @"b.circle", @"↻": @"repeat", @"▸|": @"forward.frame", @"M1": @"arrow.left.and.right.righttriangle.left.righttriangle.right", @"M2": @"arrow.left.and.right.righttriangle.left.righttriangle.right"}; NSString *symbol = symbols[title]; if (symbol) { [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal]; [button setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold] forImageInState:UIControlStateNormal]; button.accessibilityLabel = title; } else { [button setTitle:title forState:UIControlStateNormal]; button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; } button.tintColor = UIColor.whiteColor; [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; button.backgroundColor = [UIColor colorWithWhite:0 alpha:.25]; button.layer.cornerRadius = 7; button.contentEdgeInsets = UIEdgeInsetsMake(2, 5, 2, 5); [button.widthAnchor constraintEqualToConstant:38].active = YES; [button.heightAnchor constraintEqualToConstant:36].active = YES; [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button; }
- (void)updateIndividualTransportButtons { [self.mainPlayButton setImage:[UIImage systemImageNamed:(self.mainPlayer.rate > 0 ? @"pause.fill" : @"play.fill")] forState:UIControlStateNormal]; [self.subPlayButton setImage:[UIImage systemImageNamed:(self.subPlayer.rate > 0 ? @"pause.fill" : @"play.fill")] forState:UIControlStateNormal]; }
- (UIButton *)transportButton:(NSString *)symbol action:(SEL)action tag:(NSInteger)tag { UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal]; button.tintColor = UIColor.whiteColor; button.backgroundColor = [UIColor colorWithWhite:0 alpha:.45]; button.layer.cornerRadius = 6; button.tag = tag; [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button; }
- (void)updateLinkControls { self.positionSlider.hidden = !self.linkedPlayback; self.speedSlider.hidden = !self.linkedPlayback; self.mainPositionSlider.hidden = self.linkedPlayback; self.subPositionSlider.hidden = self.linkedPlayback; for (UIView *view in @[self.mainBackButton, self.mainPlayButton, self.mainForwardButton, self.subBackButton, self.subPlayButton, self.subForwardButton, self.mainMirrorButton, self.subMirrorButton]) view.hidden = self.linkedPlayback; self.linkButton.tintColor = [UIColor.systemGreenColor colorWithAlphaComponent:self.linkedPlayback ? 1.0 : .3]; [self.linkButton setImage:[UIImage systemImageNamed:@"link"] forState:UIControlStateNormal]; self.linkButton.accessibilityValue = self.linkedPlayback ? @"選択中：2画面を連動" : @"未選択：個別操作"; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; CGFloat top = self.view.safeAreaInsets.top + 32, bottom = self.view.bounds.size.height - 128; CGFloat availableHeight = MAX(1, bottom - top); CGFloat boundaryX = self.view.bounds.size.width / 2.0; CGFloat boundaryY = top + availableHeight / 2.0; CGRect mainRect, subRect; if (self.sideBySide) { CGFloat w = boundaryX; mainRect = CGRectMake(0, top, w, availableHeight); subRect = CGRectMake(w, top, w, availableHeight); } else { CGFloat h = MAX(1, availableHeight / 2.0); boundaryY = top + h; mainRect = CGRectMake(0, top, self.view.bounds.size.width, h); subRect = CGRectMake(0, boundaryY, self.view.bounds.size.width, h); } self.mainLayer.frame = mainRect; self.subLayer.frame = subRect; [self.mainLabel sizeToFit]; [self.subLabel sizeToFit]; CGFloat labelX = 12.0; self.mainLabel.frame = CGRectMake(mainRect.origin.x + labelX, mainRect.origin.y + 8.0, self.mainLabel.bounds.size.width, self.mainLabel.bounds.size.height); self.subLabel.frame = CGRectMake(subRect.origin.x + labelX, subRect.origin.y + 8.0, self.subLabel.bounds.size.width, self.subLabel.bounds.size.height); self.linkButton.frame = CGRectMake((self.sideBySide ? boundaryX : self.view.bounds.size.width / 2.0) - 24.0, boundaryY - 24.0, 48.0, 48.0); CGFloat sliderHeight = 32.0, sliderYMain = CGRectGetMaxY(mainRect) - sliderHeight - 6.0, sliderYSub = CGRectGetMaxY(subRect) - sliderHeight - 6.0; self.mainPositionSlider.frame = CGRectMake(mainRect.origin.x + 24, sliderYMain, MAX(1, mainRect.size.width - 48), sliderHeight); self.subPositionSlider.frame = CGRectMake(subRect.origin.x + 24, sliderYSub, MAX(1, subRect.size.width - 48), sliderHeight); [self layoutTransportButton:self.mainBackButton play:self.mainPlayButton forward:self.mainForwardButton inRect:mainRect sliderY:sliderYMain]; [self layoutTransportButton:self.subBackButton play:self.subPlayButton forward:self.subForwardButton inRect:subRect sliderY:sliderYSub]; CGFloat mirrorSize = 36.0; self.mainMirrorButton.frame = CGRectMake(CGRectGetMaxX(self.mainForwardButton.frame) + 6.0, self.mainForwardButton.frame.origin.y, mirrorSize, mirrorSize); self.subMirrorButton.frame = CGRectMake(CGRectGetMaxX(self.subForwardButton.frame) + 6.0, self.subForwardButton.frame.origin.y, mirrorSize, mirrorSize); [self.view bringSubviewToFront:self.linkButton]; [self.view bringSubviewToFront:self.syncPointButton]; [self.view bringSubviewToFront:self.syncBackButton]; [self.view bringSubviewToFront:self.playButton]; [self.view bringSubviewToFront:self.syncForwardButton]; [self.view bringSubviewToFront:self.mainMirrorButton]; [self.view bringSubviewToFront:self.subMirrorButton]; [self.view bringSubviewToFront:self.mainPositionSlider]; [self.view bringSubviewToFront:self.subPositionSlider]; }
- (void)layoutTransportButton:(UIButton *)back play:(UIButton *)play forward:(UIButton *)forward inRect:(CGRect)rect sliderY:(CGFloat)sliderY { CGFloat size = 36.0, gap = 8.0, total = size * 3 + gap * 2; CGFloat x = CGRectGetMidX(rect) - total / 2.0, y = sliderY - size - 4.0; back.frame = CGRectMake(x, y, size, size); play.frame = CGRectMake(x + size + gap, y, size, size); forward.frame = CGRectMake(x + (size + gap) * 2, y, size, size); }
- (void)togglePlay:(id)sender { BOOL playing = self.mainPlayer.rate > 0 || self.subPlayer.rate > 0; if (playing) { [self.mainPlayer pause]; [self.subPlayer pause]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; } else { self.mainPlayer.rate = self.speed; self.subPlayer.rate = self.speed; [self.playButton setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal]; } [self updateIndividualTransportButtons]; }
- (void)startPlayback {
    // 両方のサイドカーに記録された撮影開始時刻を使い、共通の実時刻が
    // 先頭になるよう初期位置を合わせる。メタデータがない旧動画は従来通り0秒。
    NSDictionary *(^metadata)(NSURL *) = ^NSDictionary *(NSURL *url) {
        NSData *data = [NSData dataWithContentsOfURL:[url URLByAppendingPathExtension:@"wj.json"]];
        id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        return [object isKindOfClass:NSDictionary.class] ? object : @{};
    };
    double mainStart = [metadata(self.mainURL)[@"recordingStart"] doubleValue];
    double subStart = [metadata(self.subURL)[@"recordingStart"] doubleValue];
    if (mainStart > 0 && subStart > 0 && fabs(mainStart - subStart) < 120.0) {
        double common = MAX(mainStart, subStart);
        [self.mainPlayer seekToTime:CMTimeMakeWithSeconds(MAX(0, common - mainStart), 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil];
        [self.subPlayer seekToTime:CMTimeMakeWithSeconds(MAX(0, common - subStart), 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil];
    }
    [self configureAutomaticLoop]; [self togglePlay:nil];
}
- (void)positionChanged:(UISlider *)slider { [self.mainPlayer pause]; [self.subPlayer pause]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; if (self.linkedPlayback && self.hasLinkedAnchors) { double duration = [self linkedDurationSeconds]; if (duration > 0) [self seekLinkedElapsed:duration * slider.value]; return; } double duration = CMTimeGetSeconds(self.mainPlayer.currentItem.duration); if (!isfinite(duration) || duration <= 0) return; CMTime time = CMTimeMakeWithSeconds(duration * slider.value, 600); [self.mainPlayer seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; }
- (void)individualPositionChanged:(UISlider *)slider { [self.mainPlayer pause]; [self.subPlayer pause]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; AVPlayer *player = slider == self.mainPositionSlider ? self.mainPlayer : self.subPlayer; double duration = CMTimeGetSeconds(player.currentItem.duration); if (!isfinite(duration) || duration <= 0) return; CMTime time = CMTimeMakeWithSeconds(duration * slider.value, 600); [player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; }
- (void)toggleLink:(id)sender { if (!self.linkedPlayback) { self.linkedMainAnchor = self.mainPlayer.currentTime; self.linkedSubAnchor = self.subPlayer.currentTime; self.hasLinkedAnchors = CMTIME_IS_VALID(self.linkedMainAnchor) && CMTIME_IS_VALID(self.linkedSubAnchor); } self.linkedPlayback = !self.linkedPlayback; [self updateLinkControls]; [self.view setNeedsLayout]; }
- (void)toggleLayout:(id)sender { self.sideBySide = !self.sideBySide; [self.view setNeedsLayout]; }
- (void)speedChanged:(UISlider *)slider { self.speed = roundf(slider.value * 100) / 100; BOOL playing = self.mainPlayer.rate > 0; self.mainPlayer.rate = playing ? self.speed : 0; self.subPlayer.rate = playing ? self.speed : 0; }
- (void)updatePosition { [self updateIndividualTransportButtons]; double duration = CMTimeGetSeconds(self.mainPlayer.currentItem.duration); double current = CMTimeGetSeconds(self.mainPlayer.currentTime); double subDuration = CMTimeGetSeconds(self.subPlayer.currentItem.duration); double subCurrent = CMTimeGetSeconds(self.subPlayer.currentTime); if (self.linkedPlayback && self.hasLinkedAnchors) { double linkedDuration = [self linkedDurationSeconds]; double elapsed = MAX(0, CMTimeGetSeconds(CMTimeSubtract(self.mainPlayer.currentTime, self.linkedMainAnchor))); if (linkedDuration > 0) self.positionSlider.value = MIN(1, elapsed / linkedDuration); if (self.mainPlayer.rate > 0 && linkedDuration > 0 && elapsed >= linkedDuration - .05) { [self.mainPlayer pause]; [self.subPlayer pause]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; [self updateIndividualTransportButtons]; } } else if (isfinite(duration) && duration > 0 && isfinite(current)) { self.positionSlider.value = current / duration; } if (isfinite(duration) && duration > 0 && isfinite(current)) self.mainPositionSlider.value = current / duration; if (isfinite(subDuration) && subDuration > 0 && isfinite(subCurrent)) self.subPositionSlider.value = subCurrent / subDuration; if (!self.loopSeekInProgress && self.loopEnabled && CMTIME_IS_VALID(self.loopEnd) && current >= CMTimeGetSeconds(self.loopEnd)) { self.loopSeekInProgress = YES; [self seekBoth:self.loopStart]; self.mainPlayer.rate = self.speed; self.subPlayer.rate = self.speed; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ self.loopSeekInProgress = NO; }); [self updateIndividualTransportButtons]; return; } if (self.linkedPlayback) return; if (self.automaticLoopLimit == 0 || !isfinite(duration) || duration <= 0 || !isfinite(current) || current < duration - .15) return; if (self.automaticLoopDeadline && [[NSDate date] compare:self.automaticLoopDeadline] != NSOrderedAscending) { self.automaticLoopLimit = 0; return; } if (self.automaticLoopLimit > 0 && self.automaticLoopCount >= self.automaticLoopLimit) { self.automaticLoopLimit = 0; return; } self.automaticLoopCount += 1; [self seekBoth:kCMTimeZero]; self.mainPlayer.rate = self.speed; self.subPlayer.rate = self.speed; }
- (void)configureAutomaticLoop { NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults; self.automaticLoopLimit = 0; self.automaticLoopCount = 1; self.automaticLoopDeadline = nil; if (![defaults boolForKey:@"WJLoopPlayback"]) return; NSInteger count = [defaults integerForKey:@"WJLoopCount"]; if (count == 0) count = 3; if (count > 0) self.automaticLoopLimit = count; else { self.automaticLoopLimit = -1; NSInteger seconds = [defaults integerForKey:@"WJLoopDuration"]; if (seconds > 0) self.automaticLoopDeadline = [NSDate dateWithTimeIntervalSinceNow:seconds]; } }
- (double)linkedDurationSeconds { if (!self.hasLinkedAnchors) return 0; double mainDuration = CMTimeGetSeconds(self.mainPlayer.currentItem.duration); double subDuration = CMTimeGetSeconds(self.subPlayer.currentItem.duration); double mainAnchor = CMTimeGetSeconds(self.linkedMainAnchor); double subAnchor = CMTimeGetSeconds(self.linkedSubAnchor); if (!isfinite(mainDuration) || !isfinite(subDuration) || !isfinite(mainAnchor) || !isfinite(subAnchor)) return 0; return MAX(0, MIN(mainDuration - mainAnchor, subDuration - subAnchor)); }
- (void)seekLinkedElapsed:(double)elapsed { if (!self.hasLinkedAnchors) return; double maxElapsed = [self linkedDurationSeconds]; elapsed = MAX(0, MIN(elapsed, maxElapsed)); CMTime mainTime = CMTimeMakeWithSeconds(CMTimeGetSeconds(self.linkedMainAnchor) + elapsed, 600); CMTime subTime = CMTimeMakeWithSeconds(CMTimeGetSeconds(self.linkedSubAnchor) + elapsed, 600); [self.mainPlayer seekToTime:mainTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; [self.subPlayer seekToTime:subTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; }
- (void)seekBoth:(CMTime)time { if (self.linkedPlayback && self.hasLinkedAnchors) { double elapsed = CMTimeGetSeconds(CMTimeSubtract(time, self.linkedMainAnchor)); [self seekLinkedElapsed:elapsed]; return; } [self.mainPlayer seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; [self.subPlayer seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; }
- (void)returnToSyncPoint:(id)sender { if (!self.hasLinkedAnchors) return; double mainStart = MAX(0, CMTimeGetSeconds(self.linkedMainAnchor) - 2.0); double subStart = MAX(0, CMTimeGetSeconds(self.linkedSubAnchor) - 2.0); CMTime mainTime = CMTimeMakeWithSeconds(mainStart, 600); CMTime subTime = CMTimeMakeWithSeconds(subStart, 600); [self.mainPlayer seekToTime:mainTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; [self.subPlayer seekToTime:subTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; self.mainPlayer.rate = self.speed; self.subPlayer.rate = self.speed; [self.playButton setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal]; [self updateIndividualTransportButtons]; }
- (void)syncFrameStep:(UIButton *)sender { if (!self.linkedPlayback || !self.hasLinkedAnchors) return; [self.mainPlayer pause]; [self.subPlayer pause]; double elapsed = MAX(0, CMTimeGetSeconds(CMTimeSubtract(self.mainPlayer.currentTime, self.linkedMainAnchor))); double delta = CMTimeGetSeconds([self frameDurationForPlayer:self.mainPlayer]); if (sender.tag == 8) delta = -delta; [self seekLinkedElapsed:elapsed + delta]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; [self updateIndividualTransportButtons]; }
- (void)setA:(id)sender { self.loopStart = self.mainPlayer.currentTime; self.loopEnabled = NO; [self.aButton setImage:[UIImage systemImageNamed:@"a.circle.fill"] forState:UIControlStateNormal]; }
- (void)setB:(id)sender { CMTime now = self.mainPlayer.currentTime; if (!CMTIME_IS_VALID(self.loopStart) || CMTimeCompare(now, self.loopStart) <= 0) return; self.loopEnd = now; self.loopEnabled = YES; [self.bButton setImage:[UIImage systemImageNamed:@"b.circle.fill"] forState:UIControlStateNormal]; [self.loopButton setImage:[UIImage systemImageNamed:@"repeat.1"] forState:UIControlStateNormal]; [self seekBoth:self.loopStart]; self.mainPlayer.rate = self.speed; self.subPlayer.rate = self.speed; }
- (void)toggleLoop:(id)sender { if (!CMTIME_IS_VALID(self.loopStart) || !CMTIME_IS_VALID(self.loopEnd)) return; self.loopEnabled = !self.loopEnabled; [self.loopButton setImage:[UIImage systemImageNamed:(self.loopEnabled ? @"repeat.1" : @"repeat")] forState:UIControlStateNormal]; }
- (CMTime)frameDurationForPlayer:(AVPlayer *)player { AVAssetTrack *track = [[player.currentItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject]; CMTime d = track.minFrameDuration; if (CMTIME_IS_VALID(d) && d.value > 0) return d; float fps = track.nominalFrameRate; return CMTimeMakeWithSeconds(fps > 0 ? 1.0 / fps : 1.0 / 30.0, 600); }
- (void)stepFrame:(id)sender { [self.mainPlayer pause]; [self.subPlayer pause]; CMTime step = [self frameDurationForPlayer:self.mainPlayer]; [self seekBoth:CMTimeAdd(self.mainPlayer.currentTime, step)]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; }
- (void)individualTransport:(UIButton *)sender { AVPlayer *player = sender.tag <= 3 ? self.mainPlayer : self.subPlayer; BOOL isPlay = (sender.tag == 2 || sender.tag == 5); if (isPlay) { if (player.rate > 0) { [player pause]; [sender setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; } else { player.rate = self.speed; [sender setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal]; } return; } [player pause]; CMTime current = player.currentTime; CMTime delta = [self frameDurationForPlayer:player]; if (sender.tag == 1 || sender.tag == 4) delta = CMTimeMake(-delta.value, delta.timescale); CMTime target = CMTimeAdd(current, delta); if (CMTIME_COMPARE_INLINE(target, <, kCMTimeZero)) target = kCMTimeZero; [player seekToTime:target toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; UIButton *play = sender.tag <= 3 ? self.mainPlayButton : self.subPlayButton; [play setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; }
- (void)toggleMainMirror:(id)sender { self.mainMirrored = !self.mainMirrored; self.mainLayer.affineTransform = self.mainMirrored ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity; [self.mainMirrorButton setImage:[UIImage systemImageNamed:(self.mainMirrored ? @"arrow.left.and.right.righttriangle.left.righttriangle.right.fill" : @"arrow.left.and.right.righttriangle.left.righttriangle.right")] forState:UIControlStateNormal]; }
- (void)toggleSubMirror:(id)sender { self.subMirrored = !self.subMirrored; self.subLayer.affineTransform = self.subMirrored ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity; [self.subMirrorButton setImage:[UIImage systemImageNamed:(self.subMirrored ? @"arrow.left.and.right.righttriangle.left.righttriangle.right.fill" : @"arrow.left.and.right.righttriangle.left.righttriangle.right")] forState:UIControlStateNormal]; }
- (void)comparisonPinched:(UIPinchGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.view];
    BOOL mainArea = self.sideBySide ? point.x < self.view.bounds.size.width * .5 : point.y < self.view.bounds.size.height * .5;
    CGFloat *scale = mainArea ? &_mainZoomScale : &_subZoomScale;
    *scale = MIN(3.0, MAX(1.0, *scale * gesture.scale));
    gesture.scale = 1.0;
    CGAffineTransform transform = CGAffineTransformMakeScale(mainArea ? (self.mainMirrored ? -*scale : *scale) : (self.subMirrored ? -*scale : *scale), *scale);
    if (mainArea) self.mainLayer.affineTransform = transform; else self.subLayer.affineTransform = transform;
}
- (void)close { [self.mainPlayer pause]; [self.subPlayer pause]; self.loopEnabled = NO; self.loopSeekInProgress = NO; if (self.observer) { [self.mainPlayer removeTimeObserver:self.observer]; self.observer = nil; } [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)shareVideos:(id)sender { UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[self.mainURL, self.subURL] applicationActivities:nil]; if (activity.popoverPresentationController) { activity.popoverPresentationController.sourceView = sender; activity.popoverPresentationController.sourceRect = [sender bounds]; } [self presentViewController:activity animated:YES completion:nil]; }
- (void)exportComparisonVideo:(id)sender {
    AVAsset *mainAsset = [AVAsset assetWithURL:self.mainURL], *subAsset = [AVAsset assetWithURL:self.subURL];
    AVAssetTrack *mainTrack = [mainAsset tracksWithMediaType:AVMediaTypeVideo].firstObject, *subTrack = [subAsset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!mainTrack || !subTrack) return;
    // リンクを有効にした時点のMAIN/SUB位置をそれぞれの基準にする。
    // 書き出しはリンクポイントの2秒前から開始し、短い方の終端で終了する。
    BOOL useLinkedRange = self.hasLinkedAnchors && CMTIME_IS_VALID(self.linkedMainAnchor) && CMTIME_IS_VALID(self.linkedSubAnchor);
    double mainStartSeconds = useLinkedRange ? MAX(0.0, CMTimeGetSeconds(self.linkedMainAnchor) - 2.0) : 0.0;
    double subStartSeconds = useLinkedRange ? MAX(0.0, CMTimeGetSeconds(self.linkedSubAnchor) - 2.0) : 0.0;
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
    CGSize scaledMain = CGSizeMake(mainSize.width * self.mainZoomScale, mainSize.height * self.mainZoomScale);
    CGSize scaledSub = CGSizeMake(subSize.width * self.subZoomScale, subSize.height * self.subZoomScale);
    CGSize render = self.sideBySide ? CGSizeMake(scaledMain.width + scaledSub.width, MAX(scaledMain.height, scaledSub.height)) : CGSizeMake(MAX(scaledMain.width, scaledSub.width), scaledMain.height + scaledSub.height);
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
    videoComposition.renderSize = render; videoComposition.frameDuration = CMTimeMake(1, 30);
    AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction]; instruction.timeRange = CMTimeRangeMake(kCMTimeZero, duration);
    AVMutableVideoCompositionLayerInstruction *mainInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:mainComp];
    AVMutableVideoCompositionLayerInstruction *subInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:subComp];
    CGAffineTransform mainTransform = CGAffineTransformConcat(WJNormalizedTrackTransform(mainTrack), CGAffineTransformMakeScale(self.mainMirrored ? -self.mainZoomScale : self.mainZoomScale, self.mainZoomScale));
    CGAffineTransform subTransform = CGAffineTransformConcat(WJNormalizedTrackTransform(subTrack), CGAffineTransformMakeScale(self.subMirrored ? -self.subZoomScale : self.subZoomScale, self.subZoomScale));
    if (self.sideBySide) subTransform = CGAffineTransformConcat(subTransform, CGAffineTransformMakeTranslation(scaledMain.width, 0));
    else subTransform = CGAffineTransformConcat(subTransform, CGAffineTransformMakeTranslation(0, scaledMain.height));
    [mainInstruction setTransform:mainTransform atTime:kCMTimeZero]; [subInstruction setTransform:subTransform atTime:kCMTimeZero]; instruction.layerInstructions = @[mainInstruction, subInstruction]; videoComposition.instructions = @[instruction];
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
- (void)toggleFavorites:(id)sender { NSMutableArray *paths = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"WJFavoriteVideoPaths"] ?: @[]]; BOOL selected = [paths containsObject:self.mainURL.path] && [paths containsObject:self.subURL.path]; if (selected) { [paths removeObject:self.mainURL.path]; [paths removeObject:self.subURL.path]; } else { if (![paths containsObject:self.mainURL.path]) [paths addObject:self.mainURL.path]; if (![paths containsObject:self.subURL.path]) [paths addObject:self.subURL.path]; } [[NSUserDefaults standardUserDefaults] setObject:paths forKey:@"WJFavoriteVideoPaths"]; [self.favoriteButton setImage:[UIImage systemImageNamed:(selected ? @"heart" : @"heart.fill")] forState:UIControlStateNormal]; self.favoriteButton.tintColor = selected ? UIColor.whiteColor : UIColor.systemPinkColor; }
- (void)dealloc { if (self.observer) [self.mainPlayer removeTimeObserver:self.observer]; }
@end
