//
//  AppDelegate.m
//  MTJudge
//
//  Created by Yasunori Nagashima on 2019/04/16.
//  Copyright © 2019 Yasunori Nagashima. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    
    // JSONから開発者モードの状態を取得
    BOOL isDeveloperMode = [self isDeveloperModeEnabled];

    // ストーリーボードからUITabBarControllerを取得
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UITabBarController *tabBarController = (UITabBarController *)[storyboard instantiateInitialViewController];

    if (!isDeveloperMode) {
        // 全てのビューコントローラーを取得
        NSMutableArray *allViewControllers = [tabBarController.viewControllers mutableCopy];

        // 開発者モード用のタブ（例：最後のタブ）を非表示にする
        // ここでは、配列から最後のオブジェクトを削除しています。
        if (allViewControllers.count > 1) {
            [allViewControllers removeLastObject];
            tabBarController.viewControllers = allViewControllers;
        }
    }
    
    self.window.rootViewController = tabBarController;
    [self.window makeKeyAndVisible];

    return YES;
}

- (BOOL)isDeveloperModeEnabled {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"data" ofType:@"json"];
    if (!path) {
        // 正しいファイル名を出力するように修正
        NSLog(@"data.json not found.");
        return NO;
    }

    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&error];
    if (error) {
        NSLog(@"Error reading JSON file: %@", error.localizedDescription);
        return NO;
    }

    //id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&error];
    // NSJSONReadingAllowFragmentsを削除
    id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error) {
        NSLog(@"Error parsing JSON: %@", error.localizedDescription);
        return NO;
    }

    if ([jsonObject isKindOfClass:[NSDictionary class]]) {
        NSDictionary *jsonDict = (NSDictionary *)jsonObject;
        NSDictionary *settingsDict = jsonDict[@"settings"];
        if ([settingsDict isKindOfClass:[NSDictionary class]]) {
            NSNumber *developerValue = settingsDict[@"developer"];
            if (developerValue && [developerValue intValue] == 1) {
                return YES;
            }
        }
    }

    return NO;}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}


- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}


- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}


@end
