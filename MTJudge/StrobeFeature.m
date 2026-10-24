#import "StrobeFeature.h"
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>

@interface StrobePreviewViewController : UIViewController
- (instancetype)initWithImageURL:(NSURL *)url completion:(void (^)(BOOL saved))completion;
@end

// A temporal median supplies a background reference even when Vision misses a small subject.
// The displayed background remains the first frame, preserving the existing appearance.
static CIImage *MTJStrobeBackground(AVAssetImageGenerator *generator, CIContext *context, double start, double end) {
    NSMutableArray<CIImage *> *samples = [NSMutableArray array];
    for (NSInteger i=0; i<5; i++) {
        CMTime time = CMTimeMakeWithSeconds(start+(end-start)*(i+.5)/5.0,600);
        CGImageRef cg = [generator copyCGImageAtTime:time actualTime:NULL error:nil];
        if (!cg) continue;
        CIImage *image = [CIImage imageWithCGImage:cg]; CGImageRelease(cg);
        CGFloat scale = MIN(1,640.0/MAX(image.extent.size.width,image.extent.size.height));
        image = [image imageByApplyingTransform:CGAffineTransformMakeScale(scale,scale)];
        [samples addObject:[image imageByCroppingToRect:CGRectIntegral(image.extent)]];
    }
    if (!samples.count) return nil;
    if (samples.count == 5) {
        const int pairs[][2] = {{0,1},{3,4},{2,4},{2,3},{1,4},{0,3},{0,2},{1,3},{1,2}};
        for (NSInteger i=0; i<9; i++) {
            int a=pairs[i][0], b=pairs[i][1]; CIImage *left=samples[a], *right=samples[b];
            samples[a] = [left imageByApplyingFilter:@"CIMinimumCompositing" withInputParameters:@{kCIInputBackgroundImageKey:right}];
            samples[b] = [left imageByApplyingFilter:@"CIMaximumCompositing" withInputParameters:@{kCIInputBackgroundImageKey:right}];
        }
    }
    CIImage *median = samples[samples.count == 5 ? 2 : 0];
    CGImageRef cg = [context createCGImage:median fromRect:median.extent];
    CIImage *result = cg ? [CIImage imageWithCGImage:cg] : nil; if (cg) CGImageRelease(cg);
    return result;
}
static CIImage *MTJStrobeMotionMask(CIImage *image, CIImage *reference, CIContext *context) {
    if (!reference) return nil;
    CGRect small = reference.extent;
    CIImage *scaled = [[image imageByApplyingTransform:CGAffineTransformMakeScale(small.size.width/image.extent.size.width,small.size.height/image.extent.size.height)] imageByCroppingToRect:small];
    CIImage *difference = [scaled imageByApplyingFilter:@"CIDifferenceBlendMode" withInputParameters:@{kCIInputBackgroundImageKey:reference}];
    CIVector *weights = [CIVector vectorWithX:3 Y:3 Z:3 W:0];
    CIImage *mask = [difference imageByApplyingFilter:@"CIColorMatrix" withInputParameters:@{@"inputRVector":weights,@"inputGVector":weights,@"inputBVector":weights,@"inputAVector":[CIVector vectorWithX:0 Y:0 Z:0 W:1],@"inputBiasVector":[CIVector vectorWithX:-.35 Y:-.35 Z:-.35 W:0]}];
    mask = [mask imageByApplyingFilter:@"CIColorClamp" withInputParameters:@{@"inputMinComponents":[CIVector vectorWithX:0 Y:0 Z:0 W:0],@"inputMaxComponents":[CIVector vectorWithX:1 Y:1 Z:1 W:1]}];
    mask = [mask imageByApplyingFilter:@"CIMorphologyMinimum" withInputParameters:@{kCIInputRadiusKey:@1}];
    mask = [mask imageByApplyingFilter:@"CIMorphologyMaximum" withInputParameters:@{kCIInputRadiusKey:@1}];
    // A moving camera must not paste the whole background over earlier poses.
    CIImage *average = [mask imageByApplyingFilter:@"CIAreaAverage" withInputParameters:@{kCIInputExtentKey:[CIVector vectorWithCGRect:small]}];
    uint8_t coverage[4]={0}; CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    [context render:average toBitmap:coverage rowBytes:4 bounds:CGRectMake(0,0,1,1) format:kCIFormatRGBA8 colorSpace:space]; CGColorSpaceRelease(space);
    if (coverage[0] > 102) return nil;
    return [[mask imageByApplyingTransform:CGAffineTransformMakeScale(image.extent.size.width/small.size.width,image.extent.size.height/small.size.height)] imageByCroppingToRect:image.extent];
}
static BOOL MTJStrobeMaskHasSubject(CIImage *mask, CIContext *context) {
    if (!mask) return NO;
    CIImage *maximum = [mask imageByApplyingFilter:@"CIAreaMaximum" withInputParameters:@{kCIInputExtentKey:[CIVector vectorWithCGRect:mask.extent]}];
    uint8_t pixel[4]={0}; CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    [context render:maximum toBitmap:pixel rowBytes:4 bounds:CGRectMake(0,0,1,1) format:kCIFormatRGBA8 colorSpace:space]; CGColorSpaceRelease(space);
    return MAX(pixel[0],MAX(pixel[1],pixel[2])) > 24;
}

