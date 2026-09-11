#import <UIKit/UIKit.h>

@class VideoRecorder;

@interface TagSelectionViewController : UIViewController

@property (nonatomic, strong) NSURL *videoFileURL;

- (instancetype)initWithVideoFileURL:(NSURL *)fileURL;

@end
