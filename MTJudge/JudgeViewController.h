//
//  JudgeViewController.h
//  MTJudge
//
//  Created by 長島 康敬 on 2012/11/07.
//  Copyright (c) 2012年 Yokohama. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "TouchDrawingView.h"

@interface JudgeViewController : UIViewController{
	float	f_deduction;
    float   total_rededuction;
}

//@property (retain, nonatomic) IBOutlet UIView *reduction01;
@property (weak, nonatomic) IBOutlet UITextField *txt_total_deduction;
@property (weak, nonatomic) IBOutlet UITextField *txtJudgePoint;
@property (weak, nonatomic) IBOutlet UITextField *txtDeductionPoint;
@property (weak, nonatomic) IBOutlet UITextField *txtReductionPoint;
@property (weak, nonatomic) IBOutlet UITextField *txtTotalPoint;
#if true
@property (retain, nonatomic) IBOutlet TouchDrawingView *deduct01View;
@property (retain, nonatomic) IBOutlet TouchDrawingView *deduct02View;
@property (retain, nonatomic) IBOutlet TouchDrawingView *deduct03View;
@property (retain, nonatomic) IBOutlet TouchDrawingView *deduct04View;
@property (retain, nonatomic) IBOutlet TouchDrawingView *deduct05View;
@property (retain, nonatomic) IBOutlet TouchDrawingView *reduct01View;
@property (retain, nonatomic) IBOutlet TouchDrawingView *reduct02View;
@property (retain, nonatomic) IBOutlet TouchDrawingView *reduct03View;
#else
@property (weak, nonatomic) IBOutlet TouchDrawingView *deduct01View;
@property (weak, nonatomic) IBOutlet TouchDrawingView *deduct02View;
@property (weak, nonatomic) IBOutlet TouchDrawingView *deduct03View;
@property (weak, nonatomic) IBOutlet TouchDrawingView *deduct04View;
@property (weak, nonatomic) IBOutlet TouchDrawingView *deduct05View;
@property (weak, nonatomic) IBOutlet TouchDrawingView *reduct01View;
@property (weak, nonatomic) IBOutlet TouchDrawingView *reduct02View;
@property (weak, nonatomic) IBOutlet TouchDrawingView *reduct03View;
#endif
@property (weak, nonatomic) IBOutlet UIButton *btbClear;

-(void)resetValues;
-(void)recaluculate;
-(float)getDeduction;

@end