@implementation StrobeImageComposer
+ (void)generateForVideoURL:(NSURL *)videoURL startTime:(CMTime)startTime endTime:(CMTime)endTime intervalMilliseconds:(NSInteger)intervalMilliseconds completion:(MTJStrobeCompletion)completion {
    [self generateForVideoURL:videoURL startTime:startTime endTime:endTime intervalMilliseconds:intervalMilliseconds progress:nil completion:completion];
}
+ (void)generateForVideoURL:(NSURL *)videoURL startTime:(CMTime)startTime endTime:(CMTime)endTime intervalMilliseconds:(NSInteger)intervalMilliseconds progress:(void (^)(double))progress completion:(MTJStrobeCompletion)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil; NSURL *outputURL = nil;
        @autoreleasepool {
            AVAsset *asset = [AVAsset assetWithURL:videoURL];
            AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
            double duration = CMTimeGetSeconds(asset.duration), start = CMTimeGetSeconds(startTime), end = CMTimeGetSeconds(endTime);
            NSInteger interval = MAX(20, intervalMilliseconds);
            if (!track || !isfinite(duration) || duration <= 0 || !isfinite(start) || !isfinite(end) || end <= start) error = [NSError errorWithDomain:@"MTJudge.Strobe" code:1 userInfo:@{NSLocalizedDescriptionKey:@"ストロボ対象区間が不正です。"}];
            if (!error) {
                start = MAX(0, MIN(duration, start)); end = MAX(start, MIN(duration, end));
                AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset]; generator.appliesPreferredTrackTransform = YES; generator.requestedTimeToleranceBefore = kCMTimeZero; generator.requestedTimeToleranceAfter = kCMTimeZero; generator.maximumSize = CGSizeMake(fabs(track.naturalSize.width), fabs(track.naturalSize.height));
                CIContext *context = [CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}]; CIImage *composite = nil;
                CIImage *reference = MTJStrobeBackground(generator,context,start,end);
                NSInteger subjects = 0; NSInteger frameCount = MAX(1, (NSInteger)ceil((end-start) * 1000.0 / interval) + 1);
                for (NSInteger index = 0; index < frameCount; index++) {
                    @autoreleasepool {
                        double seconds = MIN(end, start + ((double)index * interval / 1000.0)); CMTime requested = CMTimeMakeWithSeconds(seconds, 600); NSError *frameError = nil; CGImageRef cg = [generator copyCGImageAtTime:requested actualTime:NULL error:&frameError];
                        if (!cg) { if (index == 0) error = frameError ?: [NSError errorWithDomain:@"MTJudge.Strobe" code:2 userInfo:@{NSLocalizedDescriptionKey:@"動画フレームを取得できません。"}]; continue; }
                        CIImage *image = [CIImage imageWithCGImage:cg]; if (!composite) composite = image; // 開始フレームを基準背景にする
                        CIImage *mask = MTJStrobeMotionMask(image,reference,context);
                        VNGeneratePersonSegmentationRequest *request = [VNGeneratePersonSegmentationRequest new]; request.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelBalanced; request.outputPixelFormat = kCVPixelFormatType_OneComponent8;
                        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}]; NSError *visionError = nil;
                        [handler performRequests:@[request] error:&visionError];
                        VNPixelBufferObservation *observation = request.results.firstObject;
                        if (observation && !visionError) {
                            CIImage *personMask = [CIImage imageWithCVPixelBuffer:observation.pixelBuffer];
                            if (personMask.extent.size.width > 0 && personMask.extent.size.height > 0) {
                                personMask = [[personMask imageByApplyingTransform:CGAffineTransformMakeScale(image.extent.size.width/personMask.extent.size.width,image.extent.size.height/personMask.extent.size.height)] imageByCroppingToRect:image.extent];
                                mask = mask ? [personMask imageByApplyingFilter:@"CIMaximumCompositing" withInputParameters:@{kCIInputBackgroundImageKey:mask}] : personMask;
                            }
                        }
                        if (index > 0 && MTJStrobeMaskHasSubject(mask,context)) {
                            // Blend against the accumulated image; previous poses must remain visible.
                            CIImage *next = [image imageByApplyingFilter:@"CIBlendWithMask" withInputParameters:@{kCIInputBackgroundImageKey:composite,kCIInputMaskImageKey:mask}];
                            if (next) { composite = [next imageByCroppingToRect:image.extent]; subjects += 1; }
                            if (subjects%8 == 0) {
                                CGImageRef flattened = [context createCGImage:composite fromRect:composite.extent];
                                if (flattened) { composite = [CIImage imageWithCGImage:flattened]; CGImageRelease(flattened); }
                            }
                        }
                        CGImageRelease(cg);
                        if (progress) { double value = (double)(index + 1) / (double)frameCount; dispatch_async(dispatch_get_main_queue(), ^{ progress(value); }); }
                    }
                }
                if (!error && subjects == 0) error = [NSError errorWithDomain:@"MTJudge.Strobe" code:4 userInfo:@{NSLocalizedDescriptionKey:@"指定区間から人物・動いている対象物を抽出できませんでした。対象物が動いている区間と切り出し間隔を選び直してください。"}];
                if (!error && composite) {
                    CGRect extent = composite.extent; CGImageRef result = [context createCGImage:composite fromRect:extent];
                    if (result) {
                        UIImage *image = [UIImage imageWithCGImage:result]; CGImageRelease(result); NSURL *dir = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject]; dir = [dir URLByAppendingPathComponent:@"Recordings" isDirectory:YES]; [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil]; NSDateFormatter *formatter = [NSDateFormatter new]; formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; formatter.dateFormat = @"yyyyMMddHHmmssSSS"; outputURL = [dir URLByAppendingPathComponent:[NSString stringWithFormat:@"MTJStrobe_%@.JPG", [formatter stringFromDate:[NSDate date]]]]; NSData *data = UIImageJPEGRepresentation(image, .95); if (!data || ![data writeToURL:outputURL options:NSDataWritingAtomic error:&error]) outputURL = nil;
                    } else error = [NSError errorWithDomain:@"MTJudge.Strobe" code:3 userInfo:@{NSLocalizedDescriptionKey:@"合成画像を生成できません。"}];
                } else if (!error) error = [NSError errorWithDomain:@"MTJudge.Strobe" code:4 userInfo:@{NSLocalizedDescriptionKey:@"人物を検出できませんでした。"}];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(outputURL, error); });
    });
}
@end

