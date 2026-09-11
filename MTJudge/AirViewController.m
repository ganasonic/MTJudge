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


#ifndef PICKER_AIR_DATA_FROM_JSON
#define AIRPOS_FLIP 0
#define AIRPOS_3D 14
#define AIRPOS_UP 32
#endif

@interface AirViewController ()
@end

@implementation AirViewController

typedef struct _AirDdArray {
    char    airname[8];
    float   dd_point_m;
    float   dd_point_f;
} AirDdArray;

NSString *levelJudgeStr[] = {
    @"No Point",
    @"Very Poor Jump",
    @"Poor Jump",
    @"Average Jump",
    @"Good Jump",
    @"Excellent Jump"
};

#ifndef PICKER_AIR_DATA_FROM_JSON
AirDdArray    airddarray[]=
{/*2023/2024シーズン*/
    {@"bT",0.680,0.780},
    {@"bL",0.710,0.810},
    {@"bp",0.710,0.810},
    {@"bP",0.680,0.780},
    {@"bG",0.820,0.920},
    {@"bF",0.880,0.980},
    {@"bdF",1.050,1.150},
    {@"btF",1.220,1.320},
    {@"fT",0.680,0.780},
    {@"fP",0.680,0.780},
    {@"fp",0.710,0.810},
    {@"fG",0.820,0.920},
    {@"fF",0.880,0.980},

    {@"-",0.000,0.000},
    {@"3op",0.710,0.810},
    {@"3oG",0.820,0.920},
    {@"7oG",1.010,1.110},
    {@"7op",0.880,0.980},
    {@"10oG",1.200,1.300},
    {@"10op",1.050,1.150},
    {@"14op",1.220,1.320},
    {@"14oG",1.390,1.490},
    {@"l",0.680,0.780},
    {@"lp",0.710,0.810},
    {@"lG",0.820,0.920},
    {@"lF",0.850,0.950},
    {@"lpF",0.880,0.980},
    {@"lGF",1.010,1.110},

    {@"3",0.680,0.780},
    {@"3G",0.820,0.920},
    {@"3p",0.710,0.810},
    {@"7",0.850,0.950},
    {@"7G",1.010,1.110},
    {@"7p",0.880,0.980},
    {@"10",1.020,1.120},
    {@"10G",1.200,1.300},
    {@"10p",1.050,1.150},
    {@"D",0.410,0.510},
    {@"DD",0.550,0.650},
    {@"DDD",0.680,0.780},
    {@"DDDG",0.680,0.780},
    {@"DDG",0.550,0.650},
    {@"DDS",0.650,0.750},
    {@"DDT",0.650,0.750},
    {@"DDTS",0.740,0.840},
    {@"DDTT",0.740,0.840},
    {@"DDTTS",0.820,0.920},
    {@"DG",0.410,0.510},
    {@"DK",0.550,0.650},
    {@"DKG",0.550,0.650},
    {@"DS",0.520,0.620},
    {@"DSG",0.520,0.620},
    {@"DT",0.520,0.620},
    {@"DTG",0.520,0.620},
    {@"DTS",0.620,0.720},
    {@"DTSG",0.620,0.720},
    {@"DTT",0.620,0.720},
    {@"DTTG",0.620,0.720},
    {@"DTTS",0.710,0.810},
    {@"DTTSG",0.710,0.810},
    {@"DXS",0.650,0.750},
    {@"DXSG",0.650,0.750},
    {@"K",0.410,0.510},
    {@"KD",0.550,0.650},
    {@"KDD",0.680,0.780},
    {@"KM",0.550,0.650},
    {@"KMG",0.550,0.650},
    {@"KT",0.520,0.620},
    {@"KTT",0.620,0.720},
    {@"KX",0.550,0.650},
    {@"KXG",0.550,0.650},
    {@"KY",0.550,0.650},
    {@"KYG",0.550,0.650},
    {@"M",0.410,0.510},
    {@"MG",0.410,0.510},
    {@"MS",0.520,0.620},
    {@"MSG",0.520,0.620},
    {@"S",0.380,0.480},
    {@"SD",0.520,0.620},
    {@"SDG",0.520,0.620},
    {@"SG",0.380,0.480},
    {@"SM",0.520,0.620},
    {@"SS",0.490,0.590},
    {@"SSG",0.490,0.590},
    {@"SSS",0.590,0.690},
    {@"SSSG",0.590,0.690},
    {@"ST",0.490,0.590},
    {@"STG",0.490,0.590},
    {@"STK",0.620,0.720},
    {@"STKG",0.620,0.720},
    {@"STS",0.590,0.690},
    {@"STSG",0.590,0.690},
    {@"STT",0.590,0.690},
    {@"STTG",0.590,0.690},
    {@"STTK",0.710,0.810},
    {@"STTKG",0.710,0.810},
    {@"STTS",0.680,0.780},
    {@"STTSG",0.680,0.780},
    {@"STTX",0.710,0.810},
    {@"STTXG",0.710,0.810},
    {@"STTY",0.710,0.810},
    {@"STTYG",0.710,0.810},
    {@"STX",0.620,0.720},
    {@"STXG",0.620,0.720},
    {@"STY",0.620,0.720},
    {@"STYG",0.620,0.720},
    {@"SX",0.520,0.620},
    {@"SXG",0.520,0.620},
    {@"SXS",0.620,0.720},
    {@"SXSG",0.620,0.720},
    {@"SXSXS",0.820,0.920},
    {@"SY",0.520,0.620},
    {@"SYG",0.520,0.620},
    {@"SYS",0.620,0.720},
    {@"SYSG",0.620,0.720},
    {@"SZ",0.510,0.610},
    {@"SZG",0.510,0.610},
    {@"T",0.380,0.480},
    {@"TD",0.520,0.620},
    {@"TDG",0.520,0.620},
    {@"TG",0.380,0.480},
    {@"TK",0.520,0.620},
    {@"TKG",0.520,0.620},
    {@"TM",0.520,0.620},
    {@"TMG",0.520,0.620},
    {@"TS",0.490,0.590},
    {@"TSG",0.490,0.590},
    {@"TSS",0.590,0.690},
    {@"TSSG",0.590,0.690},
    {@"TST",0.590,0.690},
    {@"TSTG",0.590,0.690},
    {@"TSTS",0.680,0.780},
    {@"TSTSG",0.680,0.780},
    {@"TT",0.490,0.590},
    {@"TTD",0.620,0.720},
    {@"TTDD",0.740,0.840},
    {@"TTDDG",0.740,0.840},
    {@"TTG",0.490,0.590},
    {@"TTK",0.620,0.720},
    {@"TTKG",0.620,0.720},
    {@"TTS",0.590,0.690},
    {@"TTSG",0.590,0.690},
    {@"TTT",0.590,0.690},
    {@"TTTG",0.590,0.690},
    {@"TTTS",0.680,0.780},
    {@"TTTSG",0.680,0.780},
    {@"TTTT",0.680,0.780},
    {@"TTTTG",0.680,0.780},
    {@"TTTTS",0.760,0.860},
    {@"TTTTT",0.760,0.860},
    {@"TTTTTG",0.760,0.860},
    {@"X",0.410,0.510},
    {@"XG",0.410,0.510},
    {@"XK",0.550,0.650},
    {@"XKG",0.550,0.650},
    {@"XKX",0.680,0.780},
    {@"XKXG",0.680,0.780},
    {@"XS",0.520,0.620},
    {@"XSG",0.520,0.620},
    {@"XSX",0.650,0.750},
    {@"XSXG",0.650,0.750},
    {@"XTT",0.620,0.720},
    {@"XTTG",0.620,0.720},
    {@"XTTS",0.710,0.810},
    {@"XTTSG",0.710,0.810},
    {@"XTTT",0.710,0.810},
    {@"XTTTG",0.710,0.810},
    {@"XTTX",0.740,0.840},
    {@"Y",0.410,0.510},
    {@"YG",0.410,0.510},
    {@"YK",0.550,0.650},
    {@"YKG",0.550,0.650},
    {@"YKX",0.680,0.780},
    {@"YKXG",0.680,0.780},
    {@"YS",0.520,0.620},
    {@"YS",0.520,0.620},
    {@"YSG",0.520,0.620},
    {@"YSG",0.520,0.620},
    {@"YT",0.520,0.620},
    {@"YTG",0.520,0.620},
    {@"YTS",0.620,0.720},
    {@"YTSG",0.620,0.720},
    {@"YTTS",0.710,0.810},
    {@"YTTSG",0.710,0.810},
    {@"YXS",0.650,0.750},
    {@"YXSG",0.650,0.750},
    {@"Z",0.400,0.500},
    {@"ZG",0.400,0.500},
    {@"ZSG",0.510,0.610},
};
#else
AirDdArray *airddarray;
#endif

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

