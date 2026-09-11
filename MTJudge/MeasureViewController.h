//
//  MeasureViewController.h
//  MTJudge
//
//  Created by Yasunori Nagashima on 2019/06/03.
//  Copyright © 2019 Yasunori Nagashima. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MeasureViewController : UIViewController <CLLocationManagerDelegate>
@property (weak, nonatomic) IBOutlet UILabel *X_value;
@property (weak, nonatomic) IBOutlet UILabel *Y_value;
@property (weak, nonatomic) IBOutlet UILabel *Z_value;
@property (weak, nonatomic) IBOutlet UISwitch *AcceleSwitch;
@property (weak, nonatomic) IBOutlet UILabel *X_angle;
@property (weak, nonatomic) IBOutlet UILabel *Y_angle;
@property (weak, nonatomic) IBOutlet UILabel *Z_angle;
@property (weak, nonatomic) IBOutlet UILabel *Altitude;
@property (weak, nonatomic) IBOutlet UILabel *Latitude;
@property (weak, nonatomic) IBOutlet UILabel *Longtitude;

@end

double acceleX= 0;
double acceleY = 0;
double acceleZ = 0;
double Alpha = 0.4;

NS_ASSUME_NONNULL_END
