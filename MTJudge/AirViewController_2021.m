//
//  AirViewController.m
//  MTJudge
//
//  Created by 長島 康敬 on 11/08/21.
//  Copyright 2011 Yokohama. All rights reserved.
//

#include "Common.h"
#import "AirViewController.h"
#import "FirstViewController.h"
#import "SpeedViewController.h"
#import "ResultViewController.h"


@interface AirViewController ()

@end

@implementation AirViewController

typedef struct _AirDdArray {
    NSString    *airname;
    float        dd_point_m;
    float        dd_point_f;
} AirDdArray;

NSString *levelJudgeStr[] = {
    @"No Point",
    @"Very Poor Jump",
    @"Poor Jump",
    @"Average Jump",
    @"Good Jump",
    @"Excellent Jump"
};

#ifdef PICKER_AIR_3TYPE
AirDdArray    airddarray_fl[]=
#else
AirDdArray    airddarray[]=
#endif
{
    {@"-",0.000 ,0.000},
    {@"bdF",1.020 ,1.120},
    {@"bF",0.880 ,1.030},
    {@"bFG",1.010 ,1.160},
    {@"bFp",0.910 ,1.060},
    {@"bG",0.830 ,0.930},
    {@"bL",0.720 ,0.820},
    {@"bLp",0.750 ,0.850},
    {@"bP",0.700 ,0.800},
    {@"bp",0.730 ,0.830},
    {@"bPG",0.830 ,0.930},
    {@"bPp",0.730 ,0.830},
    {@"bPpG",0.860 ,0.960},
    {@"bT",0.700 ,0.800},
    {@"btF",1.190 ,1.290},
    {@"fdF",1.020 ,1.120},
    {@"fF",0.870 ,1.020},
    {@"fG",0.830 ,0.930},
    {@"fL",0.740 ,0.840},
    {@"fP",0.740 ,0.840},
    {@"fp",0.770 ,0.870},
    {@"fpG",0.860 ,0.960},
    {@"fPG",0.830 ,0.930},
    {@"fPpG",0.860 ,0.960},
    {@"fT",0.740 ,0.840},
    {@"fTG",0.830 ,0.930},
    {@"fTp",0.770 ,0.870},
#ifdef PICKER_AIR_3TYPE
};

AirDdArray    airddarray_3d[]=
{
#endif
    {@"-",0.000 ,0.000},
    {@"3o",0.710 ,0.810},
    {@"3oG",0.840 ,0.960},
    {@"3op",0.740 ,0.840},
    {@"7o",0.830 ,0.980},
    {@"7oG",0.960 ,1.130},
    {@"7op",0.860 ,1.010},
    {@"7opG",0.990 ,1.160},
    {@"7oPG",0.960 ,1.130},
    {@"7oppg",0.890 ,1.040},
    {@"10o",0.990 ,1.090},
    {@"10oG",1.120 ,1.240},
    {@"10op",1.020 ,1.120},
    {@"10opG",1.150 ,1.270},
    {@"14o",1.110 ,1.210},
    {@"14oG",1.240 ,1.340},
    {@"14op",1.140 ,1.240},
    {@"l",0.710 ,0.810},
    {@"lF",0.840 ,0.930},
    {@"lFP",0.840 ,0.930},
    {@"lG",0.830 ,0.940},
    {@"lGF",0.970 ,1.090},
    {@"lL",0.730 ,0.830},
    {@"lP",0.710 ,0.810},
    {@"lp",0.740 ,0.840},
    {@"lpF",0.870 ,0.970},
    {@"lpG",0.860 ,0.970},
    {@"lPG",0.830 ,0.940},
    {@"lT",0.710 ,0.810},
#ifdef PICKER_AIR_3TYPE
};

