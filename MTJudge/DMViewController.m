//
//  DMViewController.m
//  MTJudge
//
//  Created by Yasunori Nagashima on 2025/08/12.
//  Copyright © 2025 Yasunori Nagashima. All rights reserved.
//

#include "Common.h"
#import "DMViewController.h"

@implementation DMViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 切り替え用セグメントの値が変わったらメソッド呼び出し
    [self.maxOfPoint addTarget:self action:@selector(maxChanged:) forControlEvents:UIControlEventValueChanged];
    [self.numOfJudge addTarget:self action:@selector(judgeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.maxOfPoint addTarget:self action:@selector(score) forControlEvents:UIControlEventValueChanged];
    [self.numOfJudge addTarget:self action:@selector(score) forControlEvents:UIControlEventValueChanged];

    // judgePoint1が変更されたらscoreメソッドを呼び出す
    [self.judgePoint1 addTarget:self action:@selector(score) forControlEvents:UIControlEventValueChanged];
    [self.judgePoint2 addTarget:self action:@selector(score) forControlEvents:UIControlEventValueChanged];
    [self.judgePoint3 addTarget:self action:@selector(score) forControlEvents:UIControlEventValueChanged];
    [self.judgePoint4 addTarget:self action:@selector(score) forControlEvents:UIControlEventValueChanged];
    [self.judgePoint5 addTarget:self action:@selector(score) forControlEvents:UIControlEventValueChanged];
    [self.judgePoint6 addTarget:self action:@selector(score) forControlEvents:UIControlEventValueChanged];
    [self.judgePoint7 addTarget:self action:@selector(score) forControlEvents:UIControlEventValueChanged];

    [self.tieAir addTarget:self action:@selector(tieAirChanged:) forControlEvents:UIControlEventValueChanged];
    [self.tieSpeed addTarget:self action:@selector(tieSpeedChanged:) forControlEvents:UIControlEventValueChanged];

    self.judgePoint6.hidden = YES;
    self.judgePoint7.hidden = YES;
    self.label6.hidden = YES;
    self.label7.hidden = YES;

    self.tieStr.hidden = YES;
    self.blueWin.hidden = YES;
    self.redWin.hidden = YES;

    [self judgeChanged:self.numOfJudge];
    [self score];
}

