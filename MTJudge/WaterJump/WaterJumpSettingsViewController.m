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

// Keep portrait thumbnails from determining the height of an entire list row.
@interface WJLibraryListCell : UITableViewCell
@end
@implementation WJLibraryListCell
- (void)layoutSubviews {
    [super layoutSubviews];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.clipsToBounds = YES;
    self.imageView.frame = CGRectMake(12, 10, 56, 80);
    CGFloat right = self.accessoryView ? CGRectGetMinX(self.accessoryView.frame) - 8 : self.contentView.bounds.size.width - 12;
    CGFloat width = MAX(40, right - 80);
    self.textLabel.font = [UIFont systemFontOfSize:14];
    self.textLabel.numberOfLines = 2;
    self.textLabel.frame = CGRectMake(80, 8, width, 36);
    self.detailTextLabel.font = [UIFont systemFontOfSize:12];
    self.detailTextLabel.frame = CGRectMake(80, 45, width, 50);
}
@end

@interface WJVideoLibrary : UIViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITableViewDataSource, UITableViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UICollectionView *gridView;
@property(nonatomic, strong) UICollectionView *recentView;
@property(nonatomic, strong) NSArray<NSURL *> *recentVideos;
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *thumbnailCache;
@property(nonatomic, copy) void (^playbackSelectionHandler)(NSURL *url);
@property (nonatomic, strong) NSArray<NSURL *> *videos;
@property (nonatomic, strong) NSURL *selectedMainURL;
@property (nonatomic, strong) NSURL *selectedSubURL;
@property (nonatomic, assign) BOOL gridMode;
@property (nonatomic, assign) BOOL comparisonSelectionMode;
@property (nonatomic, assign) BOOL restoredComparisonPosition;
@property (nonatomic, strong) NSURL *comparisonMainURL;
@property (nonatomic, copy) void (^comparisonSelectionHandler)(NSURL *url);
@property (nonatomic, strong) UIPanGestureRecognizer *multiSelectPanGesture;
@property (nonatomic, strong) UIPanGestureRecognizer *gridSelectPanGesture;
@property (nonatomic, weak) UIScrollView *selectionScrollView;
@property (nonatomic) BOOL dragDeselects;
@property (nonatomic) CGPoint selectionStartPoint;
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
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.thumbnailCache = [NSCache new]; self.thumbnailCache.countLimit = 100;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self; self.tableView.dataSource = self; self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new]; layout.minimumInteritemSpacing = 10; layout.minimumLineSpacing = 12; layout.sectionInset = UIEdgeInsetsMake(12,12,12,12);
    self.gridView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout]; self.gridView.translatesAutoresizingMaskIntoConstraints = NO;
    self.gridView.backgroundColor = UIColor.systemBackgroundColor; self.gridView.dataSource = self; self.gridView.delegate = self;
    [self.gridView registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"video"]; [self.view addSubview:self.gridView];
    UICollectionViewFlowLayout *recentLayout = [UICollectionViewFlowLayout new]; recentLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal; recentLayout.minimumLineSpacing = 10; recentLayout.sectionInset = UIEdgeInsetsMake(4,12,4,12);
    self.recentView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:recentLayout]; self.recentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.recentView.backgroundColor = UIColor.secondarySystemBackgroundColor; self.recentView.dataSource = self; self.recentView.delegate = self;
    [self.recentView registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"video"]; [self.view addSubview:self.recentView];
    UILabel *recentLabel = [UILabel new]; recentLabel.text = MTJText(@"直近の再生履歴（最大10件）"); recentLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; recentLabel.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:recentLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.recentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.recentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.recentView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor], [self.recentView.heightAnchor constraintEqualToConstant:138],
        [recentLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12], [recentLabel.bottomAnchor constraintEqualToAnchor:self.recentView.topAnchor constant:-4],
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor], [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.tableView.bottomAnchor constraintEqualToAnchor:recentLabel.topAnchor constant:-8],
        [self.gridView.topAnchor constraintEqualToAnchor:self.tableView.topAnchor], [self.gridView.leadingAnchor constraintEqualToAnchor:self.tableView.leadingAnchor], [self.gridView.trailingAnchor constraintEqualToAnchor:self.tableView.trailingAnchor], [self.gridView.bottomAnchor constraintEqualToAnchor:self.tableView.bottomAnchor]
    ]];
    self.title = MTJText(@"練習動画");
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"WJThumbnailLibraryV2Enabled"]) {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"WJVideoGridMode"];
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"WJThumbnailLibraryV2Enabled"];
    }
    self.gridMode = [NSUserDefaults.standardUserDefaults objectForKey:@"WJVideoGridMode"] ? [NSUserDefaults.standardUserDefaults boolForKey:@"WJVideoGridMode"] : YES;
    self.gridView.hidden = !self.gridMode; self.tableView.hidden = self.gridMode;
    self.navigationItem.leftBarButtonItem = self.comparisonSelectionMode ? nil : [[UIBarButtonItem alloc] initWithTitle:MTJText(@"選択") style:UIBarButtonItemStylePlain target:self action:@selector(beginMultiSelect)];
    UIBarButtonItem *photo = [[UIBarButtonItem alloc] initWithTitle:MTJText(@"写真") style:UIBarButtonItemStylePlain target:self action:@selector(selectPhotoVideo)];
    UIBarButtonItem *grid = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:self.gridMode ? @"list.bullet" : @"square.grid.2x2"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleGridMode)];
    grid.accessibilityLabel = MTJText(@"リスト表示とサムネイル表示を切り替え");
    self.navigationItem.rightBarButtonItems = self.comparisonSelectionMode ? @[grid] : @[photo, grid];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(selectComparisonVideo:)];
    longPress.minimumPressDuration = .55;
    longPress.cancelsTouchesInView = YES;
    if (!self.comparisonSelectionMode) {
        [self.tableView addGestureRecognizer:longPress];
        UILongPressGestureRecognizer *gridPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(selectComparisonGrid:)]; gridPress.minimumPressDuration = .55; [self.gridView addGestureRecognizer:gridPress];
    }
    self.dragSelectedIndexPaths = [NSMutableSet set];
    self.multiSelectPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(multiSelectPan:)];
    self.multiSelectPanGesture.cancelsTouchesInView = YES;
    self.multiSelectPanGesture.maximumNumberOfTouches = 1;
    self.multiSelectPanGesture.enabled = NO;
    [self.tableView addGestureRecognizer:self.multiSelectPanGesture];
    self.multiSelectPanGesture.delegate = self;
    [self.tableView.panGestureRecognizer requireGestureRecognizerToFail:self.multiSelectPanGesture];
    self.gridSelectPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(multiSelectPan:)];
    self.gridSelectPanGesture.maximumNumberOfTouches = 1;
    self.gridSelectPanGesture.delegate = self;
    self.gridSelectPanGesture.enabled = NO;
    [self.gridView addGestureRecognizer:self.gridSelectPanGesture];
    [self.gridView.panGestureRecognizer requireGestureRecognizerToFail:self.gridSelectPanGesture];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshVideos) name:@"WJVideoDeleted" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshVideos) name:@"WJVideoSaved" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshVideos) name:@"WJVideoFavoritesChanged" object:nil];
    [self refreshVideos];
}
- (void)beginMultiSelect {
    self.editing = YES;
    self.multiSelectPanGesture.enabled = YES; self.gridSelectPanGesture.enabled = YES;
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
    self.multiSelectPanGesture.enabled = NO; self.gridSelectPanGesture.enabled = NO;
    [self.multiSelectAutoScrollTimer invalidate];
    self.multiSelectAutoScrollTimer = nil;
    [self.dragSelectedIndexPaths removeAllObjects];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:MTJText(@"選択") style:UIBarButtonItemStylePlain target:self action:@selector(beginMultiSelect)];
    UIBarButtonItem *photo = [[UIBarButtonItem alloc] initWithTitle:MTJText(@"写真") style:UIBarButtonItemStylePlain target:self action:@selector(selectPhotoVideo)];
    UIBarButtonItem *grid = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:self.gridMode ? @"list.bullet" : @"square.grid.2x2"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleGridMode)];
    grid.accessibilityLabel = MTJText(@"リスト表示とサムネイル表示を切り替え");
    self.navigationItem.rightBarButtonItems = self.comparisonSelectionMode ? @[grid] : @[photo, grid];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (gesture == self.multiSelectPanGesture || gesture == self.gridSelectPanGesture) self.selectionStartPoint = [touch locationInView:gesture.view];
    return YES;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gesture != self.multiSelectPanGesture && gesture != self.gridSelectPanGesture) return YES;
    if (!self.editing || self.comparisonSelectionMode) return NO;
    CGPoint point = self.selectionStartPoint;
    return gesture.view == self.gridView ? [self.gridView indexPathForItemAtPoint:point] != nil : [self.tableView indexPathForRowAtPoint:point] != nil;
}
- (void)selectDragPoint:(CGPoint)point {
    NSIndexPath *path = self.selectionScrollView == self.gridView ? [self.gridView indexPathForItemAtPoint:point] : [self.tableView indexPathForRowAtPoint:point];
    if (!path || path.row >= self.videos.count || [self.dragSelectedIndexPaths containsObject:path]) return;
    [self.dragSelectedIndexPaths addObject:path];
    if (self.dragDeselects) [self.tableView deselectRowAtIndexPath:path animated:NO];
    else [self.tableView selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
    [self.tableView cellForRowAtIndexPath:path].accessoryType = self.dragDeselects ? UITableViewCellAccessoryNone : UITableViewCellAccessoryCheckmark;
    if (self.selectionScrollView == self.gridView) [self.gridView reloadItemsAtIndexPaths:@[path]];
}
- (void)multiSelectAutoScrollTick:(NSTimer *)timer {
    if (!self.editing) return;
    UIScrollView *scroll = self.selectionScrollView;
    // Compare viewport coordinates, then convert back to content coordinates after scrolling.
    CGFloat edge = MIN(72, scroll.bounds.size.height / 3), y = self.multiSelectLastPoint.y;
    CGFloat delta = y < edge ? -10 * (1 - MAX(0,y) / edge) : (y > scroll.bounds.size.height - edge ? 10 * (1 - MAX(0,scroll.bounds.size.height-y) / edge) : 0);
    if (fabs(delta) < .5) return;
    CGFloat minY = -scroll.adjustedContentInset.top;
    CGFloat maxY = MAX(minY, scroll.contentSize.height - scroll.bounds.size.height + scroll.adjustedContentInset.bottom);
    CGPoint offset = scroll.contentOffset; offset.y = MIN(maxY, MAX(minY, offset.y + delta));
    [scroll setContentOffset:offset animated:NO];
    [self selectDragPoint:CGPointMake(self.multiSelectLastPoint.x + scroll.bounds.origin.x, self.multiSelectLastPoint.y + scroll.bounds.origin.y)];
}
- (void)multiSelectPan:(UIPanGestureRecognizer *)gesture {
    if (!self.editing || self.comparisonSelectionMode) return;
    UIScrollView *scroll = (UIScrollView *)gesture.view;
    CGPoint point = [gesture locationInView:scroll];
    CGPoint viewport = CGPointMake(point.x - scroll.bounds.origin.x, point.y - scroll.bounds.origin.y);
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.selectionScrollView = scroll;
        [self.dragSelectedIndexPaths removeAllObjects];
        // Recognition may begin after a fast swipe has crossed several cells.
        CGPoint start = self.selectionStartPoint;
        NSIndexPath *path = scroll == self.gridView ? [self.gridView indexPathForItemAtPoint:start] : [self.tableView indexPathForRowAtPoint:start];
        self.dragDeselects = path && [self.tableView.indexPathsForSelectedRows containsObject:path];
        self.multiSelectLastPoint = CGPointMake(start.x - scroll.bounds.origin.x, start.y - scroll.bounds.origin.y);
        [self selectDragPoint:start];
        self.multiSelectAutoScrollTimer = [NSTimer timerWithTimeInterval:.05 target:self selector:@selector(multiSelectAutoScrollTick:) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:self.multiSelectAutoScrollTimer forMode:NSRunLoopCommonModes];
    }
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged || gesture.state == UIGestureRecognizerStateEnded) {
        CGPoint previous = self.multiSelectLastPoint;
        NSInteger steps = MAX(1, (NSInteger)ceil(hypot(viewport.x-previous.x, viewport.y-previous.y) / 8));
        for (NSInteger i=1; i<=steps; i++) {
            CGFloat fraction = (CGFloat)i / steps;
            [self selectDragPoint:CGPointMake(previous.x + (viewport.x-previous.x)*fraction + scroll.bounds.origin.x, previous.y + (viewport.y-previous.y)*fraction + scroll.bounds.origin.y)];
        }
        self.multiSelectLastPoint = viewport;
    }
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        [self.multiSelectAutoScrollTimer invalidate]; self.multiSelectAutoScrollTimer = nil;
        self.selectionScrollView = nil;
    }
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
    if (!self.comparisonSelectionMode) { [self restoreLastPlaybackPosition]; return; }
    if (self.restoredComparisonPosition || !self.videos.count) return;
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
- (void)restoreLastPlaybackPosition {
    if (self.editing || self.comparisonSelectionMode) return;
    NSString *filename = [NSUserDefaults.standardUserDefaults stringForKey:@"WJLastPlayedFilename"];
    if (!filename.length) return;
    NSUInteger row = [self.videos indexOfObjectPassingTest:^BOOL(NSURL *url, NSUInteger index, BOOL *stop) {
        return [url.lastPathComponent isEqualToString:filename];
    }];
    if (row == NSNotFound) return; // A deleted video must not move the list to an unrelated item.
    NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
    [self.view layoutIfNeeded];
    if (self.gridMode) {
        [self.gridView layoutIfNeeded];
        [self.gridView scrollToItemAtIndexPath:path atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:NO];
    } else {
        [self.tableView layoutIfNeeded];
        [self.tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    }
}
- (void)refreshVideos {
    self.videos = [ReceivedVideoManager videos];
    NSMutableArray *recent = [NSMutableArray array];
    for (NSString *filename in [NSUserDefaults.standardUserDefaults stringArrayForKey:@"WJPlaybackHistory"]) {
        for (NSURL *url in self.videos) if ([url.lastPathComponent isEqual:filename]) { [recent addObject:url]; break; }
    }
    self.recentVideos = recent; [self.tableView reloadData]; [self.gridView reloadData]; [self.recentView reloadData];
}
- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated]; [self.tableView setEditing:editing animated:animated];
    self.gridView.allowsMultipleSelection = NO; [self.gridView reloadData];
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self.gridView.collectionViewLayout invalidateLayout]; }
- (void)thumbnailForURL:(NSURL *)url imageView:(UIImageView *)imageView {
    imageView.accessibilityIdentifier = url.lastPathComponent;
    UIImage *cached = [self.thumbnailCache objectForKey:url.lastPathComponent];
    imageView.image = cached ?: [UIImage systemImageNamed:@"video"];
    if (cached) return;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:[AVAsset assetWithURL:url]]; generator.appliesPreferredTrackTransform = YES; generator.maximumSize = CGSizeMake(480,320);
            CGImageRef ref = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil]; UIImage *image = ref ? [UIImage imageWithCGImage:ref] : nil; if (ref) CGImageRelease(ref);
            if (image) { [weakSelf.thumbnailCache setObject:image forKey:url.lastPathComponent]; dispatch_async(dispatch_get_main_queue(), ^{ if ([imageView.accessibilityIdentifier isEqual:url.lastPathComponent]) imageView.image = image; }); }
        }
    });
}
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return collectionView == self.recentView ? self.recentVideos.count : self.videos.count; }
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path {
    if (collectionView == self.recentView) return CGSizeMake(145,128);
    NSInteger columns = collectionView.bounds.size.width >= 700 ? 3 : (collectionView.bounds.size.width < 350 ? 1 : 2);
    return CGSizeMake(floor((collectionView.bounds.size.width - 24 - (columns - 1) * 10) / columns), 238);
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)path {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"video" forIndexPath:path];
    for (UIView *view in cell.contentView.subviews) [view removeFromSuperview];
    BOOL recent = collectionView == self.recentView; NSURL *url = (recent ? self.recentVideos : self.videos)[path.item];
    NSInteger row = [self.videos indexOfObject:url];
    BOOL current = [url.lastPathComponent isEqual:[NSUserDefaults.standardUserDefaults stringForKey:@"WJLastPlayedFilename"]];
    BOOL selected = [self.tableView.indexPathsForSelectedRows containsObject:[NSIndexPath indexPathForRow:row inSection:0]];
    cell.contentView.backgroundColor = UIColor.secondarySystemBackgroundColor; cell.contentView.layer.cornerRadius = 12; cell.contentView.clipsToBounds = YES;
    cell.contentView.layer.borderColor = (selected ? UIColor.systemBlueColor : UIColor.systemOrangeColor).CGColor; cell.contentView.layer.borderWidth = selected || current ? 3 : 0;
    UIImageView *thumbnail = [UIImageView new]; thumbnail.contentMode = UIViewContentModeScaleAspectFill; thumbnail.clipsToBounds = YES; thumbnail.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:thumbnail]; [self thumbnailForURL:url imageView:thumbnail];
    UILabel *title = [UILabel new]; title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2]; title.numberOfLines = 2; title.translatesAutoresizingMaskIntoConstraints = NO; title.text = url.lastPathComponent; [cell.contentView addSubview:title];
    [NSLayoutConstraint activateConstraints:@[[thumbnail.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:3], [thumbnail.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-3], [thumbnail.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:3], [thumbnail.heightAnchor constraintEqualToConstant:recent ? 88 : 142], [title.topAnchor constraintEqualToAnchor:thumbnail.bottomAnchor constant:4], [title.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:6], [title.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-6]]];
    if (current || selected) { UILabel *badge = [UILabel new]; badge.text = selected ? MTJText(@" ✓ 選択中 ") : MTJText(@" 表示中 "); badge.font = [UIFont boldSystemFontOfSize:12]; badge.backgroundColor = selected ? UIColor.systemBlueColor : UIColor.systemOrangeColor; badge.textColor = UIColor.blackColor; badge.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:badge]; [NSLayoutConstraint activateConstraints:@[[badge.leadingAnchor constraintEqualToAnchor:thumbnail.leadingAnchor constant:3], [badge.topAnchor constraintEqualToAnchor:thumbnail.topAnchor constant:3]]]; }
    if (!recent) {
        UITableViewCell *template = [self tableView:self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
        title.text = [NSString stringWithFormat:@"%@\n%@", [url isEqual:self.selectedMainURL] ? @"MAIN" : ([url isEqual:self.selectedSubURL] ? @"SUB" : @""), template.textLabel.text];
        UIView *actions = template.accessoryView; actions.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:actions];
        [NSLayoutConstraint activateConstraints:@[[actions.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor], [actions.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4], [actions.heightAnchor constraintEqualToConstant:44], [actions.widthAnchor constraintEqualToConstant:self.comparisonSelectionMode ? 40 : 168]]];
    }
    return cell;
}
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)path {
    NSURL *url = (collectionView == self.recentView ? self.recentVideos : self.videos)[path.item];
    NSIndexPath *row = [NSIndexPath indexPathForRow:[self.videos indexOfObject:url] inSection:0];
    if (self.editing) {
        if ([self.tableView.indexPathsForSelectedRows containsObject:row]) [self.tableView deselectRowAtIndexPath:row animated:NO];
        else [self.tableView selectRowAtIndexPath:row animated:NO scrollPosition:UITableViewScrollPositionNone];
        [collectionView deselectItemAtIndexPath:path animated:NO];
        [self.gridView reloadData]; return;
    }
    [self tableView:self.tableView didSelectRowAtIndexPath:row];
}

