//
//  SettingViewController.h
//  MTJudge
//
//  Created by Yasunori Nagashima on 2025/08/17.
//  Copyright © 2025 Yasunori Nagashima. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SettingViewController : UIViewController<UITextFieldDelegate>

@property (weak, nonatomic) IBOutlet UITextField *psFemale;
@property (weak, nonatomic) IBOutlet UITextField *psMale;

@end