AirDdArray    airddarray_ur[]=
{
#endif
    {@"-",0.000 ,0.000},
    {@"3",0.650 ,0.750},
    {@"7",0.850 ,1.000},
    {@"3G",0.780 ,0.900},
    {@"3p",0.680 ,0.780},
    {@"3pG",0.810 ,0.930},
    {@"3pp",0.710 ,0.810},
    {@"3ppp",0.740 ,0.840},
    {@"3w",0.710 ,0.810},
    {@"3ww",0.770 ,0.870},
    {@"7G",0.980 ,1.150},
    {@"7p",0.880 ,1.030},
    {@"7pG",1.010 ,1.180},
    {@"7pp",0.910 ,1.060},
    {@"7ppp",0.940 ,1.090},
    {@"7w",0.910 ,1.060},
    {@"7ww",0.970 ,1.120},
    {@"D",0.410 ,0.510},
    {@"DD",0.560 ,0.660},
    {@"DDD",0.700 ,0.800},
    {@"DDDG",0.830 ,0.930},
    {@"DDG",0.690 ,0.790},
    {@"DDS",0.670 ,0.770},
    {@"DDT",0.670 ,0.770},
    {@"DDTS",0.750 ,0.850},
    {@"DDTT",0.750 ,0.850},
    {@"DDTTS",0.790 ,0.890},
    {@"DG",0.540 ,0.640},
    {@"DK",0.560 ,0.660},
    {@"DKG",0.690 ,0.790},
    {@"DLD",0.890 ,0.990},
    {@"DS",0.530 ,0.630},
    {@"DSG",0.660 ,0.760},
    {@"DT",0.530 ,0.630},
    {@"DTG",0.660 ,0.760},
    {@"DTS",0.640 ,0.740},
    {@"DTSG",0.770 ,0.870},
    {@"DTT",0.640 ,0.740},
    {@"DTTG",0.770 ,0.870},
    {@"DTTS",0.720 ,0.820},
    {@"DTTSG",0.850 ,0.950},
    {@"DXS",0.670 ,0.770},
    {@"DXSG",0.800 ,0.900},
    {@"K",0.410 ,0.510},
    {@"KD",0.560 ,0.660},
    {@"KDD",0.700 ,0.800},
    {@"KM",0.560 ,0.660},
    {@"KMG",0.690 ,0.790},
    {@"KT",0.530 ,0.630},
    {@"KTT",0.640 ,0.740},
    {@"KX",0.560 ,0.660},
    {@"KXG",0.690 ,0.790},
    {@"KY",0.560 ,0.660},
    {@"KYG",0.690 ,0.790},
    {@"M",0.410 ,0.510},
    {@"MG",0.540 ,0.640},
    {@"MS",0.530 ,0.630},
    {@"MSG",0.660 ,0.760},
    {@"S",0.380 ,0.480},
    {@"SD",0.530 ,0.630},
    {@"SDG",0.660 ,0.760},
    {@"SG",0.510 ,0.610},
    {@"SM",0.530 ,0.630},
    {@"SS",0.500 ,0.600},
    {@"SSG",0.630 ,0.730},
    {@"SSS",0.610 ,0.710},
    {@"SSSG",0.740 ,0.840},
    {@"ST",0.500 ,0.600},
    {@"STG",0.630 ,0.730},
    {@"STK",0.640 ,0.740},
    {@"STKG",0.770 ,0.870},
    {@"STS",0.610 ,0.710},
    {@"STSG",0.740 ,0.840},
    {@"STT",0.610 ,0.710},
    {@"STTG",0.740 ,0.840},
    {@"STTK",0.720 ,0.820},
    {@"STTKG",0.850 ,0.950},
    {@"STTS",0.690 ,0.790},
    {@"STTSG",0.820 ,0.920},
    {@"STTX",0.720 ,0.820},
    {@"STTXG",0.850 ,0.950},
    {@"STTY",0.720 ,0.820},
    {@"STTYG",0.850 ,0.950},
    {@"STX",0.640 ,0.740},
    {@"STXG",0.770 ,0.870},
    {@"STY",0.640 ,0.740},
    {@"STYG",0.770 ,0.870},
    {@"SX",0.530 ,0.630},
    {@"SXG",0.660 ,0.760},
    {@"SXS",0.640 ,0.740},
    {@"SXSG",0.770 ,0.870},
    {@"SXSXS",0.790 ,0.890},
    {@"SY",0.530 ,0.630},
    {@"SYG",0.660 ,0.760},
    {@"SYS",0.640 ,0.740},
    {@"SYSG",0.770 ,0.870},
    {@"SZ",0.520 ,0.620},
    {@"SZG",0.650 ,0.750},
    {@"T",0.380 ,0.480},
    {@"TD",0.530 ,0.630},
    {@"TDG",0.660 ,0.760},
    {@"TG",0.510 ,0.610},
    {@"TK",0.530 ,0.630},
    {@"TKG",0.660 ,0.760},
    {@"TM",0.530 ,0.630},
    {@"TMG",0.660 ,0.760},
    {@"TS",0.500 ,0.600},
    {@"TSG",0.630 ,0.730},
    {@"TSS",0.610 ,0.710},
    {@"TSSG",0.740 ,0.840},
    {@"TST",0.610 ,0.710},
    {@"TSTG",0.740 ,0.840},
    {@"TSTS",0.690 ,0.790},
    {@"TSTSG",0.820 ,0.920},
    {@"TT",0.500 ,0.600},
    {@"TTD",0.640 ,0.740},
    {@"TTDD",0.750 ,0.850},
    {@"TTDDG",0.880 ,0.980},
    {@"TTG",0.630 ,0.730},
    {@"TTK",0.640 ,0.740},
    {@"TTKG",0.770 ,0.870},
    {@"TTS",0.610 ,0.710},
    {@"TTSG",0.740 ,0.840},
    {@"TTT",0.610 ,0.710},
    {@"TTTG",0.740 ,0.840},
    {@"TTTS",0.690 ,0.790},
    {@"TTTSG",0.820 ,0.920},
    {@"TTTT",0.690 ,0.790},
    {@"TTTTG",0.820 ,0.920},
    {@"TTTTS",0.730 ,0.830},
    {@"TTTTT",0.730 ,0.830},
    {@"TTTTTG",0.860 ,0.960},
    {@"X",0.410 ,0.510},
    {@"XG",0.540 ,0.640},
    {@"XK",0.560 ,0.660},
    {@"XKG",0.690 ,0.790},
    {@"XKX",0.700 ,0.800},
    {@"XKXG",0.830 ,0.930},
    {@"XS",0.530 ,0.630},
    {@"XSG",0.660 ,0.760},
    {@"XSX",0.670 ,0.770},
    {@"XSXG",0.800 ,0.900},
    {@"XTT",0.640 ,0.740},
    {@"XTTG",0.770 ,0.870},
    {@"XTTS",0.720 ,0.820},
    {@"XTTSG",0.850 ,0.950},
    {@"XTTT",0.720 ,0.820},
    {@"XTTTG",0.850 ,0.950},
    {@"XTTX",0.750 ,0.850},
    {@"Y",0.410 ,0.510},
    {@"YG",0.540 ,0.640},
    {@"YK",0.560 ,0.660},
    {@"YKG",0.690 ,0.790},
    {@"YKX",0.700 ,0.800},
    {@"YKXG",0.830 ,0.930},
    {@"YS",0.530 ,0.630},
    {@"YS",0.530 ,0.630},
    {@"YSG",0.660 ,0.760},
    {@"YSG",0.660 ,0.760},
    {@"YT",0.530 ,0.630},
    {@"YTG",0.660 ,0.760},
    {@"YTS",0.640 ,0.740},
    {@"YTSG",0.770 ,0.870},
    {@"YTTS",0.720 ,0.820},
    {@"YTTSG",0.850 ,0.950},
    {@"YXS",0.670 ,0.770},
    {@"YXSG",0.800 ,0.900},
    {@"Z",0.400 ,0.500},
    {@"ZG",0.530 ,0.630},
    {@"10",1.020 ,1.120},
    {@"10G",1.150 ,1.270},
    {@"10p",1.050 ,1.150},
    {@"10pG",1.180 ,1.300},
    {@"10pp",1.080 ,1.180},
    {@"10ppG",1.210 ,1.330},
};

