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
- (void)retransferVideoURL:(NSURL *)url;
- (BOOL)protectsVideo:(NSURL *)url;
- (void)applySettings;
- (NSDictionary *)status;
- (NSDictionary *)command:(NSString *)command;
- (void)publish;
- (void)saveAutomatic:(NSURL *)url completion:(void (^)(NSURL *, NSDictionary *, NSError *))completion;
- (void)enqueueAutomaticVideoURL:(NSURL *)url metadata:(NSDictionary *)metadata tags:(NSArray<NSDictionary *> *)tags;
- (void)sendSubCameraCommand:(NSString *)command;
@end
