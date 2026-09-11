#import <UIKit/UIKit.h>

@class Tag;
@class TagItem;

@protocol TagItemSelectionDelegate <NSObject>

- (void)didSelectTagItem:(TagItem *)tagItem;

@end

@interface TagItemSelectionViewController : UIViewController

@property (nonatomic, weak) id<TagItemSelectionDelegate> delegate;

- (instancetype)initWithTag:(Tag *)tag;

@end