//static const float AREA_PICKER_ACCESSORY_HEIGHT = 44;
//static const float AREA_PICKER_HEIGHT = 216;

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad
{
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
    
    _txt_judgepoint.text =  [NSString stringWithFormat:@"%2.1f", _sld_airpoint.value];
    _txt_airdd.text = [NSString stringWithFormat:@"%1.3f", 0.0];
    f_judgepoint = _sld_airpoint.value;
    ddlist = [[NSMutableArray alloc] init];
    for (int i=0; i<(sizeof(airddarray)/sizeof(AirDdArray)-1); i++) {
        [ddlist addObject:airddarray[i].airname];
    }
    
    _txt_judgepoint2.text =  [NSString stringWithFormat:@"%2.1f", _sld_airpoint2.value];
    _txt_airdd2.text = [NSString stringWithFormat:@"%1.3f", 0.0];
    f_judgepoint2 = _sld_airpoint2.value;
    ddlist2 = [[NSMutableArray alloc] init];
    for (int i=0; i<(sizeof(airddarray)/sizeof(AirDdArray)-1); i++) {
        [ddlist2 addObject:airddarray[i].airname];
    }
    
    // CGRectの生成
    
    //CGRect rect = CGRectMake(200, 94, 120, 137);
    CGRect rect = CGRectMake(200, self.txt_airpoint.frame.origin.y+40, 120, 137);
    //CGRect rect2 = CGRectMake(200, 318, 120, 137);
    CGRect rect2 = CGRectMake(200, self.txt_airpoint2.frame.origin.y+40, 120, 137);
    //位置とサイズを設定
    _pickerView = [[UIPickerView alloc] init];
    _pickerView.frame = rect;
    _pickerView.delegate = self;
    _pickerView.dataSource = self;
    _pickerView.showsSelectionIndicator = YES;
    _pickerView.tag=1;
    [self.view addSubview:_pickerView];
    
    //位置とサイズを設定
    _pickerView2 = [[UIPickerView alloc] init];
    _pickerView2.frame = rect2;
    _pickerView2.delegate = self;
    _pickerView2.dataSource = self;
    _pickerView2.showsSelectionIndicator = YES;
    _pickerView2.tag=2;
    [self.view addSubview:_pickerView2];
    isLoaded = true;

    //グラブボタン起動時はdisable
    self.GgrabMax1.enabled=false;
    self.GtouchMax1.enabled=false;
    self.GnograbMax1.enabled=false;
    self.GgrabMax2.enabled=false;
    self.GtouchMax2.enabled=false;
    self.GnograbMax2.enabled=false;
    
    
    _AirJudgePointSgm1.selectedSegmentIndex=2;
    _AirJudgePointSgm2.selectedSegmentIndex=2;
    _sld_airpoint.value = 5.0;
    _sld_airpoint2.value = 5.0;
    [self summaryAirPoint];

}

