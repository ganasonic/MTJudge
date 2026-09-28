#import "WaterJumpComparisonViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface WaterJumpComparisonViewController ()
@property (nonatomic, strong) NSURL *mainURL;
@property (nonatomic, strong) NSURL *subURL;
@property (nonatomic, strong) AVPlayer *mainPlayer;
@property (nonatomic, strong) AVPlayer *subPlayer;
@property (nonatomic, strong) AVPlayerLayer *mainLayer;
@property (nonatomic, strong) AVPlayerLayer *subLayer;
@property (nonatomic, strong) UISlider *positionSlider;
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
@property (nonatomic, assign) CMTime loopStart;
@property (nonatomic, assign) CMTime loopEnd;
@property (nonatomic, assign) BOOL loopEnabled;
@property (nonatomic, assign) BOOL mainMirrored;
@property (nonatomic, assign) BOOL subMirrored;
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
    self.mainLayer = [AVPlayerLayer playerLayerWithPlayer:self.mainPlayer];
    self.subLayer = [AVPlayerLayer playerLayerWithPlayer:self.subPlayer];
    self.mainLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.subLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.view.layer addSublayer:self.mainLayer]; [self.view.layer addSublayer:self.subLayer];
    self.mainLabel = [self label:@"Main Camera"]; self.subLabel = [self label:@"Sub Camera"];
    [self.view addSubview:self.mainLabel]; [self.view addSubview:self.subLabel];
    self.positionSlider = [UISlider new]; self.positionSlider.minimumValue = 0; self.positionSlider.maximumValue = 1;
    [self.positionSlider addTarget:self action:@selector(positionChanged:) forControlEvents:UIControlEventValueChanged];
    self.speedSlider = [UISlider new]; self.speedSlider.minimumValue = .25; self.speedSlider.maximumValue = 2; self.speedSlider.value = 1;
    [self.speedSlider addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    self.playButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; self.playButton.tintColor = UIColor.whiteColor; [self.playButton addTarget:self action:@selector(togglePlay:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem]; [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal]; close.tintColor = UIColor.whiteColor; [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    self.aButton = [self featureButton:@"A" action:@selector(setA:)];
    self.bButton = [self featureButton:@"B" action:@selector(setB:)];
    self.loopButton = [self featureButton:@"↻" action:@selector(toggleLoop:)];
    self.frameButton = [self featureButton:@"▸|" action:@selector(stepFrame:)];
    self.mainMirrorButton = [self featureButton:@"M1" action:@selector(toggleMainMirror:)];
    self.subMirrorButton = [self featureButton:@"M2" action:@selector(toggleSubMirror:)];
    for (UIView *view in @[self.positionSlider, self.speedSlider, self.playButton, close, self.aButton, self.bButton, self.loopButton, self.frameButton, self.mainMirrorButton, self.subMirrorButton]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:view]; }
    self.positionSlider.accessibilityLabel = @"比較再生位置"; self.speedSlider.accessibilityLabel = @"比較再生速度";
    [NSLayoutConstraint activateConstraints:@[
        [self.mainLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12], [self.mainLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.subLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12], [self.subLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.positionSlider.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24], [self.positionSlider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24], [self.positionSlider.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-78],
        [self.speedSlider.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:100], [self.speedSlider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-100], [self.speedSlider.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-36],
        [self.aButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20], [self.aButton.bottomAnchor constraintEqualToAnchor:self.positionSlider.topAnchor constant:-4],
        [self.bButton.leadingAnchor constraintEqualToAnchor:self.aButton.trailingAnchor constant:6], [self.bButton.centerYAnchor constraintEqualToAnchor:self.aButton.centerYAnchor],
        [self.loopButton.leadingAnchor constraintEqualToAnchor:self.bButton.trailingAnchor constant:6], [self.loopButton.centerYAnchor constraintEqualToAnchor:self.aButton.centerYAnchor],
        [self.frameButton.leadingAnchor constraintEqualToAnchor:self.loopButton.trailingAnchor constant:6], [self.frameButton.centerYAnchor constraintEqualToAnchor:self.aButton.centerYAnchor],
        [self.mainMirrorButton.leadingAnchor constraintEqualToAnchor:self.frameButton.trailingAnchor constant:6], [self.mainMirrorButton.centerYAnchor constraintEqualToAnchor:self.aButton.centerYAnchor],
        [self.subMirrorButton.leadingAnchor constraintEqualToAnchor:self.mainMirrorButton.trailingAnchor constant:6], [self.subMirrorButton.centerYAnchor constraintEqualToAnchor:self.aButton.centerYAnchor],
        [self.playButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor], [self.playButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4], [self.playButton.widthAnchor constraintEqualToConstant:44], [self.playButton.heightAnchor constraintEqualToConstant:36],
        [close.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12], [close.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4], [close.widthAnchor constraintEqualToConstant:44], [close.heightAnchor constraintEqualToConstant:44]
    ]];
    __weak typeof(self) weakSelf = self;
    self.observer = [self.mainPlayer addPeriodicTimeObserverForInterval:CMTimeMake(1, 10) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) { [weakSelf updatePosition]; }];
    self.loopStart = kCMTimeInvalid; self.loopEnd = kCMTimeInvalid;
}

