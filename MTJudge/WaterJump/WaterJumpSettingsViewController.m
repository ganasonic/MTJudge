#import "../MTJLocalization.h"
#import "WaterJumpSettingsViewController.h"
#import "../TagSelectionViewController.h"

static NSArray<NSURL *> *WJVideoAndRelatedJSONFiles(NSURL *videoURL) {
    if (!videoURL) return @[];
    NSMutableArray<NSURL *> *targets = [NSMutableArray arrayWithObject:videoURL];
    NSURL *directory = [videoURL URLByDeletingLastPathComponent];
    NSString *prefix = [videoURL.lastPathComponent stringByAppendingString:@"."];
    NSArray<NSURL *> *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:nil];
    for (NSURL *entry in entries) {
        NSString *name = entry.lastPathComponent.lowercaseString;
        if ([entry.lastPathComponent hasPrefix:prefix] && [name hasSuffix:@".json"]) [targets addObject:entry];
    }
    return targets;
}
#import "WaterJumpCoordinator.h"
#import "MTJudge-Swift.h"
#import "WaterJumpReceivedPlayerViewController.h"
#import "WaterJumpComparisonViewController.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreImage/CoreImage.h>
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>

@interface WJVideoLibrary : UITableViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) NSArray<NSURL *> *videos;
@property (nonatomic, strong) NSURL *selectedMainURL;
@property (nonatomic, strong) NSURL *selectedSubURL;
@property (nonatomic, assign) BOOL gridMode;
@property (nonatomic, assign) BOOL comparisonSelectionMode;
@property (nonatomic, assign) BOOL restoredComparisonPosition;
@property (nonatomic, strong) NSURL *comparisonMainURL;
@property (nonatomic, copy) void (^comparisonSelectionHandler)(NSURL *url);
@property (nonatomic, strong) UIPanGestureRecognizer *multiSelectPanGesture;
@property (nonatomic, strong) NSMutableSet<NSIndexPath *> *dragSelectedIndexPaths;
@property (nonatomic, strong) NSTimer *multiSelectAutoScrollTimer;
@property (nonatomic, assign) CGPoint multiSelectLastPoint;
@end
static UIImage *WJQRCodeImage(NSString *value) {
    if (!value.length) return nil;
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setValue:[value dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *output = filter.outputImage;
    if (!output) return nil;
    CGFloat scale = 8.0;
    CIImage *scaled = [output imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    return [UIImage imageWithCIImage:scaled scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
}

@interface WJQRScannerViewController : UIViewController <AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, copy) NSString *initialValue;
@property (nonatomic, copy) NSString *screenTitle;
@property (nonatomic, copy) void (^completion)(NSString *value);
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureMetadataOutput *metadataOutput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, weak) UIView *previewContainer;
@property (nonatomic, weak) UILabel *hintLabel;
@property (nonatomic, strong) UITextField *valueField;
@property (nonatomic, assign) BOOL completed;
@property (nonatomic, assign) BOOL processingFrame;
@end

@implementation WJQRScannerViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = self.screenTitle ?: MTJText(@"QRコード読み取り");

    UIView *preview = [UIView new];
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    preview.backgroundColor = UIColor.blackColor;
    preview.clipsToBounds = YES;
    self.previewContainer = preview;
    [self.view addSubview:preview];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [preview.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        [preview.topAnchor constraintEqualToAnchor:guide.topAnchor constant:24],
        [preview.widthAnchor constraintLessThanOrEqualToConstant:300],
        [preview.widthAnchor constraintEqualToAnchor:guide.widthAnchor multiplier:.82],
        [preview.heightAnchor constraintEqualToAnchor:preview.widthAnchor]
    ]];

    UIView *target = [UIView new];
    target.translatesAutoresizingMaskIntoConstraints = NO;
    target.userInteractionEnabled = NO;
    target.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:.65].CGColor;
    target.layer.borderWidth = 1.0;
    [preview addSubview:target];
    [NSLayoutConstraint activateConstraints:@[
        [target.centerXAnchor constraintEqualToAnchor:preview.centerXAnchor],
        [target.centerYAnchor constraintEqualToAnchor:preview.centerYAnchor],
        [target.widthAnchor constraintEqualToAnchor:preview.widthAnchor multiplier:.75],
        [target.heightAnchor constraintEqualToAnchor:preview.heightAnchor multiplier:.75]
    ]];

    UILabel *hint = [UILabel new];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.text = MTJText(@"枠内にQRコードを合わせてください");
    hint.textAlignment = NSTextAlignmentCenter;
    hint.textColor = UIColor.secondaryLabelColor;
    hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.hintLabel = hint;
    [self.view addSubview:hint];

    self.valueField = [UITextField new];
    self.valueField.translatesAutoresizingMaskIntoConstraints = NO;
    self.valueField.borderStyle = UITextBorderStyleRoundedRect;
    self.valueField.placeholder = MTJText(@"読み取れない場合は入力");
    self.valueField.text = self.initialValue;
    self.valueField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.valueField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.view addSubview:self.valueField];

    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    save.translatesAutoresizingMaskIntoConstraints = NO;
    [save setTitle:MTJText(@"保存") forState:UIControlStateNormal];
    [save addTarget:self action:@selector(saveValue) forControlEvents:UIControlEventTouchUpInside];
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    [cancel setTitle:MTJText(@"キャンセル") forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(cancelScan) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:save]; [self.view addSubview:cancel];
    [NSLayoutConstraint activateConstraints:@[
        [hint.topAnchor constraintEqualToAnchor:preview.bottomAnchor constant:8],
        [hint.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16],
        [hint.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [self.valueField.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:14],
        [self.valueField.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:20],
        [self.valueField.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-20],
        [save.topAnchor constraintEqualToAnchor:self.valueField.bottomAnchor constant:12],
        [save.trailingAnchor constraintEqualToAnchor:guide.centerXAnchor constant:-8],
        [cancel.topAnchor constraintEqualToAnchor:self.valueField.bottomAnchor constant:12],
        [cancel.leadingAnchor constraintEqualToAnchor:guide.centerXAnchor constant:8]
    ]];

    [self configureCaptureIfAuthorized];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusNotDetermined) {
        __weak typeof(self) weakSelf = self;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (granted) [weakSelf configureCaptureIfAuthorized]; else weakSelf.hintLabel.text = MTJText(@"カメラの使用を許可してください。許可しない場合は下の欄へ入力してください"); });
        }];
    } else {
        [self configureCaptureIfAuthorized];
    }
}
- (void)configureCaptureIfAuthorized {
    if (self.captureSession) return;
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status != AVAuthorizationStatusAuthorized) {
        if (status == AVAuthorizationStatusDenied || status == AVAuthorizationStatusRestricted) self.hintLabel.text = MTJText(@"カメラの使用を許可できないため、下の欄へ入力してください");
        return;
    }
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;
    AVCaptureDeviceInput *input = device ? [AVCaptureDeviceInput deviceInputWithDevice:device error:&error] : nil;
    AVCaptureSession *session = [AVCaptureSession new];
    if (input && [session canAddInput:input]) [session addInput:input]; else { self.hintLabel.text = MTJText(@"カメラを使用できないため、下の欄へ入力してください"); return; }
    AVCaptureMetadataOutput *output = [AVCaptureMetadataOutput new];
    if (![session canAddOutput:output]) { self.hintLabel.text = MTJText(@"QR読み取りを開始できません。下の欄へ入力してください"); return; }
    [session addOutput:output];
    AVCaptureVideoDataOutput *videoOutput = [AVCaptureVideoDataOutput new];
    videoOutput.alwaysDiscardsLateVideoFrames = YES;
    videoOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
    if ([session canAddOutput:videoOutput]) {
        [session addOutput:videoOutput];
        [videoOutput setSampleBufferDelegate:self queue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)];
        self.videoOutput = videoOutput;
    }
    if ([session canSetSessionPreset:AVCaptureSessionPresetHigh]) session.sessionPreset = AVCaptureSessionPresetHigh;
    self.captureSession = session;
    self.metadataOutput = output;
    [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];
    output.rectOfInterest = CGRectMake(0, 0, 1, 1);
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:session];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer.frame = self.previewContainer.bounds;
    [self.previewContainer.layer insertSublayer:self.previewLayer atIndex:0];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [session startRunning]; });
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; self.previewLayer.frame = self.previewLayer.superlayer.bounds; }
- (void)metadataOutput:(AVCaptureMetadataOutput *)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataMachineReadableCodeObject *> *)objects fromConnection:(AVCaptureConnection *)connection {
    if (self.completed) return;
    for (AVMetadataMachineReadableCodeObject *object in objects) {
        NSString *value = object.stringValue;
        if (value.length) { [self finishWithValue:value]; break; }
    }
}
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (self.completed || self.processingFrame || !sampleBuffer) return;
    self.processingFrame = YES;
    CVImageBufferRef buffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!buffer) { self.processingFrame = NO; return; }
    VNDetectBarcodesRequest *request = [[VNDetectBarcodesRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *error) {
        NSString *found = nil;
        for (VNBarcodeObservation *observation in request.results) {
            if ([observation.symbology isEqualToString:VNBarcodeSymbologyQR] && observation.payloadStringValue.length) { found = observation.payloadStringValue; break; }
        }
        self.processingFrame = NO;
        if (found.length) dispatch_async(dispatch_get_main_queue(), ^{ [self finishWithValue:found]; });
    }];
    request.symbologies = @[VNBarcodeSymbologyQR];
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:buffer orientation:kCGImagePropertyOrientationUp options:@{}];
    [handler performRequests:@[request] error:nil];
}
- (void)saveValue { [self finishWithValue:[self.valueField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]]; }
- (void)finishWithValue:(NSString *)value {
    if (self.completed) return;
    self.completed = YES;
    self.valueField.text = value ?: @"";
    [self.captureSession stopRunning];
    void (^completion)(NSString *) = [self.completion copy];
    NSString *result = [value copy] ?: @"";
    [self dismissViewControllerAnimated:YES completion:^{
        if (completion) completion(result);
    }];
}
- (void)cancelScan {
    self.completed = YES;
    [self.captureSession stopRunning];
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

@implementation WJVideoLibrary
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = MTJText(@"練習動画");
    self.gridMode = [[NSUserDefaults standardUserDefaults] boolForKey:@"WJVideoGridMode"];
    self.navigationItem.leftBarButtonItem = self.comparisonSelectionMode ? nil : [[UIBarButtonItem alloc] initWithTitle:MTJText(@"選択") style:UIBarButtonItemStylePlain target:self action:@selector(beginMultiSelect)];
    UIBarButtonItem *photo = [[UIBarButtonItem alloc] initWithTitle:MTJText(@"写真") style:UIBarButtonItemStylePlain target:self action:@selector(selectPhotoVideo)];
    UIBarButtonItem *grid = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:self.gridMode ? @"list.bullet" : @"square.grid.2x2"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleGridMode)];
    grid.accessibilityLabel = MTJText(@"リスト表示とサムネイル表示を切り替え");
    self.navigationItem.rightBarButtonItems = self.comparisonSelectionMode ? @[grid] : @[photo, grid];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(selectComparisonVideo:)];
    longPress.minimumPressDuration = .55;
    longPress.cancelsTouchesInView = YES;
    if (!self.comparisonSelectionMode) [self.tableView addGestureRecognizer:longPress];
    self.dragSelectedIndexPaths = [NSMutableSet set];
    self.multiSelectPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(multiSelectPan:)];
    self.multiSelectPanGesture.cancelsTouchesInView = NO;
    self.multiSelectPanGesture.maximumNumberOfTouches = 1;
    self.multiSelectPanGesture.enabled = NO;
    [self.tableView addGestureRecognizer:self.multiSelectPanGesture];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshVideos) name:@"WJVideoDeleted" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshVideos) name:@"WJVideoSaved" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshVideos) name:@"WJVideoFavoritesChanged" object:nil];
    [self refreshVideos];
}
- (void)beginMultiSelect {
    self.editing = YES;
    self.multiSelectPanGesture.enabled = YES;
    [self.dragSelectedIndexPaths removeAllObjects];
    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:MTJText(@"キャンセル") style:UIBarButtonItemStylePlain target:self action:@selector(endMultiSelect)];
    UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareSelectedVideos)];
    UIBarButtonItem *transfer = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.doc"] style:UIBarButtonItemStylePlain target:self action:@selector(transferSelectedVideos)];
    transfer.accessibilityLabel = MTJText(@"選択した動画と関連JSONをMTJudgeへ転送");
    UIBarButtonItem *delete = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(deleteSelectedVideos)];
    delete.tintColor = UIColor.systemRedColor;
    self.navigationItem.rightBarButtonItems = @[delete, transfer, share];
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    // 行左端の赤い削除記号は使わず、選択状態はチェックマークで示す。
    return UITableViewCellEditingStyleNone;
}
- (void)endMultiSelect {
    self.editing = NO;
    self.multiSelectPanGesture.enabled = NO;
    [self.multiSelectAutoScrollTimer invalidate];
    self.multiSelectAutoScrollTimer = nil;
    [self.dragSelectedIndexPaths removeAllObjects];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:MTJText(@"選択") style:UIBarButtonItemStylePlain target:self action:@selector(beginMultiSelect)];
    UIBarButtonItem *photo = [[UIBarButtonItem alloc] initWithTitle:MTJText(@"写真") style:UIBarButtonItemStylePlain target:self action:@selector(selectPhotoVideo)];
    UIBarButtonItem *grid = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:self.gridMode ? @"list.bullet" : @"square.grid.2x2"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleGridMode)];
    grid.accessibilityLabel = MTJText(@"リスト表示とサムネイル表示を切り替え");
    self.navigationItem.rightBarButtonItems = self.comparisonSelectionMode ? @[grid] : @[photo, grid];
}
- (void)multiSelectAutoScrollTick:(NSTimer *)timer {
    if (!self.editing) return;
    CGFloat edge = 72.0;
    CGFloat y = self.multiSelectLastPoint.y;
    CGFloat delta = 0;
    if (y < edge) delta = -10.0 * (1.0 - MAX(0, y) / edge);
    else if (y > self.tableView.bounds.size.height - edge) delta = 10.0 * (1.0 - MAX(0, self.tableView.bounds.size.height - y) / edge);
    if (fabs(delta) < 0.5) return;
    CGPoint offset = self.tableView.contentOffset;
    CGFloat minY = -self.tableView.adjustedContentInset.top;
    CGFloat maxY = MAX(minY, self.tableView.contentSize.height - self.tableView.bounds.size.height + self.tableView.adjustedContentInset.bottom);
    offset.y = MIN(maxY, MAX(minY, offset.y + delta));
    [self.tableView setContentOffset:offset animated:NO];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:self.multiSelectLastPoint];
    if (indexPath && indexPath.section == 0 && indexPath.row < self.videos.count && ![self.dragSelectedIndexPaths containsObject:indexPath]) {
        [self.dragSelectedIndexPaths addObject:indexPath];
        [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
        [self.tableView cellForRowAtIndexPath:indexPath].accessoryType = UITableViewCellAccessoryCheckmark;
    }
}
- (void)updateMultiSelectAutoScroll {
    CGFloat edge = 72.0;
    BOOL nearEdge = self.multiSelectLastPoint.y < edge || self.multiSelectLastPoint.y > self.tableView.bounds.size.height - edge;
    if (nearEdge && !self.multiSelectAutoScrollTimer) {
        self.multiSelectAutoScrollTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(multiSelectAutoScrollTick:) userInfo:nil repeats:YES];
    } else if (!nearEdge) {
        [self.multiSelectAutoScrollTimer invalidate];
        self.multiSelectAutoScrollTimer = nil;
    }
}
- (void)multiSelectPan:(UIPanGestureRecognizer *)gesture {
    if (!self.editing || self.comparisonSelectionMode) return;
    UIGestureRecognizerState state = gesture.state;
    self.multiSelectLastPoint = [gesture locationInView:self.tableView];
    if (state == UIGestureRecognizerStateBegan) [self.dragSelectedIndexPaths removeAllObjects];
    if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled || state == UIGestureRecognizerStateFailed) {
        [self.multiSelectAutoScrollTimer invalidate];
        self.multiSelectAutoScrollTimer = nil;
        return;
    }
    if (state != UIGestureRecognizerStateBegan && state != UIGestureRecognizerStateChanged) return;
    [self updateMultiSelectAutoScroll];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:self.multiSelectLastPoint];
    if (!indexPath || indexPath.section != 0 || indexPath.row >= self.videos.count || [self.dragSelectedIndexPaths containsObject:indexPath]) return;
    [self.dragSelectedIndexPaths addObject:indexPath];
    [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryCheckmark;
}
- (NSArray<NSURL *> *)selectedVideoURLs {
    NSMutableArray *urls = [NSMutableArray array];
    for (NSIndexPath *indexPath in self.tableView.indexPathsForSelectedRows ?: @[]) {
        if (indexPath.row < self.videos.count) [urls addObject:self.videos[indexPath.row]];
    }
    return urls;
}
- (void)shareSelectedVideos {
    NSArray<NSURL *> *urls = [self selectedVideoURLs];
    if (!urls.count) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
    if (activity.popoverPresentationController) { activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject; }
    [self presentViewController:activity animated:YES completion:nil];
}
- (void)transferSelectedVideos {
    NSArray<NSURL *> *urls = [self selectedVideoURLs];
    if (!urls.count) return;
    for (NSURL *url in urls) [[WaterJumpCoordinator shared] retransferVideoURL:url];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTJText(@"転送を開始しました") message:MTJText(@"選択した動画と、同じ動画名に紐づくJSONを登録済みのMTJudge端末へ転送します。受信側のRecordingsへ保存されます。") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)deleteSelectedVideos {
    NSArray<NSURL *> *urls = [self selectedVideoURLs];
    if (!urls.count) return;
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSURL *url in urls) for (NSURL *target in WJVideoAndRelatedJSONFiles(url)) [files removeItemAtURL:target error:nil];
    [self endMultiSelect];
    [self refreshVideos];
}
- (void)dealloc { [self.multiSelectAutoScrollTimer invalidate]; [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refreshVideos]; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.comparisonSelectionMode || self.restoredComparisonPosition || !self.videos.count) return;
    self.restoredComparisonPosition = YES;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *identity = [defaults stringForKey:@"WJComparisonLastSelectedVideo"];
    if (!identity.length) return;
    NSUInteger row = [self.videos indexOfObjectPassingTest:^BOOL(NSURL *url, NSUInteger index, BOOL *stop) {
        return [[ReceivedVideoManager videoIdentity:url] isEqualToString:identity];
    }];
    if (row == NSNotFound) row = MIN(MAX(0, [defaults integerForKey:@"WJComparisonLastSelectedRow"]), self.videos.count - 1);
    [self.tableView layoutIfNeeded];
    [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
}
- (void)refreshVideos { if (@available(iOS 13.0, *)) { self.videos = [ReceivedVideoManager videos]; [self.tableView reloadData]; } }
- (void)toggleGridMode {
    NSIndexPath *anchor = self.tableView.indexPathsForVisibleRows.firstObject;
    self.gridMode = !self.gridMode;
    [[NSUserDefaults standardUserDefaults] setBool:self.gridMode forKey:@"WJVideoGridMode"];
    UIBarButtonItem *photo = [[UIBarButtonItem alloc] initWithTitle:MTJText(@"写真") style:UIBarButtonItemStylePlain target:self action:@selector(selectPhotoVideo)];
    UIBarButtonItem *grid = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:self.gridMode ? @"list.bullet" : @"square.grid.2x2"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleGridMode)];
    grid.accessibilityLabel = MTJText(@"リスト表示とサムネイル表示を切り替え");
    self.navigationItem.rightBarButtonItems = self.comparisonSelectionMode ? @[grid] : @[photo, grid];
    [self.tableView reloadData];
    [self.tableView layoutIfNeeded];
    if (anchor && anchor.row < self.videos.count) [self.tableView scrollToRowAtIndexPath:anchor atScrollPosition:UITableViewScrollPositionTop animated:NO];
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.gridMode ? 220.0 : UITableViewAutomaticDimension;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.videos.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSURL *url = self.videos[indexPath.row];
    NSDictionary *info = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[url URLByAppendingPathExtension:@"wj.json"]] ?: [NSData data] options:0 error:nil];
    AVAsset *asset = [AVAsset assetWithURL:url];
    NSDictionary *fileValues = [url resourceValuesForKeys:@[NSURLCreationDateKey, NSURLFileSizeKey] error:nil];
    double duration = [info[@"duration"] doubleValue]; if (duration <= 0) duration = CMTimeGetSeconds(asset.duration);
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[info[@"created"] doubleValue]]; if ([info[@"created"] doubleValue] <= 0) date = fileValues[NSURLCreationDateKey] ?: [NSDate date];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    NSNumber *size = info[@"size"] ?: fileValues[NSURLFileSizeKey];
    NSString *width = info[@"width"] ?: [NSString stringWithFormat:@"%.0f", fabs(track.naturalSize.width)];
    NSString *height = info[@"height"] ?: [NSString stringWithFormat:@"%.0f", fabs(track.naturalSize.height)];
    NSString *fps = info[@"fps"] ?: [NSString stringWithFormat:@"%.1f", track.nominalFrameRate];
    NSString *prefix = [url isEqual:self.selectedMainURL] ? @"MAIN  " : ([url isEqual:self.selectedSubURL] ? @"SUB  " : @"");
    cell.textLabel.text = [prefix stringByAppendingString:[NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle]];
    cell.detailTextLabel.text = [NSString stringWithFormat:MTJText(@"%.0f秒・%.1f MB・%@ × %@・%@ fps・%@"), duration, size.doubleValue/1048576, width, height, fps, info[@"codec"] ?: @"?"];
    cell.detailTextLabel.numberOfLines = 0;
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:[AVAsset assetWithURL:url]];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = self.gridMode ? CGSizeMake(420, 240) : CGSizeMake(160, 100);
    CGImageRef imageRef = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
    if (imageRef) {
        cell.imageView.image = [UIImage imageWithCGImage:imageRef];
        if (self.gridMode) cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
        CGImageRelease(imageRef);
    }
    UIButton *retransferButton = [UIButton buttonWithType:UIButtonTypeSystem];
    retransferButton.tag = indexPath.row;
    retransferButton.accessibilityIdentifier = url.path;
    retransferButton.accessibilityLabel = MTJText(@"この動画を再転送");
    retransferButton.tintColor = UIColor.systemBlueColor;
    [retransferButton setImage:[UIImage systemImageNamed:@"arrow.clockwise.icloud"] forState:UIControlStateNormal];
    [retransferButton addTarget:self action:@selector(retransferVideo:) forControlEvents:UIControlEventTouchUpInside];
    retransferButton.frame = CGRectMake(0, 0, 40, 44);
    UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    deleteButton.tag = indexPath.row;
    deleteButton.accessibilityIdentifier = url.path;
    deleteButton.accessibilityLabel = MTJText(@"動画を削除");
    deleteButton.tintColor = UIColor.systemRedColor;
    [deleteButton setImage:[UIImage systemImageNamed:@"trash"] forState:UIControlStateNormal];
    [deleteButton addTarget:self action:@selector(deleteVideo:) forControlEvents:UIControlEventTouchUpInside];
    deleteButton.frame = CGRectMake(0, 0, 40, 44);
    UIButton *shareButton = [UIButton buttonWithType:UIButtonTypeSystem];
    shareButton.accessibilityIdentifier = url.path;
    shareButton.accessibilityLabel = MTJText(@"動画を共有");
    shareButton.tintColor = UIColor.systemGreenColor;
    [shareButton setImage:[UIImage systemImageNamed:@"square.and.arrow.up"] forState:UIControlStateNormal];
    [shareButton addTarget:self action:@selector(shareVideo:) forControlEvents:UIControlEventTouchUpInside];
    shareButton.frame = CGRectMake(0, 0, 40, 44);
    UIButton *favoriteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    favoriteButton.accessibilityIdentifier = url.path;
    favoriteButton.accessibilityLabel = MTJText(@"お気に入り");
    BOOL favorite = [ReceivedVideoManager isFavoriteVideo:url];
    favoriteButton.tintColor = favorite ? UIColor.systemPinkColor : UIColor.secondaryLabelColor;
    [favoriteButton setImage:[UIImage systemImageNamed:(favorite ? @"heart.fill" : @"heart")] forState:UIControlStateNormal];
    [favoriteButton addTarget:self action:@selector(toggleFavoriteInList:) forControlEvents:UIControlEventTouchUpInside];
    favoriteButton.frame = CGRectMake(0, 0, 40, 44);
    if (self.comparisonSelectionMode) {
        cell.accessoryView = favoriteButton;
    } else {
        UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[retransferButton, shareButton, favoriteButton, deleteButton]];
        actions.axis = UILayoutConstraintAxisHorizontal; actions.spacing = 2; actions.frame = CGRectMake(0, 0, 168, 44);
        cell.accessoryView = actions;
    }
    if (self.editing) {
        BOOL selected = [self.tableView.indexPathsForSelectedRows containsObject:indexPath];
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}
- (void)selectComparisonVideo:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath || indexPath.row >= self.videos.count) return;
    NSURL *url = self.videos[indexPath.row];
    if ([url isEqual:self.selectedMainURL]) return;
    if (!self.selectedMainURL) {
        self.selectedMainURL = url;
        [self.tableView reloadData];
        return;
    }
    // 1本目はMAINとして保持し、2本目以降の長押しは常にSUBを更新する。
    self.selectedSubURL = url;
    [self.tableView reloadData];
    WaterJumpComparisonViewController *comparison = [[WaterJumpComparisonViewController alloc] initWithMainURL:self.selectedMainURL subURL:self.selectedSubURL];
    [self presentViewController:comparison animated:YES completion:^{ [comparison startPlayback]; }];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.comparisonSelectionMode) {
        NSURL *url = self.videos[indexPath.row];
        if ([url.path isEqualToString:self.comparisonMainURL.path]) { [tableView deselectRowAtIndexPath:indexPath animated:NO]; return; }
        [[NSUserDefaults standardUserDefaults] setObject:[ReceivedVideoManager videoIdentity:url] forKey:@"WJComparisonLastSelectedVideo"];
        [[NSUserDefaults standardUserDefaults] setInteger:indexPath.row forKey:@"WJComparisonLastSelectedRow"];
        void (^handler)(NSURL *) = self.comparisonSelectionHandler;
        [self.navigationController dismissViewControllerAnimated:YES completion:^{ if (handler) handler(url); }];
        return;
    }
    // 複数選択モードでは行タップは選択／解除だけにし、動画を再生しない。
    if (self.editing) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
        return;
    }
    WaterJumpReceivedPlayerViewController *player = [[WaterJumpReceivedPlayerViewController alloc] initWithVideoURL:self.videos[indexPath.row]];
    [player setPlaylist:self.videos currentIndex:indexPath.row];
    [self presentViewController:player animated:YES completion:^{ [player.player play]; }];
}
- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.editing) return;
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryNone;
}
- (void)deleteVideo:(UIButton *)sender {
    NSURL *url = sender.accessibilityIdentifier.length ? [NSURL fileURLWithPath:sender.accessibilityIdentifier] : nil;
    NSInteger row = [self.videos indexOfObject:url];
    if (!url || row == NSNotFound || ![url.pathExtension.lowercaseString isEqualToString:@"mov"]) return;
    NSError *error = nil;
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSURL *target in WJVideoAndRelatedJSONFiles(url)) {
        if (![files fileExistsAtPath:target.path]) continue;
        NSError *removeError = nil;
        if (![files removeItemAtURL:target error:&removeError]) { error = removeError; break; }
    }
    if (error) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTJText(@"削除できません") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSMutableArray *updated = [self.videos mutableCopy]; [updated removeObjectAtIndex:row]; self.videos = updated;
    [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]] withRowAnimation:UITableViewRowAnimationAutomatic];
}
- (void)retransferVideo:(UIButton *)sender {
    NSURL *url = sender.accessibilityIdentifier.length ? [NSURL fileURLWithPath:sender.accessibilityIdentifier] : nil;
    if (!url || ![url.pathExtension.lowercaseString isEqualToString:@"mov"] || ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) return;
    [[WaterJumpCoordinator shared] retransferVideoURL:url];
    sender.enabled = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ sender.enabled = YES; });
}
- (void)shareVideo:(UIButton *)sender {
    NSURL *url = sender.accessibilityIdentifier.length ? [NSURL fileURLWithPath:sender.accessibilityIdentifier] : nil;
    if (!url || ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    if (activity.popoverPresentationController) {
        activity.popoverPresentationController.sourceView = sender;
        activity.popoverPresentationController.sourceRect = sender.bounds;
    }
    [self presentViewController:activity animated:YES completion:nil];
}
- (void)toggleFavoriteInList:(UIButton *)sender {
    NSString *path = sender.accessibilityIdentifier;
    if (!path.length) return;
    NSURL *url = [NSURL fileURLWithPath:path];
    [ReceivedVideoManager setFavoriteVideo:url favorite:![ReceivedVideoManager isFavoriteVideo:url]];
    [self.tableView reloadData];
}
- (void)selectPhotoVideo {
    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[UTTypeMovie.identifier];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    NSURL *url = info[UIImagePickerControllerMediaURL];
    if (!url) { [picker dismissViewControllerAnimated:YES completion:nil]; return; }
    picker.view.userInteractionEnabled = NO;
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.center = picker.view.center;
    spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [picker.view addSubview:spinner]; [spinner startAnimating];
    [ReceivedVideoManager importPhotoVideo:url completion:^(NSURL *saved, NSError *error) {
        [spinner removeFromSuperview];
        picker.view.userInteractionEnabled = YES;
        [picker dismissViewControllerAnimated:YES completion:^{
            if (!saved) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTJText(@"動画を読み込めませんでした") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
            [self refreshVideos];
            WaterJumpReceivedPlayerViewController *player = [[WaterJumpReceivedPlayerViewController alloc] initWithVideoURL:saved];
            [player setPlaylist:@[saved] currentIndex:0];
            [self presentViewController:player animated:YES completion:^{ [player.player play]; }];
        }];
    }];
}
@end

static NSString *WJRoleTitle(NSString *role) {
    NSDictionary *titles = @{@"MAIN":@"メイン端末（受信端末を兼ねる）", @"CAMERA_1":@"カメラ1", @"CAMERA_2":@"カメラ2", @"CAMERA_3":@"カメラ3", @"RECEIVER":@"受信端末（メイン以外）"};
    return MTJText(titles[role ?: @""] ?: @"未設定");
}
@interface WJSetupMenu : UITableViewController
@property(nonatomic) BOOL easy;
@end
@implementation WJSetupMenu
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = MTJText(self.easy ? @"簡単設定" : @"リモート操作モード");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 64;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:WJStatusChanged object:nil];
    if (self.easy) [[WaterJumpCoordinator shared].group beginSearch];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)refresh { [self.tableView reloadData]; }
