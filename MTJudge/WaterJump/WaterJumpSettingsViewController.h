#import <UIKit/UIKit.h>
@interface WaterJumpSettingsViewController : UITableViewController
+ (UIViewController *)remoteSetupViewController;
+ (UIViewController *)playbackScreenViewController;
+ (void)installRemotePreviewOn:(UIViewController *)host recordingButton:(UIView *)recordingButton;
+ (void)presentCameraNameFrom:(UIViewController *)host;
+ (void)presentDurationFrom:(UIViewController *)host;
+ (void)presentLoopSettingsFrom:(UIViewController *)host;
+ (void)presentDefaultTagsFrom:(UIViewController *)host;
+ (UIViewController *)videoLibraryViewController;
+ (UIViewController *)videoLibraryViewControllerForComparisonWithMainURL:(NSURL *)mainURL selection:(void (^)(NSURL *url))selection;
@end