-(BOOL)isClassLoaded{
    return isLoaded;
}


- (void)viewDidAppear:(BOOL)animated{
    [self summaryAirPoint];
}

-(float)getAirPoint{
    if (_txt_judgepoint==nil) {
        [self viewDidLoad];
    }
    return f_airpoint;
}

-(NSString*)getAirCode{
    return str_airdd;
}

-(float)getAirPoint2{
    if (_txt_judgepoint==nil) {
        [self viewDidLoad];
    }
    return f_airpoint2;
}

-(NSString*)getAirCode2{
    return str_airdd2;
}

-(NSString *)getCurrentAirLevel :(float) level{
    int index = 0;
    if (0.0==level) {
        index = 0;
    }else if (0.1<level && level<=2.0) {
        index = 1;
    }else if (2.0<level && level<=4.0) {
        index = 2;
    }else if (4.0<level && level<=6.0) {
        index = 3;
    }else if (6.0<level && level<=8.0) {
        index = 4;
    }else if (8.0<level) {
        index = 5;
    }
    return levelJudgeStr[index];
}


-(void)summaryAirPoint{
    NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    sexindex = _sgmSex.selectedSegmentIndex;
    //1st Air
    if(sexindex==0){
        f_airdd = (airddarray+cur_row)->dd_point_m;
    }else{
        f_airdd = (airddarray+cur_row)->dd_point_f;
    }
    _txt_airdd.text = [NSString stringWithFormat:@"%1.3f", f_airdd];
    f_judgepoint = [[NSString stringWithFormat:@"%2.1f", _sld_airpoint.value] floatValue];
    f_airpoint = f_judgepoint*f_airdd;
    f_airpoint = f_airpoint>10.0?10.0:f_airpoint;
    
    _txt_judgepoint.text = [NSString stringWithFormat:@"%2.1f", f_judgepoint];
    _lbl_airlevel.text = [self getCurrentAirLevel:f_judgepoint];
    _txt_airpoint.text = [NSString stringWithFormat:@"%2.2f", f_airpoint];
    
    //2nd Air
    if(sexindex==0){
        f_airdd2 = (airddarray+cur_row2)->dd_point_m;
    }else{
        f_airdd2 = (airddarray+cur_row2)->dd_point_f;
    }
    _txt_airdd2.text = [NSString stringWithFormat:@"%1.3f", f_airdd2];
    f_judgepoint2 = [[NSString stringWithFormat:@"%2.1f", _sld_airpoint2.value] floatValue];
    f_airpoint2 = f_judgepoint2*f_airdd2;
    f_airpoint2 = f_airpoint2>10.0?10.0:f_airpoint2;
    
    _txt_judgepoint2.text = [NSString stringWithFormat:@"%2.1f", f_judgepoint2];
    _lbl_airlevel2.text = [self getCurrentAirLevel:f_judgepoint2];
    _txt_airpoint2.text = [NSString stringWithFormat:@"%2.2f", f_airpoint2];
    
    NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}