- (void)toggleGridMode {
    NSIndexPath *anchor = self.tableView.indexPathsForVisibleRows.firstObject;
    self.gridMode = !self.gridMode; self.gridView.hidden = !self.gridMode; self.tableView.hidden = self.gridMode;
    [[NSUserDefaults standardUserDefaults] setBool:self.gridMode forKey:@"WJVideoGridMode"];
    UIBarButtonItem *photo = [[UIBarButtonItem alloc] initWithTitle:MTJText(@"写真") style:UIBarButtonItemStylePlain target:self action:@selector(selectPhotoVideo)];
    UIBarButtonItem *grid = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:self.gridMode ? @"list.bullet" : @"square.grid.2x2"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleGridMode)];
    grid.accessibilityLabel = MTJText(@"リスト表示とサムネイル表示を切り替え");
    self.navigationItem.rightBarButtonItems = self.comparisonSelectionMode ? @[grid] : @[photo, grid];
    [self.tableView reloadData];
    [self.tableView layoutIfNeeded];
    if (anchor && anchor.row < self.videos.count) [self.tableView scrollToRowAtIndexPath:anchor atScrollPosition:UITableViewScrollPositionTop animated:NO];
    [self restoreLastPlaybackPosition];
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 100.0;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.videos.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[WJLibraryListCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
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
    [self thumbnailForURL:url imageView:cell.imageView];
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
- (void)selectComparisonGrid:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || self.editing) return;
    NSIndexPath *path = [self.gridView indexPathForItemAtPoint:[gesture locationInView:self.gridView]];
    if (path) [self selectComparisonURL:self.videos[path.item]];
}
- (void)selectComparisonVideo:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath || indexPath.row >= self.videos.count) return;
    [self selectComparisonURL:self.videos[indexPath.row]];
}
- (void)selectComparisonURL:(NSURL *)url {
    if ([url isEqual:self.selectedMainURL]) return;
    if (!self.selectedMainURL) {
        self.selectedMainURL = url;
        [self.gridView reloadData]; [self.tableView reloadData];
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
    if (self.playbackSelectionHandler) { self.playbackSelectionHandler(self.videos[indexPath.row]); return; }
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
    [self refreshVideos];
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
@interface WJDurationList : UITableViewController
@property(nonatomic, strong) NSMutableArray<NSNumber *> *durations;
@end
@implementation WJDurationList
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = MTJText(@"録画時間");
    self.durations = [[NSUserDefaults.standardUserDefaults arrayForKey:@"WJDurationOptions"] ?: @[@0,@10,@20,@30] mutableCopy];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addDuration)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.durations.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSInteger seconds = self.durations[path.row].integerValue;
    cell.textLabel.text = seconds ? [NSString stringWithFormat:MTJText(@"%ld秒"), (long)seconds] : MTJText(@"手動停止");
    cell.accessoryType = [NSUserDefaults.standardUserDefaults integerForKey:@"WJDuration"] == seconds ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if ([WaterJumpCoordinator shared].recordingBusy) return;
    [NSUserDefaults.standardUserDefaults setObject:self.durations[path.row] forKey:@"WJDuration"];
    [[WaterJumpCoordinator shared] applySettings]; [tableView reloadData];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path { return self.durations.count > 1 && ![WaterJumpCoordinator shared].recordingBusy; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete || [WaterJumpCoordinator shared].recordingBusy || self.durations.count <= 1) return;
    NSNumber *removed = self.durations[path.row]; [self.durations removeObjectAtIndex:path.row];
    if (removed.integerValue == [NSUserDefaults.standardUserDefaults integerForKey:@"WJDuration"]) {
        [NSUserDefaults.standardUserDefaults setObject:self.durations.firstObject forKey:@"WJDuration"]; [[WaterJumpCoordinator shared] applySettings];
    }
    [NSUserDefaults.standardUserDefaults setObject:self.durations forKey:@"WJDurationOptions"]; [tableView reloadData];
}
- (void)addDuration {
    if ([WaterJumpCoordinator shared].recordingBusy) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTJText(@"録画時間を追加") message:MTJText(@"秒数を入力（0は手動停止）。項目を左にスワイプすると削除できます。") preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.keyboardType = UIKeyboardTypeNumberPad; field.placeholder = @"10"; }];
    [alert addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:MTJText(@"追加") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!text.length || [text rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound || [WaterJumpCoordinator shared].recordingBusy) return;
        NSScanner *scanner = [NSScanner scannerWithString:text]; long long seconds;
        if (![scanner scanLongLong:&seconds] || !scanner.isAtEnd || seconds < 0 || seconds > NSIntegerMax) return;
        NSNumber *value = @(seconds); if (![self.durations containsObject:value]) [self.durations addObject:value];
        [self.durations sortUsingSelector:@selector(compare:)];
        [NSUserDefaults.standardUserDefaults setObject:self.durations forKey:@"WJDurationOptions"]; [self.tableView reloadData];
    }]]; [self presentViewController:alert animated:YES completion:nil];
}
@end

