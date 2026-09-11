#import "Tag.h"

@implementation Tag

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithTagName:(NSString *)tagName {
    self = [super init];
    if (self) {
        _tagName = tagName;
        _tagItems = [NSMutableArray array];
        _isDefault = NO;
        _defaultTagItemId = nil;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _tagName = [coder decodeObjectOfClass:[NSString class] forKey:@"tagName"];
        _tagItems = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSMutableArray class], [TagItem class], nil] forKey:@"tagItems"];
        _isDefault = [coder decodeBoolForKey:@"isDefault"];
        _defaultTagItemId = [coder decodeObjectOfClass:[NSString class] forKey:@"defaultTagItemId"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.tagName forKey:@"tagName"];
    [coder encodeObject:self.tagItems forKey:@"tagItems"];
    [coder encodeBool:self.isDefault forKey:@"isDefault"];
    [coder encodeObject:self.defaultTagItemId forKey:@"defaultTagItemId"];
}

@end