- (UILabel *)label:(NSString *)text { UILabel *label = [UILabel new]; label.text = text; label.textColor = UIColor.whiteColor; label.backgroundColor = [UIColor colorWithWhite:0 alpha:.45]; label.translatesAutoresizingMaskIntoConstraints = NO; return label; }
- (UIButton *)featureButton:(NSString *)title action:(SEL)action { UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:title forState:UIControlStateNormal]; button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]; button.tintColor = UIColor.whiteColor; [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; button.backgroundColor = [UIColor colorWithWhite:0 alpha:.45]; button.layer.cornerRadius = 6; button.contentEdgeInsets = UIEdgeInsetsMake(4, 7, 4, 7); [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; CGFloat top = self.view.safeAreaInsets.top + 32, bottom = self.view.bounds.size.height - 128; CGFloat h = MAX(1, (bottom - top) / 2); self.mainLayer.frame = CGRectMake(0, top, self.view.bounds.size.width, h); self.subLayer.frame = CGRectMake(0, top + h, self.view.bounds.size.width, h); }
- (void)togglePlay:(id)sender { BOOL playing = self.mainPlayer.rate > 0; if (playing) { [self.mainPlayer pause]; [self.subPlayer pause]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; } else { self.mainPlayer.rate = self.speed; self.subPlayer.rate = self.speed; [self.playButton setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal]; } }
- (void)startPlayback { [self configureAutomaticLoop]; [self togglePlay:nil]; }
- (void)positionChanged:(UISlider *)slider { double duration = CMTimeGetSeconds(self.mainPlayer.currentItem.duration); if (!isfinite(duration) || duration <= 0) return; CMTime time = CMTimeMakeWithSeconds(duration * slider.value, 600); [self.mainPlayer seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; [self.subPlayer seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; }
- (void)speedChanged:(UISlider *)slider { self.speed = roundf(slider.value * 100) / 100; BOOL playing = self.mainPlayer.rate > 0; self.mainPlayer.rate = playing ? self.speed : 0; self.subPlayer.rate = playing ? self.speed : 0; }
- (void)updatePosition { double duration = CMTimeGetSeconds(self.mainPlayer.currentItem.duration); double current = CMTimeGetSeconds(self.mainPlayer.currentTime); if (isfinite(duration) && duration > 0 && isfinite(current)) self.positionSlider.value = current / duration; if (self.loopEnabled && CMTIME_IS_VALID(self.loopEnd) && current >= CMTimeGetSeconds(self.loopEnd)) { [self seekBoth:self.loopStart]; self.mainPlayer.rate = self.speed; self.subPlayer.rate = self.speed; return; } if (self.automaticLoopLimit == 0 || !isfinite(duration) || duration <= 0 || !isfinite(current) || current < duration - .15) return; if (self.automaticLoopDeadline && [[NSDate date] compare:self.automaticLoopDeadline] != NSOrderedAscending) { self.automaticLoopLimit = 0; return; } if (self.automaticLoopLimit > 0 && self.automaticLoopCount >= self.automaticLoopLimit) { self.automaticLoopLimit = 0; return; } self.automaticLoopCount += 1; [self seekBoth:kCMTimeZero]; self.mainPlayer.rate = self.speed; self.subPlayer.rate = self.speed; }
- (void)configureAutomaticLoop { NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults; self.automaticLoopLimit = 0; self.automaticLoopCount = 1; self.automaticLoopDeadline = nil; if (![defaults boolForKey:@"WJLoopPlayback"]) return; NSInteger count = [defaults integerForKey:@"WJLoopCount"]; if (count == 0) count = 3; if (count > 0) self.automaticLoopLimit = count; else { self.automaticLoopLimit = -1; NSInteger seconds = [defaults integerForKey:@"WJLoopDuration"]; if (seconds > 0) self.automaticLoopDeadline = [NSDate dateWithTimeIntervalSinceNow:seconds]; } }
- (void)seekBoth:(CMTime)time { [self.mainPlayer seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; [self.subPlayer seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; }
- (void)setA:(id)sender { self.loopStart = self.mainPlayer.currentTime; self.loopEnabled = NO; [self.aButton setTitle:@"A✓" forState:UIControlStateNormal]; }
- (void)setB:(id)sender { CMTime now = self.mainPlayer.currentTime; if (!CMTIME_IS_VALID(self.loopStart) || CMTimeCompare(now, self.loopStart) <= 0) return; self.loopEnd = now; self.loopEnabled = YES; [self.bButton setTitle:@"B✓" forState:UIControlStateNormal]; [self.loopButton setTitle:@"↻✓" forState:UIControlStateNormal]; [self seekBoth:self.loopStart]; self.mainPlayer.rate = self.speed; self.subPlayer.rate = self.speed; }
- (void)toggleLoop:(id)sender { if (!CMTIME_IS_VALID(self.loopStart) || !CMTIME_IS_VALID(self.loopEnd)) return; self.loopEnabled = !self.loopEnabled; [self.loopButton setTitle:(self.loopEnabled ? @"↻✓" : @"↻") forState:UIControlStateNormal]; }
- (CMTime)frameDurationForPlayer:(AVPlayer *)player { AVAssetTrack *track = [[player.currentItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject]; CMTime d = track.minFrameDuration; if (CMTIME_IS_VALID(d) && d.value > 0) return d; float fps = track.nominalFrameRate; return CMTimeMakeWithSeconds(fps > 0 ? 1.0 / fps : 1.0 / 30.0, 600); }
- (void)stepFrame:(id)sender { [self.mainPlayer pause]; [self.subPlayer pause]; CMTime step = [self frameDurationForPlayer:self.mainPlayer]; [self seekBoth:CMTimeAdd(self.mainPlayer.currentTime, step)]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; }
- (void)toggleMainMirror:(id)sender { self.mainMirrored = !self.mainMirrored; self.mainLayer.affineTransform = self.mainMirrored ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity; [self.mainMirrorButton setTitle:(self.mainMirrored ? @"M1✓" : @"M1") forState:UIControlStateNormal]; }
- (void)toggleSubMirror:(id)sender { self.subMirrored = !self.subMirrored; self.subLayer.affineTransform = self.subMirrored ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity; [self.subMirrorButton setTitle:(self.subMirrored ? @"M2✓" : @"M2") forState:UIControlStateNormal]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)dealloc { if (self.observer) [self.mainPlayer removeTimeObserver:self.observer]; }
@end
