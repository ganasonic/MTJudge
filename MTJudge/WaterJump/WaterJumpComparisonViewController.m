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
@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, assign) CMTime loopStart;
@property (nonatomic, assign) CMTime loopEnd;
@property (nonatomic, assign) BOOL loopEnabled;
@property (nonatomic, assign) BOOL mainMirrored;
@property (nonatomic, assign) BOOL subMirrored;
@property (nonatomic, assign) BOOL sideBySide;
@property (nonatomic, assign) BOOL linkedPlayback;
@property (nonatomic, strong) UIButton *linkButton;
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
    self.mainLabel = [self label:@"MAIN"]; self.subLabel = [self label:@"SUB"];
    [self.view addSubview:self.mainLabel]; [self.view addSubview:self.subLabel];
    self.positionSlider = [UISlider new]; self.positionSlider.minimumValue = 0; self.positionSlider.maximumValue = 1;
    [self.positionSlider addTarget:self action:@selector(positionChanged:) forControlEvents:UIControlEventValueChanged];
    self.mainPositionSlider = [UISlider new]; self.mainPositionSlider.minimumValue = 0; self.mainPositionSlider.maximumValue = 1; [self.mainPositionSlider addTarget:self action:@selector(individualPositionChanged:) forControlEvents:UIControlEventValueChanged];
    self.subPositionSlider = [UISlider new]; self.subPositionSlider.minimumValue = 0; self.subPositionSlider.maximumValue = 1; [self.subPositionSlider addTarget:self action:@selector(individualPositionChanged:) forControlEvents:UIControlEventValueChanged];
    self.speedSlider = [UISlider new]; self.speedSlider.minimumValue = .25; self.speedSlider.maximumValue = 2; self.speedSlider.value = 1;
    [self.speedSlider addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    self.playButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; self.playButton.tintColor = UIColor.whiteColor; [self.playButton addTarget:self action:@selector(togglePlay:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem]; [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal]; close.tintColor = UIColor.whiteColor; [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    self.shareButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.shareButton setImage:[UIImage systemImageNamed:@"square.and.arrow.up"] forState:UIControlStateNormal]; self.shareButton.tintColor = UIColor.whiteColor; [self.shareButton addTarget:self action:@selector(shareVideos:) forControlEvents:UIControlEventTouchUpInside];
    self.favoriteButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.favoriteButton setImage:[UIImage systemImageNamed:@"heart"] forState:UIControlStateNormal]; self.favoriteButton.tintColor = UIColor.whiteColor; [self.favoriteButton addTarget:self action:@selector(toggleFavorites:) forControlEvents:UIControlEventTouchUpInside];
    self.linkButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.linkButton setImage:[UIImage systemImageNamed:@"link"] forState:UIControlStateNormal]; self.linkButton.tintColor = UIColor.systemGreenColor; self.linkButton.backgroundColor = [UIColor colorWithWhite:0 alpha:.45]; self.linkButton.layer.cornerRadius = 18; self.linkButton.layer.borderWidth = 0; self.linkButton.accessibilityLabel = @"2画面シーク連動"; [self.linkButton addTarget:self action:@selector(toggleLink:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *layoutButton = [UIButton buttonWithType:UIButtonTypeSystem]; [layoutButton setImage:[UIImage systemImageNamed:@"rectangle.split.2x1"] forState:UIControlStateNormal]; layoutButton.tintColor = UIColor.whiteColor; [layoutButton addTarget:self action:@selector(toggleLayout:) forControlEvents:UIControlEventTouchUpInside];
    self.aButton = [self featureButton:@"A" action:@selector(setA:)];
    self.bButton = [self featureButton:@"B" action:@selector(setB:)];
    self.loopButton = [self featureButton:@"↻" action:@selector(toggleLoop:)];
    self.frameButton = [self featureButton:@"▸|" action:@selector(stepFrame:)];
    self.mainMirrorButton = [self featureButton:@"M1" action:@selector(toggleMainMirror:)];
    self.subMirrorButton = [self featureButton:@"M2" action:@selector(toggleSubMirror:)];
    for (UIView *view in @[self.positionSlider, self.mainPositionSlider, self.subPositionSlider, self.speedSlider, self.playButton, close, self.shareButton, self.favoriteButton, self.linkButton, layoutButton, self.aButton, self.bButton, self.loopButton, self.frameButton, self.mainMirrorButton, self.subMirrorButton]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:view]; }
    self.positionSlider.accessibilityLabel = @"比較再生位置"; self.speedSlider.accessibilityLabel = @"比較再生速度";
    [NSLayoutConstraint activateConstraints:@[
        [self.positionSlider.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24], [self.positionSlider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24], [self.positionSlider.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-78],
        [self.mainPositionSlider.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24], [self.mainPositionSlider.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:.42], [self.mainPositionSlider.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-112],
        [self.subPositionSlider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24], [self.subPositionSlider.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:.42], [self.subPositionSlider.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-112],
        [self.speedSlider.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:100], [self.speedSlider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-100], [self.speedSlider.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-36],
        [self.aButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20], [self.aButton.centerYAnchor constraintEqualToAnchor:self.playButton.centerYAnchor],
        [self.bButton.leadingAnchor constraintEqualToAnchor:self.aButton.trailingAnchor constant:6], [self.bButton.centerYAnchor constraintEqualToAnchor:self.aButton.centerYAnchor],
        [self.loopButton.leadingAnchor constraintEqualToAnchor:self.bButton.trailingAnchor constant:6], [self.loopButton.centerYAnchor constraintEqualToAnchor:self.aButton.centerYAnchor],
        [self.frameButton.leadingAnchor constraintEqualToAnchor:self.loopButton.trailingAnchor constant:6], [self.frameButton.centerYAnchor constraintEqualToAnchor:self.aButton.centerYAnchor],
        [self.mainMirrorButton.leadingAnchor constraintEqualToAnchor:self.frameButton.trailingAnchor constant:6], [self.mainMirrorButton.centerYAnchor constraintEqualToAnchor:self.aButton.centerYAnchor],
        [self.subMirrorButton.leadingAnchor constraintEqualToAnchor:self.mainMirrorButton.trailingAnchor constant:6], [self.subMirrorButton.centerYAnchor constraintEqualToAnchor:self.aButton.centerYAnchor],
        [self.playButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor], [self.playButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4], [self.playButton.widthAnchor constraintEqualToConstant:44], [self.playButton.heightAnchor constraintEqualToConstant:36],
        [close.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12], [close.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4], [close.widthAnchor constraintEqualToConstant:44], [close.heightAnchor constraintEqualToConstant:44],
        [self.favoriteButton.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-4], [self.favoriteButton.topAnchor constraintEqualToAnchor:close.topAnchor], [self.favoriteButton.widthAnchor constraintEqualToConstant:44], [self.favoriteButton.heightAnchor constraintEqualToConstant:44],
        [self.shareButton.trailingAnchor constraintEqualToAnchor:self.favoriteButton.leadingAnchor constant:-4], [self.shareButton.topAnchor constraintEqualToAnchor:close.topAnchor], [self.shareButton.widthAnchor constraintEqualToConstant:44], [self.shareButton.heightAnchor constraintEqualToConstant:44],
        [layoutButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12], [layoutButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4], [layoutButton.widthAnchor constraintEqualToConstant:44], [layoutButton.heightAnchor constraintEqualToConstant:44]
    ]];
    self.mainLabel.translatesAutoresizingMaskIntoConstraints = YES;
    self.subLabel.translatesAutoresizingMaskIntoConstraints = YES;
    self.linkButton.translatesAutoresizingMaskIntoConstraints = YES;
    __weak typeof(self) weakSelf = self;
    self.observer = [self.mainPlayer addPeriodicTimeObserverForInterval:CMTimeMake(1, 10) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) { [weakSelf updatePosition]; }];
    self.loopStart = kCMTimeInvalid; self.loopEnd = kCMTimeInvalid; self.linkedPlayback = YES; self.sideBySide = NO;
}

