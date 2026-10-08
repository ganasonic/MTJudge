#import "WaterJumpSettingsViewController.h"

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
    self.title = self.screenTitle ?: @"QRコード読み取り";

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
    hint.text = @"枠内にQRコードを合わせてください";
    hint.textAlignment = NSTextAlignmentCenter;
    hint.textColor = UIColor.secondaryLabelColor;
    hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.hintLabel = hint;
    [self.view addSubview:hint];

    self.valueField = [UITextField new];
    self.valueField.translatesAutoresizingMaskIntoConstraints = NO;
    self.valueField.borderStyle = UITextBorderStyleRoundedRect;
    self.valueField.placeholder = @"読み取れない場合は入力";
    self.valueField.text = self.initialValue;
    self.valueField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.valueField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.view addSubview:self.valueField];

    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    save.translatesAutoresizingMaskIntoConstraints = NO;
    [save setTitle:@"保存" forState:UIControlStateNormal];
    [save addTarget:self action:@selector(saveValue) forControlEvents:UIControlEventTouchUpInside];
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    [cancel setTitle:@"キャンセル" forState:UIControlStateNormal];
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
            dispatch_async(dispatch_get_main_queue(), ^{ if (granted) [weakSelf configureCaptureIfAuthorized]; else weakSelf.hintLabel.text = @"カメラの使用を許可してください。許可しない場合は下の欄へ入力してください"; });
        }];
    } else {
        [self configureCaptureIfAuthorized];
    }
}
- (void)configureCaptureIfAuthorized {
    if (self.captureSession) return;
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status != AVAuthorizationStatusAuthorized) {
        if (status == AVAuthorizationStatusDenied || status == AVAuthorizationStatusRestricted) self.hintLabel.text = @"カメラの使用を許可できないため、下の欄へ入力してください";
        return;
    }
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;
    AVCaptureDeviceInput *input = device ? [AVCaptureDeviceInput deviceInputWithDevice:device error:&error] : nil;
    AVCaptureSession *session = [AVCaptureSession new];
    if (input && [session canAddInput:input]) [session addInput:input]; else { self.hintLabel.text = @"カメラを使用できないため、下の欄へ入力してください"; return; }
    AVCaptureMetadataOutput *output = [AVCaptureMetadataOutput new];
    if (![session canAddOutput:output]) { self.hintLabel.text = @"QR読み取りを開始できません。下の欄へ入力してください"; return; }
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
    self.title = @"練習動画";
    self.gridMode = [[NSUserDefaults standardUserDefaults] boolForKey:@"WJVideoGridMode"];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"選択" style:UIBarButtonItemStylePlain target:self action:@selector(beginMultiSelect)];
    UIBarButtonItem *photo = [[UIBarButtonItem alloc] initWithTitle:@"写真" style:UIBarButtonItemStylePlain target:self action:@selector(selectPhotoVideo)];
    UIBarButtonItem *grid = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:self.gridMode ? @"list.bullet" : @"square.grid.2x2"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleGridMode)];
    grid.accessibilityLabel = @"リスト表示とサムネイル表示を切り替え";
    self.navigationItem.rightBarButtonItems = @[photo, grid];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(selectComparisonVideo:)];
    longPress.minimumPressDuration = .55;
    longPress.cancelsTouchesInView = YES;
    [self.tableView addGestureRecognizer:longPress];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshVideos) name:@"WJVideoDeleted" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshVideos) name:@"WJVideoSaved" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshVideos) name:@"WJVideoFavoritesChanged" object:nil];
    [self refreshVideos];
}
- (void)beginMultiSelect {
    self.editing = YES;
    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"キャンセル" style:UIBarButtonItemStylePlain target:self action:@selector(endMultiSelect)];
    UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareSelectedVideos)];
    UIBarButtonItem *transfer = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.doc"] style:UIBarButtonItemStylePlain target:self action:@selector(transferSelectedVideos)];
    transfer.accessibilityLabel = @"選択した動画と関連JSONをMTJudgeへ転送";
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
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"選択" style:UIBarButtonItemStylePlain target:self action:@selector(beginMultiSelect)];
    UIBarButtonItem *photo = [[UIBarButtonItem alloc] initWithTitle:@"写真" style:UIBarButtonItemStylePlain target:self action:@selector(selectPhotoVideo)];
    UIBarButtonItem *grid = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:self.gridMode ? @"list.bullet" : @"square.grid.2x2"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleGridMode)];
    grid.accessibilityLabel = @"リスト表示とサムネイル表示を切り替え";
    self.navigationItem.rightBarButtonItems = @[photo, grid];
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"転送を開始しました" message:@"選択した動画と、同じ動画名に紐づくJSONを登録済みのMTJudge端末へ転送します。受信側のRecordingsへ保存されます。" preferredStyle:UIAlertControllerStyleAlert];
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
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refreshVideos]; }
- (void)refreshVideos { if (@available(iOS 13.0, *)) { self.videos = [ReceivedVideoManager videos]; [self.tableView reloadData]; } }
- (void)toggleGridMode {
    self.gridMode = !self.gridMode;
    [[NSUserDefaults standardUserDefaults] setBool:self.gridMode forKey:@"WJVideoGridMode"];
    UIBarButtonItem *photo = [[UIBarButtonItem alloc] initWithTitle:@"写真" style:UIBarButtonItemStylePlain target:self action:@selector(selectPhotoVideo)];
    UIBarButtonItem *grid = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:self.gridMode ? @"list.bullet" : @"square.grid.2x2"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleGridMode)];
    grid.accessibilityLabel = @"リスト表示とサムネイル表示を切り替え";
    self.navigationItem.rightBarButtonItems = @[photo, grid];
    [self.tableView reloadData];
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
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f秒・%.1f MB・%@ × %@・%@ fps・%@", duration, size.doubleValue/1048576, width, height, fps, info[@"codec"] ?: @"?"];
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
    retransferButton.accessibilityLabel = @"この動画を再転送";
    retransferButton.tintColor = UIColor.systemBlueColor;
    [retransferButton setImage:[UIImage systemImageNamed:@"arrow.clockwise.icloud"] forState:UIControlStateNormal];
    [retransferButton addTarget:self action:@selector(retransferVideo:) forControlEvents:UIControlEventTouchUpInside];
    retransferButton.frame = CGRectMake(0, 0, 40, 44);
    UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    deleteButton.tag = indexPath.row;
    deleteButton.accessibilityIdentifier = url.path;
    deleteButton.accessibilityLabel = @"動画を削除";
    deleteButton.tintColor = UIColor.systemRedColor;
    [deleteButton setImage:[UIImage systemImageNamed:@"trash"] forState:UIControlStateNormal];
    [deleteButton addTarget:self action:@selector(deleteVideo:) forControlEvents:UIControlEventTouchUpInside];
    deleteButton.frame = CGRectMake(0, 0, 40, 44);
    UIButton *shareButton = [UIButton buttonWithType:UIButtonTypeSystem];
    shareButton.accessibilityIdentifier = url.path;
    shareButton.accessibilityLabel = @"動画を共有";
    shareButton.tintColor = UIColor.systemGreenColor;
    [shareButton setImage:[UIImage systemImageNamed:@"square.and.arrow.up"] forState:UIControlStateNormal];
    [shareButton addTarget:self action:@selector(shareVideo:) forControlEvents:UIControlEventTouchUpInside];
    shareButton.frame = CGRectMake(0, 0, 40, 44);
    UIButton *favoriteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    favoriteButton.accessibilityIdentifier = url.path;
    favoriteButton.accessibilityLabel = @"お気に入り";
    BOOL favorite = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"WJFavoriteVideoPaths"] containsObject:url.path];
    favoriteButton.tintColor = favorite ? UIColor.systemPinkColor : UIColor.whiteColor;
    [favoriteButton setImage:[UIImage systemImageNamed:(favorite ? @"heart.fill" : @"heart")] forState:UIControlStateNormal];
    [favoriteButton addTarget:self action:@selector(toggleFavoriteInList:) forControlEvents:UIControlEventTouchUpInside];
    favoriteButton.frame = CGRectMake(0, 0, 40, 44);
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[retransferButton, shareButton, favoriteButton, deleteButton]];
    actions.axis = UILayoutConstraintAxisHorizontal; actions.spacing = 2; actions.frame = CGRectMake(0, 0, 168, 44);
    cell.accessoryView = actions;
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
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"削除できません" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
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
    NSMutableArray *paths = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"WJFavoriteVideoPaths"] ?: @[]];
    if ([paths containsObject:path]) [paths removeObject:path]; else [paths addObject:path];
    [[NSUserDefaults standardUserDefaults] setObject:paths forKey:@"WJFavoriteVideoPaths"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WJVideoFavoritesChanged" object:[NSURL fileURLWithPath:path]];
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
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!url) return;
        WaterJumpReceivedPlayerViewController *player = [[WaterJumpReceivedPlayerViewController alloc] initWithVideoURL:url];
        [player setPlaylist:@[url] currentIndex:0];
        [self presentViewController:player animated:YES completion:^{ [player.player play]; }];
    }];
}
@end

