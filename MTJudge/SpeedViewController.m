//
//  SpeedViewController.m
//  MTJudge
//
//  Created by 長島 康敬 on 11/06/07.
//  Copyright 2011 Yokohama. All rights reserved.
//

#include "Common.h"

#import "SpeedViewController.h"
#import "FirstViewController.h"
#import "AirViewController.h"
#import "ResultViewController.h"


@implementation SpeedViewController

//#define F_SpeedPerSec 9.0
//#define M_SpeedPerSec 10.3

// The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization.
    }
    return self;
}


// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
    // 文字列を読み込む
    NSString *psFemale = [[NSUserDefaults standardUserDefaults] stringForKey:@"psFemale"];
    NSString *psMale = [[NSUserDefaults standardUserDefaults] stringForKey:@"psMale"];
    if (psFemale == nil) {
        // 値がnilの場合、デフォルト値として10.3を設定
        F_SpeedPerSec = 9.0f;
    } else {
        // 値が存在する場合、その値をfloatに変換して使用
        F_SpeedPerSec = [psFemale floatValue];
    }
    if (psMale == nil) {
        // 値がnilの場合、デフォルト値として10.3を設定
        M_SpeedPerSec = 10.3f;
    } else {
        // 値が存在する場合、その値をfloatに変換して使用
        M_SpeedPerSec = [psMale floatValue];
    }
    
    //iPhone/iPadの画面サイズに合わせて画像を拡大・縮小する
    UIGraphicsBeginImageContext(self.view.frame.size);
    [[UIImage imageNamed:@"backpage.png"] drawInRect:self.view.bounds];
    UIImage *backview = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIImageView *imageview = [[UIImageView alloc] initWithFrame:self.view.bounds];
    [imageview setAlpha:0.1];
    imageview.image = backview;
    [self.view addSubview:imageview];
    

    [super viewDidLoad];
	[self paceSetTime];
	//キーパッドを消すため
    [_txtCourseLength setDelegate:self];
    [_txtYourTime setDelegate:self];
    isLoaded = true;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // 文字列を読み込む
    NSString *psFemale = [[NSUserDefaults standardUserDefaults] stringForKey:@"psFemale"];
    NSString *psMale = [[NSUserDefaults standardUserDefaults] stringForKey:@"psMale"];
    if (psFemale == nil) {
        // 値がnilの場合、デフォルト値として10.3を設定
        F_SpeedPerSec = 9.0f;
    } else {
        // 値が存在する場合、その値をfloatに変換して使用
        F_SpeedPerSec = [psFemale floatValue];
    }
    if (psMale == nil) {
        // 値がnilの場合、デフォルト値として10.3を設定
        M_SpeedPerSec = 10.3f;
    } else {
        // 値が存在する場合、その値をfloatに変換して使用
        M_SpeedPerSec = [psMale floatValue];
    }
    [self paceSetTime];
}

- (void)viewRotationOrientation
{
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    NSArray *topLevelObjects;
    //Landscape(横レイアウトの場合)
    if(UIInterfaceOrientationIsLandscape(orientation)) {
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
            topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"SpeedViewController_Landscape" owner:self options:nil];
            // iPadの場合
        } else {
            topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"SpeedViewController_Landscape" owner:self options:nil];
        }
        //Portrait(縦レイアウトの場合)
    } else {
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
            topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"SpeedViewController" owner:self options:nil];
        } else {
            topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"SpeedViewController" owner:self options:nil];
        }
    }
}

-(BOOL)isClassLoaded{
    return isLoaded;
}

-(void)paceSetTime{
	f_courselength = floor(_sld_courselength.value/10);
    _stpr_courselength.value = f_courselength*10;
	_txtCourseLength.text =  [NSString stringWithFormat:@"%3.1f", f_courselength];
    //int i_yourtime = (int)(sld_yourtime.value*10);
    _stpr_timesec.value = _sld_yourtime.value;
    f_yourtime = _sld_yourtime.value;
    _txtYourTime.text =  [NSString stringWithFormat:@"%3.2f", f_yourtime];
	f_gender = _sgmSex.selectedSegmentIndex == 1 ? F_SpeedPerSec : M_SpeedPerSec;
	_lblPaseTime.text = [NSString stringWithFormat:@"%2.1f", f_gender];
	f_pasesettime = f_courselength/f_gender;
	_lblPaseSetTime.text = [NSString stringWithFormat:@"%3.2f", f_pasesettime];
	[self summaryTimePoint];
}

