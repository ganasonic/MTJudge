#import "WatchRemoteController.h"
#import <WatchConnectivity/WatchConnectivity.h>
@interface WatchRemoteController () <WCSessionDelegate>
@end
@implementation WatchRemoteController
- (void)activate {
    if ([WCSession isSupported]) { WCSession.defaultSession.delegate = self; [WCSession.defaultSession activateSession]; }
}
- (void)publish {
    WCSession *session = WCSession.defaultSession;
    if (session.activationState != WCSessionActivationStateActivated || !session.isPaired || !session.isWatchAppInstalled) return;
    NSDictionary *state = self.status ? self.status() : @{@"state":@"IDLE"};
    [session updateApplicationContext:state error:nil];
    if (session.isReachable) [session sendMessage:state replyHandler:nil errorHandler:^(NSError *error) {}];
}
- (void)session:(WCSession *)session didReceiveMessage:(NSDictionary<NSString *,id> *)message replyHandler:(void (^)(NSDictionary<NSString *,id> *))replyHandler {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *command = [message[@"command"] isKindOfClass:NSString.class] ? message[@"command"] : @"";
        if ([command isEqual:@"STATUS"]) { replyHandler(self.status ? self.status() : @{@"state":@"IDLE"}); return; }
        if (![[NSUserDefaults standardUserDefaults] boolForKey:@"WJWatch"]) { replyHandler(@{@"error":@"Apple Watch RemoteをONにしてください。"}); return; }
        replyHandler(self.command ? self.command(command) : @{@"error":@"カメラ未準備"});
    });
}
- (void)session:(WCSession *)session activationDidCompleteWithState:(WCSessionActivationState)activationState error:(NSError *)error { dispatch_async(dispatch_get_main_queue(), ^{ [self publish]; }); }
- (void)sessionDidBecomeInactive:(WCSession *)session {}
- (void)sessionDidDeactivate:(WCSession *)session { [session activateSession]; }
- (void)sessionReachabilityDidChange:(WCSession *)session { dispatch_async(dispatch_get_main_queue(), ^{ [self publish]; }); }
@end
