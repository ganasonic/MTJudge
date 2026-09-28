#import "WaterJumpSettingsViewController.h"
#import "WaterJumpCoordinator.h"
#import "MTJudge-Swift.h"
#import "WaterJumpReceivedPlayerViewController.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

@interface WJVideoLibrary : UITableViewController
@property (nonatomic, strong) NSArray<NSURL *> *videos;
@end
@implementation WJVideoLibrary
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"練習動画"; [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshVideos) name:@"WJVideoDeleted" object:nil]; [self refreshVideos]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self name:@"WJVideoDeleted" object:nil]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refreshVideos]; }
- (void)refreshVideos { if (@available(iOS 13.0, *)) { self.videos = [ReceivedVideoManager videos]; [self.tableView reloadData]; } }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.videos.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSURL *url = self.videos[indexPath.row];
    NSDictionary *info = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[url URLByAppendingPathExtension:@"wj.json"]] ?: [NSData data] options:0 error:nil];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[info[@"created"] doubleValue]];
    cell.textLabel.text = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f秒・%.1f MB・%@ × %@・%@ fps・%@", [info[@"duration"] doubleValue], [info[@"size"] doubleValue]/1048576, info[@"width"] ?: @"?", info[@"height"] ?: @"?", info[@"fps"] ?: @"?", info[@"codec"] ?: @"?"];
    cell.detailTextLabel.numberOfLines = 0;
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:[AVAsset assetWithURL:url]];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(160, 100);
    CGImageRef imageRef = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
    if (imageRef) { cell.imageView.image = [UIImage imageWithCGImage:imageRef]; CGImageRelease(imageRef); }
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
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[retransferButton, shareButton, deleteButton]];
    actions.axis = UILayoutConstraintAxisHorizontal; actions.spacing = 2; actions.frame = CGRectMake(0, 0, 126, 44);
    cell.accessoryView = actions;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    WaterJumpReceivedPlayerViewController *player = [[WaterJumpReceivedPlayerViewController alloc] initWithVideoURL:self.videos[indexPath.row]];
    [player setPlaylist:self.videos currentIndex:indexPath.row];
    [self presentViewController:player animated:YES completion:^{ [player.player play]; }];
}
- (void)deleteVideo:(UIButton *)sender {
    NSURL *url = sender.accessibilityIdentifier.length ? [NSURL fileURLWithPath:sender.accessibilityIdentifier] : nil;
    NSInteger row = [self.videos indexOfObject:url];
    if (!url || row == NSNotFound || ![url.pathExtension.lowercaseString isEqualToString:@"mov"]) return;
    NSError *error = nil;
    NSFileManager *files = NSFileManager.defaultManager;
    NSArray<NSURL *> *targets = @[url, [url URLByAppendingPathExtension:@"wj.json"], [url URLByAppendingPathExtension:@"tags.json"], [url URLByAppendingPathExtension:@"pose.json"]];
    for (NSURL *target in targets) {
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
@end

@implementation WaterJumpSettingsViewController
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
    if (section == 0) return 9;
    if (section == 1) return 6;
    if (section == 2) return 2;
    return [WaterJumpCoordinator shared].discoveredPeers.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"録画・受信設定", @"接続情報", @"動画", @"検出した受信端末（選択して登録）"][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"通常録画は従来通りダウンロードへ保存します。ウォータージャンプ録画と受信動画はDocuments/Recordingsへ自動保存します。撮影と受信は別の端末で行ってください。";
    if (section == 1) return @"同じWi-Fiで両端末を前景起動してください。接続URL・登録コードは操作を許可する相手だけに渡してください。URLはRemote Cameraの再起動で変わります。";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    WaterJumpCoordinator *manager = [WaterJumpCoordinator shared];
    if (indexPath.section == 0) {
        NSArray *names = @[@"ウォータージャンプモード", @"Remote Camera", @"Apple Watch Remote", @"録画時間", @"録画後自動転送", @"この端末で受信待機", @"タグ付け後に転送", @"転送先でループ再生する", @"ループ再生設定"];
        cell.textLabel.text = names[indexPath.row];
        if (indexPath.row == 3) { cell.accessibilityIdentifier = @"WJDuration"; cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld秒", (long)[[NSUserDefaults standardUserDefaults] integerForKey:@"WJDuration"]]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
        else if (indexPath.row == 8) {
            NSInteger count = [[NSUserDefaults standardUserDefaults] integerForKey:@"WJLoopCount"]; if (count == 0) count = 3;
            NSInteger seconds = [[NSUserDefaults standardUserDefaults] integerForKey:@"WJLoopDuration"];
            NSString *countText = count < 0 ? @"無限" : [NSString stringWithFormat:@"%ld回", (long)count];
            NSString *timeText = count < 0 ? (seconds > 0 ? [NSString stringWithFormat:@"%ld分", (long)(seconds / 60)] : @"時間制限なし") : @"";
            cell.detailTextLabel.text = timeText.length ? [NSString stringWithFormat:@"%@・%@", countText, timeText] : countText;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            NSArray *keys = @[@"WJMode",@"WJWeb",@"WJWatch",@"WJDuration",@"WJTransfer",@"WJReceive",@"WJTagBeforeTransfer",@"WJLoopPlayback"];
            UISwitch *toggle = [UISwitch new]; toggle.tag = indexPath.row;
            toggle.accessibilityIdentifier = keys[indexPath.row];
            toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:keys[indexPath.row]];
            toggle.enabled = !manager.recordingBusy && (indexPath.row != 6 || ([[NSUserDefaults standardUserDefaults] boolForKey:@"WJMode"] && [[NSUserDefaults standardUserDefaults] boolForKey:@"WJTransfer"])) && (indexPath.row != 7 || [[NSUserDefaults standardUserDefaults] boolForKey:@"WJTransfer"]);
            if ((indexPath.row == 6 || indexPath.row == 7) && !toggle.enabled) toggle.on = NO;
            [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        }
    } else if (indexPath.section == 1) {
        NSArray *titles = @[@"状態", @"WebリモコンURL（タップでコピー）", @"この端末の登録コード（タップでコピー）", @"転送先", @"登録コードを入力して転送先を登録", @"2台目撮影用iPhone Remote URL"];
        cell.textLabel.text = titles[indexPath.row];
        if (indexPath.row == 0) cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@", manager.status[@"state"], manager.status[@"message"]];
        if (indexPath.row == 1) cell.detailTextLabel.text = manager.remoteAddress.length ? manager.remoteAddress : @"Remote CameraをONにしてください";
        if (indexPath.row == 2) cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"] ? manager.pairingCode : @"受信端末で受信待機をONにしてください";
        if (indexPath.row == 3) cell.detailTextLabel.text = manager.peerDescription;
        if (indexPath.row == 5) cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJSubCameraURL"] ?: @"未登録（2台目iPhoneのRemote Camera URLを入力）";
    } else if (indexPath.section == 2) {
        cell.textLabel.text = indexPath.row == 0 ? @"転送を再送" : @"保存・受信した練習動画を見る"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        NSDictionary *peer = manager.discoveredPeers[indexPath.row]; cell.textLabel.text = peer[@"name"]; cell.detailTextLabel.text = peer[@"id"]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)toggle:(UISwitch *)sender {
    NSArray *keys = @[@"WJMode",@"WJWeb",@"WJWatch",@"WJDuration",@"WJTransfer",@"WJReceive",@"WJTagBeforeTransfer",@"WJLoopPlayback"];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:sender.on forKey:keys[sender.tag]];
    if (sender.tag == 6 && sender.on && (![defaults boolForKey:@"WJMode"] || ![defaults boolForKey:@"WJTransfer"])) [defaults setBool:NO forKey:@"WJTagBeforeTransfer"];
    if (sender.on && sender.tag == 5) { [defaults setBool:NO forKey:@"WJMode"]; [defaults setBool:NO forKey:@"WJTransfer"]; }
    if (sender.on && (sender.tag == 0 || sender.tag == 4)) [defaults setBool:NO forKey:@"WJReceive"];
    [[WaterJumpCoordinator shared] applySettings]; [self refresh];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    WaterJumpCoordinator *manager = [WaterJumpCoordinator shared];
    if (indexPath.section == 0 && indexPath.row == 3 && !manager.recordingBusy) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"録画時間" message:nil preferredStyle:UIAlertControllerStyleAlert];
        for (NSNumber *seconds in @[@10,@15,@20,@30,@45,@60]) [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@秒",seconds] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[NSUserDefaults standardUserDefaults] setObject:seconds forKey:@"WJDuration"]; [manager applySettings];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
    }
    if (indexPath.section == 0 && indexPath.row == 8 && !manager.recordingBusy) {
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
    if (indexPath.section == 1 && indexPath.row == 1 && manager.remoteAddress.length) UIPasteboard.generalPasteboard.string = manager.remoteAddress;
    if (indexPath.section == 1 && indexPath.row == 2 && [[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"]) UIPasteboard.generalPasteboard.string = manager.pairingCode;
    if (indexPath.section == 2 && indexPath.row == 0) [manager retryTransfer];
    if (indexPath.section == 2 && indexPath.row == 1) [self.navigationController pushViewController:[WJVideoLibrary new] animated:YES];
    if ((indexPath.section == 1 && indexPath.row == 4) || indexPath.section == 3) {
        NSDictionary *peer = indexPath.section == 3 ? manager.discoveredPeers[indexPath.row] : nil;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"転送先登録" message:@"iPadの設定画面に表示された登録コードを入力・貼り付けしてください。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"登録コード"; field.autocorrectionType = UITextAutocorrectionTypeNo; field.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"登録" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *code = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            BOOL matches = !peer || [code hasPrefix:[peer[@"id"] stringByAppendingString:@":"]];
            if (!matches || ![manager registerPeer:peer[@"name"] ?: @"登録済みiPad" code:code]) {
                UIAlertController *error = [UIAlertController alertControllerWithTitle:@"登録できません" message:@"選択した端末の登録コードを確認してください。" preferredStyle:UIAlertControllerStyleAlert];
                [error addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:error animated:YES completion:nil];
            }
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    if (indexPath.section == 1 && indexPath.row == 5) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"2台目撮影用iPhone" message:@"2台目iPhoneでRemote CameraをONにして表示されたURL（末尾の#を含む）を入力してください。START/STOPをメイン端末から同期送信します。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"http://192.168.x.x:8765/#..."; field.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"WJSubCameraURL"]; field.autocorrectionType = UITextAutocorrectionTypeNo; field.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *url = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (url.length) [[NSUserDefaults standardUserDefaults] setObject:url forKey:@"WJSubCameraURL"]; else [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"WJSubCameraURL"];
            [self refresh];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end