-(void)paceSetTime2{
	f_gender = _sgmSex.selectedSegmentIndex == 1 ? F_SpeedPerSec : M_SpeedPerSec;
	_lblPaseTime.text = [NSString stringWithFormat:@"%2.1f", f_gender];
	f_pasesettime = f_courselength/f_gender;
	_lblPaseSetTime.text = [NSString stringWithFormat:@"%3.2f", f_pasesettime];
	[self summaryTimePoint];
}

-(void)paceSetTime3{
    _sld_courselength.value = _stpr_courselength.value;
	f_courselength = floor(_stpr_courselength.value)/10;
	_txtCourseLength.text =  [NSString stringWithFormat:@"%3.1f", f_courselength];
    f_yourtime = _sld_yourtime.value;
    _txtYourTime.text =  [NSString stringWithFormat:@"%3.2f", f_yourtime];
	f_gender = _sgmSex.selectedSegmentIndex == 1 ? F_SpeedPerSec : M_SpeedPerSec;
	_lblPaseTime.text = [NSString stringWithFormat:@"%2.1f", f_gender];
	f_pasesettime = f_courselength/f_gender;
	_lblPaseSetTime.text = [NSString stringWithFormat:@"%3.2f", f_pasesettime];
	[self summaryTimePoint];
}

- (IBAction)onChangeCourseLengthStepper:(id)sender {
	NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
	[self paceSetTime3];
	NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

- (IBAction)onChangeTimeSecStepper:(id)sender {
    _sld_yourtime.value = _stpr_timesec.value;
	[self paceSetTime];
}

-(IBAction)onChangeValueCourseLength:(id)sender {
	NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
	[self paceSetTime];
	NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

-(IBAction)onChangeValueYourTime:(id)sender {
	NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
	[self paceSetTime];
	NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

-(IBAction)onChangeTextCourseLength:(id)sender {
	NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
	_sld_courselength.value = [_txtCourseLength.text floatValue] * 10;
	[self paceSetTime2];
	NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

-(IBAction)onChangeTextYourTime:(id)sender {
	NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
	_sld_yourtime.value = [_txtYourTime.text floatValue];
	[self paceSetTime2];
	NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

-(BOOL)textFieldShouldReturn:(UITextField *)textField {
	NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    if (textField == _txtCourseLength) {
		_sld_courselength.value = [_txtCourseLength.text floatValue] * 10;
		f_courselength = floor(_sld_courselength.value)/10;
		[self paceSetTime2];
		[_txtCourseLength resignFirstResponder];
	}else if (textField == _txtYourTime) {
		_sld_yourtime.value = [_txtYourTime.text floatValue];
		f_yourtime = _sld_yourtime.value;
		[self paceSetTime2];
		[_txtYourTime resignFirstResponder];
	}
	NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
	return YES;
}

-(IBAction)onChangeValueSex:(id)sender {
	[self paceSetTime];
    sexindex = self.sgmSex.selectedSegmentIndex;
    //ベース
	FirstViewController *basepoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_BASEPOINT];
    [basepoint setSexType:sexindex];
    //リザルト
	ResultViewController *resultpoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_RESULTPOINT];
    [resultpoint setSexType:sexindex];
    //エアポイント1
	AirViewController *airpoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_AIR1POINT];
    if ([airpoint isClassLoaded]==false) {
        [airpoint viewDidLoad];
    }
    [airpoint setSexType:sexindex];
}

-(void)summaryTimePoint{
	NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
	//RoundDown
//    f_timepoint = 18-(12*f_yourtime/f_pasesettime);
    f_timepoint = 48-(32*f_yourtime/f_pasesettime);
	if (f_timepoint>20.0) {
		f_timepoint = 20.0;
	}else if (f_timepoint<0) {
		f_timepoint = 0.0;
	}
    _lblTimePoint.text = [NSString stringWithFormat:@"%3.2f", f_timepoint];
	NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc. that aren't in use.
}

-(float)getTimePoint{
	return f_timepoint;
}

-(float)getTimeSec{
	return f_yourtime;
}

-(void)setSexType:(NSInteger)sex{
    self.sgmSex.selectedSegmentIndex=(NSInteger)sex;
    sexindex = self.sgmSex.selectedSegmentIndex;
	[self paceSetTime];
}

@end