#ifdef PICKER_AIR_DATA_FROM_JSON
    [self loadJSONData];
#endif
#if false
    ddlist = [[NSMutableArray alloc] init];
    for (int i=0; i<(sizeof(airddarray)/sizeof(AirDdArray)-1); i++) {
        //[ddlist addObject:airddarray[i].airname];
        // C言語の文字列をNSStringに変換
        NSString *airnameString = [NSString stringWithUTF8String:airddarray[i].airname];
        [ddlist addObject:airnameString];
    }
#endif
    _txt_judgepoint2.text =  [NSString stringWithFormat:@"%2.1f", _sld_airpoint2.value];
    _txt_airdd2.text = [NSString stringWithFormat:@"%1.3f", 0.0];
    f_judgepoint2 = _sld_airpoint2.value;

#if false
    ddlist2 = [[NSMutableArray alloc] init];
    for (int i=0; i<(sizeof(airddarray)/sizeof(AirDdArray)-1); i++) {
        //[ddlist2 addObject:airddarray[i].airname];
        // C言語の文字列をNSStringに変換
        NSString *airnameString = [NSString stringWithUTF8String:airddarray[i].airname];
        [ddlist2 addObject:airnameString];
    }
#endif

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

#ifdef PICKER_AIR_DATA_FROM_JSON