- (void)showMessage:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:MTJText(@"カメラグループ") message:MTJText(message) preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.easy ? 3 : 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (!self.easy) return 2;
    CameraGroupManager *g = [WaterJumpCoordinator shared].group;
    return section == 0 ? 5 : (section == 1 ? g.groups.count : g.members.count);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (!self.easy) return nil;
    return MTJText(@[@"グループと役割", @"検索中・同じWi-Fiのグループ", @"接続端末一覧（メインは選択して登録解除）"][section]);
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (!self.easy || section != 0) return nil;
    return MTJText(@"メイン＋カメラ1〜3の最大4台。受信はメイン＋追加3台の最大4台です。同じWi-Fiでアプリを前景にし、ローカルネットワークを許可してください。撮影端末は接続後にカメラ画面を開いてください。");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.textLabel.numberOfLines = 0; c.detailTextLabel.numberOfLines = 0;
    CameraGroupManager *g = [WaterJumpCoordinator shared].group;
    if (!self.easy) {
        c.textLabel.text = MTJText(path.row == 0 ? @"簡単設定" : @"詳細設定");
        c.detailTextLabel.text = MTJText(path.row == 0 ? @"グループと役割だけで接続を設定します" : (g.automatic ? @"自動設定の内容を確認・従来方式へ切替" : @"URL・QRコードによる従来の接続設定"));
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (path.section == 0) {
        c.textLabel.text = MTJText(@[@"カメラグループを作成",@"この端末の役割",@"この端末のカメラ名",@"接続状態",@"設定をリセット"][path.row]);
        if (path.row == 0) {
            NSString *groupName = [NSUserDefaults.standardUserDefaults stringForKey:@"WJCameraGroupName"];
            c.detailTextLabel.text = g.groupID.length && groupName.length ? groupName : MTJText(@"この端末をメインにして新しいグループを作成");
        }
        if (path.row == 1) c.detailTextLabel.text = WJRoleTitle(g.role);
        if (path.row == 2) c.detailTextLabel.text = [NSUserDefaults.standardUserDefaults stringForKey:@"WJCameraName"] ?: UIDevice.currentDevice.name;
        if (path.row == 3) c.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@\n%@",[NSUserDefaults.standardUserDefaults stringForKey:@"WJCameraGroupName"] ?: @"",g.groupID,MTJText(g.message)];
        if (path.row == 4) c.textLabel.textColor = UIColor.systemRedColor;
    } else if (path.section == 1) {
        NSDictionary *group = g.groups[path.row]; c.textLabel.text = group[@"name"]; c.detailTextLabel.text = group[@"group"]; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        NSDictionary *member = g.members[path.row]; c.textLabel.text = member[@"name"];
        c.detailTextLabel.text = [NSString stringWithFormat:@"%@・%@\n%@", WJRoleTitle(member[@"role"]),MTJText([member[@"connected"] isEqual:@"1"] ? @"認証済み" : @"未接続"),member[@"id"]];
    }
    return c;
}
- (void)selectRoleForGroup:(NSString *)groupID {
    CameraGroupManager *g = [WaterJumpCoordinator shared].group;
    if (!groupID.length || ([g.role isEqual:@"MAIN"] && [groupID isEqual:g.groupID])) { [self showMessage:@"メインはグループ作成時に設定されます。他の役割は検索したグループを選択して設定してください。"]; return; }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:MTJText(@"この端末の役割") message:MTJText(@"既存の通信設定を置き換えます。動画・タグは保持します。初回はメイン端末で参加を承認してください。") preferredStyle:UIAlertControllerStyleAlert];
    for (NSString *role in @[@"CAMERA_1",@"CAMERA_2",@"CAMERA_3",@"RECEIVER"]) {
        [a addAction:[UIAlertAction actionWithTitle:WJRoleTitle(role) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { if (![g joinGroup:groupID role:role]) [self showMessage:g.message]; }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    CameraGroupManager *g = [WaterJumpCoordinator shared].group;
    if (!self.easy) {
        if (path.row == 0) { WJSetupMenu *vc = [WJSetupMenu new]; vc.easy = YES; [self.navigationController pushViewController:vc animated:YES]; }
        else [self.navigationController pushViewController:[WaterJumpSettingsViewController new] animated:YES];
        return;
    }
    if (path.section == 1) { [self selectRoleForGroup:g.groups[path.row][@"group"]]; return; }
    if (path.section == 2) {
        if (![g.role isEqual:@"MAIN"]) return;
        NSDictionary *member = g.members[path.row];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:MTJText(@"端末の登録を解除") message:[NSString stringWithFormat:@"%@\n%@",member[@"name"],MTJText(@"この端末との接続が解除され、役割番号が空きます。動画は削除しません。再参加には承認が必要です。") ] preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:MTJText(@"解除") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { if (![g removeMember:member[@"id"]]) [self showMessage:@"録画・転送・受信の終了後に変更してください"]; }]]; [self presentViewController:a animated:YES completion:nil]; return;
    }
    if (path.row == 0) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:MTJText(@"カメラグループを作成") message:MTJText(@"既存の通信設定を置き換え、この端末をメインにします。旧グループの端末は再設定が必要です。動画・タグは保持します。") preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *f){
            f.placeholder = MTJText(@"例：Aグループ");
            f.text = [NSUserDefaults.standardUserDefaults stringForKey:@"WJCameraGroupName"] ?: @"";
        }];
        [a addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:MTJText(@"作成") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ if (![g createGroup:a.textFields.firstObject.text]) [self showMessage:g.message]; }]]; [self presentViewController:a animated:YES completion:nil];
    } else if (path.row == 1) [self selectRoleForGroup:g.groupID];
    else if (path.row == 2) [WaterJumpSettingsViewController presentCameraNameFrom:self];
    else if (path.row == 4) {
        NSString *message = [g.role isEqual:@"MAIN"] ? @"管理端末の接続設定をリセットすると、グループの他端末は接続できなくなります。録画済み・未転送動画、タグ、描画データは削除しません。続けますか？" : @"通信設定と参加情報をリセットします。録画済み・未転送動画、タグ、描画データは削除しません。続けますか？";
        UIAlertController *a = [UIAlertController alertControllerWithTitle:MTJText(@"設定をリセット") message:MTJText(message) preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:MTJText(@"リセット") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { if (![g reset]) [self showMessage:g.message]; }]]; [self presentViewController:a animated:YES completion:nil];
    }
}
@end

