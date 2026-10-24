//
//  SceneDelegate.m
//  MTJudge
//

#import "SceneDelegate.h"
#import "AppDelegate.h"
#import "MTJLocalization.h"
#import "WaterJump/WaterJumpCoordinator.h"
#import "WaterJump/RecordingController.h"
#import "WaterJump/WaterJumpSettingsViewController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene
willConnectToSession:(UISceneSession *)session
       options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];

    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UITabBarController *tabBarController = (UITabBarController *)[storyboard instantiateInitialViewController];

    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    if (![appDelegate isDeveloperModeEnabled]) {
        NSMutableArray *viewControllers = [tabBarController.viewControllers mutableCopy];
        if (viewControllers.count > 1) {
            [viewControllers removeLastObject];
            tabBarController.viewControllers = viewControllers;
        }
    }

    NSMutableArray *tabs = [tabBarController.viewControllers mutableCopy];
    UIViewController *playback = [WaterJumpSettingsViewController playbackScreenViewController];
    playback.tabBarItem = [[UITabBarItem alloc] initWithTitle:MTJText(@"動画再生") image:[UIImage systemImageNamed:@"play.rectangle"] tag:110];
    NSUInteger cameraIndex = [tabs indexOfObjectPassingTest:^BOOL(UIViewController *vc, NSUInteger index, BOOL *stop) { return [vc isKindOfClass:NSClassFromString(@"VideoRecordingViewController")]; }];
    [tabs insertObject:playback atIndex:cameraIndex == NSNotFound ? tabs.count : cameraIndex + 1]; tabBarController.viewControllers = tabs;
    tabBarController.delegate = self;
    self.window.rootViewController = tabBarController;
    MTJLocalizeController(tabBarController);
    [self.window makeKeyAndVisible];
}

- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController {
    if (viewController.tabBarItem.tag == 110 && [WaterJumpCoordinator shared].recording.busy) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTJText(@"動画再生") message:MTJText(@"本体の録画・保存が終了してから切り替えてください。") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [tabBarController.selectedViewController presentViewController:alert animated:YES completion:nil]; return NO;
    }
    return YES;
}
- (void)sceneDidBecomeActive:(UIScene *)scene {
    // 既存のapplicationDidBecomeActive:には処理がないため、移行対象はない。
}

- (void)sceneWillResignActive:(UIScene *)scene {
    // 既存のapplicationWillResignActive:には処理がないため、移行対象はない。
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    // 既存のapplicationDidEnterBackground:には処理がないため、移行対象はない。
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    // Pick up edits made in Files while MTJudge was in the background.
    [MTJLocalization reload:nil];
}

@end