- (void)tieAirChanged:(UISegmentedControl *)sender {
    if (self.tieAir.isOn) {
        //5 Judge
        if (_numOfJudge.selectedSegmentIndex == 0) {
            self.judgePoint3.selectedSegmentIndex = 0;
            self.judgePoint3.enabled = NO;
            self.judgePoint5.enabled = YES;
         //7 Judge
        } else {
            [self.judgePoint5 removeAllSegments];
            for (int i = 0; i <= 5; i++) {
                [self.judgePoint5 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
            }
            self.judgePoint3.enabled = YES;
            self.judgePoint5.selectedSegmentIndex = 0;
            self.judgePoint5.enabled = NO;
            self.judgePoint6.selectedSegmentIndex = 0;
            self.judgePoint6.enabled = NO;
        }
    }else{
        //5 Judge
        if (_numOfJudge.selectedSegmentIndex == 0) {
            self.judgePoint3.enabled = YES;
            //7 Judge
        } else {
            self.judgePoint5.enabled = YES;
            self.judgePoint6.enabled = YES;
        }
    }
    [self setSverallSegment];
    [self score];
}

- (void)tieSpeedChanged:(UISegmentedControl *)sender {
    if (self.tieSpeed.isOn) {
        //5 Judge
        if (_numOfJudge.selectedSegmentIndex == 0) {
            self.judgePoint4.selectedSegmentIndex = 3;
            self.judgePoint4.enabled = NO;
            //7 Judge
        } else {
            self.judgePoint4.enabled = YES;
            self.judgePoint7.selectedSegmentIndex = 3;
            self.judgePoint7.enabled = NO;
        }
    }else{
        //5 Judge
        if (_numOfJudge.selectedSegmentIndex == 0) {
            self.judgePoint4.enabled = YES;
            //7 Judge
        } else {
            self.judgePoint4.enabled = YES;
            self.judgePoint7.enabled = YES;
        }
    }
    [self setSverallSegment];
    [self score];
}

-(void)setSverallSegment{
    
    if (_maxOfPoint.selectedSegmentIndex == 0) {
        [self.judgePoint5 removeAllSegments];
        for (int i = 0; i <= 5; i++) {
            [self.judgePoint5 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
        }
        self.judgePoint5.selectedSegmentIndex = 0;

        if (_numOfJudge.selectedSegmentIndex == 0) {
            if (self.tieAir.isOn) {
                NSInteger countnum = self.judgePoint5.numberOfSegments-2;
                [self.judgePoint5 removeAllSegments];
                for (int i = 0; i <= countnum; i++) {
                    [self.judgePoint5 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
                }
            }
            if (self.tieSpeed.isOn) {
                NSInteger countnum = self.judgePoint5.numberOfSegments-2;
                [self.judgePoint5 removeAllSegments];
                for (int i = 0; i <= countnum; i++) {
                    [self.judgePoint5 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
                }
            }
            self.judgePoint5.selectedSegmentIndex = 0;
        }
    }
}

- (void)maxChanged:(UISegmentedControl *)sender {
    // まず既存のセグメントを全て削除
    [self.judgePoint1 removeAllSegments];
    [self.judgePoint2 removeAllSegments];
    [self.judgePoint3 removeAllSegments];
    [self.judgePoint4 removeAllSegments];
    [self.judgePoint5 removeAllSegments];
    [self.judgePoint6 removeAllSegments];
    [self.judgePoint7 removeAllSegments];

    if (sender.selectedSegmentIndex == 0) {
        // "5" が選ばれたとき → 6個追加
        for (int i = 0; i <= 5; i++) {
            [self.judgePoint1 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
            [self.judgePoint2 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
            [self.judgePoint3 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
            [self.judgePoint4 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
            [self.judgePoint5 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
            [self.judgePoint6 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
            [self.judgePoint7 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
        }
        self.tieAir.enabled = YES;
        self.tieSpeed.enabled = YES;
    } else {
        // "1" が選ばれたとき → 2個追加
        for (int i = 0; i <= 1; i++) {
            [self.judgePoint1 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
            [self.judgePoint2 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
            [self.judgePoint3 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
            [self.judgePoint4 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
            [self.judgePoint5 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
            [self.judgePoint6 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
            [self.judgePoint7 insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:NO];
        }
        self.tieAir.on = NO;
        self.tieSpeed.on = NO;
        self.tieAir.enabled = NO;
        self.tieSpeed.enabled = NO;
        self.judgePoint3.enabled = YES;
        self.judgePoint4.enabled = YES;
        self.judgePoint5.enabled = YES;
        self.judgePoint6.enabled = YES;
        self.judgePoint7.enabled = YES;
    }
    
    // 初期選択位置を0に設定
    self.judgePoint1.selectedSegmentIndex = 0;
    self.judgePoint2.selectedSegmentIndex = 0;
    self.judgePoint3.selectedSegmentIndex = 0;
    self.judgePoint4.selectedSegmentIndex = 0;
    self.judgePoint5.selectedSegmentIndex = 0;
    self.judgePoint6.selectedSegmentIndex = 0;
    self.judgePoint7.selectedSegmentIndex = 0;
    
    //5 Judge
    if (_numOfJudge.selectedSegmentIndex == 0) {
        self.judgePoint6.hidden = YES;
        self.judgePoint7.hidden = YES;
        self.label6.hidden = YES;
        self.label7.hidden = YES;
    //7 Judge
    } else {
        self.judgePoint6.hidden = NO;
        self.judgePoint7.hidden = NO;
        self.label6.hidden = NO;
        self.label7.hidden = NO;
    }
}


- (void)judgeChanged:(UISegmentedControl *)sender {
    self.judgePoint1.selectedSegmentIndex = 0;
    self.judgePoint2.selectedSegmentIndex = 0;
    self.judgePoint3.selectedSegmentIndex = 0;
    self.judgePoint4.selectedSegmentIndex = 0;
    self.judgePoint5.selectedSegmentIndex = 0;
    self.judgePoint6.selectedSegmentIndex = 0;
    self.judgePoint7.selectedSegmentIndex = 0;
    [self tieAirChanged:self.tieAir];
    [self tieSpeedChanged:self.tieSpeed];

    //5 Judge
    if (sender.selectedSegmentIndex == 0) {
        self.judgePoint6.hidden = YES;
        self.judgePoint7.hidden = YES;
        self.label6.hidden = YES;
        self.label7.hidden = YES;
        self.label3.text = @"Judge 3 Air";
        self.label4.text = @"Judge 4 Speed";
        self.label5.text = @"Judge 5 Overall";

    //7 Judge
    } else {
        self.judgePoint6.hidden = NO;
        self.judgePoint7.hidden = NO;
        self.label6.hidden = NO;
        self.label7.hidden = NO;
        self.label3.text = @"Judge 3 Turn";
        self.label4.text = @"Judge 4 Turn";
        self.label5.text = @"Judge 5 Air";
    }
}

-(float)maxVotes{
    float value;
    if (_numOfJudge.selectedSegmentIndex == 0) {
        if (_maxOfPoint.selectedSegmentIndex == 0) {
            value = 5*5;
            if (self.tieAir.isOn) {
                value = 5*4-1;
            }
        }else{
            value = 5*1 ;
        }
    //7 Judge
    } else {
        if (_maxOfPoint.selectedSegmentIndex == 0) {
            value = 7*5 ;
            if (self.tieAir.isOn) {
                value = 5*5;
            }
        }else{
            value = 7*1;
        }
    }
    return value;
}

-(void)score{
    float iblue = 0;
    float iblueT = 0;
    float iblueA = 0;
    float iblueS = 0;
    float ired = 0;
    //5 Judge
    if (_numOfJudge.selectedSegmentIndex == 0) {
        iblueT = self.judgePoint1.selectedSegmentIndex+self.judgePoint2.selectedSegmentIndex;
        if (self.tieAir.isOn) {
            iblueA = 0;
        }else{
            iblueA = self.judgePoint3.selectedSegmentIndex;
        }
        if (self.tieSpeed.isOn) {
            iblueS = 3;
        }else{
            iblueS = self.judgePoint4.selectedSegmentIndex;
        }
        iblue = iblueT + iblueA + iblueS + self.judgePoint5.selectedSegmentIndex;
    //7 Judge
    } else {
        iblueT =
        self.judgePoint1.selectedSegmentIndex+
        self.judgePoint2.selectedSegmentIndex+
        self.judgePoint3.selectedSegmentIndex+
        self.judgePoint4.selectedSegmentIndex;
        if (self.tieAir.isOn) {
            iblueA = 0;
        }else{
            iblueA = self.judgePoint5.selectedSegmentIndex + self.judgePoint6.selectedSegmentIndex;
        }
        if (self.tieSpeed.isOn) {
            iblueS = 2.5;
        }else{
            iblueS = self.judgePoint7.selectedSegmentIndex;
        }
        iblue = iblueT + iblueA + iblueS;
    }

    //display format
    if(self.tieSpeed.isOn && _numOfJudge.selectedSegmentIndex == 1){
        ired = [self maxVotes] - iblue;
        self.blue.font = [UIFont systemFontOfSize:70.0];
        self.red.font = [UIFont systemFontOfSize:70.0];
        self.blue.text = [NSString stringWithFormat:@"%.1f", (float)iblue];
        self.red.text = [NSString stringWithFormat:@"%.1f", (float)ired];
    }else{
        ired = [self maxVotes] - iblue;
        self.blue.font = [UIFont systemFontOfSize:90.0];
        self.red.font = [UIFont systemFontOfSize:90.0];
        self.blue.text = [NSString stringWithFormat:@"%ld", (long)iblue];
        self.red.text = [NSString stringWithFormat:@"%ld", (long)ired];
    }
    if(iblue>ired){
        self.blueWin.hidden = NO;
        self.redWin.hidden = YES;
        self.tieStr.hidden = YES;
    }else if(iblue==ired){
        self.blueWin.hidden = YES;
        self.redWin.hidden = YES;
        self.tieStr.hidden = NO;
    }else{
        self.blueWin.hidden = YES;
        self.redWin.hidden = NO;
        self.tieStr.hidden = YES;
    }
}

- (IBAction)clearScore:(id)sender {
    // 初期選択位置を0に設定
    self.judgePoint1.selectedSegmentIndex = 0;
    self.judgePoint2.selectedSegmentIndex = 0;
    self.judgePoint3.selectedSegmentIndex = 0;
    self.judgePoint4.selectedSegmentIndex = 0;
    self.judgePoint5.selectedSegmentIndex = 0;
    self.judgePoint6.selectedSegmentIndex = 0;
    self.judgePoint7.selectedSegmentIndex = 0;

    self.tieAir.on = NO;
    self.tieSpeed.on = NO;
    self.tieAir.enabled = YES;
    self.tieSpeed.enabled = YES;
    self.judgePoint3.enabled = YES;
    self.judgePoint4.enabled = YES;
    self.judgePoint5.enabled = YES;
    self.judgePoint6.enabled = YES;
    self.judgePoint7.enabled = YES;

    [self setSverallSegment];
    [self score];
}

@end
