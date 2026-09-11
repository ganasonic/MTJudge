//
//  DMViewController.h
//  MTJudge
//
//  Created by Yasunori Nagashima on 2025/08/12.
//  Copyright © 2025 Yasunori Nagashima. All rights reserved.
//

#import <UIKit/UIKit.h>
@interface DMViewController : UIViewController
@property (weak, nonatomic) IBOutlet UISegmentedControl *numOfJudge;
@property (weak, nonatomic) IBOutlet UISegmentedControl *maxOfPoint;
@property (weak, nonatomic) IBOutlet UISegmentedControl *judgePoint1;
@property (weak, nonatomic) IBOutlet UISegmentedControl *judgePoint2;
@property (weak, nonatomic) IBOutlet UISegmentedControl *judgePoint3;
@property (weak, nonatomic) IBOutlet UISegmentedControl *judgePoint4;
@property (weak, nonatomic) IBOutlet UISegmentedControl *judgePoint5;
@property (weak, nonatomic) IBOutlet UISegmentedControl *judgePoint6;
@property (weak, nonatomic) IBOutlet UISegmentedControl *judgePoint7;
@property (weak, nonatomic) IBOutlet UILabel *label1;
@property (weak, nonatomic) IBOutlet UILabel *label2;
@property (weak, nonatomic) IBOutlet UILabel *label3;
@property (weak, nonatomic) IBOutlet UILabel *label4;
@property (weak, nonatomic) IBOutlet UILabel *label5;
@property (weak, nonatomic) IBOutlet UILabel *label6;
@property (weak, nonatomic) IBOutlet UILabel *label7;
@property (weak, nonatomic) IBOutlet UILabel *blue;
@property (weak, nonatomic) IBOutlet UILabel *red;
@property (weak, nonatomic) IBOutlet UISwitch *tieAir;
@property (weak, nonatomic) IBOutlet UISwitch *tieSpeed;
@property (weak, nonatomic) IBOutlet UILabel *blueWin;
@property (weak, nonatomic) IBOutlet UILabel *redWin;
@property (weak, nonatomic) IBOutlet UIButton *clearBtn;
@property (weak, nonatomic) IBOutlet UILabel *tieStr;

-(void)score;
-(void)setSverallSegment;
-(float)maxVotes;

@end

