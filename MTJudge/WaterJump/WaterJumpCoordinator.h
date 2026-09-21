#import <Foundation/Foundation.h>
@class RecordingController;
extern NSString * const WJStatusChanged;
@interface WaterJumpCoordinator : NSObject
+ (instancetype)shared;
@property (nonatomic, weak) RecordingController *recording;
@property (nonatomic, readonly) BOOL modeEnabled;
@property (nonatomic, readonly) NSString *remoteAddress;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, readonly) BOOL recordingBusy;
@property (nonatomic, readonly) NSString *pairingCode;
@property (nonatomic, readonly) NSString *peerDescription;
@property (nonatomic, readonly) NSArray<NSDictionary *> *discoveredPeers;
- (BOOL)registerPeer:(NSString *)name code:(NSString *)code;
- (void)retryTransfer;
- (BOOL)protectsVideo:(NSURL *)url;
- (void)applySettings;
- (NSDictionary *)status;
- (NSDictionary *)command:(NSString *)command;
- (void)publish;
- (void)saveAutomatic:(NSURL *)url completion:(void (^)(NSURL *, NSError *))completion;
@end
