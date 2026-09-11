#import <Foundation/Foundation.h>

@interface TagItem : NSObject <NSSecureCoding>

@property (nonatomic, strong) NSString *tagItemId;
@property (nonatomic, strong) NSString *itemName;

@end