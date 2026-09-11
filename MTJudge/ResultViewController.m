    //
//  ResultViewController.m
//  MTJudge
//
//  Created by 長島 康敬 on 11/05/19.
//  Copyright 2011 Yokohama. All rights reserved.
//

#include "Common.h"
#import "ResultViewController.h"
#import "FirstViewController.h"
#import "SecondViewController.h"
#import "ReductionViewControler.h"
#import "AirViewController.h"
#import "SpeedViewController.h"
#import "JudgeViewController.h"


@implementation ResultViewController

- (void)viewDidLoad {
/*
 */
    [super viewDidLoad];
    //iPhone/iPadの画面サイズに合わせて画像を拡大・縮小する
    UIGraphicsBeginImageContext(self.view.frame.size);
    [[UIImage imageNamed:@"backpage.png"] drawInRect:self.view.bounds];
    UIImage *backview = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIImageView *imageview = [[UIImageView alloc] initWithFrame:self.view.bounds];
    [imageview setAlpha:0.1];
    imageview.image = backview;
    [self.view addSubview:imageview];
    

    //タイム
    SpeedViewController *speedpoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_TIMEPOINT];
    float speedpnt = [speedpoint getTimePoint];
    float timepnt = [speedpoint getTimeSec];
    if (speedpnt==0.0 && timepnt==0.0) {
        [speedpoint viewDidLoad];
    }
}

- (void)viewDidAppear:(BOOL)animated{
	[super viewDidAppear:true];
	[self resetValues];
}

-(void)resetValues{
    //ベース点
	FirstViewController *basepoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_BASEPOINT];
    txt_basepoint.text = [NSString stringWithFormat:@"%2.1f", [basepoint getBasePoint]];
    //ディダクション
    JudgeViewController *deduction = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_JUDGING];

    txt_deduction.text = [NSString stringWithFormat:@"%2.1f", [deduction getDeduction]];
    //リダクション
	ReductionViewControler *reduction = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_REDUCTION];
    txt_reduction.text = [NSString stringWithFormat:@"%2.1f", [reduction getReduction]];
    //エアポイント
	AirViewController *airpoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_AIR1POINT];
    if (airpoint!=nil) {
        //エアポイント1
        txt_airpoint1.text = [NSString stringWithFormat:@"%3.2f", [airpoint getAirPoint]];
        txt_aircode1.text = [airpoint getAirCode];
        //エアポイント2
        txt_airpoint2.text = [NSString stringWithFormat:@"%3.2f", [airpoint getAirPoint2]];
        txt_aircode2.text = [airpoint getAirCode2];
    }
    //スピードポイント
	SpeedViewController *timepoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_TIMEPOINT];
    txt_timepoint.text = [NSString stringWithFormat:@"%3.2f", [timepoint getTimePoint]];
    txt_timesec.text = [NSString stringWithFormat:@"%3.2f", [timepoint getTimeSec]];
    //ディダクション
//2014/11/12コメント化
//	JudgeViewController *deduction1 = [self.tabBarController.viewControllers objectAtIndex:7];
    //txt_deduction.text = [NSString stringWithFormat:@"%2.1f", [deduction1 getDeduction]];
    
	float total = [basepoint getBasePoint]+[deduction getDeduction]+[reduction getReduction];
    float totalturn = total*3;
    if(totalturn<=0){
        totalturn = 0.3;
    }
    txt_judgepoint.text = [NSString stringWithFormat:@"%2.1f", total];
    //ターントータル
    txt_turntotal.text = [NSString stringWithFormat:@"%2.1f", totalturn];
    //トータルスコア
    float airpoint1 = [airpoint getAirPoint];
    float airpoint2 = [airpoint getAirPoint2];
    float totalscore = totalturn+airpoint1+airpoint2+[timepoint getTimePoint];
    txt_totalscore.text = [NSString stringWithFormat:@"%2.2f", totalscore];
}

-(void)allClear:(id)sender{
	FirstViewController *basepoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_BASEPOINT];
    [basepoint resetValues];
	ReductionViewControler *reduction = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_REDUCTION];
    [reduction resetValues];
	[self resetValues];
}

- (IBAction)touchUpInsideAllClear:(id)sender {
    FirstViewController *basepoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_BASEPOINT];
    [basepoint resetValues];
    ReductionViewControler *reduction = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_REDUCTION];
    [reduction resetValues];
    [self resetValues];}

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc. that aren't in use.
}

- (IBAction)onChangeSexValue:(id)sender {
    sexindex = sgmSex.selectedSegmentIndex;
    //ベース
	FirstViewController *basepoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_BASEPOINT];
    [basepoint setSexType:sexindex];
    //タイム
	SpeedViewController *speedpoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_TIMEPOINT];
    if ([speedpoint isClassLoaded]==false) {
        [speedpoint viewDidLoad];
    }
    [speedpoint setSexType:sexindex];
    //エアポイント1
	AirViewController *airpoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_AIR1POINT];
    if ([airpoint isClassLoaded]==false) {
        [airpoint viewDidLoad];
    }
    [airpoint setSexType:sexindex];
	[self resetValues];
}

-(void)setSexType:(NSInteger)sex{
    sgmSex.selectedSegmentIndex=sex;
    sexindex = sgmSex.selectedSegmentIndex;
}

@end
