//
//  SceneDelegate.m
//  MTJudge
//

#import "SceneDelegate.h"
#import "AppDelegate.h"

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

    self.window.rootViewController = tabBarController;
    [self.window makeKeyAndVisible];
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
    // 既存のapplicationWillEnterForeground:には処理がないため、移行対象はない。
}

@end
