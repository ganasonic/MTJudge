//
//  FirstViewController.h
//  MTJudge
//
//  Created by Yasunori Nagashima on 2019/04/16.
//  Copyright © 2019 Yasunori Nagashima. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface FirstViewController : UIViewController{
    float    f_uppderbody;
    float    f_carving;
    float    f_absorption;
    float    f_basepoint;
    NSInteger     sexindex;
}

@property (weak, nonatomic) IBOutlet UITextField *txt_basepoint;
@property (weak, nonatomic) IBOutlet UITextField *txt_carving;
@property (weak, nonatomic) IBOutlet UITextField *txt_absorption;
@property (weak, nonatomic) IBOutlet UITextField *txt_uppderbody;
@property (weak, nonatomic) IBOutlet UISlider *sld_carving;
@property (weak, nonatomic) IBOutlet UISlider *sld_absorption;
@property (weak, nonatomic) IBOutlet UISlider *sld_uppderbody;
@property (weak, nonatomic) IBOutlet UILabel *lblBasepoint;
@property (weak, nonatomic) IBOutlet UILabel *lblCarving;
@property (weak, nonatomic) IBOutlet UILabel *lblAbsorption;
@property (weak, nonatomic) IBOutlet UILabel *lblUpperbody;

@property (weak, nonatomic) IBOutlet UISegmentedControl *sgmSex;

-(IBAction)onChangeValueCarving:(id)sender;
-(IBAction)onChangeValueAbsorption:(id)sender;
-(IBAction)onChangeValueUppderbody:(id)sender;
-(void)summaryBasepoint;
-(float)getBasePoint;
-(void)drawLevelBar;
-(void)resetValues;
-(void)setSexType:(NSInteger)sex;
@end

