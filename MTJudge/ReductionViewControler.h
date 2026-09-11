//
//  ReductionViewControler.h
//  MTJudge
//
//  Created by 長島 康敬 on 11/05/28.
//  Copyright 2011 Yokohama. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DrawingView.h"

@class DrawingView;

@interface ReductionViewControler : UIViewController {
    //IBOutlet DrawingView *drawingView;
	//UIImageView *imageview;
	float		f_reduction;
	float		side_reduction;
	float		fall_reduction;
	float		total_reduction;
	float		side_sum;
	float		fall_sum;
	int			intFall;
	int			intSide;
	NSMutableArray	*aryReduction;
	UILabel		*labelSide;
    float       CTRL_GATE_UNIT;
    float       COURSE_IMAGE_WIDTH;
}

@property (weak, nonatomic) IBOutlet DrawingView  *drawingView;
@property (weak, nonatomic) IBOutlet UITextField	*txt_reduction;
@property (retain, nonatomic) IBOutlet UIImageView *imageview;
@property (weak, nonatomic) IBOutlet UILabel		*intFallValue;
@property (weak, nonatomic) IBOutlet UILabel		*intSideValue;
@property (weak, nonatomic) IBOutlet UILabel		*sumFallValue;
@property (weak, nonatomic) IBOutlet UILabel		*sumSideValue;
@property (weak, nonatomic) IBOutlet UILabel		*curFallVal;
@property (weak, nonatomic) IBOutlet UILabel		*curSideVal;
@property (weak, nonatomic) IBOutlet UITextField *txt_basepoint;

-(float)getReduction;	
//-(void)clear:(id)sender;
-(void)toggleColor:(id)sender;
-(void)setLineWidth:(id)sender;
-(IBAction)setReduction:(float)value;
-(IBAction)onChangeValue;
-(IBAction)setFallDirection:(int)value;
-(IBAction)setSideDirection:(int)value;
- (float) getFallReduction:(int)value;
- (float) getSideReduction:(int)value;
- (void)recalculate:(CGPoint)point;
- (void)createLabel:(CGPoint)point;
-(void)resetValues;
-(IBAction)showLabelReduction;
@end
