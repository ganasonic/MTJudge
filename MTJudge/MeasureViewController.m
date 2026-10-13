//
//  MeasureViewController.m
//  MTJudge
//
//  Created by Yasunori Nagashima on 2019/06/03.
//  Copyright © 2019 Yasunori Nagashima. All rights reserved.
//

#import "MeasureViewController.h"
#import "MTJLocalization.h"

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
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) [self configureIPadLayout];
    motionMgr = [[CMMotionManager alloc] init];
    //[self setupAccellerometer];
    self.AcceleSwitch.on=NO;

    [self setupLocationManager];

}

// The legacy root scales frames that Auto Layout has already positioned for iPad.
// This screen uses safe-area constraints on iPad instead; iPhone keeps its storyboard.
- (UILabel *)iPadLabel:(NSString *)text style:(UIFontTextStyle)style {
    UILabel *label = [UILabel new];
    label.text = text; label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0; label.lineBreakMode = NSLineBreakByWordWrapping;
    return label;
}
- (UIView *)iPadMeasurement:(UILabel *)value title:(NSString *)title {
    value.transform = CGAffineTransformIdentity;
    [NSLayoutConstraint deactivateConstraints:value.constraints];
    value.translatesAutoresizingMaskIntoConstraints = NO;
    value.font = [UIFont monospacedDigitSystemFontOfSize:56 weight:UIFontWeightMedium];
    value.textAlignment = NSTextAlignmentCenter;
    value.adjustsFontSizeToFitWidth = YES; value.minimumScaleFactor = 0.5;
    UILabel *caption = [self iPadLabel:title style:UIFontTextStyleTitle3];
    caption.textAlignment = NSTextAlignmentCenter;
    UIStackView *card = [[UIStackView alloc] initWithArrangedSubviews:@[caption,value]];
    card.axis = UILayoutConstraintAxisVertical; card.spacing = 12;
    card.layoutMarginsRelativeArrangement = YES;
    card.layoutMargins = UIEdgeInsetsMake(20, 12, 20, 12);
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 16;
    return card;
}
- (UIStackView *)iPadValueRow:(UILabel *)value title:(NSString *)title {
    value.transform = CGAffineTransformIdentity;
    [NSLayoutConstraint deactivateConstraints:value.constraints];
    value.translatesAutoresizingMaskIntoConstraints = NO;
    value.font = [UIFont monospacedDigitSystemFontOfSize:22 weight:UIFontWeightRegular];
    value.adjustsFontSizeToFitWidth = YES; value.minimumScaleFactor = 0.5;
    value.textAlignment = NSTextAlignmentRight;
    UILabel *caption = [self iPadLabel:title style:UIFontTextStyleBody];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[caption,value]];
    row.spacing = 20; row.alignment = UIStackViewAlignmentCenter;
    [value.widthAnchor constraintEqualToAnchor:row.widthAnchor multiplier:0.5].active = YES;
    [row.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return row;
}
- (void)configureIPadLayout {
    // Keep the original outlet objects, switch action, and measurement calculations.
    NSArray<UILabel *> *values = @[self.X_angle,self.Y_angle,self.Z_angle,self.X_value,self.Y_value,self.Z_value,self.Altitude,self.Latitude,self.Longtitude];
    UISwitch *toggle = self.AcceleSwitch;
    for (UIView *value in values) [value removeFromSuperview];
    [toggle removeFromSuperview];
    self.view = [UIView new]; self.view.backgroundColor = UIColor.systemBackgroundColor;
    UIScrollView *scroll = [UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    UIStackView *content = [UIStackView new]; content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 24; content.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:32],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-32],
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:24],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-64]
    ]];
    toggle.transform = CGAffineTransformIdentity;
    UIStackView *heading = [[UIStackView alloc] initWithArrangedSubviews:@[[self iPadLabel:@"Angle measurement for air bump" style:UIFontTextStyleTitle2],toggle]];
    heading.alignment = UIStackViewAlignmentCenter; heading.spacing = 20;
    [content addArrangedSubview:heading];
    UILabel *instructions = [self iPadLabel:@"Place the screen facing up at the measurement point of the Air Bump" style:UIFontTextStyleBody];
    instructions.textColor = UIColor.systemOrangeColor;
    [content addArrangedSubview:instructions];
    UIStackView *angles = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self iPadMeasurement:values[2] title:@"Air bump angle"],
        [self iPadMeasurement:values[1] title:@"side angle"],
        [self iPadMeasurement:values[0] title:@"Left-right balance"]
    ]];
    angles.distribution = UIStackViewDistributionFillEqually; angles.spacing = 20;
    [content addArrangedSubview:angles];
    for (NSUInteger i = 0; i < 3; i++) [content addArrangedSubview:[self iPadValueRow:values[i+3] title:@[@"X=",@"Y=",@"Z="][i]]];
    for (NSUInteger i = 0; i < 3; i++) [content addArrangedSubview:[self iPadValueRow:values[i+6] title:@[@"altitude",@"latitude",@"longitude"][i]]];
    MTJLocalizeView(self.view);
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) MTJLocalizeView(self.view);
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