@implementation WaterJumpSettingsViewController
+ (UIViewController *)videoLibraryViewController { return [WJVideoLibrary new]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"ウォータージャンプ";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem.accessibilityIdentifier = @"WJDone";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:WJStatusChanged object:nil];
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 60;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)refresh { [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 13;
    if (section == 1) return 9;
    if (section == 2) return 1;
    return [WaterJumpCoordinator shared].discoveredPeers.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"録画・受信設定", @"接続情報", @"動画", @"検出したカメラグループ／受信端末（選択して参加）"][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"録画・受信した動画はMTJudge/Recordingsへ保存されます。撮影と受信は別の端末でも使用できます。";
    if (section == 1) return @"同じWi-Fiで両端末を前景起動してください。接続URL・登録コードは操作を許可する相手だけに渡してください。URLはRemote Cameraの再起動で変わります。";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    WaterJumpCoordinator *manager = [WaterJumpCoordinator shared];
    if (indexPath.section == 0) {
        NSArray *names = @[@"ウォータージャンプモード", @"Remote Camera", @"Apple Watch Remote", @"録画時間", @"録画後自動転送", @"この端末で受信待機", @"タグ付け後に転送", @"転送後自動再生", @"転送先でループ再生する", @"リモートカメラ1を使う", @"ループ再生設定", @"カメラ名", @"リモートカメラ2を使う"];
        cell.textLabel.text = names[indexPath.row];
        if (indexPath.row == 3) { cell.accessibilityIdentifier = @"WJDuration"; NSInteger duration = [[NSUserDefaults standardUserDefaults] integerForKey:@"WJDuration"]; cell.detailTextLabel.text = duration > 0 ? [NSString stringWithFormat:@"%ld秒", (long)duration] : @"ー（手動停止）"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
        else if (indexPath.row == 10) {
            NSInteger count = [[NSUserDefaults standardUserDefaults] integerForKey:@"WJLoopCount"]; if (count == 0) count = 3;
            NSInteger seconds = [[NSUserDefaults standardUserDefaults] integerForKey:@"WJLoopDuration"];
            NSString *countText = count < 0 ? @"無限" : [NSString stringWithFormat:@"%ld回", (long)count];
            NSString *timeText = count < 0 ? (seconds > 0 ? [NSString stringWithFormat:@"%ld分", (long)(seconds / 60)] : @"時間制限なし") : @"";
            cell.detailTextLabel.text = timeText.length ? [NSString stringWithFormat:@"%@・%@", countText, timeText] : countText;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 11) {
            NSString *name = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJCameraName"];
            cell.detailTextLabel.text = name.length ? name : UIDevice.currentDevice.name;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            NSArray *keys = @[@"WJMode",@"WJWeb",@"WJWatch",@"WJDuration",@"WJTransfer",@"WJReceive",@"WJTagBeforeTransfer",@"WJAutoPlayAfterTransfer",@"WJLoopPlayback",@"WJUseSubCamera",@"WJLoopPlayback",@"WJCameraName",@"WJUseSubCamera2"];
            if (indexPath.row == 12) {
                UISwitch *toggle = [UISwitch new]; toggle.tag = indexPath.row; toggle.accessibilityIdentifier = keys[indexPath.row];
                toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:keys[indexPath.row]];
                toggle.enabled = !manager.recordingBusy && [[NSUserDefaults standardUserDefaults] stringForKey:@"WJSubCamera2URL"].length > 0 && [[NSUserDefaults standardUserDefaults] boolForKey:@"WJUseSubCamera"];
                [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
                return cell;
            }
            UISwitch *toggle = [UISwitch new]; toggle.tag = indexPath.row;
            toggle.accessibilityIdentifier = keys[indexPath.row];
            toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:keys[indexPath.row]];
            BOOL transferOrReceive = [[NSUserDefaults standardUserDefaults] boolForKey:@"WJTransfer"] || [[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"];
            BOOL hasSubCamera = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJSubCameraURL"].length > 0;
            toggle.enabled = !manager.recordingBusy && (indexPath.row != 6 || ([[NSUserDefaults standardUserDefaults] boolForKey:@"WJMode"] && [[NSUserDefaults standardUserDefaults] boolForKey:@"WJTransfer"])) && (indexPath.row != 7 || transferOrReceive) && (indexPath.row != 8 || [[NSUserDefaults standardUserDefaults] boolForKey:@"WJAutoPlayAfterTransfer"]) && (indexPath.row != 9 || hasSubCamera);
            if ((indexPath.row == 6 || indexPath.row == 8) && !toggle.enabled) toggle.on = NO;
            [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        }
    } else if (indexPath.section == 1) {
        NSArray *titles = @[@"状態", @"WebリモコンURL（タップでQR表示）", @"この端末の登録コード（タップでQR表示）", @"転送先", @"転送先URL登録", @"リモートカメラ1登録", @"リモートカメラ2登録", @"カメラグループ", @"同じWi-Fiのカメラグループを探す"];
        cell.textLabel.text = titles[indexPath.row];
        if (indexPath.row == 0) cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@", manager.status[@"state"], manager.status[@"message"]];
        if (indexPath.row == 1) cell.detailTextLabel.text = manager.remoteAddress.length ? manager.remoteAddress : @"Remote CameraをONにしてください";
        if (indexPath.row == 2) cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"] ? manager.pairingCode : @"受信端末で受信待機をONにしてください";
        if (indexPath.row == 3) {
            NSArray *registered = manager.registeredPeers;
            if (registered.count) {
                NSMutableArray *labels = [NSMutableArray array];
                for (NSDictionary *peer in registered) [labels addObject:[NSString stringWithFormat:@"%@%@", peer[@"name"] ?: @"端末", [peer[@"id"] isEqual:([[NSUserDefaults standardUserDefaults] stringForKey:@"WJPeerID"] ?: @"")] ? @"（選択中）" : @""]];
                cell.detailTextLabel.text = [labels componentsJoinedByString:@"\n"];
            } else cell.detailTextLabel.text = manager.peerDescription;
        }
        if (indexPath.row == 5) cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJSubCameraURL"] ?: @"未登録（リモートカメラ1のRemote Camera URLを入力）";
        if (indexPath.row == 6) {
            cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJSubCamera2URL"] ?: @"未登録";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        if (indexPath.row == 7) {
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            NSString *name = [defaults stringForKey:@"WJCameraGroupName"];
            NSString *groupID = [defaults stringForKey:@"WJCameraGroupID"];
            cell.detailTextLabel.text = name.length && groupID.length ? [NSString stringWithFormat:@"%@\n%@", name, groupID] : @"未設定（タップして作成）";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        if (indexPath.row == 8) {
            NSArray *peers = manager.discoveredPeers;
            NSMutableArray *groups = [NSMutableArray array];
            for (NSDictionary *peer in peers) {
                NSString *label = peer[@"groupName"] ?: peer[@"groupID"];
                if (label.length && ![groups containsObject:label]) [groups addObject:label];
            }
            cell.detailTextLabel.text = groups.count ? [groups componentsJoinedByString:@"、"] : @"検出中…（同じWi-Fi・受信待機を確認）";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        if (indexPath.row == 1 || indexPath.row == 2 || indexPath.row == 4 || indexPath.row == 5 || indexPath.row == 6) {
            UIButton *qr = [UIButton buttonWithType:UIButtonTypeSystem];
            [qr setImage:[UIImage systemImageNamed:@"qrcode"] forState:UIControlStateNormal];
            qr.tintColor = UIColor.secondaryLabelColor; qr.frame = CGRectMake(0, 0, 36, 36); qr.accessibilityLabel = @"QRコードを読み取る"; qr.tag = indexPath.row;
            [qr addTarget:self action:@selector(scanQRButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            cell.accessoryView = qr;
        }
    } else if (indexPath.section == 2) {
        cell.textLabel.text = @"転送を再送"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        NSDictionary *peer = manager.discoveredPeers[indexPath.row];
        NSString *group = peer[@"groupName"] ?: peer[@"groupID"];
        cell.textLabel.text = group.length ? [NSString stringWithFormat:@"%@（%@）", group, peer[@"name"] ?: @"端末"] : (peer[@"name"] ?: @"端末");
        cell.detailTextLabel.text = group.length ? [NSString stringWithFormat:@"%@\n%@", peer[@"role"] ?: @"受信端末", peer[@"id"] ?: @""] : peer[@"id"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)toggle:(UISwitch *)sender {
    NSArray *keys = @[@"WJMode",@"WJWeb",@"WJWatch",@"WJDuration",@"WJTransfer",@"WJReceive",@"WJTagBeforeTransfer",@"WJAutoPlayAfterTransfer",@"WJLoopPlayback",@"WJUseSubCamera",@"WJLoopPlayback",@"WJCameraName",@"WJUseSubCamera2"];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:sender.on forKey:keys[sender.tag]];
    if (sender.tag == 6 && sender.on && (![defaults boolForKey:@"WJMode"] || ![defaults boolForKey:@"WJTransfer"])) [defaults setBool:NO forKey:@"WJTagBeforeTransfer"];
    if (sender.tag == 7 && !sender.on) [defaults setBool:NO forKey:@"WJLoopPlayback"];
    if (sender.on && sender.tag == 5) { [defaults setBool:NO forKey:@"WJMode"]; [defaults setBool:NO forKey:@"WJTransfer"]; }
    if (sender.on && (sender.tag == 0 || sender.tag == 4)) [defaults setBool:NO forKey:@"WJReceive"];
    [[WaterJumpCoordinator shared] applySettings]; [self refresh];
}
- (void)showQRCodeForValue:(NSString *)value title:(NSString *)title {
    UIImage *image = WJQRCodeImage(value);
    if (!image) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:@"別端末のカメラで読み取ってください。" preferredStyle:UIAlertControllerStyleAlert];
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
    [alert addAction:[UIAlertAction actionWithTitle:@"閉じる" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)presentPeerScanner:(NSDictionary *)peer {
    WaterJumpCoordinator *manager = [WaterJumpCoordinator shared];
    WJQRScannerViewController *scanner = [WJQRScannerViewController new];
    scanner.screenTitle = @"転送先URL登録";
    scanner.completion = ^(NSString *code) {
        BOOL matches = !peer || [code hasPrefix:[peer[@"id"] stringByAppendingString:@":"]];
        if (!matches || ![manager registerPeer:peer[@"name"] ?: @"登録済みiPad" code:code]) {
            UIAlertController *error = [UIAlertController alertControllerWithTitle:@"登録できません" message:@"選択した端末の登録コードを確認してください。" preferredStyle:UIAlertControllerStyleAlert];
            [error addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:error animated:YES completion:nil];
        } else {
            // QR登録が成功したら、検出情報にGroup IDが欠けていても必ず役割を選択させる。
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            NSString *groupID = peer[@"groupID"];
            NSString *groupName = peer[@"groupName"] ?: peer[@"name"];
            if (groupID.length) [defaults setObject:groupID forKey:@"WJCameraGroupID"];
            if (groupName.length) [defaults setObject:groupName forKey:@"WJCameraGroupName"];
            UIAlertController *role = [UIAlertController alertControllerWithTitle:@"カメラ役割" message:@"この端末の役割を選択してください。" preferredStyle:UIAlertControllerStyleActionSheet];
            for (NSDictionary *choice in @[@{@"title":@"カメラ1", @"role":@"MAIN_CAMERA"}, @{@"title":@"カメラ2", @"role":@"SUB_CAMERA"}, @{@"title":@"カメラ3", @"role":@"SUB_CAMERA"}]) {
                [role addAction:[UIAlertAction actionWithTitle:choice[@"title"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [defaults setObject:choice[@"role"] forKey:@"WJCameraRole"];
                    [[WaterJumpCoordinator shared] applySettings];
                    [self refresh];
                }]];
            }
            [role addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:role animated:YES completion:nil];
        }
    };
    scanner.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:scanner animated:YES completion:nil];
}
- (void)presentSubCameraScanner {
    [self presentSubCameraScannerForKey:@"WJSubCameraURL" title:@"リモートカメラ1登録"];
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
- (void)scanQRButtonTapped:(UIButton *)sender {
    WaterJumpCoordinator *manager = [WaterJumpCoordinator shared];
    if (sender.tag == 1 && manager.remoteAddress.length) { UIPasteboard.generalPasteboard.string = manager.remoteAddress; [self showQRCodeForValue:manager.remoteAddress title:@"WebリモコンURL"]; }
    else if (sender.tag == 2 && [[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"]) { UIPasteboard.generalPasteboard.string = manager.pairingCode; [self showQRCodeForValue:manager.pairingCode title:@"この端末の登録コード"]; }
    else if (sender.tag == 4) [self presentPeerScanner:nil];
    else if (sender.tag == 5) [self presentSubCameraScanner];
    else if (sender.tag == 6) [self presentSubCameraScannerForKey:@"WJSubCamera2URL" title:@"リモートカメラ2登録"];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    WaterJumpCoordinator *manager = [WaterJumpCoordinator shared];
    if (indexPath.section == 0 && indexPath.row == 3 && !manager.recordingBusy) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"録画時間" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"ー（手動停止）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[NSUserDefaults standardUserDefaults] setDouble:0 forKey:@"WJDuration"]; [manager applySettings]; [self refresh];
        }]];
        for (NSNumber *seconds in @[@10,@15,@20,@30,@45,@60]) [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@秒",seconds] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[NSUserDefaults standardUserDefaults] setObject:seconds forKey:@"WJDuration"]; [manager applySettings];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
    }
    if (indexPath.section == 0 && indexPath.row == 10 && !manager.recordingBusy) {
        UIAlertController *countAlert = [UIAlertController alertControllerWithTitle:@"ループ再生回数" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSNumber *count in @[@3, @5, @10]) {
            [countAlert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@回", count] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [[NSUserDefaults standardUserDefaults] setInteger:count.integerValue forKey:@"WJLoopCount"]; [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"WJLoopDuration"]; [self refresh]; }]];
        }
        [countAlert addAction:[UIAlertAction actionWithTitle:@"無限" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UIAlertController *timeAlert = [UIAlertController alertControllerWithTitle:@"無限ループの時間制限" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            for (NSNumber *seconds in @[@0, @60, @180, @300, @600]) {
                NSString *title = seconds.integerValue == 0 ? @"時間制限なし" : [NSString stringWithFormat:@"%ld分", (long)(seconds.integerValue / 60)];
                [timeAlert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [[NSUserDefaults standardUserDefaults] setInteger:-1 forKey:@"WJLoopCount"]; [[NSUserDefaults standardUserDefaults] setInteger:seconds.integerValue forKey:@"WJLoopDuration"]; [self refresh]; }]];
            }
            [timeAlert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:timeAlert animated:YES completion:nil];
        }]];
        [countAlert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:countAlert animated:YES completion:nil];
    }
    if (indexPath.section == 0 && indexPath.row == 11 && !manager.recordingBusy) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"カメラ名" message:@"動画情報と端末間転送のメタデータに使用します。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = UIDevice.currentDevice.name;
            field.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJCameraName"];
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (name.length) [[NSUserDefaults standardUserDefaults] setObject:name forKey:@"WJCameraName"];
            else [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"WJCameraName"];
            [self refresh];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    if (indexPath.section == 1 && indexPath.row == 7) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"カメラグループ" message:@"同じグループIDの端末だけが録画・転送対象になります。空欄でグループ設定を解除します。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = @"例：Aグループ";
            field.text = [defaults stringForKey:@"WJCameraGroupName"];
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
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
        UIAlertController *groups = [UIAlertController alertControllerWithTitle:@"カメラグループを選択" message:@"同じWi-Fi上で検出されたグループです。選択すると登録コードの読み取りへ進みます。" preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSDictionary *peer in peers) {
            NSString *group = peer[@"groupName"] ?: peer[@"groupID"];
            if (!group.length) continue;
            NSString *title = [NSString stringWithFormat:@"%@（%@）", group, peer[@"name"] ?: @"端末"];
            [groups addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self presentPeerScanner:peer]; }]];
        }
        if (!groups.actions.count) [groups addAction:[UIAlertAction actionWithTitle:@"検出されていません" style:UIAlertActionStyleDefault handler:nil]];
        [groups addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:groups animated:YES completion:nil];
    }
    if (indexPath.section == 1 && indexPath.row == 1 && manager.remoteAddress.length) { UIPasteboard.generalPasteboard.string = manager.remoteAddress; [self showQRCodeForValue:manager.remoteAddress title:@"WebリモコンURL"]; }
    if (indexPath.section == 1 && indexPath.row == 2 && [[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"]) { UIPasteboard.generalPasteboard.string = manager.pairingCode; [self showQRCodeForValue:manager.pairingCode title:@"この端末の登録コード"]; }
    if (indexPath.section == 2 && indexPath.row == 0) [manager retryTransfer];
    if ((indexPath.section == 1 && indexPath.row == 4) || indexPath.section == 3) {
        NSDictionary *peer = indexPath.section == 3 ? manager.discoveredPeers[indexPath.row] : nil;
        [self presentPeerScanner:peer];
    }
    if (indexPath.section == 1 && indexPath.row == 5) {
        [self presentSubCameraScanner];
    }
    if (indexPath.section == 1 && indexPath.row == 6) {
        [self presentSubCameraScannerForKey:@"WJSubCamera2URL" title:@"リモートカメラ2登録"];
    }
}
@end