@interface StrobeConfigurationViewController ()
@property (nonatomic, strong) NSURL *videoURL;
@property (nonatomic, copy) void (^completion)(NSURL * _Nullable);
@property (nonatomic, strong) UISlider *startSlider;
@property (nonatomic, strong) UISlider *endSlider;
@property (nonatomic, strong) UISegmentedControl *intervalControl;
@property (nonatomic, strong) UILabel *startLabel;
@property (nonatomic, strong) UILabel *endLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *previewView;
@property (nonatomic, strong) AVPlayer *previewPlayer;
@property (nonatomic, strong) AVPlayerLayer *previewLayer;
@property (nonatomic, strong) UISlider *positionSlider;
@property (nonatomic, strong) UIButton *previewPlayButton;
@property (nonatomic, strong) id previewObserver;
@property (nonatomic, strong) UIScrollView *settingsScrollView;
@property (nonatomic, assign) double duration;
@end

@implementation StrobeConfigurationViewController
- (instancetype)initWithVideoURL:(NSURL *)videoURL completion:(void (^)(NSURL * _Nullable))completion { if ((self = [super init])) { _videoURL = videoURL; _completion = [completion copy]; self.modalPresentationStyle = UIModalPresentationFormSheet; } return self; }
- (void)dealloc { if (self.previewObserver && self.previewPlayer) [self.previewPlayer removeTimeObserver:self.previewObserver]; }
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor = UIColor.systemBackgroundColor; self.title = @"ストロボ設定"; self.duration = CMTimeGetSeconds([AVAsset assetWithURL:self.videoURL].duration); if (!isfinite(self.duration) || self.duration <= 0) self.duration = 1;
    self.previewView = [UIView new]; self.previewView.translatesAutoresizingMaskIntoConstraints = NO; self.previewView.backgroundColor = UIColor.blackColor; self.previewView.clipsToBounds = YES; [self.view addSubview:self.previewView];
    self.previewPlayer = [AVPlayer playerWithURL:self.videoURL]; self.previewLayer = [AVPlayerLayer playerLayerWithPlayer:self.previewPlayer]; self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspect; [self.previewView.layer addSublayer:self.previewLayer];
    self.settingsScrollView = [UIScrollView new]; self.settingsScrollView.translatesAutoresizingMaskIntoConstraints = NO; self.settingsScrollView.alwaysBounceVertical = YES; self.settingsScrollView.showsVerticalScrollIndicator = YES; [self.view addSubview:self.settingsScrollView];
    UIStackView *stack = [[UIStackView alloc] init]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = NO; [self.settingsScrollView addSubview:stack];
    UILabel *header = [UILabel new]; header.text = @"合成する区間と間隔を指定"; header.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.startLabel = [UILabel new]; self.endLabel = [UILabel new]; self.startSlider = [UISlider new]; self.endSlider = [UISlider new]; self.startSlider.maximumValue = self.duration; self.endSlider.maximumValue = self.duration; self.endSlider.value = self.duration; [self.startSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged]; [self.endSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    self.intervalControl = [[UISegmentedControl alloc] initWithItems:@[@"50ms", @"100ms", @"150ms", @"200ms", @"250ms", @"500ms"]]; self.intervalControl.selectedSegmentIndex = 1;
    self.positionSlider = [UISlider new]; self.positionSlider.maximumValue = self.duration; [self.positionSlider addTarget:self action:@selector(positionChanged:) forControlEvents:UIControlEventValueChanged];
    self.previewPlayButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.previewPlayButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; self.previewPlayButton.tintColor = UIColor.whiteColor; self.previewPlayButton.backgroundColor = [UIColor colorWithWhite:0 alpha:.55]; self.previewPlayButton.layer.cornerRadius = 18; self.previewPlayButton.translatesAutoresizingMaskIntoConstraints = NO; [self.previewView addSubview:self.previewPlayButton]; [self.previewPlayButton addTarget:self action:@selector(togglePreview:) forControlEvents:UIControlEventTouchUpInside];
    UIButton *generate = [UIButton buttonWithType:UIButtonTypeSystem]; [generate setTitle:@"ストロボ画像を生成" forState:UIControlStateNormal]; generate.titleLabel.font = [UIFont boldSystemFontOfSize:17]; generate.tintColor = UIColor.whiteColor; generate.backgroundColor = UIColor.systemBlueColor; generate.layer.cornerRadius = 10; [generate addTarget:self action:@selector(generate:) forControlEvents:UIControlEventTouchUpInside]; [generate.heightAnchor constraintGreaterThanOrEqualToConstant:48].active = YES;
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem]; [cancel setTitle:@"キャンセル" forState:UIControlStateNormal]; cancel.tintColor = UIColor.labelColor; cancel.backgroundColor = UIColor.secondarySystemFillColor; cancel.layer.cornerRadius = 10; [cancel addTarget:self action:@selector(cancel:) forControlEvents:UIControlEventTouchUpInside]; [cancel.heightAnchor constraintGreaterThanOrEqualToConstant:48].active = YES;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; self.spinner.hidden = YES; self.statusLabel = [self label:@""]; self.statusLabel.textAlignment = NSTextAlignmentCenter;
    for (UIView *v in @[header,self.startLabel,self.startSlider,self.endLabel,self.endSlider,[self label:@"現在位置"],self.positionSlider,[self label:@"切り出し間隔"],self.intervalControl,generate,cancel]) [stack addArrangedSubview:v]; [stack addArrangedSubview:self.spinner]; [stack addArrangedSubview:self.statusLabel];
    [NSLayoutConstraint activateConstraints:@[[self.previewView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],[self.previewView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],[self.previewView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],[self.previewView.heightAnchor constraintEqualToAnchor:self.previewView.widthAnchor multiplier:.56],[self.previewPlayButton.centerXAnchor constraintEqualToAnchor:self.previewView.centerXAnchor],[self.previewPlayButton.centerYAnchor constraintEqualToAnchor:self.previewView.centerYAnchor],[self.previewPlayButton.widthAnchor constraintEqualToConstant:44],[self.previewPlayButton.heightAnchor constraintEqualToConstant:44],[self.settingsScrollView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],[self.settingsScrollView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],[self.settingsScrollView.topAnchor constraintEqualToAnchor:self.previewView.bottomAnchor constant:10],[self.settingsScrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],[stack.leadingAnchor constraintEqualToAnchor:self.settingsScrollView.contentLayoutGuide.leadingAnchor constant:8],[stack.trailingAnchor constraintEqualToAnchor:self.settingsScrollView.contentLayoutGuide.trailingAnchor constant:-8],[stack.topAnchor constraintEqualToAnchor:self.settingsScrollView.contentLayoutGuide.topAnchor constant:4],[stack.bottomAnchor constraintEqualToAnchor:self.settingsScrollView.contentLayoutGuide.bottomAnchor constant:-12],[stack.widthAnchor constraintEqualToAnchor:self.settingsScrollView.frameLayoutGuide.widthAnchor constant:-16]]]; [self sliderChanged:nil]; self.previewLayer.frame = self.previewView.bounds; self.previewObserver = [self.previewPlayer addPeriodicTimeObserverForInterval:CMTimeMake(1,30) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) { if (!self.positionSlider.isTracking) self.positionSlider.value = CMTimeGetSeconds(time); }]; }
