//
//  SettingViewController.m
//  MTJudge
//
//  Created by Yasunori Nagashima on 2025/08/17.
//  Copyright © 2025 Yasunori Nagashima. All rights reserved.
//

#include "Common.h"
#import "SettingViewController.h"
#import "MTJLocalization.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "WaterJump/WaterJumpSettingsViewController.h"

float F_SpeedPerSec;
float M_SpeedPerSec;

@interface SettingViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UISegmentedControl *languageControl;
@property (nonatomic, strong) UISwitch *onlineSwitch;
@property (nonatomic, strong) UITextField *apiField;
@property (nonatomic, strong) UIView *apiSection;
@end

@implementation SettingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildSettingsView];
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

- (UILabel *)settingLabel:(NSString *)text {
    UILabel *label = [UILabel new]; label.text = text; label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}
- (UIButton *)settingButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return button;
}
- (UIStackView *)settingRow:(NSString *)title control:(UIView *)control {
    UILabel *label = [self settingLabel:title];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label,control]];
    row.axis = UILayoutConstraintAxisHorizontal; row.alignment = UIStackViewAlignmentCenter; row.spacing = 12;
    [control setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [control setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [row.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return row;
}
- (UITextField *)paceFieldWithAction:(SEL)action {
    UITextField *field = [UITextField new]; field.borderStyle = UITextBorderStyleRoundedRect;
    field.keyboardType = UIKeyboardTypeDecimalPad; field.textAlignment = NSTextAlignmentRight;
    [field.widthAnchor constraintEqualToConstant:100].active = YES;
    [field addTarget:self action:action forControlEvents:UIControlEventEditingDidEnd];
    field.delegate = self;
    return field;
}
- (void)buildSettingsView {
    // Replace only this screen's fixed storyboard layout with a scrolling form.
    // Existing pace fields keep the same persistence keys and actions.
    self.view = [UIView new]; self.view.backgroundColor = UIColor.systemBackgroundColor;
    UIScrollView *scroll = [UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scroll];
    UIStackView *stack = [UIStackView new]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO; [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]
    ]];
    [stack addArrangedSubview:[self settingLabel:@"Language"]];
    self.languageControl = [[UISegmentedControl alloc] initWithItems:@[@"日本語", @"English"]];
    self.languageControl.accessibilityIdentifier = @"MTJLanguage";
    self.languageControl.selectedSegmentIndex = [[MTJLocalization language] isEqual:@"ja"] ? 0 : 1;
    [self.languageControl addTarget:self action:@selector(changeLanguage:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.languageControl];
    self.onlineSwitch = [UISwitch new]; self.onlineSwitch.accessibilityIdentifier = @"MTJOnlineJudging";
    self.onlineSwitch.on = [NSUserDefaults.standardUserDefaults boolForKey:@"MTJOnlineJudging"];
    [self.onlineSwitch addTarget:self action:@selector(changeOnlineJudging:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:[self settingRow:@"Online judging" control:self.onlineSwitch]];
    self.apiField = [UITextField new]; self.apiField.borderStyle = UITextBorderStyleRoundedRect;
    self.apiField.autocorrectionType = UITextAutocorrectionTypeNo; self.apiField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.apiField.accessibilityIdentifier = @"MTJAPICommand";
    self.apiField.text = [NSUserDefaults.standardUserDefaults stringForKey:@"MTJAPICommand"] ?: @"";
    self.apiField.delegate = self; self.apiField.returnKeyType = UIReturnKeyDone;
    [self.apiField addTarget:self action:@selector(saveAPICommand:) forControlEvents:UIControlEventEditingChanged];
    UIStackView *api = [[UIStackView alloc] initWithArrangedSubviews:@[[self settingLabel:@"API command"],self.apiField]];
    api.axis = UILayoutConstraintAxisVertical; api.spacing = 8; self.apiSection = api;
    api.hidden = !self.onlineSwitch.on; [stack addArrangedSubview:api];
    [stack addArrangedSubview:[self settingLabel:@"Pase set time"]];
    UITextField *female = [self paceFieldWithAction:@selector(onChangePaseTimeFemale:)];
    [stack addArrangedSubview:[self settingRow:@"Female" control:female]]; self.psFemale = female;
    UITextField *male = [self paceFieldWithAction:@selector(onChangePaseTimeMale:)];
    [stack addArrangedSubview:[self settingRow:@"Male" control:male]]; self.psMale = male;
    [stack addArrangedSubview:[self settingLabel:@"m/sec"]];
    [stack addArrangedSubview:[self settingButton:@"Apply" action:@selector(applyPasesetTime:)]];
    [stack addArrangedSubview:[self settingButton:@"事前タグ選択" action:@selector(editDefaultTags)]];
    [stack addArrangedSubview:[self settingButton:@"リモート操作モード" action:@selector(openWaterJump)]];
    [stack addArrangedSubview:[self settingButton:@"Import language JSON" action:@selector(importLanguageJSON)]];
    [stack addArrangedSubview:[self settingButton:@"Reload language JSON" action:@selector(reloadLanguageJSON)]];
    [stack addArrangedSubview:[self settingLabel:@"Edit MTJLanguages.json in the MTJudge folder, then reload; or import a JSON file."]];
    MTJLocalizeView(self.view);
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; MTJLocalizeView(self.view); }
- (void)changeLanguage:(UISegmentedControl *)sender {
    [self.view endEditing:YES];
    [MTJLocalization setLanguage:sender.selectedSegmentIndex == 0 ? @"ja" : @"en"];
}
- (void)changeOnlineJudging:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"MTJOnlineJudging"];
    if (!sender.on) [self.apiField resignFirstResponder];
    self.apiSection.hidden = !sender.on;
}
- (void)saveAPICommand:(UITextField *)sender { [NSUserDefaults.standardUserDefaults setObject:sender.text ?: @"" forKey:@"MTJAPICommand"]; }
- (void)showLanguageResult:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTJText(error ? @"Could not load language file" : @"Language file loaded") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)reloadLanguageJSON { NSError *error = nil; [MTJLocalization reload:&error]; [self showLanguageResult:error]; }
- (void)importLanguageJSON {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (!url) return;
    BOOL access = [url startAccessingSecurityScopedResource];
    NSError *error = nil; [MTJLocalization importURL:url error:&error];
    if (access) [url stopAccessingSecurityScopedResource];
    [controller dismissViewControllerAnimated:YES completion:^{ [self showLanguageResult:error]; }];
}

- (void)editCameraName { [WaterJumpSettingsViewController presentCameraNameFrom:self]; }
- (void)editDefaultTags { [WaterJumpSettingsViewController presentDefaultTagsFrom:self]; }
- (void)editRecordingDuration { [WaterJumpSettingsViewController presentDurationFrom:self]; }
- (void)openWaterJump {
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:[WaterJumpSettingsViewController remoteSetupViewController]] animated:YES completion:nil];
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
