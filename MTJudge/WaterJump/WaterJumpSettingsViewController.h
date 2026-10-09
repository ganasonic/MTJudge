#import <UIKit/UIKit.h>
@interface WaterJumpSettingsViewController : UITableViewController
+ (UIViewController *)videoLibraryViewController;
+ (UIViewController *)videoLibraryViewControllerForComparisonWithMainURL:(NSURL *)mainURL selection:(void (^)(NSURL *url))selection;
@end
