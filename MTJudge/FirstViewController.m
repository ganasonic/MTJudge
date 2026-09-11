//
//  FirstViewController.m
//  MTJudge
//
//  Created by Yasunori Nagashima on 2019/04/16.
//  Copyright © 2019 Yasunori Nagashima. All rights reserved.
//

#include "Common.h"
#import "FirstViewController.h"
#import "AirViewController.h"
#import "SpeedViewController.h"
#import "ResultViewController.h"

@interface FirstViewController ()

@end

@implementation FirstViewController
NSString *levelStr[] = {
    @"Not skied",
    @"Poor",
    @"Managing",
    @"Adequate",
    @"Good",
    @"Excellent"
};

- (void)viewDidLoad {
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

    
    [super viewDidLoad];
    _txt_uppderbody.text =  [NSString stringWithFormat:@"%2.1f", _sld_uppderbody.value/10];
    _txt_carving.text =  [NSString stringWithFormat:@"%2.1f", _sld_carving.value/10];
    _txt_absorption.text =  [NSString stringWithFormat:@"%2.1f", _sld_absorption.value/10];
    
    int intvalue;
    intvalue = (int)_sld_uppderbody.value;
    f_uppderbody = intvalue/10;
    intvalue = (int)_sld_carving.value;
    f_carving = intvalue/10;
    intvalue = (int)_sld_absorption.value;
    f_absorption = intvalue/10;
}

-(void)viewDidAppear:(BOOL)animated{
    [self summaryBasepoint];
}

-(void)resetValues{
    _sld_uppderbody.value=0.0;
    _sld_carving.value=0.0;
    _sld_absorption.value=0.0;
    
    _txt_uppderbody.text =  [NSString stringWithFormat:@"%2.1f", 0.0];
    _txt_carving.text =  [NSString stringWithFormat:@"%2.1f", 0.0];
    _txt_absorption.text =  [NSString stringWithFormat:@"%2.1f", 0.0];
    
    f_uppderbody = f_carving = f_absorption = 0.0;
    
    _lblUpperbody.text = levelStr[0];
    _lblCarving.text = levelStr[0];
    _lblAbsorption.text = levelStr[0];
    [self summaryBasepoint];
    [self drawLevelBar];
}

-(void)drawLevelBar{
    //めもり描画
}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc. that aren't in use.
}

- (void)viewRotationOrientation
{
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    NSArray *topLevelObjects;
    //Landscape(横レイアウトの場合)
    if(UIInterfaceOrientationIsLandscape(orientation)) {
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
            topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"FirstView_Landscape" owner:self options:nil];
            // iPadの場合
        } else {
            topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"FirstView_Landscape" owner:self options:nil];
        }
        //Portrait(縦レイアウトの場合)
    } else {
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
            topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"FirstView" owner:self options:nil];
        } else {
            topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"FirstView" owner:self options:nil];
        }
    }
}

-(float)getBasePoint{
    return f_basepoint;
}

-(NSString *)getCurrentLevel :(float) level{
    int index = 0;
    if (0.0==level) {
        index = 0;
    }else if (0.1<=level && level<4.1) {
        index = 1;
    }else if (4.1<=level && level<8.1) {
        index = 2;
    }else if (8.1<=level && level<12.1) {
        index = 3;
    }else if (12.1<=level && level<16.1) {
        index = 4;
    }else if (16.1<=level && level<=20.0) {
        index = 5;
    }
    return levelStr[index];
}

-(NSString *)getCurrentLevelCarving :(float) level{
    return [self getCurrentLevel:level*2.0];;
}

-(NSString *)getCurrentLevelAbsExtUpper :(float) level{
    return [self getCurrentLevel:level*4];;
}

-(IBAction)onChangeValueUppderbody:(id)sender{
    //    NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    int intvalue = (int)_sld_uppderbody.value;
    f_uppderbody = intvalue/10.0;
    _txt_uppderbody.text =  [NSString stringWithFormat:@"%2.1f", f_uppderbody];
    _lblUpperbody.text = [self getCurrentLevelAbsExtUpper:f_uppderbody];
    [self summaryBasepoint];
    //    NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

-(IBAction)onChangeValueCarving:(id)sender{
    //    NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    int intvalue = (int)_sld_carving.value;
    f_carving = intvalue/10.0;
    _txt_carving.text =  [NSString stringWithFormat:@"%2.1f", f_carving];
    _lblCarving.text = [self getCurrentLevelCarving:f_carving];
    [self summaryBasepoint];
    //    NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

-(IBAction)onChangeValueAbsorption:(id)sender{
    //    NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    int intvalue = (int)_sld_absorption.value;
    f_absorption = intvalue/10.0;
    _txt_absorption.text =  [NSString stringWithFormat:@"%2.1f", f_absorption];
    _lblAbsorption.text = [self getCurrentLevelAbsExtUpper:f_absorption];
    [self summaryBasepoint];
    //    NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

-(void)summaryBasepoint{
    //    NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    //f_basepoint = (f_uppderbody+f_carving+f_absorption)/3.0;
    f_basepoint = (f_uppderbody+f_carving+f_absorption);
    _lblBasepoint.text = [self getCurrentLevel:f_basepoint];
    _txt_basepoint.text = [NSString stringWithFormat:@"%2.1f", f_basepoint];
    NSLog(@"ログ（%-20s,%-24s:%6.3f\n", __FILE__, __PRETTY_FUNCTION__, f_basepoint);
    //    NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

- (IBAction)onSexValueChanged:(id)sender {
    sexindex = self.sgmSex.selectedSegmentIndex;
    //リザルト
    ResultViewController *resultpoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_RESULTPOINT];
    [resultpoint setSexType:sexindex];
    //タイム
    SpeedViewController *speedpoint = self.tabBarController.viewControllers[TAB_NAB_TIMEPOINT];
    //SpeedViewController *speedpoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_TIMEPOINT];
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
}

-(void)setSexType:(NSInteger)sex{
    self.sgmSex.selectedSegmentIndex=(NSInteger)sex;
    sexindex = self.sgmSex.selectedSegmentIndex;
}

@end