- (IBAction)onTouchUpAxis:(id)sender {
    if (sender == _AirGreenMax1) {
        _sld_airpoint.maximumValue = 10;
    }else if (sender == _AirYellowMax1){
        _sld_airpoint.maximumValue = 8;
    }else if (sender == _AirRedMax1){
        _sld_airpoint.maximumValue = 4;
    }else if (sender == _AirGreenMax2) {
        _sld_airpoint2.maximumValue = 10;
    }else if (sender == _AirYellowMax2){
        _sld_airpoint2.maximumValue = 8;
    }else if (sender == _AirRedMax2){
        _sld_airpoint2.maximumValue = 4;
    }
    [self summaryAirPoint];

}
- (IBAction)onTouchUpGrabing:(id)sender {
    if (sender == _GgrabMax1) {
        _sld_airpoint.maximumValue = 10;
    }else if (sender == _GtouchMax1){
        _sld_airpoint.maximumValue = 6;
    }else if (sender == _GnograbMax1){
        _sld_airpoint.maximumValue = 4;
    }else if (sender == _GgrabMax2) {
        _sld_airpoint2.maximumValue = 10;
    }else if (sender == _GtouchMax2){
        _sld_airpoint2.maximumValue = 6;
    }else if (sender == _GnograbMax2){
        _sld_airpoint2.maximumValue = 4;
    }
    [self summaryAirPoint];
}

- (IBAction)onChangeValueAirPoint:(id)sender {
    //NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    [self summaryAirPoint];
    //f_judgepoint = [[NSString stringWithFormat:@"%2.1f", _sld_airpoint.value] floatValue];
    //_txt_judgepoint.text = [NSString stringWithFormat:@"%2.1f", f_judgepoint];
    //_lbl_airlevel.text = [self getCurrentAirLevel:f_judgepoint];
    //NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

- (IBAction)onChangeValueAirPoint2:(id)sender {
    //NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    [self summaryAirPoint];
    //f_judgepoint2 = [[NSString stringWithFormat:@"%2.1f", _sld_airpoint2.value] floatValue];
    //_txt_judgepoint2.text = [NSString stringWithFormat:@"%2.1f", f_judgepoint2];
    //_lbl_airlevel2.text = [self getCurrentAirLevel:f_judgepoint2];
    //NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

- (IBAction)onChangeValueAirCode:(id)sender {
    NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    //[self changeAirType];
    NSInteger selectedIndex = 0;
    if(_sgmAir.selectedSegmentIndex==0){
        selectedIndex = 0;//フリップ系の位置
    }else if(_sgmAir.selectedSegmentIndex==1){
        selectedIndex = 27;//３Dの位置
    }else{
        selectedIndex = 56;//アップライトの位置
    }
    [self.pickerView selectRow:selectedIndex inComponent:0 animated:YES];
}

- (IBAction)onChangeValueAirCode2:(id)sender {
    NSInteger selectedIndex = 0;
    if(_sgmAir2.selectedSegmentIndex==0){
        selectedIndex = 0;//フリップ系の位置
    }else if(_sgmAir2.selectedSegmentIndex==1){
        selectedIndex = 27;//３Dの位置
    }else{
        selectedIndex = 56;//アップライトの位置
    }
    [self.pickerView2 selectRow:selectedIndex inComponent:0 animated:YES];
}

-(IBAction)onChangeValueSex:(id)sender {
    sexindex = self.sgmSex.selectedSegmentIndex;
    [self summaryAirPoint];
    //ベース
	FirstViewController *basepoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_BASEPOINT];
    [basepoint setSexType:sexindex];
    //リザルト
	ResultViewController *resultpoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_RESULTPOINT];
    [resultpoint setSexType:sexindex];
    //タイム
	SpeedViewController *speedpoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_TIMEPOINT];
    if ([speedpoint isClassLoaded]==false) {
        [speedpoint viewDidLoad];
    }
    [speedpoint setSexType:sexindex];
    //エアポイント1
	AirViewController *airpoint = [self.tabBarController.viewControllers objectAtIndex:TAB_NAB_AIR1POINT];
    if (airpoint!=self) {
        if ([airpoint isClassLoaded]==false) {
            [airpoint viewDidLoad];
        }
        [airpoint setSexType:sexindex];
    }
}

