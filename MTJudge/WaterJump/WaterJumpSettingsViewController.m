#import "WaterJumpSettingsViewController.h"
#import "WaterJumpCoordinator.h"
#import "MTJudge-Swift.h"
#import <AVKit/AVKit.h>

@interface WJVideoLibrary : UITableViewController
@property (nonatomic, strong) NSArray<NSURL *> *videos;
@end
@implementation WJVideoLibrary
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"練習動画"; if (@available(iOS 13.0, *)) self.videos = [ReceivedVideoManager videos]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.videos.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSURL *url = self.videos[indexPath.row];
    NSDictionary *info = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[url URLByAppendingPathExtension:@"wj.json"]] ?: [NSData data] options:0 error:nil];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[info[@"created"] doubleValue]];
    cell.textLabel.text = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f秒・%.1f MB・%@ × %@・%@ fps・%@", [info[@"duration"] doubleValue], [info[@"size"] doubleValue]/1048576, info[@"width"] ?: @"?", info[@"height"] ?: @"?", info[@"fps"] ?: @"?", info[@"codec"] ?: @"?"];
    cell.detailTextLabel.numberOfLines = 0; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    AVPlayerViewController *player = [AVPlayerViewController new]; player.player = [AVPlayer playerWithURL:self.videos[indexPath.row]];
    [self presentViewController:player animated:YES completion:^{ [player.player play]; }];
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
    if (section == 0) return 6;
    if (section == 1) return 5;
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
        NSArray *names = @[@"ウォータージャンプモード", @"Remote Camera", @"Apple Watch Remote", @"録画時間", @"録画後自動転送", @"この端末で受信待機"];
        cell.textLabel.text = names[indexPath.row];
        if (indexPath.row == 3) { cell.accessibilityIdentifier = @"WJDuration"; cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld秒", (long)[[NSUserDefaults standardUserDefaults] integerForKey:@"WJDuration"]]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
        else {
            NSArray *keys = @[@"WJMode",@"WJWeb",@"WJWatch",@"WJDuration",@"WJTransfer",@"WJReceive"];
            UISwitch *toggle = [UISwitch new]; toggle.tag = indexPath.row;
            toggle.accessibilityIdentifier = keys[indexPath.row];
            toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:keys[indexPath.row]];
            toggle.enabled = !manager.recordingBusy;
            [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        }
    } else if (indexPath.section == 1) {
        NSArray *titles = @[@"状態", @"WebリモコンURL（タップでコピー）", @"この端末の登録コード（タップでコピー）", @"転送先", @"登録コードを入力して転送先を登録"];
        cell.textLabel.text = titles[indexPath.row];
        if (indexPath.row == 0) cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@", manager.status[@"state"], manager.status[@"message"]];
        if (indexPath.row == 1) cell.detailTextLabel.text = manager.remoteAddress.length ? manager.remoteAddress : @"Remote CameraをONにしてください";
        if (indexPath.row == 2) cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] boolForKey:@"WJReceive"] ? manager.pairingCode : @"受信端末で受信待機をONにしてください";
        if (indexPath.row == 3) cell.detailTextLabel.text = manager.peerDescription;
    } else if (indexPath.section == 2) {
        cell.textLabel.text = indexPath.row == 0 ? @"転送を再送" : @"保存・受信した練習動画を見る"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        NSDictionary *peer = manager.discoveredPeers[indexPath.row]; cell.textLabel.text = peer[@"name"]; cell.detailTextLabel.text = peer[@"id"]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)toggle:(UISwitch *)sender {
    NSArray *keys = @[@"WJMode",@"WJWeb",@"WJWatch",@"WJDuration",@"WJTransfer",@"WJReceive"];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:sender.on forKey:keys[sender.tag]];
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
}
@end
