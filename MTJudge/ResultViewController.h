//
//  ResultViewController.h
//  MTJudge
//
//  Created by 長島 康敬 on 11/05/19.
//  Copyright 2011 Yokohama. All rights reserved.
//

#import <UIKit/UIKit.h>


@interface ResultViewController : UIViewController {
	IBOutlet UITextField 	*txt_basepoint;
	IBOutlet UITextField 	*txt_deduction;
    IBOutlet UITextField 	*txt_reduction;
    IBOutlet UITextField 	*txt_judgepoint;
    IBOutlet UITextField *txt_turntotal;
    IBOutlet UITextField *txt_airpoint1;
    IBOutlet UITextField *txt_airpoint2;
    IBOutlet UITextField *txt_timepoint;
    IBOutlet UITextField *txt_totalscore;
    IBOutlet UITextField *txt_aircode1;
    IBOutlet UITextField *txt_aircode2;
    IBOutlet UITextField *txt_timesec;
    IBOutlet UISegmentedControl *sgmSex;

	float	f_basepoint;	
	float	f_deduction;	
	float	f_reduction;	
	float	judgepoint;	
	float	gTurnTotal;
	float	gAirPoint1;
	float	gAirPoint2;
	float	gAirTotal;
	float	gTimePoint;
	float	gTotalScore;
    NSInteger sexindex;
}
- (IBAction)onChangeSexValue:(id)sender;

-(void)allClear:(id)sender;
- (IBAction)touchUpInsideAllClear:(id)sender;
-(void)setSexType:(NSInteger)sex;

@end