@interface WJTransferQueueList : UITableViewController
@property(nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
@property(nonatomic, strong) UIBarButtonItem *removeButton;
@end
@implementation WJTransferQueueList
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = MTJText(@"転送待ち動画の管理");
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 100;
    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    self.navigationItem.rightBarButtonItems = @[self.editButtonItem, [[UIBarButtonItem alloc] initWithTitle:MTJText(@"区分選択") style:UIBarButtonItemStylePlain target:self action:@selector(selectCategory)]];
    self.removeButton = [[UIBarButtonItem alloc] initWithTitle:MTJText(@"選択した転送対象を削除") style:UIBarButtonItemStylePlain target:self action:@selector(removeSelected)];
    self.removeButton.tintColor = UIColor.systemRedColor;
    self.toolbarItems = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil], self.removeButton];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:WJStatusChanged object:nil];
    [self refresh];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.navigationController setToolbarHidden:NO animated:animated]; [self refresh]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.navigationController setToolbarHidden:YES animated:animated]; }
- (NSArray<NSString *> *)categoryTitles { return @[MTJText(@"旧転送先への待ち情報"), MTJText(@"以前のグループ・接続設定の待ち情報"), MTJText(@"現在の転送待ち"), MTJText(@"元動画なし・自動再送対象外")]; }
- (NSDictionary *)entryAt:(NSIndexPath *)path { return self.sections[path.section][path.row]; }
- (void)refresh {
    NSMutableSet *selected = [NSMutableSet set];
    for (NSIndexPath *path in self.tableView.indexPathsForSelectedRows) [selected addObject:[self entryAt:path][@"key"]];
    NSMutableArray *groups = [NSMutableArray array]; for (NSInteger i = 0; i < 4; i++) [groups addObject:[NSMutableArray array]];
    for (NSDictionary *entry in [WaterJumpCoordinator shared].transferQueueEntries) [groups[[entry[@"category"] integerValue]] addObject:entry];
    self.sections = groups; [self.tableView reloadData];
    for (NSInteger section = 0; section < 4; section++) for (NSInteger row = 0; row < self.sections[section].count; row++) {
        NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
        if ([selected containsObject:[self entryAt:path][@"key"]]) [self.tableView selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
    [self updateSelection];
}
- (void)updateSelection { NSInteger count = self.tableView.indexPathsForSelectedRows.count; self.removeButton.enabled = count > 0; self.removeButton.title = [NSString stringWithFormat:MTJText(@"選択した転送対象を削除（%ld件）"), (long)count]; }
- (void)setEditing:(BOOL)editing animated:(BOOL)animated { [super setEditing:editing animated:animated]; [self updateSelection]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.sections[section].count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return [NSString stringWithFormat:@"%@（%ld件）", [self categoryTitles][section], (long)self.sections[section].count]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return MTJText(@"現在の転送先に登録されていない端末への待ち情報です。左へスワイプして個別削除、または「区分選択」でまとめて選択できます。動画本体は削除しません。");
    if (section == 3) return MTJText(@"元動画がない項目は自動再送しません。不要な待ち情報は削除できます。元動画がある項目は、通常表示でタップすると再生できます。");
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *entry = [self entryAt:path];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = entry[@"filename"]; cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    NSDateFormatter *formatter = [NSDateFormatter new]; formatter.dateStyle = NSDateFormatterMediumStyle; formatter.timeStyle = NSDateFormatterShortStyle;
    NSString *date = [entry[@"created"] doubleValue] > 0 ? [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:[entry[@"created"] doubleValue]]] : MTJText(@"撮影日時不明");
    NSString *state = [entry[@"active"] boolValue] ? MTJText(@"転送中") : ([entry[@"missing"] boolValue] ? MTJText(@"元動画なし") : MTJText(@"動画保存済み"));
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@・%@\n転送先：%@\n%@", date, state, MTJText(entry[@"peerName"]), entry[@"peerID"]];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (self.editing) { [self updateSelection]; return; }
    [tableView deselectRowAtIndexPath:path animated:YES]; NSDictionary *entry = [self entryAt:path];
    NSString *file = entry[@"path"];
    if (!file.length || ![NSFileManager.defaultManager fileExistsAtPath:file]) { [self showError:MTJText(@"元動画がないため再生できません。不要な待ち情報は左へスワイプして転送対象から削除できます。")]; return; }
    WaterJumpReceivedPlayerViewController *player = [[WaterJumpReceivedPlayerViewController alloc] initWithVideoURL:[NSURL fileURLWithPath:file]];
    [self presentViewController:player animated:YES completion:^{ [player.player play]; }];
}
- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)path { [self updateSelection]; }
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path { return ![[self entryAt:path][@"active"] boolValue]; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style == UITableViewCellEditingStyleDelete) [self removeKeys:@[[self entryAt:path][@"key"]]];
}
- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTJText(@"転送待ち動画の管理") message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)removeKeys:(NSArray<NSString *> *)keys {
    NSString *error = [[WaterJumpCoordinator shared] removeTransferEntries:keys];
    if (error.length) [self showError:MTJText(error)];
    [self refresh];
}
- (void)removeSelected {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSIndexPath *path in self.tableView.indexPathsForSelectedRows) [keys addObject:[self entryAt:path][@"key"]];
    if (!keys.count) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTJText(@"選択した転送対象を削除") message:[NSString stringWithFormat:MTJText(@"%ld件の転送待ち情報を削除します。動画本体・タグは削除しません。"), (long)keys.count] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:MTJText(@"削除") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self removeKeys:keys]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)selectCategory {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTJText(@"まとめて選択") message:MTJText(@"選択後、下部の削除ボタンで転送対象から外せます。") preferredStyle:UIAlertControllerStyleAlert];
    for (NSInteger section = 0; section < 4; section++) {
        if (!self.sections[section].count) continue;
        NSString *title = [self tableView:self.tableView titleForHeaderInSection:section];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self setEditing:YES animated:YES];
            for (NSIndexPath *path in self.tableView.indexPathsForSelectedRows) [self.tableView deselectRowAtIndexPath:path animated:NO];
            for (NSInteger row = 0; row < self.sections[section].count; row++) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
                if (![[self entryAt:path][@"active"] boolValue]) [self.tableView selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
            }
            [self updateSelection];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
}
@end

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
    if (!self.easy) return 9;
    CameraGroupManager *g = [WaterJumpCoordinator shared].group;
    return section == 0 ? 5 : (section == 1 ? g.groups.count : g.members.count);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (!self.easy) return nil;
    return MTJText(@[@"グループと役割", @"検索中・同じWi-Fiのグループ", @"接続端末一覧（未接続の端末はタップで再接続）"][section]);
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.easy && section == 2) return MTJText(@"未接続の端末は名前をタップして再接続します。メイン端末ではⓘから登録を解除できます。");
    if (!self.easy || section != 0) return nil;
    return MTJText(@"メイン＋カメラ1〜3の最大4台。受信はメイン＋追加3台の最大4台です。同じWi-Fiでアプリを前景にし、ローカルネットワークを許可してください。撮影端末は接続後にカメラ画面を開いてください。");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.textLabel.numberOfLines = 0; c.detailTextLabel.numberOfLines = 0;
    CameraGroupManager *g = [WaterJumpCoordinator shared].group;
    if (!self.easy) {
        if (path.row < 3) {
            c.textLabel.text = MTJText(@[@"この端末のカメラ名", @"録画時間", @"転送時2画面同時再生"][path.row]);
            if (path.row == 0) c.detailTextLabel.text = [NSUserDefaults.standardUserDefaults stringForKey:@"WJCameraName"] ?: UIDevice.currentDevice.name;
            if (path.row == 1) { NSInteger seconds = [NSUserDefaults.standardUserDefaults integerForKey:@"WJDuration"]; c.detailTextLabel.text = seconds ? [NSString stringWithFormat:MTJText(@"%ld秒"), (long)seconds] : MTJText(@"手動停止"); }
            if (path.row == 2) { UISwitch *toggle = [UISwitch new]; toggle.on = [NSUserDefaults.standardUserDefaults boolForKey:@"WJCompareAfterTransfer"]; [toggle addTarget:self action:@selector(compareChanged:) forControlEvents:UIControlEventValueChanged]; c.accessoryView = toggle; }
            else c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return c;
        }
        if (path.row < 6) {
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            WaterJumpCoordinator *manager = [WaterJumpCoordinator shared];
            c.textLabel.text = MTJText(@[@"受信後自動再生", @"転送先でループ再生する", @"ループ再生設定"][path.row - 3]);
            if (path.row == 5) {
                NSInteger count = [defaults integerForKey:@"WJLoopCount"]; if (!count) count = 3;
                NSInteger seconds = [defaults integerForKey:@"WJLoopDuration"];
                c.detailTextLabel.text = count < 0 ? (seconds > 0 ? [NSString stringWithFormat:MTJText(@"無限・%ld分"), (long)(seconds / 60)] : MTJText(@"無限・時間制限なし")) : [NSString stringWithFormat:MTJText(@"%ld回"), (long)count];
                c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                UISwitch *toggle = [UISwitch new]; toggle.tag = path.row;
                NSString *key = path.row == 3 ? @"WJAutoPlayAfterTransfer" : @"WJLoopPlayback";
                toggle.accessibilityIdentifier = key;
                BOOL available = manager.receivedPlaybackAvailable && !manager.recordingBusy;
                toggle.enabled = available && (path.row == 3 || [defaults boolForKey:@"WJAutoPlayAfterTransfer"]);
                toggle.on = manager.receivedPlaybackAvailable && [defaults boolForKey:key];
                if (path.row == 4) toggle.on = toggle.on && [defaults boolForKey:@"WJAutoPlayAfterTransfer"];
                [toggle addTarget:self action:@selector(playbackChanged:) forControlEvents:UIControlEventValueChanged]; c.accessoryView = toggle;
                if (path.row == 3 && !manager.receivedPlaybackAvailable) c.detailTextLabel.text = MTJText(@"メインまたは受信端末の役割で、受信待機中に有効です。");
            }
            return c;
        }
        if (path.row == 8) {
            c.textLabel.text = MTJText(@"転送待ち動画の管理");
            c.detailTextLabel.text = [NSString stringWithFormat:MTJText(@"%ld件・旧転送先の待ち情報を確認・削除"), (long)[WaterJumpCoordinator shared].transferQueueEntries.count];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return c;
        }
        c.textLabel.text = MTJText(path.row == 6 ? @"簡単設定" : @"詳細設定");
        c.detailTextLabel.text = MTJText(path.row == 6 ? @"グループと役割だけで接続を設定します" : (g.automatic ? @"自動設定の内容を確認・従来方式へ切替" : @"URL・QRコードによる従来の接続設定"));
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
        if ([g.role isEqual:@"MAIN"]) c.accessoryType = UITableViewCellAccessoryDetailButton;
        c.detailTextLabel.text = [NSString stringWithFormat:@"%@・%@\n%@", WJRoleTitle(member[@"role"]),MTJText([member[@"connected"] isEqual:@"1"] ? @"認証済み" : @"未接続"),member[@"id"]];
    }
    return c;
}
- (void)playbackChanged:(UISwitch *)sender {
    WaterJumpCoordinator *manager = [WaterJumpCoordinator shared];
    if (!manager.receivedPlaybackAvailable || manager.recordingBusy) { [self refresh]; return; }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:sender.on forKey:sender.tag == 3 ? @"WJAutoPlayAfterTransfer" : @"WJLoopPlayback"];
    if (sender.tag == 3 && !sender.on) [defaults setBool:NO forKey:@"WJLoopPlayback"];
    [manager applySettings]; [self refresh];
}
- (void)compareChanged:(UISwitch *)sender { [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"WJCompareAfterTransfer"]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)selectRoleForGroup:(NSString *)groupID {
    CameraGroupManager *g = [WaterJumpCoordinator shared].group;
    if (!groupID.length || ([g.role isEqual:@"MAIN"] && [groupID isEqual:g.groupID])) { [self showMessage:@"メインはグループ作成時に設定されます。他の役割は検索したグループを選択して設定してください。"]; return; }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:MTJText(@"この端末の役割") message:MTJText(@"既存の通信設定を置き換えます。動画・タグは保持します。初回はメイン端末で参加を承認してください。") preferredStyle:UIAlertControllerStyleAlert];
    for (NSString *role in @[@"CAMERA_1",@"CAMERA_2",@"CAMERA_3",@"RECEIVER"]) {
        [a addAction:[UIAlertAction actionWithTitle:WJRoleTitle(role) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { if (![g joinGroup:groupID role:role]) [self showMessage:g.message]; }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)confirmRemovalOfMember:(NSDictionary *)member {
    CameraGroupManager *g = [WaterJumpCoordinator shared].group;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:MTJText(@"端末の登録を解除") message:[NSString stringWithFormat:@"%@\n%@",member[@"name"],MTJText(@"この端末との接続が解除され、役割番号が空きます。動画は削除しません。再参加には承認が必要です。") ] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:MTJText(@"解除") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { if (![g removeMember:member[@"id"]]) [self showMessage:@"録画・転送・受信の終了後に変更してください"]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)path {
    CameraGroupManager *g = [WaterJumpCoordinator shared].group;
    if (self.easy && path.section == 2 && [g.role isEqual:@"MAIN"] && path.row < g.members.count) [self confirmRemovalOfMember:g.members[path.row]];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    CameraGroupManager *g = [WaterJumpCoordinator shared].group;
    if (!self.easy) {
        if (path.row == 0) { [WaterJumpSettingsViewController presentCameraNameFrom:self]; return; }
        if (path.row == 1) { [WaterJumpSettingsViewController presentDurationFrom:self]; return; }
        if (path.row == 2) return;
        if (path.row == 8) { [self.navigationController pushViewController:[WJTransferQueueList new] animated:YES]; return; }
        if (path.row == 3 || path.row == 4) return;
        if (path.row == 5) { [WaterJumpSettingsViewController presentLoopSettingsFrom:self]; return; }
        if (path.row == 6) { WJSetupMenu *vc = [WJSetupMenu new]; vc.easy = YES; [self.navigationController pushViewController:vc animated:YES]; }
        else [self.navigationController pushViewController:[WaterJumpSettingsViewController new] animated:YES];
        return;
    }
    if (path.section == 1) { [self selectRoleForGroup:g.groups[path.row][@"group"]]; return; }
    if (path.section == 2) {
        if (path.row >= g.members.count) return;
        NSDictionary *member = g.members[path.row];
        if (![member[@"connected"] isEqual:@"1"]) {
            if (![g reconnectMember:member[@"id"]]) [self showMessage:g.message];
            [self refresh];
        } else if ([g.role isEqual:@"MAIN"]) [self confirmRemovalOfMember:member];
        return;
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

@interface WJPreviewTouchView : UIView
@end
@implementation WJPreviewTouchView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { UIView *hit = [super hitTest:point withEvent:event]; return hit == self ? nil : hit; }
@end
@interface WJRemotePreviewController : UIViewController
@property(nonatomic, strong) UIStackView *windows;
@property(nonatomic, strong) UIButton *connectionButton;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDataTask *> *requests;
@property(nonatomic, strong) NSArray<NSDictionary *> *cameras;
@property(nonatomic) BOOL showing;
@end
@implementation WJRemotePreviewController
- (void)loadView { self.view = [WJPreviewTouchView new]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.requests = [NSMutableDictionary dictionary];
    self.connectionButton = [UIButton buttonWithType:UIButtonTypeSystem]; self.connectionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.connectionButton setImage:[UIImage systemImageNamed:@"network"] forState:UIControlStateNormal]; self.connectionButton.tintColor = UIColor.whiteColor; self.connectionButton.backgroundColor = [UIColor colorWithWhite:0 alpha:.7]; self.connectionButton.layer.cornerRadius = 12;
    self.connectionButton.accessibilityLabel = MTJText(@"接続情報・カメラプレビューの表示切替");
    [self.connectionButton addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:self.connectionButton];
    self.windows = [UIStackView new]; self.windows.axis = UILayoutConstraintAxisHorizontal; self.windows.distribution = UIStackViewDistributionFillEqually; self.windows.spacing = 8; self.windows.translatesAutoresizingMaskIntoConstraints = NO; self.windows.hidden = YES; [self.view addSubview:self.windows];
    [NSLayoutConstraint activateConstraints:@[[self.connectionButton.widthAnchor constraintEqualToConstant:44], [self.connectionButton.heightAnchor constraintEqualToConstant:44], [self.windows.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:110], [self.windows.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.windows.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.windows.heightAnchor constraintEqualToConstant:140]]];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self startTimer]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.timer invalidate]; self.timer = nil; for (NSURLSessionDataTask *task in self.requests.allValues) [task cancel]; [self.requests removeAllObjects]; }
- (void)dealloc { [_timer invalidate]; for (NSURLSessionDataTask *task in _requests.allValues) [task cancel]; }
- (void)startTimer { [self.timer invalidate]; if (!self.showing) return; __weak typeof(self) weakSelf = self; self.timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }]; [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes]; [self refresh]; }
- (void)toggle { self.showing = !self.showing; self.windows.hidden = !self.showing; self.connectionButton.tintColor = self.showing ? UIColor.systemGreenColor : UIColor.whiteColor; if (self.showing) [self startTimer]; else { [self.timer invalidate]; self.timer = nil; for (NSURLSessionDataTask *task in self.requests.allValues) [task cancel]; [self.requests removeAllObjects]; } }
- (void)refresh {
    if (!self.showing || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSArray *cameras = [WaterJumpCoordinator shared].remoteCameras;
    if (![cameras isEqual:self.cameras]) {
        for (NSURLSessionDataTask *task in self.requests.allValues) [task cancel]; [self.requests removeAllObjects]; self.cameras = cameras;
        for (UIView *view in self.windows.arrangedSubviews) { [self.windows removeArrangedSubview:view]; [view removeFromSuperview]; }
        NSArray *display = cameras.count ? cameras : @[@{@"name":MTJText(@"カメラ未接続"), @"id":@"none"}];
        for (NSDictionary *camera in display) {
            UIView *card = [UIView new]; card.backgroundColor = UIColor.blackColor; card.layer.cornerRadius = 8; card.clipsToBounds = YES;
            UILabel *name = [UILabel new]; name.text = camera[@"name"]; name.textAlignment = NSTextAlignmentCenter; name.textColor = UIColor.whiteColor; name.font = [UIFont boldSystemFontOfSize:12]; name.translatesAutoresizingMaskIntoConstraints = NO;
            UIImageView *image = [UIImageView new]; image.contentMode = UIViewContentModeScaleAspectFit; image.tag = 101; image.translatesAutoresizingMaskIntoConstraints = NO;
            UILabel *error = [UILabel new]; error.text = MTJText(@"接続を確認中…"); error.textColor = UIColor.systemRedColor; error.font = [UIFont systemFontOfSize:12]; error.numberOfLines = 0; error.textAlignment = NSTextAlignmentCenter; error.tag = 102; error.translatesAutoresizingMaskIntoConstraints = NO;
            [card addSubview:image]; [card addSubview:name]; [card addSubview:error]; [self.windows addArrangedSubview:card];
            [NSLayoutConstraint activateConstraints:@[[name.topAnchor constraintEqualToAnchor:card.topAnchor constant:3], [name.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:2], [name.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-2], [name.heightAnchor constraintEqualToConstant:20], [image.topAnchor constraintEqualToAnchor:name.bottomAnchor], [image.leadingAnchor constraintEqualToAnchor:card.leadingAnchor], [image.trailingAnchor constraintEqualToAnchor:card.trailingAnchor], [image.bottomAnchor constraintEqualToAnchor:card.bottomAnchor], [error.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:4], [error.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-4], [error.topAnchor constraintEqualToAnchor:name.bottomAnchor], [error.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]]];
        }
    }
    if (!cameras.count) { UILabel *label = [self.windows.arrangedSubviews.firstObject viewWithTag:102]; label.text = MTJText(@"設定からカメラを接続してください"); return; }
    for (NSInteger i = 0; i < cameras.count; i++) {
        NSDictionary *camera = cameras[i]; UIView *card = self.windows.arrangedSubviews[i]; UIImageView *image = [card viewWithTag:101]; UILabel *errorLabel = [card viewWithTag:102]; NSString *identifier = camera[@"id"];
        if (![camera[@"connected"] boolValue]) { image.image = nil; errorLabel.text = MTJText(@"未接続：同じWi-Fiと撮影端末の前景起動を確認"); errorLabel.hidden = NO; continue; }
        if (self.requests[identifier]) continue;
        NSURLComponents *parts = [NSURLComponents componentsWithString:camera[@"url"]]; NSString *token = parts.fragment; parts.fragment = nil;
        if (!parts.URL || !token.length) { image.image = nil; errorLabel.text = MTJText(@"接続情報を更新中"); errorLabel.hidden = NO; continue; }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[parts.URL URLByAppendingPathComponent:@"preview"]]; request.timeoutInterval = 2.5;
        [request setValue:token forHTTPHeaderField:@"X-MTJudge-Token"]; [request setValue:[WaterJumpCoordinator shared].group.groupID forHTTPHeaderField:@"X-MTJudge-Group"];
        __weak typeof(self) weakSelf = self;
        NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSDictionary *reply = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSData *jpeg = [reply[@"image"] isKindOfClass:NSString.class] ? [[NSData alloc] initWithBase64EncodedString:reply[@"image"] options:0] : nil;
            UIImage *frame = jpeg ? [UIImage imageWithData:jpeg] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) self = weakSelf; if (!self) return; [self.requests removeObjectForKey:identifier];
                if (!self.showing || ![self.windows.arrangedSubviews containsObject:card]) return;
                if (!error && [(NSHTTPURLResponse *)response statusCode] == 200 && frame) { image.image = frame; errorLabel.hidden = YES; }
                else { image.image = nil; errorLabel.hidden = NO; errorLabel.text = error.localizedDescription ?: reply[@"error"] ?: MTJText(@"プレビューを受信できません。撮影端末を更新しカメラ画面を開いてください。"); }
            });
        }]; self.requests[identifier] = task; [task resume];
    }
}
@end

