//
//  JudgeViewController.m
//  MTJudge
//
//  Created by 長島 康敬 on 2012/11/07.
//  Copyright (c) 2012年 Yokohama. All rights reserved.
//

#include "Common.h"
#import "JudgeViewController.h"
#import "FirstViewController.h"

@interface JudgeViewController ()

@end

@implementation JudgeViewController

extern NSString *levelStr[];

#if false
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}
#endif
- (void)viewDidLoad
{
    [super viewDidLoad];
//    [self viewRotationOrientation];
	//iPhone,iPadの判断
	//if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
	// iPadの場合の動作
	//} else {
	// iPhone, iPod Touchの場合の動作
	//}
    //iPhone/iPadの画面サイズに合わせて画像を拡大・縮小する
    UIGraphicsBeginImageContext(self.view.frame.size);
    [[UIImage imageNamed:@"backpage.png"] drawInRect:self.view.bounds];
    UIImage *backview = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIImageView *imageview = [[UIImageView alloc] initWithFrame:self.view.bounds];
    [imageview setAlpha:0.1];
    imageview.image = backview;
    [self.view addSubview:imageview];

//	[self.view addSubview:TouchDrawingView];
    // Do any additional setup after loading the view from its nib.

    [_deduct01View setDrawType:DRAW_TYPE_D15];
    [_deduct02View setDrawType:DRAW_TYPE_D11];
    [_deduct03View setDrawType:DRAW_TYPE_D08];
    [_deduct04View setDrawType:DRAW_TYPE_D06];
    [_deduct05View setDrawType:DRAW_TYPE_D01];
    [_reduct01View setDrawType:DRAW_TYPE_REDUCTION];
    [_reduct02View setDrawType:DRAW_TYPE_LANECHANGE];
    [_reduct03View setDrawType:DRAW_TYPE_NOTURN];
    [_deduct01View setDelegate:self];
    [_deduct02View setDelegate:self];
    [_deduct03View setDelegate:self];
    [_deduct04View setDelegate:self];
    [_deduct05View setDelegate:self];
    [_reduct01View setDelegate:self];
    [_reduct02View setDelegate:self];
    [_reduct03View setDelegate:self];
    //UIColor *myColor1 = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.5];
	//UIImage *courseview = [[UIImage imageNamed:@"course.png"] autorelease];
    //[deduct01View setBackgroundColor:myColor1];
//    _txtJudgePoint.text = [NSString stringWithFormat:@"%2.1f", _sdl_basepoint.value];
    [self.view addSubview:_deduct01View];

}

-(void)viewDidAppear:(BOOL)animated{
    //ベース点
	FirstViewController *basepoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_BASEPOINT];
    _txtJudgePoint.text = [NSString stringWithFormat:@"%2.1f", [basepoint getBasePoint]];
    [self recaluculate];
    [super viewDidAppear:true];
}

-(void)resetValues{
//	[self clear];
    [self clear:self];
}

- (IBAction)onClear:(id)sender {
    [self clear:self];
    //ベース点
    FirstViewController *basepoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_BASEPOINT];
    _txtJudgePoint.text = [NSString stringWithFormat:@"%2.1f", [basepoint getBasePoint]];
}

- (void)clear:(id)sender{
    [_deduct01View clearInner];
    [_deduct02View clearInner];
    [_deduct03View clearInner];
    [_deduct04View clearInner];
    [_deduct05View clearInner];
    [_reduct01View clearInner];
    [_reduct02View clearInner];
    [_reduct03View clearInner];
    [self recaluculate];
}

- (void)calucTotalPoint
{
    //ベース点
    FirstViewController *basepoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_BASEPOINT];
    float total_point = [basepoint getBasePoint];
    _txtTotalPoint.text = [NSString stringWithFormat:@"%2.1f", total_point];
}

-(void)recaluculate{
    float deduction_point1 = [_deduct01View getTotalReduction];
    float deduction_point2 = [_deduct02View getTotalReduction];
    float deduction_point3 = [_deduct03View getTotalReduction];
    float deduction_point4 = [_deduct04View getTotalReduction];
    float deduction_point5 = [_deduct05View getTotalReduction];
    float deduction_point = deduction_point1+deduction_point2
            +deduction_point3+deduction_point4+deduction_point5;
    _txtDeductionPoint.text = [NSString stringWithFormat:@"%2.1f", deduction_point];
    float reduction_point1 = [_reduct01View getTotalReduction];
    float reduction_point2 = [_reduct02View getTotalReduction];
    float reduction_point3 = [_reduct03View getTotalReduction];
    float reduction_point = reduction_point1+reduction_point2+reduction_point3;
    _txtReductionPoint.text = [NSString stringWithFormat:@"%2.1f", reduction_point];
    //ベース点
    FirstViewController *basepoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_BASEPOINT];
    float total_point = [basepoint getBasePoint]+(deduction_point+reduction_point);
    
    total_rededuction = deduction_point + reduction_point;
    
    if(total_point<0){
        total_point = 0.10;
    }
    _txt_total_deduction.text = [NSString stringWithFormat:@"%2.1f", total_rededuction];
    _txtTotalPoint.text = [NSString stringWithFormat:@"%2.1f", total_point];
    //return;
}

-(NSString *)getCurrentLevel :(float) level{
	int index = 0;
	if (0.0==level) {
		index = 0;
	}else if (0.1<=level && level<4.1) {
		index = 1;
	}else if (4.1<=level && level<8.1) {
		index = 2;
	}else if (8.1<=level && level<10.1) {
		index = 3;
	}else if (10.1<=level && level<12.1) {
		index = 4;
	}else if (12.1<=level && level<14.1) {
		index = 5;
	}else if (14.1<=level && level<16.1) {
		index = 6;
	}else if (16.1<=level && level<18.1) {
		index = 7;
	}else if (18.1<=level && level<=20.0) {
		index = 8;
	}
	return levelStr[index];
}

-(float)getDeduction{
	return total_rededuction;
}

@end
