#import <UIKit/UIKit.h>
@interface WaterJumpSettingsViewController : UITableViewController
+ (UIViewController *)remoteSetupViewController;
+ (void)presentCameraNameFrom:(UIViewController *)host;
+ (void)presentDurationFrom:(UIViewController *)host;
+ (void)presentLoopSettingsFrom:(UIViewController *)host;
+ (void)presentDefaultTagsFrom:(UIViewController *)host;
+ (UIViewController *)videoLibraryViewController;
+ (UIViewController *)videoLibraryViewControllerForComparisonWithMainURL:(NSURL *)mainURL selection:(void (^)(NSURL *url))selection;
@end