@interface WJPlaybackScreen : UIViewController <MTJReceivedPlaybackHost, UIGestureRecognizerDelegate>
@property(nonatomic, strong) UIButton *syncButton;
@property(nonatomic, strong) UIStackView *controls;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) WaterJumpReceivedPlayerViewController *embeddedPlayer;
@property(nonatomic, strong) WaterJumpComparisonViewController *embeddedComparison;
@property(nonatomic) BOOL presentedInitialList;
@end
@implementation WJPlaybackScreen
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.blackColor;
    UILabel *brand = [UILabel new]; brand.text = @"MTJudge"; brand.font = [UIFont boldSystemFontOfSize:36]; brand.textColor = [UIColor colorWithWhite:.55 alpha:1]; brand.textAlignment = NSTextAlignmentCenter; brand.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:brand]; [NSLayoutConstraint activateConstraints:@[[brand.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor], [brand.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]]];
    UITapGestureRecognizer *statusTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleComparisonPlayback)]; statusTap.delegate = self; statusTap.cancelsTouchesInView = NO; [self.view addGestureRecognizer:statusTap];
    UIButton *library = [self button:@"rectangle.stack" label:@"練習動画を選択" action:@selector(openLibrary)];
    UIButton *settings = [self button:@"gearshape" label:@"リモート操作モード" action:@selector(openSettings)];
    self.controls = [[UIStackView alloc] initWithArrangedSubviews:@[library,settings]]; self.controls.axis = UILayoutConstraintAxisVertical; self.controls.spacing = 4; self.controls.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:self.controls];
    self.syncButton = [self button:@"record.circle.fill" label:@"接続中カメラの同期録画開始・停止" action:@selector(toggleSync)]; self.syncButton.tintColor = UIColor.systemOrangeColor; self.syncButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.syncButton setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:48 weight:UIImageSymbolWeightRegular] forImageInState:UIControlStateNormal]; [self.view addSubview:self.syncButton];
    self.statusLabel = [UILabel new]; self.statusLabel.textColor = UIColor.whiteColor; self.statusLabel.numberOfLines = 0; self.statusLabel.font = [UIFont systemFontOfSize:13]; self.statusLabel.textAlignment = NSTextAlignmentCenter; self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:self.statusLabel];
    [NSLayoutConstraint activateConstraints:@[[self.controls.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12], [self.controls.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:60], [self.syncButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16], [self.syncButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor], [self.syncButton.widthAnchor constraintEqualToConstant:64], [self.syncButton.heightAnchor constraintEqualToConstant:64], [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.controls.trailingAnchor constant:12], [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.syncButton.leadingAnchor constant:-12], [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-36]]];
    [WaterJumpSettingsViewController installRemotePreviewOn:self recordingButton:self.syncButton];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshStatus) name:WJStatusChanged object:nil]; [self refreshStatus];
}
- (UIButton *)button:(NSString *)symbol label:(NSString *)label action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal]; button.accessibilityLabel = MTJText(label); button.tintColor = UIColor.whiteColor; button.backgroundColor = [UIColor colorWithWhite:.1 alpha:.8]; button.layer.cornerRadius = 14; [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; [button.widthAnchor constraintGreaterThanOrEqualToConstant:44].active = YES; [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES; return button;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (!self.embeddedComparison || [touch.view isDescendantOfView:self.embeddedComparison.view]) return NO;
    for (UIView *view = touch.view; view && view != self.view; view = view.superview) if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UIScrollView.class]) return NO;
    return [touch locationInView:self.view].y >= CGRectGetMaxY(self.embeddedComparison.view.frame);
}
- (void)toggleComparisonPlayback { [self.embeddedComparison togglePlayback]; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [WaterJumpCoordinator shared].playbackHost = self; if (!self.presentedInitialList) { self.presentedInitialList = YES; [self openLibrary]; } }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)refreshStatus { BOOL recording = [WaterJumpCoordinator shared].remoteOnlyRecording; [self.syncButton setImage:[UIImage systemImageNamed:recording ? @"stop.circle.fill" : @"record.circle.fill"] forState:UIControlStateNormal]; self.statusLabel.text = [WaterJumpCoordinator shared].message; }
- (void)toggleSync { NSString *error = [[WaterJumpCoordinator shared] toggleRemoteOnlyRecording]; if (error) { UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTJText(@"同期録画") message:MTJText(error) preferredStyle:UIAlertControllerStyleAlert]; [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil]; } }
- (void)openSettings { if (self.presentedViewController) return; [self presentViewController:[[UINavigationController alloc] initWithRootViewController:[WaterJumpSettingsViewController remoteSetupViewController]] animated:YES completion:nil]; }
- (void)openLibrary {
    if (self.presentedViewController) return;
    [self.embeddedPlayer.player pause]; [self.embeddedComparison pausePlayback];
    WJVideoLibrary *library = [WJVideoLibrary new]; UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:library];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    nav.sheetPresentationController.detents = @[[UISheetPresentationControllerDetent customDetentWithIdentifier:@"videoLibrary" resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) { return context.maximumDetentValue * .8; }], UISheetPresentationControllerDetent.largeDetent]; nav.sheetPresentationController.prefersGrabberVisible = YES;
    __weak typeof(self) weakSelf = self; __weak UINavigationController *weakNav = nav;
    library.playbackSelectionHandler = ^(NSURL *url) { [weakNav dismissViewControllerAnimated:YES completion:^{ [weakSelf playURL:url]; }]; };
    [self presentViewController:nav animated:YES completion:nil];
}
- (BOOL)displayReceivedMainURL:(NSURL *)mainURL subURL:(NSURL *)subURL {
    if (!self.view.window || self.presentedViewController || self.tabBarController.selectedViewController != self) return NO;
    if (!subURL) { [self playURL:mainURL]; return YES; }
    [self clearEmbedded];
    WaterJumpComparisonViewController *comparison = [[WaterJumpComparisonViewController alloc] initWithMainURL:mainURL subURL:subURL]; self.embeddedComparison = comparison;
    comparison.showsReceivedCameraNames = YES;
    [self addChildViewController:comparison]; comparison.view.frame = CGRectMake(0,0,self.view.bounds.size.width,MAX(0,self.view.bounds.size.height - 150)); comparison.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [self.view insertSubview:comparison.view atIndex:1]; [comparison didMoveToParentViewController:self];
    __weak typeof(self) weakSelf = self; comparison.closeHandler = ^{ weakSelf.embeddedComparison = nil; }; [comparison startPlayback]; return YES;
}
- (void)clearEmbedded {
    self.controls.hidden = NO;
    if (self.embeddedComparison) { [self.embeddedComparison prepareForAutoplayReplacement]; [self.embeddedComparison willMoveToParentViewController:nil]; [self.embeddedComparison.view removeFromSuperview]; [self.embeddedComparison removeFromParentViewController]; self.embeddedComparison = nil; }
    if (self.embeddedPlayer) { [self.embeddedPlayer prepareForAutoplayReplacement]; [self.embeddedPlayer willMoveToParentViewController:nil]; [self.embeddedPlayer.view removeFromSuperview]; [self.embeddedPlayer removeFromParentViewController]; self.embeddedPlayer = nil; }
}
- (void)playURL:(NSURL *)url {
    [self clearEmbedded];
    WaterJumpReceivedPlayerViewController *player = [[WaterJumpReceivedPlayerViewController alloc] initWithVideoURL:url]; NSArray *videos = [ReceivedVideoManager videos]; NSUInteger index = [videos indexOfObject:url]; [player setPlaylist:videos currentIndex:index == NSNotFound ? 0 : index]; self.embeddedPlayer = player;
    [self addChildViewController:player]; player.view.frame = CGRectMake(0, 0, self.view.bounds.size.width, MAX(0, self.view.bounds.size.height - 150)); player.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [self.view insertSubview:player.view atIndex:1]; [player didMoveToParentViewController:self];
    __weak typeof(self) weakSelf = self; player.drawingModeChangedHandler = ^(BOOL drawing) { weakSelf.controls.hidden = drawing; };
    player.closeHandler = ^{ weakSelf.controls.hidden = NO; weakSelf.embeddedPlayer = nil; }; [player.player play];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.embeddedPlayer.player pause]; [self.embeddedComparison pausePlayback]; }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; if (self.tabBarController.selectedViewController != self && [WaterJumpCoordinator shared].playbackHost == self) [WaterJumpCoordinator shared].playbackHost = nil; }