- (UILabel *)label:(NSString *)text { UILabel *l = [UILabel new]; l.text = text; l.textColor = UIColor.secondaryLabelColor; return l; }
- (void)sliderChanged:(id)sender { self.startSlider.value = MIN(self.startSlider.value, self.endSlider.value - .01); self.startLabel.text = [NSString stringWithFormat:@"開始 %.2f秒", self.startSlider.value]; self.endLabel.text = [NSString stringWithFormat:@"終了 %.2f秒", self.endSlider.value]; if (sender == self.startSlider || sender == self.endSlider) { double seconds = (sender == self.startSlider) ? self.startSlider.value : self.endSlider.value; [self.previewPlayer pause]; [self.previewPlayButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; [self.previewPlayer seekToTime:CMTimeMakeWithSeconds(seconds, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; self.positionSlider.value = seconds; } }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; self.previewLayer.frame = self.previewView.bounds; }
- (void)positionChanged:(UISlider *)slider { [self.previewPlayer pause]; [self.previewPlayButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; [self.previewPlayer seekToTime:CMTimeMakeWithSeconds(slider.value, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; }
- (void)togglePreview:(id)sender { if (self.previewPlayer.rate > 0) { [self.previewPlayer pause]; [self.previewPlayButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal]; } else { if (CMTimeGetSeconds(self.previewPlayer.currentTime) >= self.duration - .05) [self.previewPlayer seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil]; self.previewPlayer.rate = 1.0; [self.previewPlayButton setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal]; } }
- (void)generate:(id)sender { NSInteger values[] = {50,100,150,200,250,500}; NSInteger interval = values[MAX(0, MIN(5, self.intervalControl.selectedSegmentIndex))]; NSInteger frameCount = MAX(1, (NSInteger)ceil((self.endSlider.value - self.startSlider.value) * 1000.0 / interval) + 1); if (frameCount > 240) { UIAlertController *warning = [UIAlertController alertControllerWithTitle:@"フレーム数が多くなります" message:[NSString stringWithFormat:@"約%ld枚の人物像を合成します。処理に時間がかかる場合があります。続行しますか？", (long)frameCount] preferredStyle:UIAlertControllerStyleAlert]; [warning addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]]; [warning addAction:[UIAlertAction actionWithTitle:@"続行" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self generateAfterWarning:interval]; }]]; [self presentViewController:warning animated:YES completion:nil]; return; } [self generateAfterWarning:interval]; }
- (void)generateAfterWarning:(NSInteger)interval { self.spinner.hidden = NO; self.statusLabel.text = @"ストロボ画像を生成中… 0%"; [self.spinner startAnimating]; for (UIView *v in self.view.subviews) v.userInteractionEnabled = NO; __weak typeof(self) weakSelf = self; [StrobeImageComposer generateForVideoURL:self.videoURL startTime:CMTimeMakeWithSeconds(self.startSlider.value,600) endTime:CMTimeMakeWithSeconds(self.endSlider.value,600) intervalMilliseconds:interval progress:^(double progress) { weakSelf.statusLabel.text = [NSString stringWithFormat:@"ストロボ画像を生成中… %d%%", (int)round(progress * 100.0)]; } completion:^(NSURL *outputURL, NSError *error) { if (!weakSelf) return; [weakSelf.spinner stopAnimating]; if (error || !outputURL) { for (UIView *v in weakSelf.view.subviews) v.userInteractionEnabled = YES; weakSelf.statusLabel.text = @""; NSString *message = error.localizedDescription ?: @"画像ファイルを書き出せませんでした。対象区間と動画ファイルを確認してください。"; UIAlertController *a = [UIAlertController alertControllerWithTitle:@"生成失敗" message:message preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [weakSelf presentViewController:a animated:YES completion:nil]; return; } StrobePreviewViewController *preview = [[StrobePreviewViewController alloc] initWithImageURL:outputURL completion:^(BOOL saved) { if (!saved) [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil]; for (UIView *v in weakSelf.view.subviews) v.userInteractionEnabled = YES; weakSelf.spinner.hidden = YES; weakSelf.statusLabel.text = @""; if (weakSelf.completion) weakSelf.completion(saved ? outputURL : nil); [weakSelf dismissViewControllerAnimated:YES completion:nil]; }]; [weakSelf presentViewController:preview animated:YES completion:nil]; }]; }
- (void)cancel:(id)sender { if (self.completion) self.completion(nil); [self dismissViewControllerAnimated:YES completion:nil]; }
@end

@interface StrobePreviewViewController ()
@property (nonatomic, strong) NSURL *imageURL;
@property (nonatomic, copy) void (^completion)(BOOL);
@end
@implementation StrobePreviewViewController
- (instancetype)initWithImageURL:(NSURL *)url completion:(void (^)(BOOL))completion { if ((self=[super init])) { _imageURL=url; _completion=[completion copy]; self.modalPresentationStyle=UIModalPresentationFullScreen; } return self; }
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor=UIColor.blackColor; UIImageView *imageView=[[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:self.imageURL.path]]; imageView.translatesAutoresizingMaskIntoConstraints=NO; imageView.contentMode=UIViewContentModeScaleAspectFit; [self.view addSubview:imageView]; UIButton *save=[UIButton buttonWithType:UIButtonTypeSystem]; [save setTitle:@"保存" forState:UIControlStateNormal]; save.tintColor=UIColor.whiteColor; save.backgroundColor=[UIColor colorWithWhite:0 alpha:.55]; save.translatesAutoresizingMaskIntoConstraints=NO; [save addTarget:self action:@selector(save:) forControlEvents:UIControlEventTouchUpInside]; UIButton *cancel=[UIButton buttonWithType:UIButtonTypeSystem]; [cancel setTitle:@"キャンセル" forState:UIControlStateNormal]; cancel.tintColor=UIColor.whiteColor; cancel.translatesAutoresizingMaskIntoConstraints=NO; [cancel addTarget:self action:@selector(cancel:) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:save]; [self.view addSubview:cancel]; [NSLayoutConstraint activateConstraints:@[[imageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[imageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[imageView.topAnchor constraintEqualToAnchor:self.view.topAnchor],[imageView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],[save.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],[save.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],[save.widthAnchor constraintEqualToConstant:100],[save.heightAnchor constraintEqualToConstant:44],[cancel.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],[cancel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],[cancel.widthAnchor constraintEqualToConstant:100],[cancel.heightAnchor constraintEqualToConstant:44]]]; }
- (void)save:(id)sender { if (self.completion) self.completion(YES); }
- (void)cancel:(id)sender { if (self.completion) self.completion(NO); }
@end