-(void)setSexType:(NSInteger)sex{
    self.sgmSex.selectedSegmentIndex=sex;
    sexindex = self.sgmSex.selectedSegmentIndex;
    [self summaryAirPoint];
}

- (NSInteger)numberOfComponentsInPickerView:(nonnull UIPickerView *)pickerView {
    return 1;
}

- (NSInteger)pickerView:(nonnull UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    switch(component) {
        case(0):
            if(pickerView.tag==1){
                return [ddlist count];
            }else{
                //if(pickerView.tag==2){
                return [ddlist2 count];
            }
            break;
    }
    return 0;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    switch (component) {
        case(0):
            if(pickerView.tag==1){
                return [ddlist objectAtIndex:row];
            }else{
                //if(pickerView.tag==2){
                return [ddlist2 objectAtIndex:row];
            }
            break;
    }
    return nil;
}

- (void)pickerView:(UIPickerView *)pickerView
      didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
    NSLog(@"ログ（%-20s,%-24s:%5d）in    cur_row : %ld\n", __FILE__, __PRETTY_FUNCTION__, __LINE__, (long)row);
    if(pickerView.tag==_pickerView.tag){
        if(_sgmSex.selectedSegmentIndex==0){
            f_airdd = airddarray[row].dd_point_m;
        }else{
            f_airdd = airddarray[row].dd_point_f;
        }
        cur_row = (int)row;
        str_airdd = airddarray[row].airname;
        //Gを含むかどうか
        NSString *serach = @"G";
        NSRange range = [str_airdd rangeOfString:serach];
        if (range.location != NSNotFound) {
            self.GgrabMax1.enabled=true;
            self.GtouchMax1.enabled=true;
            self.GnograbMax1.enabled=true;
        }else{
            self.GgrabMax1.enabled=false;
            self.GtouchMax1.enabled=false;
            self.GnograbMax1.enabled=false;
            _sld_airpoint.maximumValue = 10;
        }
    }//else{
    if(pickerView.tag==_pickerView2.tag){
        if(_sgmSex.selectedSegmentIndex==0){
            f_airdd2 = airddarray[row].dd_point_m;
        }else{
            f_airdd2 = airddarray[row].dd_point_f;
        }
        cur_row2 = (int)row;
        str_airdd2 = airddarray[row].airname;
        //Gを含むかどうか
        NSString *serach = @"G";
        NSRange range = [str_airdd2 rangeOfString:serach];
        if (range.location != NSNotFound) {
            self.GgrabMax2.enabled=true;
            self.GtouchMax2.enabled=true;
            self.GnograbMax2.enabled=true;
        }else{
            self.GgrabMax2.enabled=false;
            self.GtouchMax2.enabled=false;
            self.GnograbMax2.enabled=false;
            _sld_airpoint2.maximumValue = 10;
        }
    }
    [self summaryAirPoint];
}
- (IBAction)onChangeAirJudgeLevelPosition1:(id)sender {
    if(_AirJudgePointSgm1.selectedSegmentIndex==0){
        _sld_airpoint.value = 1.0;
    }else if(_AirJudgePointSgm1.selectedSegmentIndex==1){
        _sld_airpoint.value = 3.0;
    }else if(_AirJudgePointSgm1.selectedSegmentIndex==2){
        _sld_airpoint.value = 5.0;
    }else if(_AirJudgePointSgm1.selectedSegmentIndex==3){
        _sld_airpoint.value = 7.0;
    }else if(_AirJudgePointSgm1.selectedSegmentIndex==4){
        _sld_airpoint.value = 9.0;
    }
    [self summaryAirPoint];
}
- (IBAction)onChangeAirJudgeLevelPosition2:(id)sender {
    if(_AirJudgePointSgm2.selectedSegmentIndex==0){
        _sld_airpoint2.value = 1.0;
    }else if(_AirJudgePointSgm2.selectedSegmentIndex==1){
        _sld_airpoint2.value = 3.0;
    }else if(_AirJudgePointSgm2.selectedSegmentIndex==2){
        _sld_airpoint2.value = 5.0;
    }else if(_AirJudgePointSgm2.selectedSegmentIndex==3){
        _sld_airpoint2.value = 7.0;
    }else if(_AirJudgePointSgm2.selectedSegmentIndex==4){
        _sld_airpoint2.value = 9.0;
    }
    [self summaryAirPoint];
}

- (IBAction)txt_total_deduction:(id)sender {
}
@end