- (UILabel *)label:(NSString *)text { UILabel *label = [UILabel new]; label.text = text; label.textColor = UIColor.whiteColor; label.backgroundColor = [UIColor colorWithWhite:0 alpha:.45]; label.translatesAutoresizingMaskIntoConstraints = NO; return label; }
- (UIButton *)featureButton:(NSString *)title action:(SEL)action { UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:title forState:UIControlStateNormal]; button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]; button.tintColor = UIColor.whiteColor; [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; button.backgroundColor = [UIColor colorWithWhite:0 alpha:.45]; button.layer.cornerRadius = 6; button.contentEdgeInsets = UIEdgeInsetsMake(4, 7, 4, 7); [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; CGFloat top = self.view.safeAreaInsets.top + 32, bottom = self.view.bounds.size.height - 128; CGFloat availableHeight = MAX(1, bottom - top); CGFloat boundaryX = self.view.bounds.size.width / 2.0; CGFloat boundaryY = top + availableHeight / 2.0; if (self.sideBySide) { CGFloat w = boundaryX; self.mainLayer.frame = CGRectMake(0, top, w, availableHeight); self.subLayer.frame = CGRectMake(w, top, w, availableHeight); } else { CGFloat h = MAX(1, availableHeight / 2.0); boundaryY = top + h; self.mainLayer.frame = CGRectMake(0, top, self.view.bounds.size.width, h); self.subLayer.frame = CGRectMake(0, boundaryY, self.view.bounds.size.width, h); } [self.mainLabel sizeToFit]; [self.subLabel sizeToFit]; CGFloat labelX = 12.0; self.mainLabel.frame = CGRectMake(labelX, top + 8.0, self.mainLabel.bounds.size.width, self.mainLabel.bounds.size.height); self.subLabel.frame = CGRectMake(self.sideBySide ? boundaryX + labelX : labelX, self.sideBySide ? top + 8.0 : boundaryY + 8.0, self.subLabel.bounds.size.width, self.subLabel.bounds.size.height); self.linkButton.frame = CGRectMake((self.sideBySide ? boundaryX : self.view.bounds.size.width / 2.0) - 24.0, boundaryY - 24.0, 48.0, 48.0); [self.view bringSubviewToFront:self.linkButton]; [self.view bringSubviewToFront:self.mainPositionSlider]; [self.view bringSubviewToFront:self.subPositionSlider]; }
- (void)togglePlay:(id)sender { BOOL playing = self.mainPlayer.rate > 0; if (playing) { [self.mainPlayer pause]; [self.subPlayer pause]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; } else { self.mainPlayer.rate = self.speed; self.subPlayer.rate = self.speed; [self.playButton setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal]; } }
- (void)startPlayback { [self configureAutomaticLoop]; [self togglePlay:nil]; }
- (void)positionChanged:(UISlider *)slider { [self.mainPlayer pause]; [self.subPlayer pause]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; double duration = CMTimeGetSeconds(self.mainPlayer.currentItem.duration); if (!isfinite(duration) || duration <= 0) return; CMTime time = CMTimeMakeWithSeconds(duration * slider.value, 600); if (self.linkedPlayback) [self seekBoth:time]; else [self.mainPlayer seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; }
- (void)individualPositionChanged:(UISlider *)slider { [self.mainPlayer pause]; [self.subPlayer pause]; [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; AVPlayer *player = slider == self.mainPositionSlider ? self.mainPlayer : self.subPlayer; double duration = CMTimeGetSeconds(player.currentItem.duration); if (!isfinite(duration) || duration <= 0) return; CMTime time = CMTimeMakeWithSeconds(duration * slider.value, 600); [player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; }
- (void)toggleLink:(id)sender { self.linkedPlayback = !self.linkedPlayback; [self.linkButton setImage:[UIImage systemImageNamed:(self.linkedPlayback ? @"link" : @"link.slash")] forState:UIControlStateNormal]; }
- (void)toggleLayout:(id)sender { self.sideBySide = !self.sideBySide; [self.view setNeedsLayout]; }
- (void)speedChanged:(UISlider *)slider { self.speed = roundf(slider.value * 100) / 100; BOOL playing = self.mainPlayer.rate > 0; self.mainPlayer.rate = playing ? self.speed : 0; self.subPlayer.rate = playing ? self.speed : 0; }
- (void)updatePosition { double duration = CMTimeGetSeconds(self.mainPlayer.currentItem.duration); double current = CMTimeGetSeconds(self.mainPlayer.currentTime); if (isfinite(duration) && duration > 0 && isfinite(current)) { self.positionSlider.value = current / duration; self.mainPositionSlider.value = current / duration; } double subDuration = CMTimeGetSeconds(self.subPlayer.currentItem.duration); double subCurrent = CMTimeGetSeconds(self.subPlayer.currentTime); if (isfinite(subDuration) && subDuration > 0 && isfinite(subCurrent)) self.subPositionSlider.value = subCurrent / subDuration; if (self.loopEnabled && CMTIME_IS_VALID(self.loopEnd) && current >= CMTimeGetSeconds(self.loopEnd)) { [self seekBoth:self.loopStart]; self.mainPlayer.rate = self.speed; self.subPlayer.rate = self.speed; return; } if (self.automaticLoopLimit == 0 || !isfinite(duration) || duration <= 0 || !isfinite(current) || current < duration - .15) return; if (self.automaticLoopDeadline && [[NSDate date] compare:self.automaticLoopDeadline] != NSOrderedAscending) { self.automaticLoopLimit = 0; return; } if (self.automaticLoopLimit > 0 && self.automaticLoopCount >= self.automaticLoopLimit) { self.automaticLoopLimit = 0; return; } self.automaticLoopCount += 1; [self seekBoth:kCMTimeZero]; self.mainPlayer.rate = self.speed; self.subPlayer.rate = self.speed; }
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
- (void)shareVideos:(id)sender { UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[self.mainURL, self.subURL] applicationActivities:nil]; if (activity.popoverPresentationController) { activity.popoverPresentationController.sourceView = sender; activity.popoverPresentationController.sourceRect = [sender bounds]; } [self presentViewController:activity animated:YES completion:nil]; }
- (void)toggleFavorites:(id)sender { NSMutableArray *paths = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"WJFavoriteVideoPaths"] ?: @[]]; BOOL selected = [paths containsObject:self.mainURL.path] && [paths containsObject:self.subURL.path]; if (selected) { [paths removeObject:self.mainURL.path]; [paths removeObject:self.subURL.path]; } else { if (![paths containsObject:self.mainURL.path]) [paths addObject:self.mainURL.path]; if (![paths containsObject:self.subURL.path]) [paths addObject:self.subURL.path]; } [[NSUserDefaults standardUserDefaults] setObject:paths forKey:@"WJFavoriteVideoPaths"]; [self.favoriteButton setImage:[UIImage systemImageNamed:(selected ? @"heart" : @"heart.fill")] forState:UIControlStateNormal]; self.favoriteButton.tintColor = selected ? UIColor.whiteColor : UIColor.systemPinkColor; }
- (void)dealloc { if (self.observer) [self.mainPlayer removeTimeObserver:self.observer]; }
@end
