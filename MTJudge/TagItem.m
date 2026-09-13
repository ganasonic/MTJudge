#import "TagItem.h"

@implementation TagItem

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _tagItemId = [coder decodeObjectOfClass:[NSString class] forKey:@"tagItemId"];
        _itemName = [coder decodeObjectOfClass:[NSString class] forKey:@"itemName"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.tagItemId forKey:@"tagItemId"];
    [coder encodeObject:self.itemName forKey:@"itemName"];
}

@end
