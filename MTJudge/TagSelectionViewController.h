#import <UIKit/UIKit.h>

@interface TagSelectionViewController : UIViewController
@property (nonatomic, strong) NSURL *videoFileURL;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *selections;
@property (nonatomic, copy) void (^saveHandler)(NSArray<NSDictionary<NSString *, NSString *> *> *selections);
@property (nonatomic, copy) void (^exportHandler)(NSArray<NSDictionary<NSString *, NSString *> *> *selections);
- (instancetype)initWithVideoFileURL:(NSURL *)fileURL;
@end
