#import <Foundation/Foundation.h>
#import "TagItem.h"

@interface Tag : NSObject <NSSecureCoding>

@property (nonatomic, strong) NSString *tagName;
@property (nonatomic, strong) NSMutableArray<TagItem *> *tagItems;
@property (nonatomic, assign) BOOL isDefault;
@property (nonatomic, strong) NSString *defaultTagItemId;

- (instancetype)initWithTagName:(NSString *)tagName;

@end