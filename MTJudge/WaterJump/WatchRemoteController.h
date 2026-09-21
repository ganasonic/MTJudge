#import <Foundation/Foundation.h>
@interface WatchRemoteController : NSObject
@property (nonatomic, copy) NSDictionary *(^command)(NSString *command);
@property (nonatomic, copy) NSDictionary *(^status)(void);
- (void)activate;
- (void)publish;
@end