@end

@implementation WaterJumpSettingsViewController
+ (UIViewController *)playbackScreenViewController { return [WJPlaybackScreen new]; }
+ (void)installRemotePreviewOn:(UIViewController *)host recordingButton:(UIView *)recordingButton {
    WJRemotePreviewController *preview = [WJRemotePreviewController new];
    [host addChildViewController:preview]; preview.view.translatesAutoresizingMaskIntoConstraints = NO;
    [host.view addSubview:preview.view]; [preview didMoveToParentViewController:host];
    [NSLayoutConstraint activateConstraints:@[
        [preview.view.leadingAnchor constraintEqualToAnchor:host.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [preview.view.trailingAnchor constraintEqualToAnchor:host.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [preview.view.topAnchor constraintEqualToAnchor:host.view.topAnchor],
        [preview.view.bottomAnchor constraintEqualToAnchor:host.view.bottomAnchor],
        [preview.connectionButton.centerXAnchor constraintEqualToAnchor:recordingButton.centerXAnchor],
        [preview.connectionButton.bottomAnchor constraintEqualToAnchor:recordingButton.topAnchor constant:-12]
    ]];
}
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
    [host presentViewController:[[UINavigationController alloc] initWithRootViewController:[WJDurationList new]] animated:YES completion:nil];
}
+ (void)presentLoopSettingsFrom:(UIViewController *)host {
    if ([WaterJumpCoordinator shared].recordingBusy) return;
        UIAlertController *countAlert = [UIAlertController alertControllerWithTitle:MTJText(@"ループ再生回数") message:nil preferredStyle:UIAlertControllerStyleAlert];
        for (NSNumber *count in @[@3, @5, @10]) {
            [countAlert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:MTJText(@"%@回"), count] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [[NSUserDefaults standardUserDefaults] setInteger:count.integerValue forKey:@"WJLoopCount"]; [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"WJLoopDuration"]; [[WaterJumpCoordinator shared] publish]; }]];
        }
        [countAlert addAction:[UIAlertAction actionWithTitle:MTJText(@"無限") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UIAlertController *timeAlert = [UIAlertController alertControllerWithTitle:MTJText(@"無限ループの時間制限") message:nil preferredStyle:UIAlertControllerStyleAlert];
            for (NSNumber *seconds in @[@0, @60, @180, @300, @600]) {
                NSString *title = seconds.integerValue == 0 ? MTJText(@"時間制限なし") : [NSString stringWithFormat:MTJText(@"%ld分"), (long)(seconds.integerValue / 60)];
                [timeAlert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [[NSUserDefaults standardUserDefaults] setInteger:-1 forKey:@"WJLoopCount"]; [[NSUserDefaults standardUserDefaults] setInteger:seconds.integerValue forKey:@"WJLoopDuration"]; [[WaterJumpCoordinator shared] publish]; }]];
            }
            [timeAlert addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
            [host presentViewController:timeAlert animated:YES completion:nil];
        }]];
        [countAlert addAction:[UIAlertAction actionWithTitle:MTJText(@"キャンセル") style:UIAlertActionStyleCancel handler:nil]];
        [host presentViewController:countAlert animated:YES completion:nil];
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
    for (NSNumber *number in @[@0, @1, @2, @4, @6, @5, @9, @12, @14]) {
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
        [WaterJumpSettingsViewController presentDurationFrom:self];
    }
    if (indexPath.section == 0 && indexPath.row == 10 && !manager.recordingBusy) {
        [WaterJumpSettingsViewController presentLoopSettingsFrom:self];
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
