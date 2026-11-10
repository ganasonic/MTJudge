#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface OverlaySessionStore : NSObject
@property(nonatomic, readonly) NSURL *directory;
@property(nonatomic, readonly) NSURL *cacheDirectory;
@property(nonatomic, readonly) NSDictionary *sources;
/// Hashes contents, so a same-name replacement cannot reuse another video's alignment.
- (nullable instancetype)initWithMainURL:(NSURL *)mainURL subURL:(NSURL *)subURL error:(NSError **)error;
- (nullable NSDictionary *)load;
- (BOOL)save:(NSDictionary *)state error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
