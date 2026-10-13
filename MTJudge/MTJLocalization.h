#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *MTJText(NSString *source);
FOUNDATION_EXPORT void MTJLocalizeView(UIView *view);
FOUNDATION_EXPORT void MTJLocalizeController(UIViewController *controller);
FOUNDATION_EXPORT NSString *const MTJLanguageDidChangeNotification;
@interface MTJLocalization : NSObject
+ (NSString *)language;
+ (void)setLanguage:(NSString *)language;
+ (BOOL)reload:(NSError **)error;
+ (BOOL)importURL:(NSURL *)url error:(NSError **)error;
+ (NSURL *)editableURL;
@end
NS_ASSUME_NONNULL_END
