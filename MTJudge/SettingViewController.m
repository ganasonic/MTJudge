//
//  SettingViewController.m
//  MTJudge
//
//  Created by Yasunori Nagashima on 2025/08/17.
//  Copyright © 2025 Yasunori Nagashima. All rights reserved.
//

#include "Common.h"
#import "SettingViewController.h"
#import "WaterJump/WaterJumpSettingsViewController.h"

float F_SpeedPerSec;
float M_SpeedPerSec;

@implementation SettingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    UIButton *waterJump = [UIButton buttonWithType:UIButtonTypeSystem];
    [waterJump setTitle:@"ウォータージャンプ / リモート録画" forState:UIControlStateNormal];
    waterJump.translatesAutoresizingMaskIntoConstraints = NO;
    [waterJump addTarget:self action:@selector(openWaterJump) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:waterJump];
    [NSLayoutConstraint activateConstraints:@[
        [waterJump.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [waterJump.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [waterJump.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [waterJump.heightAnchor constraintEqualToConstant:44]
    ]];
 
    // 文字列を読み込む
    NSString *psFemale = [[NSUserDefaults standardUserDefaults] stringForKey:@"psFemale"];
    NSString *psMale = [[NSUserDefaults standardUserDefaults] stringForKey:@"psMale"];
    if (psFemale == nil) {
        // 値がnilの場合、デフォルト値として10.3を設定
        F_SpeedPerSec = 9.0f;
    } else {
        // 値が存在する場合、その値をfloatに変換して使用
        F_SpeedPerSec = [psFemale floatValue];
    }
    if (psMale == nil) {
        // 値がnilの場合、デフォルト値として10.3を設定
        M_SpeedPerSec = 10.3f;
    } else {
        // 値が存在する場合、その値をfloatに変換して使用
        M_SpeedPerSec = [psMale floatValue];
    }
    self.psFemale.text = [NSString stringWithFormat:@"%.1f", (float)F_SpeedPerSec];
    self.psMale.text = [NSString stringWithFormat:@"%.1f", (float)M_SpeedPerSec];
	//キーパッドを消すため
    self.psFemale.delegate = self;
    self.psMale.delegate = self;
 }

- (void)openWaterJump {
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:[WaterJumpSettingsViewController new]] animated:YES completion:nil];
}
- (IBAction)applyPasesetTime:(id)sender {
    NSString *psFemaleValue = self.psFemale.text;
    NSString *psMaleValue = self.psMale.text;
    // 文字列を保存
    [[NSUserDefaults standardUserDefaults] setObject:psFemaleValue forKey:@"psFemale"];
    [[NSUserDefaults standardUserDefaults] setObject:psMaleValue forKey:@"psMale"];

    // 変更を即座にディスクに書き込む
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (IBAction)onChangePaseTimeFemale:(id)sender {
    NSString *psFemaleValue = self.psFemale.text;
    // 文字列を保存
    [[NSUserDefaults standardUserDefaults] setObject:psFemaleValue forKey:@"psFemale"];
    // 変更を即座にディスクに書き込む
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (IBAction)onChangePaseTimeMale:(id)sender {
    NSString *psMaleValue = self.psMale.text;
    // 文字列を保存
    [[NSUserDefaults standardUserDefaults] setObject:psMaleValue forKey:@"psMale"];
    // 変更を即座にディスクに書き込む
    [[NSUserDefaults standardUserDefaults] synchronize];
}

-(BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
