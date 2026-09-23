#import "WaterJumpReceivedPlayerViewController.h"

@interface WaterJumpReceivedPlayerViewController ()
@property (nonatomic, assign) float wjSelectedSpeed;
@property (nonatomic, strong) UIView *speedControlContainer;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UILabel *speedValueLabel;
@property (nonatomic, strong) NSTimer *speedHideTimer;
@end

@implementation WaterJumpReceivedPlayerViewController

- (instancetype)initWithVideoURL:(NSURL *)url {
    if ((self = [super init])) {
        _wjSelectedSpeed = 1.0f;
        self.player = [AVPlayer playerWithURL:url];
        self.videoGravity = AVLayerVideoGravityResizeAspect;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        self.showsPlaybackControls = YES;
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
    [self showSpeedControls];
    [self resetAndPlay];
}

- (void)dealloc { [self.speedHideTimer invalidate]; }

- (void)buildSpeedControls {
    UIView *host = self.view;
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
}

- (void)replaceVideoURL:(NSURL *)url {
    if (!url || ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
        self.wjSelectedSpeed = 1.0f;
        [self.player replaceCurrentItemWithPlayerItem:item];
        [self updateSpeedSlider];
        [self resetAndPlay];
    });
}

- (void)resetAndPlay {
    if (!self.player) return;
    self.player.rate = 0.0f;
    [self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finished && self.player.currentItem.status != AVPlayerItemStatusFailed) {
                self.player.rate = self.wjSelectedSpeed;
            }
        });
    }];
}

- (void)playerTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) [self showSpeedControls];
}

- (void)showSpeedControls {
    self.speedControlContainer.hidden = NO;
    [self.view bringSubviewToFront:self.speedControlContainer];
    [self.speedHideTimer invalidate];
    self.speedHideTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(hideSpeedControls) userInfo:nil repeats:NO];
}

- (void)hideSpeedControls { self.speedControlContainer.hidden = YES; }

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

@end