- (void)loadJSONData {
    // 1. バージョン情報を取得
    NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedVersion = [defaults objectForKey:@"LastCopiedVersion"];
    
    // 2. ドキュメントディレクトリのパスとファイルマネージャを取得
    NSString *docsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString *filePath = [docsPath stringByAppendingPathComponent:@"data.json"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // 3. コピーが必要か判定
    if (![currentVersion isEqualToString:savedVersion]) {
        // アプリのバージョンが更新された場合、古いファイルを削除
        if ([fileManager fileExistsAtPath:filePath]) {
            NSError *removeError = nil;
            [fileManager removeItemAtPath:filePath error:&removeError];
            if (removeError) {
                NSLog(@"古いJSONファイルの削除に失敗しました: %@", removeError);
            }
        }
        
        // バンドルから新しいファイルをコピー
        NSString *sourcePath = [[NSBundle mainBundle] pathForResource:@"data" ofType:@"json"];
        if (sourcePath) {
            NSError *copyError = nil;
            [fileManager copyItemAtPath:sourcePath toPath:filePath error:&copyError];
            
            if (copyError) {
                NSLog(@"初期ファイルのコピーに失敗しました: %@", copyError);
            } else {
                NSLog(@"新しいJSONファイルをドキュメントディレクトリにコピーしました。");
                // コピー成功時に新しいバージョンを保存
                [defaults setObject:currentVersion forKey:@"LastCopiedVersion"];
            }
        }
    }
    // 4. ドキュメントディレクトリからJSONデータを読み込む
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    if (!data) {
        NSLog(@"JSONデータの読み込みに失敗しました。");
        return;
    }
    
    NSError *error = nil;
    NSDictionary *jsonDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    
    if (error || !jsonDictionary) {
        NSLog(@"JSONパースエラー: %@", error);
        return;
    }
    
    // 5. インデックス値をプロパティに代入する
    NSDictionary *indexes = jsonDictionary[@"indexes"];
    if (indexes) {
        self.AIRPOS_FLIP = [indexes[@"airpos_flip"] integerValue];
        self.AIRPOS_3D = [indexes[@"airpos_3d"] integerValue];
        self.AIRPOS_UP = [indexes[@"airpos_up"] integerValue];
    }
    
    // 6. data配列をairddarrayに代入する
    NSArray *dataArray = jsonDictionary[@"data"];
    if (dataArray) {
        // 既存のairddarrayを解放
        if (airddarray) {
            for (int i = 0; i < self.airddarrayCount; i++) {
                if (airddarray[i].airname[0]) {
                    // airnameのメモリを解放
                    //free((void *)airddarray[i].airname);
                }
            }
            free(airddarray);
            airddarray = NULL;
        }
        
        // 新しいJSONデータの件数に合わせてメモリを動的に確保
        self.airddarrayCount = [dataArray count];
        airddarray = (AirDdArray *)malloc(self.airddarrayCount * sizeof(AirDdArray));
        
        for (int i = 0; i < self.airddarrayCount; i++) {
            NSDictionary *item = dataArray[i];
            
            // NSStringをC言語の文字列に変換してメモリを確保
            NSString *airname = item[@"airname"];
            const char *cString = [airname UTF8String];
            strcpy((char *)airddarray[i].airname, cString);
            airddarray[i].dd_point_m = [item[@"dd_point_m"] floatValue];
            airddarray[i].dd_point_f = [item[@"dd_point_f"] floatValue];
        }

        // ここからが重要: ddlistをここで作成します
        ddlist = [[NSMutableArray alloc] init];
        for (int i=0; i < self.airddarrayCount; i++) {
            NSString *airnameString = [NSString stringWithUTF8String:airddarray[i].airname];
            [ddlist addObject:airnameString];
        }

        ddlist2 = [[NSMutableArray alloc] init];
        for (int i=0; i < self.airddarrayCount; i++) {
            NSString *airnameString = [NSString stringWithUTF8String:airddarray[i].airname];
            [ddlist2 addObject:airnameString];
        }

        // ピッカービューの再読み込み
        [_pickerView reloadAllComponents];
        [_pickerView2 reloadAllComponents];

    }
}
#endif


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
    NSInteger selectedIndex = self.AIRPOS_FLIP;
    if(_sgmAir.selectedSegmentIndex==0){
        selectedIndex = self.AIRPOS_FLIP;//フリップ系の位置
    }else if(_sgmAir.selectedSegmentIndex==1){
        selectedIndex = self.AIRPOS_3D;//３Dの位置
    }else{
        selectedIndex = self.AIRPOS_UP;//アップライトの位置
    }
    [self.pickerView selectRow:selectedIndex inComponent:0 animated:YES];
}

- (IBAction)onChangeValueAirCode2:(id)sender {
    NSInteger selectedIndex = self.AIRPOS_FLIP;
    if(_sgmAir2.selectedSegmentIndex==0){
        selectedIndex = self.AIRPOS_FLIP;//フリップ系の位置
    }else if(_sgmAir2.selectedSegmentIndex==1){
        selectedIndex = self.AIRPOS_3D;//３Dの位置
    }else{
        selectedIndex = self.AIRPOS_UP;//アップライトの位置
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
        //str_airdd = airddarray[row].airname;
        str_airdd = [NSString stringWithUTF8String:airddarray[row].airname];
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
        //str_airdd2 = airddarray[row].airname;
        str_airdd2 = [NSString stringWithUTF8String:airddarray[row].airname];
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
