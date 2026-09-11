//
//  SpeedViewController.h
//  MTJudge
//
//  Created by 長島 康敬 on 11/06/07.
//  Copyright 2011 Yokohama. All rights reserved.
//

#import <UIKit/UIKit.h>


@interface SpeedViewController : UIViewController<UITextFieldDelegate> {
	float		f_courselength;
	float		f_pasesettime;
	float		f_yourtime;
	float		f_gender;
	float		f_timepoint;
    NSInteger sexindex;
    BOOL    isLoaded;
}

@property (weak, nonatomic) IBOutlet UISlider	*sld_courselength;
@property (weak, nonatomic) IBOutlet UISlider	*sld_yourtime;
@property (weak, nonatomic) IBOutlet UISegmentedControl	*sgmSex;
@property (weak, nonatomic) IBOutlet UITextField		*txtCourseLength;
@property (weak, nonatomic) IBOutlet UITextField		*txtYourTime;
@property (weak, nonatomic) IBOutlet UILabel		*lblPaseTime;
@property (weak, nonatomic) IBOutlet UILabel		*lblPaseSetTime;
@property (weak, nonatomic) IBOutlet UILabel		*lblTimePoint;
@property (weak, nonatomic) IBOutlet UIStepper *stpr_courselength;
@property (weak, nonatomic) IBOutlet UIStepper *stpr_timesec;

-(IBAction)onChangeValueCourseLength:(id)sender;
-(IBAction)onChangeValueYourTime:(id)sender;
-(IBAction)onChangeTextCourseLength:(id)sender;
-(IBAction)onChangeTextYourTime:(id)sender;
-(IBAction)onChangeValueSex:(id)sender;
-(float)getTimePoint;
-(float)getTimeSec;
-(void)setSexType:(NSInteger)sex;
-(BOOL)isClassLoaded;

@end
