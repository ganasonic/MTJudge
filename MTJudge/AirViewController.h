//
//  AirViewController.h
//  MTJudge
//
//  Created by 長島 康敬 on 11/08/21.
//  Copyright 2011 Yokohama. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface AirViewController : UIViewController <UIPickerViewDelegate, UIPickerViewDataSource>{
    float       f_airpoint;
    float       f_judgepoint;
    float       f_airdd;
    NSMutableArray  *ddlist;
    NSString        *str_airdd;
    int         cur_row;
    //UIPickerView *pickerView;
    
    float       f_airpoint2;
    float       f_judgepoint2;
    float       f_airdd2;
    NSMutableArray  *ddlist2;
    NSString        *str_airdd2;
    int         cur_row2;
    //UIPickerView *pickerView2;
    NSInteger       sexindex;
    bool        isLoaded;
}
@property (weak, nonatomic) IBOutlet UISlider *sld_airpoint;
@property (weak, nonatomic) IBOutlet UISegmentedControl *sgmAir;
@property (weak, nonatomic) IBOutlet UITextField *txt_judgepoint;
@property (weak, nonatomic) IBOutlet UITextField *txt_airdd;
@property (weak, nonatomic) IBOutlet UITextField *txt_airpoint;
//@property (retain,  nonatomic) IBOutlet UIPickerView *pickerView;
@property (retain,  nonatomic) UIPickerView *pickerView;
@property (weak, nonatomic) IBOutlet UILabel *lbl_airlevel;
@property (weak, nonatomic) IBOutlet UISlider *sld_airpoint2;
@property (weak, nonatomic) IBOutlet UISegmentedControl *sgmAir2;
@property (weak, nonatomic) IBOutlet UITextField *txt_judgepoint2;
@property (weak, nonatomic) IBOutlet UITextField *txt_airdd2;
@property (weak, nonatomic) IBOutlet UITextField *txt_airpoint2;
//@property (retain, nonatomic) IBOutlet UIPickerView *pickerView2;
@property (retain, nonatomic) UIPickerView *pickerView2;
@property (weak, nonatomic) IBOutlet UILabel *lbl_airlevel2;
@property (retain, nonatomic) IBOutlet UISegmentedControl *sgmSex;

@property (weak, nonatomic) IBOutlet UIButton *AirGreenMax1;
@property (weak, nonatomic) IBOutlet UIButton *AirGreenMax2;
@property (weak, nonatomic) IBOutlet UIButton *AirYellowMax1;
@property (weak, nonatomic) IBOutlet UIButton *AirYellowMax2;
@property (weak, nonatomic) IBOutlet UIButton *AirRedMax1;
@property (weak, nonatomic) IBOutlet UIButton *AirRedMax2;
@property (weak, nonatomic) IBOutlet UIButton *GgrabMax1;
@property (weak, nonatomic) IBOutlet UIButton *GgrabMax2;
@property (weak, nonatomic) IBOutlet UIButton *GtouchMax1;
@property (weak, nonatomic) IBOutlet UIButton *GtouchMax2;
@property (weak, nonatomic) IBOutlet UIButton *GnograbMax1;
@property (weak, nonatomic) IBOutlet UIButton *GnograbMax2;
@property (weak, nonatomic) IBOutlet UISegmentedControl *AirJudgePointSgm1;
@property (weak, nonatomic) IBOutlet UISegmentedControl *AirJudgePointSgm2;

#ifdef PICKER_AIR_DATA_FROM_JSON
@property (nonatomic) NSInteger AIRPOS_FLIP;
@property (nonatomic) NSInteger AIRPOS_3D;
@property (nonatomic) NSInteger AIRPOS_UP;
//@property (nonatomic, assign) AirDdArray *airddarray;
@property (nonatomic, assign) NSInteger airddarrayCount;

@property (nonatomic, strong) NSArray *jsonArray; // 全データを保持するプロパティ
#endif

-(BOOL)isClassLoaded;
-(float)getAirPoint;
-(NSString*)getAirCode;
-(float)getAirPoint2;
-(NSString*)getAirCode2;
-(void)setSexType:(NSInteger)sex;
@end
