//
//  MeasureViewController.m
//  MTJudge
//
//  Created by Yasunori Nagashima on 2019/06/03.
//  Copyright © 2019 Yasunori Nagashima. All rights reserved.
//

#import "MeasureViewController.h"

@interface MeasureViewController ()

@end

@implementation MeasureViewController{
    CMMotionManager *motionMgr;
    CLLocationManager *locationMgr;
}

#if false
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}
#endif

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    motionMgr = [[CMMotionManager alloc] init];
    //[self setupAccellerometer];
    self.AcceleSwitch.on=NO;

    [self setupLocationManager];

}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
}

- (void)viewDidDisappear:(BOOL)animated {
    [motionMgr stopAccelerometerUpdates];
    // 位置情報の取得停止
    if ([CLLocationManager locationServicesEnabled]) {
        [locationMgr stopUpdatingLocation];
    }
    self.AcceleSwitch.on = NO;
}

-(void)setupAccellerometer{
    if(motionMgr.accelerometerAvailable){
        motionMgr.accelerometerUpdateInterval = 0.5; //5Hz
        //ハンドラーを指定
        CMAccelerometerHandler handler = ^(CMAccelerometerData *data, NSError *error){
            float g = -0.98;
            float pi = 3.14152692;
            float xvalue = data.acceleration.x;
            float yvalue = data.acceleration.y;
            float zvalue = data.acceleration.z;
            
            //ローパスフィルタ
            acceleX = Alpha * xvalue + acceleX * (1.0 - Alpha);
            acceleY = Alpha * yvalue + acceleY * (1.0 - Alpha);
            acceleZ = Alpha * zvalue + acceleZ * (1.0 - Alpha);

            //double xangle = asin(fabs(xvalue/g)>1?1:fabs(xvalue/g))*180/pi;
            //double yangle = asin(fabs(yvalue/g)>1?1:fabs(yvalue/g))*180/pi;
            //double zangle = fabs(asin(fabs(zvalue/g)>1?1:fabs(zvalue/g))*180/pi-90);

            double xangle = asin(fabs(acceleX/g)>1?1:fabs(acceleX/g))*180/pi;
            double yangle = asin(fabs(acceleY/g)>1?1:fabs(acceleY/g))*180/pi;
            double zangle = fabs(asin(fabs(acceleZ/g)>1?1:fabs(acceleZ/g))*180/pi-90);

            //加速度表示
            //self.X_value.text = [NSString stringWithFormat:@"%-8.6f", xvalue];
            //self.Y_value.text = [NSString stringWithFormat:@"%-8.6f", yvalue];
            //self.Z_value.text = [NSString stringWithFormat:@"%-8.6f", zvalue];
            self.X_value.text = [NSString stringWithFormat:@"%-8.6f", acceleX];
            self.Y_value.text = [NSString stringWithFormat:@"%-8.6f", acceleY];
            self.Z_value.text = [NSString stringWithFormat:@"%-8.6f", acceleZ];

            //傾き表示
            self.X_angle.text = [NSString stringWithFormat:@"%4.1f", xangle];
            self.Y_angle.text = [NSString stringWithFormat:@"%4.1f", yangle];
            self.Z_angle.text = [NSString stringWithFormat:@"%4.1f", zangle];
       };
        
        if(self.AcceleSwitch.isOn){
            [motionMgr startAccelerometerUpdatesToQueue:[NSOperationQueue currentQueue] withHandler:handler];
        }
    }
}

- (void)setupLocationManager
{
    // インスタンスを生成
    locationMgr = [[CLLocationManager alloc] init];
    // iOS 8以上
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0) {
        [locationMgr requestWhenInUseAuthorization];
    }
    
    // デリゲートを設定
    locationMgr.delegate = self;
    locationMgr.distanceFilter = 10;
}

#if false
- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
{
    _elevation.text= [NSString stringWithFormat:@"%.2f m", newLocation.altitude];
}
#endif

// 位置情報が更新されるたびに呼ばれる
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    //_Altitude.text= [NSString stringWithFormat:@"%.2f m", locations.firstObject.altitude];
    self.Altitude.text= [NSString stringWithFormat:@"%7.2f m", locations.firstObject.altitude];
    self.Latitude.text= [NSString stringWithFormat:@"%+.6f°", locations.firstObject.coordinate.latitude];
    self.Longtitude.text= [NSString stringWithFormat:@"%+.6f°", locations.firstObject.coordinate.longitude];
}

- (IBAction)onAcceleSwich:(id)sender {
    if(self.AcceleSwitch.isOn){
        [self setupAccellerometer];
        if ([CLLocationManager locationServicesEnabled])
        {
            // 位置情報の取得開始
            [locationMgr startUpdatingLocation];
        }
    }else{
        [motionMgr stopAccelerometerUpdates];
        //表示
        self.X_value.text = [NSString stringWithFormat:@"%f", 0.0f];
        self.Y_value.text = [NSString stringWithFormat:@"%f", 0.0f];
        self.Z_value.text = [NSString stringWithFormat:@"%f", 0.0f];
    }
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