@implementation WaterJumpSettingsViewController
+ (UIViewController *)remoteSetupViewController { return [WJSetupMenu new]; }
+ (void)presentCameraNameFrom:(UIViewController *)host {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:MTJText(@"この端末のカメラ名") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = [NSUserDefaults.standardUserDefaults stringForKey:@"WJCameraName"]; f.placeholder = UIDevice.currentDevice.name; }];
    [a addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:MTJText(@"保存") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length > 100) name = [name substringToIndex:100];
        [NSUserDefaults.standardUserDefaults setObject:name.length ? name : UIDevice.currentDevice.name forKey:@"WJCameraName"];
        [[WaterJumpCoordinator shared] applySettings];
    }]]; [host presentViewController:a animated:YES completion:nil];
}
+ (void)presentDurationFrom:(UIViewController *)host {
    if ([WaterJumpCoordinator shared].recordingBusy) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:MTJText(@"録画時間") message:nil preferredStyle:UIAlertControllerStyleAlert];
    for (NSNumber *seconds in @[@0,@10,@15,@20,@30,@45,@60]) {
        NSString *title = seconds.integerValue ? [NSString stringWithFormat:MTJText(@"%@秒"),seconds] : MTJText(@"ー（手動停止）");
        [a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [NSUserDefaults.standardUserDefaults setObject:seconds forKey:@"WJDuration"]; [[WaterJumpCoordinator shared] applySettings]; }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]]; [host presentViewController:a animated:YES completion:nil];
}
+ (void)presentDefaultTagsFrom:(UIViewController *)host {
    TagSelectionViewController *selection = [[TagSelectionViewController alloc] initWithVideoFileURL:nil]; selection.selections = @[];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:selection]; nav.modalPresentationStyle = UIModalPresentationFormSheet;
    __weak UINavigationController *weakNav = nav;
    selection.saveHandler = ^(NSArray *tags) { [weakNav dismissViewControllerAnimated:YES completion:nil]; };
    [host presentViewController:nav animated:YES completion:nil];
}
- (void)requestManualMode {
    CameraGroupManager *g = [WaterJumpCoordinator shared].group;
    if (!g.automatic) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:MTJText(@"従来方式へ切替") message:MTJText(@"グループの自動接続を解除し、通信設定を初期化します。URL・QRで接続先を再登録してください。動画・タグは保持します。") preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:MTJText(@"切り替える") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (![g useManual]) { UIAlertController *busy = [UIAlertController alertControllerWithTitle:MTJText(@"処理中") message:MTJText(@"録画・転送・受信の終了後に変更してください") preferredStyle:UIAlertControllerStyleAlert]; [busy addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:busy animated:YES completion:nil]; }
        [self refresh];
    }]]; [self presentViewController:a animated:YES completion:nil];
}
+ (UIViewController *)videoLibraryViewController { return [WJVideoLibrary new]; }
+ (UIViewController *)videoLibraryViewControllerForComparisonWithMainURL:(NSURL *)mainURL selection:(void (^)(NSURL *url))selection {
    WJVideoLibrary *library = [WJVideoLibrary new];
    library.comparisonSelectionMode = YES;
    library.comparisonMainURL = mainURL;
    library.comparisonSelectionHandler = selection;
    return library;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = MTJText(@"詳細設定");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem.accessibilityIdentifier = @"WJDone";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:WJStatusChanged object:nil];
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 60;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    if (controller.popoverPresentationController && !controller.popoverPresentationController.sourceView && !controller.popoverPresentationController.barButtonItem) {
        controller.popoverPresentationController.sourceView = self.view;
        controller.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);
    }
    [super presentViewController:controller animated:animated completion:completion];
}
- (void)refresh {
    self.navigationItem.rightBarButtonItem = [WaterJumpCoordinator shared].group.automatic ? [[UIBarButtonItem alloc] initWithTitle:MTJText(@"従来方式へ切替") style:UIBarButtonItemStylePlain target:self action:@selector(requestManualMode)] : [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    [self.tableView reloadData];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }
// Rows refer to the original action IDs, independent of their visible position.
- (NSArray<NSIndexPath *> *)recordingSettingRows {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSNumber *number in @[@0, @1, @2, @4, @6, @5, @7, @8, @10, @9, @12, @14]) {
        NSInteger row = number.integerValue;
        [rows addObject:[NSIndexPath indexPathForRow:row inSection:0]];
        if (row == 1 && [defaults boolForKey:@"WJWeb"]) [rows addObject:[NSIndexPath indexPathForRow:1 inSection:1]];
        if (row == 6 && [defaults boolForKey:@"WJTransfer"]) {
            [rows addObject:[NSIndexPath indexPathForRow:3 inSection:1]];
            [rows addObject:[NSIndexPath indexPathForRow:4 inSection:1]];
        }
        if (row == 5 && [defaults boolForKey:@"WJReceive"]) [rows addObject:[NSIndexPath indexPathForRow:2 inSection:1]];
        if (row == 9 && ([defaults boolForKey:@"WJUseSubCamera"] || [WaterJumpCoordinator shared].group.automatic)) [rows addObject:[NSIndexPath indexPathForRow:5 inSection:1]];
        if (row == 12 && ([defaults boolForKey:@"WJUseSubCamera2"] || [WaterJumpCoordinator shared].group.automatic)) [rows addObject:[NSIndexPath indexPathForRow:6 inSection:1]];
        if (row == 14 && ([defaults boolForKey:@"WJUseSubCamera3"] || [WaterJumpCoordinator shared].group.automatic)) [rows addObject:[NSIndexPath indexPathForRow:9 inSection:1]];
    }
    return rows;
}
- (NSIndexPath *)settingIdentifierForIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return [self recordingSettingRows][indexPath.row];
    if (indexPath.section == 1) return [NSIndexPath indexPathForRow:[@[@0, @7, @8][indexPath.row] integerValue] inSection:1];
    return indexPath;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return [self recordingSettingRows].count;
    if (section == 1) return 3;
    if (section == 2) return 0;
    return [WaterJumpCoordinator shared].discoveredPeers.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[MTJText(@"録画・受信設定"), MTJText(@"接続情報"), @"", MTJText(@"検出したカメラグループ／受信端末（選択して参加）")][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return MTJText(@"録画・受信した動画はMTJudge/Recordingsへ保存されます。撮影と受信は別の端末でも使用できます。");
    if (section == 1) return MTJText(@"同じWi-Fiで両端末を前景起動してください。接続URL・登録コードは操作を許可する相手だけに渡してください。URLはリモート録画の再起動で変わります。");
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    indexPath = [self settingIdentifierForIndexPath:indexPath];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    WaterJumpCoordinator *manager = [WaterJumpCoordinator shared];
    if (indexPath.section == 0) {
        NSArray *names = @[MTJText(@"リモート操作モード"), MTJText(@"リモート録画"), MTJText(@"Apple Watch録画"), MTJText(@"録画時間"), MTJText(@"録画後自動転送"), MTJText(@"この端末で受信待機"), MTJText(@"タグ付け後に転送"), MTJText(@"受信後自動再生"), MTJText(@"転送先でループ再生する"), MTJText(@"リモートカメラ1を使う"), MTJText(@"ループ再生設定"), MTJText(@"この端末のカメラ名"), MTJText(@"リモートカメラ2を使う"), MTJText(@"事前タグ選択"), MTJText(@"リモートカメラ3を使う")];
        cell.textLabel.text = names[indexPath.row];
        if (indexPath.row == 1) cell.detailTextLabel.text = MTJText(@"スマホから録画操作またはリモートカメラとして撮影する場合");
        if (indexPath.row == 2) cell.detailTextLabel.text = MTJText(@"Apple Watchから録画開始・停止操作する場合");
        if (indexPath.row == 13) { cell.detailTextLabel.text = MTJText(@"録画前に選手名などの既定タグを選択"); cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
        else if (indexPath.row == 3) { cell.accessibilityIdentifier = @"WJDuration"; NSInteger duration = [[NSUserDefaults standardUserDefaults] integerForKey:@"WJDuration"]; cell.detailTextLabel.text = duration > 0 ? [NSString stringWithFormat:MTJText(@"%ld秒"), (long)duration] : MTJText(@"ー（手動停止）"); cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
        else if (indexPath.row == 10) {
            NSInteger count = [[NSUserDefaults standardUserDefaults] integerForKey:@"WJLoopCount"]; if (count == 0) count = 3;
            NSInteger seconds = [[NSUserDefaults standardUserDefaults] integerForKey:@"WJLoopDuration"];
            NSString *countText = count < 0 ? MTJText(@"無限") : [NSString stringWithFormat:MTJText(@"%ld回"), (long)count];
            NSString *timeText = count < 0 ? (seconds > 0 ? [NSString stringWithFormat:MTJText(@"%ld分"), (long)(seconds / 60)] : MTJText(@"時間制限なし")) : @"";
            cell.detailTextLabel.text = timeText.length ? [NSString stringWithFormat:MTJText(@"%@・%@"), countText, timeText] : countText;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 11) {
            NSString *name = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJCameraName"];
            cell.detailTextLabel.text = name.length ? name : UIDevice.currentDevice.name;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            NSArray *keys = @[@"WJMode",@"WJWeb",@"WJWatch",@"WJDuration",@"WJTransfer",@"WJReceive",@"WJTagBeforeTransfer",@"WJAutoPlayAfterTransfer",@"WJLoopPlayback",@"WJUseSubCamera",@"WJLoopPlayback",@"WJCameraName",@"WJUseSubCamera2",@"WJDefaultTags",@"WJUseSubCamera3"];
            if (indexPath.row == 12 || indexPath.row == 14) {
                UISwitch *toggle = [UISwitch new]; toggle.tag = indexPath.row; toggle.accessibilityIdentifier = keys[indexPath.row];
                toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:keys[indexPath.row]];
                toggle.enabled = !manager.recordingBusy && !manager.group.automatic;
                [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
                return cell;
            }
            UISwitch *toggle = [UISwitch new]; toggle.tag = indexPath.row;
            toggle.accessibilityIdentifier = keys[indexPath.row];
            toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:keys[indexPath.row]];
            BOOL transferOrReceive = [[NSUserDefaults standardUserDefaults] boolForKey:@"WJTransfer"] || [[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"];
            toggle.enabled = indexPath.row == 6 ? [[NSUserDefaults standardUserDefaults] boolForKey:@"WJTransfer"] : (!manager.recordingBusy && (indexPath.row != 7 || transferOrReceive) && (indexPath.row != 8 || [[NSUserDefaults standardUserDefaults] boolForKey:@"WJAutoPlayAfterTransfer"]));
            if (manager.group.automatic && ![@[@2,@7,@8] containsObject:@(indexPath.row)]) toggle.enabled = NO;
            if (!manager.group.automatic && (indexPath.row == 6 || indexPath.row == 8) && !toggle.enabled) toggle.on = NO;
            [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        }
    } else if (indexPath.section == 1) {
        NSArray *titles = @[MTJText(@"状態"), MTJText(@"リモート操作用URL"), MTJText(@"この端末の登録コード"), MTJText(@"転送先"), MTJText(@"転送先URL登録"), MTJText(@"リモートカメラ1登録"), MTJText(@"リモートカメラ2登録"), MTJText(@"カメラグループ"), MTJText(@"同じWi-Fiのカメラグループを探す"), MTJText(@"リモートカメラ3登録")];
        cell.textLabel.text = titles[indexPath.row];
        if (indexPath.row == 0) cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@", MTJText(manager.status[@"state"]), MTJText(manager.status[@"message"])];
        if (indexPath.row == 1) cell.detailTextLabel.text = [NSString stringWithFormat:MTJText(@"録画操作する端末側で読み取らせるURLです\n%@"), manager.remoteAddress.length ? manager.remoteAddress : MTJText(@"URLを準備中…")];
        if (indexPath.row == 2) cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"] ? manager.pairingCode : MTJText(@"受信端末で受信待機をONにしてください");
        if (indexPath.row == 3) {
            NSArray *registered = manager.registeredPeers;
            if (registered.count) {
                NSMutableArray *labels = [NSMutableArray array];
                for (NSDictionary *peer in registered) [labels addObject:[NSString stringWithFormat:@"%@%@", peer[@"name"] ?: MTJText(@"端末"), [peer[@"id"] isEqual:([[NSUserDefaults standardUserDefaults] stringForKey:@"WJPeerID"] ?: @"")] ? MTJText(@"（選択中）") : @""]];
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@",[labels componentsJoinedByString:@"\n"],[NSUserDefaults.standardUserDefaults stringForKey:@"WJTransferEndpoint"] ?: @""];
            } else cell.detailTextLabel.text = manager.peerDescription;
        }
        if (indexPath.row == 5) cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJSubCameraURL"] ?: MTJText(@"未登録（リモートカメラ1のリモート操作用URLを入力）");
        if (indexPath.row == 6) {
            cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJSubCamera2URL"] ?: MTJText(@"未登録");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        if (indexPath.row == 9) cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJSubCamera3URL"] ?: MTJText(@"未登録");
        if (indexPath.row == 7) {
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            NSString *name = [defaults stringForKey:@"WJCameraGroupName"];
            NSString *groupID = [defaults stringForKey:@"WJCameraGroupID"];
            cell.detailTextLabel.text = name.length && groupID.length ? [NSString stringWithFormat:@"%@\n%@", name, groupID] : MTJText(@"未設定（タップして作成）");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        if (indexPath.row == 8) {
            NSArray *peers = manager.discoveredPeers;
            NSMutableArray *groups = [NSMutableArray array];
            for (NSDictionary *peer in peers) {
                NSString *label = peer[@"groupName"] ?: peer[@"groupID"];
                if (label.length && ![groups containsObject:label]) [groups addObject:label];
            }
            cell.detailTextLabel.text = groups.count ? [groups componentsJoinedByString:@"、"] : MTJText(@"検出中…（同じWi-Fi・受信待機を確認）");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        if (indexPath.row == 1 || indexPath.row == 2 || indexPath.row == 4 || indexPath.row == 5 || indexPath.row == 6 || indexPath.row == 9) {
            UIButton *qr = [UIButton buttonWithType:UIButtonTypeSystem];
            [qr setImage:[UIImage systemImageNamed:@"qrcode"] forState:UIControlStateNormal];
            qr.tintColor = UIColor.secondaryLabelColor; qr.frame = CGRectMake(0, 0, 36, 36); qr.accessibilityLabel = MTJText(@"QRコードを読み取る"); qr.tag = indexPath.row;
            [qr addTarget:self action:@selector(scanQRButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            qr.enabled = !manager.group.automatic || indexPath.row == 1 || indexPath.row == 2;
            cell.accessoryView = qr;
        }
    } else if (indexPath.section == 2) {
        cell.textLabel.text = MTJText(@"転送を再送"); cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        NSDictionary *peer = manager.discoveredPeers[indexPath.row];
        NSString *group = peer[@"groupName"] ?: peer[@"groupID"];
        cell.textLabel.text = group.length ? [NSString stringWithFormat:@"%@（%@）", group, peer[@"name"] ?: MTJText(@"端末")] : (peer[@"name"] ?: MTJText(@"端末"));
        cell.detailTextLabel.text = group.length ? [NSString stringWithFormat:@"%@\n%@", peer[@"role"] ?: MTJText(@"受信端末"), peer[@"id"] ?: @""] : peer[@"id"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)toggle:(UISwitch *)sender {
    if ([WaterJumpCoordinator shared].group.automatic && ![@[@2,@7,@8] containsObject:@(sender.tag)]) { [self requestManualMode]; return; }
    NSArray *keys = @[@"WJMode",@"WJWeb",@"WJWatch",@"WJDuration",@"WJTransfer",@"WJReceive",@"WJTagBeforeTransfer",@"WJAutoPlayAfterTransfer",@"WJLoopPlayback",@"WJUseSubCamera",@"WJLoopPlayback",@"WJCameraName",@"WJUseSubCamera2",@"WJDefaultTags",@"WJUseSubCamera3"];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:sender.on forKey:keys[sender.tag]];
    if (sender.tag == 6 && sender.on && ![defaults boolForKey:@"WJTransfer"]) [defaults setBool:NO forKey:@"WJTagBeforeTransfer"];
    if (sender.tag == 7 && !sender.on) [defaults setBool:NO forKey:@"WJLoopPlayback"];
    if (sender.on && sender.tag == 5) { [defaults setBool:NO forKey:@"WJMode"]; [defaults setBool:NO forKey:@"WJTransfer"]; }
    if (sender.on && (sender.tag == 0 || sender.tag == 4)) [defaults setBool:NO forKey:@"WJReceive"];
    if (![defaults boolForKey:@"WJTransfer"]) [defaults setBool:NO forKey:@"WJTagBeforeTransfer"];
    [[WaterJumpCoordinator shared] applySettings]; [self refresh];
}
- (void)showQRCodeForValue:(NSString *)value title:(NSString *)title {
    UIImage *image = WJQRCodeImage(value);
    if (!image) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:MTJText(@"別端末のカメラで読み取ってください。") preferredStyle:UIAlertControllerStyleAlert];
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    [alert.view addSubview:imageView];
    // UIAlertControllerのアクション領域と重ならないよう、画像を独立した領域に配置する。
    [NSLayoutConstraint activateConstraints:@[
        [imageView.centerXAnchor constraintEqualToAnchor:alert.view.centerXAnchor],
        [imageView.topAnchor constraintEqualToAnchor:alert.view.topAnchor constant:112],
        [imageView.widthAnchor constraintEqualToConstant:260],
        [imageView.heightAnchor constraintEqualToConstant:260],
        [alert.view.heightAnchor constraintGreaterThanOrEqualToConstant:430]
    ]];
    [alert addAction:[UIAlertAction actionWithTitle:MTJText(@"閉じる") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)presentPeerScanner:(NSDictionary *)peer {
    WaterJumpCoordinator *manager = [WaterJumpCoordinator shared];
    WJQRScannerViewController *scanner = [WJQRScannerViewController new];
    scanner.screenTitle = MTJText(@"転送先URL登録");
    scanner.completion = ^(NSString *code) {
        BOOL matches = !peer || [code hasPrefix:[peer[@"id"] stringByAppendingString:@":"]];
        if (!matches || ![manager registerPeer:peer[@"name"] ?: @"登録済みiPad" code:code]) {
            UIAlertController *error = [UIAlertController alertControllerWithTitle:MTJText(@"登録できません") message:MTJText(@"選択した端末の登録コードを確認してください。") preferredStyle:UIAlertControllerStyleAlert];
            [error addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:error animated:YES completion:nil];
        } else {
            // QR登録が成功したら、検出情報にGroup IDが欠けていても必ず役割を選択させる。
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            NSString *groupID = peer[@"groupID"];
            NSString *groupName = peer[@"groupName"] ?: peer[@"name"];
            if (groupID.length) [defaults setObject:groupID forKey:@"WJCameraGroupID"];
            if (groupName.length) [defaults setObject:groupName forKey:@"WJCameraGroupName"];
            UIAlertController *role = [UIAlertController alertControllerWithTitle:MTJText(@"カメラ役割") message:MTJText(@"この端末の役割を選択してください。") preferredStyle:UIAlertControllerStyleActionSheet];
            for (NSDictionary *choice in @[@{@"title":@"カメラ1", @"role":@"MAIN_CAMERA"}, @{@"title":@"カメラ2", @"role":@"SUB_CAMERA"}, @{@"title":@"カメラ3", @"role":@"SUB_CAMERA"}]) {
                [role addAction:[UIAlertAction actionWithTitle:MTJText(choice[@"title"]) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [defaults setObject:choice[@"role"] forKey:@"WJCameraRole"];
                    [[WaterJumpCoordinator shared] applySettings];
                    [self refresh];
                }]];
            }
            [role addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:role animated:YES completion:nil];
        }
    };
    scanner.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:scanner animated:YES completion:nil];
}
- (void)presentSubCameraScanner {
    [self presentSubCameraScannerForKey:@"WJSubCameraURL" title:MTJText(@"リモートカメラ1登録")];
}
- (void)presentSubCameraScannerForKey:(NSString *)defaultsKey title:(NSString *)title {
    WJQRScannerViewController *scanner = [WJQRScannerViewController new];
    scanner.screenTitle = title;
    scanner.initialValue = [[NSUserDefaults standardUserDefaults] stringForKey:defaultsKey];
    scanner.completion = ^(NSString *value) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        if (value.length) [defaults setObject:value forKey:defaultsKey];
        else [defaults removeObjectForKey:defaultsKey];
        [self refresh];
    };
    scanner.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:scanner animated:YES completion:nil];
}
- (void)presentDefaultTagSelection {
    TagSelectionViewController *selection = [[TagSelectionViewController alloc] initWithVideoFileURL:nil];
    selection.selections = @[];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:selection];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    __weak UINavigationController *weakNavigation = navigation;
    __weak typeof(self) weakSelf = self;
    selection.saveHandler = ^(NSArray<NSDictionary<NSString *,NSString *> *> *tags) {
        __strong typeof(weakSelf) self = weakSelf;
        [weakNavigation dismissViewControllerAnimated:YES completion:^{ [self refresh]; }];
    };
    UIViewController *presenter = self.presentingViewController;
    [self dismissViewControllerAnimated:YES completion:^{
        UIViewController *host = presenter ?: self;
        [host presentViewController:navigation animated:YES completion:nil];
    }];
}
- (void)scanQRButtonTapped:(UIButton *)sender {
    WaterJumpCoordinator *manager = [WaterJumpCoordinator shared];
    if (manager.group.automatic && sender.tag != 1 && sender.tag != 2) { [self requestManualMode]; return; }
    if (sender.tag == 9) { [self presentSubCameraScannerForKey:@"WJSubCamera3URL" title:MTJText(@"リモートカメラ3登録")]; return; }
    if (sender.tag == 1 && manager.remoteAddress.length) { UIPasteboard.generalPasteboard.string = manager.remoteAddress; [self showQRCodeForValue:manager.remoteAddress title:MTJText(@"リモート操作用URL")]; }
    else if (sender.tag == 2 && [[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"]) { UIPasteboard.generalPasteboard.string = manager.pairingCode; [self showQRCodeForValue:manager.pairingCode title:MTJText(@"この端末の登録コード")]; }
    else if (sender.tag == 4) [self presentPeerScanner:nil];
    else if (sender.tag == 5) [self presentSubCameraScanner];
    else if (sender.tag == 6) [self presentSubCameraScannerForKey:@"WJSubCamera2URL" title:MTJText(@"リモートカメラ2登録")];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    indexPath = [self settingIdentifierForIndexPath:indexPath];
    WaterJumpCoordinator *manager = [WaterJumpCoordinator shared];
    if (manager.group.automatic && !(indexPath.section == 1 && indexPath.row <= 3) && !(indexPath.section == 0 && indexPath.row == 10)) { [self requestManualMode]; return; }
    if (indexPath.section == 1 && indexPath.row == 9) { [self presentSubCameraScannerForKey:@"WJSubCamera3URL" title:MTJText(@"リモートカメラ3登録")]; return; }
    if (indexPath.section == 0 && indexPath.row == 13) {
        [self presentDefaultTagSelection];
        return;
    }
    if (indexPath.section == 0 && indexPath.row == 3 && !manager.recordingBusy) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTJText(@"録画時間") message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:MTJText(@"ー（手動停止）") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[NSUserDefaults standardUserDefaults] setDouble:0 forKey:@"WJDuration"]; [manager applySettings]; [self refresh];
        }]];
        for (NSNumber *seconds in @[@10,@15,@20,@30,@45,@60]) [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:MTJText(@"%@秒"),seconds] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[NSUserDefaults standardUserDefaults] setObject:seconds forKey:@"WJDuration"]; [manager applySettings];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
    }
    if (indexPath.section == 0 && indexPath.row == 10 && !manager.recordingBusy) {
        UIAlertController *countAlert = [UIAlertController alertControllerWithTitle:MTJText(@"ループ再生回数") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSNumber *count in @[@3, @5, @10]) {
            [countAlert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:MTJText(@"%@回"), count] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [[NSUserDefaults standardUserDefaults] setInteger:count.integerValue forKey:@"WJLoopCount"]; [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"WJLoopDuration"]; [self refresh]; }]];
        }
        [countAlert addAction:[UIAlertAction actionWithTitle:MTJText(@"無限") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UIAlertController *timeAlert = [UIAlertController alertControllerWithTitle:MTJText(@"無限ループの時間制限") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            for (NSNumber *seconds in @[@0, @60, @180, @300, @600]) {
                NSString *title = seconds.integerValue == 0 ? MTJText(@"時間制限なし") : [NSString stringWithFormat:MTJText(@"%ld分"), (long)(seconds.integerValue / 60)];
                [timeAlert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [[NSUserDefaults standardUserDefaults] setInteger:-1 forKey:@"WJLoopCount"]; [[NSUserDefaults standardUserDefaults] setInteger:seconds.integerValue forKey:@"WJLoopDuration"]; [self refresh]; }]];
            }
            [timeAlert addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:timeAlert animated:YES completion:nil];
        }]];
        [countAlert addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:countAlert animated:YES completion:nil];
    }
    if (indexPath.section == 0 && indexPath.row == 11) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTJText(@"この端末のカメラ名") message:MTJText(@"動画情報と端末間転送のメタデータに使用します。") preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = UIDevice.currentDevice.name;
            field.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJCameraName"];
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:MTJText(@"保存") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (name.length) [[NSUserDefaults standardUserDefaults] setObject:name forKey:@"WJCameraName"];
            else [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"WJCameraName"];
            [self refresh];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    if (indexPath.section == 1 && indexPath.row == 7) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTJText(@"カメラグループ") message:MTJText(@"同じグループIDの端末だけが録画・転送対象になります。空欄でグループ設定を解除します。") preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = MTJText(@"例：Aグループ");
            field.text = [defaults stringForKey:@"WJCameraGroupName"];
        }];
        [alert addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:MTJText(@"保存") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!name.length) {
                [defaults removeObjectForKey:@"WJCameraGroupName"];
                [defaults removeObjectForKey:@"WJCameraGroupID"];
            } else {
                [defaults setObject:name forKey:@"WJCameraGroupName"];
                if (![defaults stringForKey:@"WJCameraGroupID"].length) [defaults setObject:NSUUID.UUID.UUIDString forKey:@"WJCameraGroupID"];
            }
            [[WaterJumpCoordinator shared] applySettings];
            [self refresh];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    if (indexPath.section == 1 && indexPath.row == 8) {
        NSArray *peers = manager.discoveredPeers;
        UIAlertController *groups = [UIAlertController alertControllerWithTitle:MTJText(@"カメラグループを選択") message:MTJText(@"同じWi-Fi上で検出されたグループです。選択すると登録コードの読み取りへ進みます。") preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSDictionary *peer in peers) {
            NSString *group = peer[@"groupName"] ?: peer[@"groupID"];
            if (!group.length) continue;
            NSString *title = [NSString stringWithFormat:@"%@（%@）", group, peer[@"name"] ?: MTJText(@"端末")];
            [groups addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self presentPeerScanner:peer]; }]];
        }
        if (!groups.actions.count) [groups addAction:[UIAlertAction actionWithTitle:MTJText(@"検出されていません") style:UIAlertActionStyleDefault handler:nil]];
        [groups addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:groups animated:YES completion:nil];
    }
    if (indexPath.section == 1 && indexPath.row == 1 && manager.remoteAddress.length) { UIPasteboard.generalPasteboard.string = manager.remoteAddress; [self showQRCodeForValue:manager.remoteAddress title:MTJText(@"リモート操作用URL")]; }
    if (indexPath.section == 1 && indexPath.row == 2 && [[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"]) { UIPasteboard.generalPasteboard.string = manager.pairingCode; [self showQRCodeForValue:manager.pairingCode title:MTJText(@"この端末の登録コード")]; }
    if (indexPath.section == 2 && indexPath.row == 0) [manager retryTransfer];
    if ((indexPath.section == 1 && indexPath.row == 4) || indexPath.section == 3) {
        NSDictionary *peer = indexPath.section == 3 ? manager.discoveredPeers[indexPath.row] : nil;
        [self presentPeerScanner:peer];
    }
    if (indexPath.section == 1 && indexPath.row == 5) {
        [self presentSubCameraScanner];
    }
    if (indexPath.section == 1 && indexPath.row == 6) {
        [self presentSubCameraScannerForKey:@"WJSubCamera2URL" title:MTJText(@"リモートカメラ2登録")];
    }
}
@end
