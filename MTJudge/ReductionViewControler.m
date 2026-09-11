//
//  ReductionViewControler.m
//  MTJudge
//
//  Created by 長島 康敬 on 11/05/28.
//  Copyright 2011 Yokohama. All rights reserved.
//

#include "Common.h"
#import "ReductionViewControler.h"
#import "FirstViewController.h"


@implementation ReductionViewControler
//@synthesize    drawingView;

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
    //iPhone/iPadの画面サイズに合わせて画像を拡大・縮小する
    UIGraphicsBeginImageContext(self.view.frame.size);
    [[UIImage imageNamed:@"backpage.png"] drawInRect:self.view.bounds];
    UIImage *backview = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIImageView *imageview = [[UIImageView alloc] initWithFrame:self.view.bounds];
    [imageview setAlpha:0.1];
    imageview.image = backview;
    [self.view addSubview:imageview];
    
	UIImage *courseview = [UIImage imageNamed:@"course.png"];
    _imageview = [[UIImageView alloc] initWithFrame:self.drawingView.frame];
    _imageview.image = courseview;
    CTRL_GATE_UNIT = self.drawingView.frame.size.height/10;
    COURSE_IMAGE_WIDTH = self.drawingView.frame.size.width/4;
    [self.view addSubview:_imageview];
    [self.view addSubview:_drawingView];
    [super viewDidLoad];
	f_reduction = 0.0;
	_txt_reduction.text = [NSString stringWithFormat:@"%2.1f", f_reduction];
    aryReduction = [[NSMutableArray alloc] init];
}

-(void)viewDidAppear:(BOOL)animated{
	[_drawingView setLineWidth:14];
	[_drawingView setDelegate:self];
    //ベース点
	FirstViewController *basepoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_BASEPOINT];
	_txt_basepoint.text = [NSString stringWithFormat:@"%2.1f", [basepoint getBasePoint]];
    [super viewDidAppear:true];
}

-(void)resetValues{
	[self clearReduction];
}

- (void)clearReduction{
	//int count = [aryReduction count];
	for (UILabel *obj in aryReduction) {
		NSLog(@"ログ（%-20s,%-24s:%5d） \n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
		[obj removeFromSuperview];
	}
	[self setSideDirection:0];
	[self setFallDirection:0];
	[_drawingView setLineWidth:1];
    [_drawingView clear];
	[_drawingView setLineWidth:14];
	f_reduction = 0.0;
	side_reduction = 0.0;
	fall_reduction = 0.0;
	side_sum = 0.0;
	fall_sum = 0.0;
	_intSideValue.text = [NSString stringWithFormat:@"%2.1f", (side_reduction)];
    _intFallValue.text = [NSString stringWithFormat:@"%2.1f", (fall_reduction)];
	_sumSideValue.text = [NSString stringWithFormat:@"%2.1f", (side_sum)];
    _sumFallValue.text = [NSString stringWithFormat:@"%2.1f", (fall_sum)];
	_txt_reduction.text = [NSString stringWithFormat:@"%2.1f", f_reduction];
}

- (IBAction)clear:(id)sender {
    [self clearReduction];
}

- (void)toggleColor:(id)sender{
    static BOOL isBlack = YES;
    isBlack = !isBlack;
    [_drawingView toggleColor:isBlack];
}

- (void)setLineWidth:(id)sender{
    UISlider *slider = (UISlider *)sender;
    [_drawingView setLineWidth:slider.value];
}

- (void)recalculate:(CGPoint)point {
	side_reduction = -([self getSideReduction:intSide]);
	fall_reduction = -([self getFallReduction:intFall]);
    total_reduction = side_reduction + fall_reduction;
    
    side_sum = side_sum + side_reduction;
	fall_sum = fall_sum + fall_reduction;
	
	_sumSideValue.text = [NSString stringWithFormat:@"%2.1f", -(side_sum)];
    _sumFallValue.text = [NSString stringWithFormat:@"%2.1f", -(fall_sum)];
	
	f_reduction = (f_reduction+side_reduction+fall_reduction);
    
    //ベース点
	FirstViewController *basepoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_BASEPOINT];
    float basePnt = [basepoint getBasePoint];
    float totalReduction = f_reduction;
    if ((basePnt+f_reduction)<=0.1) {
        totalReduction = basePnt-0.1;
    }
	_txt_reduction.text = [NSString stringWithFormat:@"%2.1f", totalReduction];
    NSLog(@"side: %-5.2f,  fall: %5.2f,  total:%5.2f ¥tside: %-5.2f,  fall: %5.2f,  total:%5.2f \n", side_reduction, fall_reduction, total_reduction, side_sum, fall_sum, f_reduction);
}

- (void)createLabel:(CGPoint)point {
    UIFont *myfont = [UIFont fontWithName:@"Courier" size:10];
	labelSide = [[UILabel alloc] initWithFrame:CGRectMake(point.x, point.y-24, 30, 12)];
	labelSide.font = myfont;
	labelSide.text = [NSString stringWithFormat:@"%2.1f", total_reduction];
	[_drawingView addSubview:labelSide];
	//ページを追加
	[aryReduction addObject:labelSide];
    
}

- (float) getFallReduction:(int)value {
    float target = 0.0;
    NSInteger shooting = (int)(CTRL_GATE_UNIT*0.8);

    if (value<shooting) {
        if (value<shooting/4) {
            target = 0.0;
        }else{
            target = 1;
        }
    }else{
        target = (int)(value/shooting)*2;
    }
    _curFallVal.text = [NSString stringWithFormat:@"%2.1f", target];
    return target;
}

- (float) getSideReduction:(int)value {
    float target = 0.0;
    NSInteger lanechange = (int)(COURSE_IMAGE_WIDTH*0.7);
    
    if (value<lanechange) {
        if (value<lanechange/2) {
            target = 0.0;
        }else{
            target = LANE_CHANGE_UNIT/2;
        }
    }else{
        target = ((int)(value/lanechange))*LANE_CHANGE_UNIT;
    }
    _curSideVal.text = [NSString stringWithFormat:@"%2.1f", target];
    return target;
}

-(IBAction)showLabelReduction{
	side_reduction = -([self getSideReduction:intSide]);
	fall_reduction = -([self getFallReduction:intFall]);
    total_reduction = side_reduction + fall_reduction;
    labelSide.text = [NSString stringWithFormat:@"%2.1f", total_reduction];
}

-(IBAction)setFallDirection:(int)value{
    intFall = value;
    _intFallValue.text = [NSString stringWithFormat:@"%2.1f", -[self getFallReduction:intFall]];
}

-(IBAction)setSideDirection:(int)value{
    intSide = value;
	_intSideValue.text = [NSString stringWithFormat:@"%2.1f", -[self getSideReduction:intSide]];
}

-(IBAction)setReduction:(float)value{
    f_reduction = value;
	[self onChangeValue];
}

-(IBAction)onChangeValue{
    _txt_reduction.text = [NSString stringWithFormat:@"%2.1f", f_reduction];
}

-(float)getReduction{
	return f_reduction;
}

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc. that aren't in use.
}

@end
