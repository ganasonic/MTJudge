// Standalone Foundation regression test; uses an isolated file, never app data.
#import <Foundation/Foundation.h>
#import "TagManager.h"
#import "Tag.h"
#import "TagItem.h"

@interface RegressionTagManager : TagManager
@property (nonatomic, copy) NSString *testPath;
@end
@implementation RegressionTagManager
- (NSString *)tagsFilePath { return self.testPath; }
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        Check(argc == 3, @"Expected mode and isolated archive path");
        RegressionTagManager *manager = [RegressionTagManager new];
        manager.testPath = [NSString stringWithUTF8String:argv[2]];
        NSString *mode = [NSString stringWithUTF8String:argv[1]];
        if ([mode isEqualToString:@"write"]) {
            Tag *location = [[Tag alloc] initWithTagName:@"場所"];
            for (NSString *name in @[@"自宅", @"スキー場", @"S-Air"]) {
                TagItem *item = [TagItem new];
                item.itemName = name;
                item.tagItemId = [@"id-" stringByAppendingString:name];
                [location.tagItems addObject:item];
            }
            location.isDefault = YES;
            location.defaultTagItemId = @"id-S-Air";
            [manager addTag:location];
            [manager addTag:[[Tag alloc] initWithTagName:@"空のカテゴリ"]];
        } else {
            [manager loadTags];
            Check(manager.tags.count == 2, @"Categories retained");
            Tag *location = manager.tags[0];
            Check([location.tagName isEqualToString:@"場所"], @"Category name retained");
            Check(location.tagItems.count == 3, @"All child tags retained");
            NSArray *names = @[@"自宅", @"スキー場", @"S-Air"];
            for (NSUInteger i = 0; i < names.count; i++) {
                Check([location.tagItems[i].itemName isEqualToString:names[i]], @"Child name/order retained");
                Check([location.tagItems[i].tagItemId isEqualToString:[@"id-" stringByAppendingString:names[i]]], @"Child ID retained");
            }
            Check(location.isDefault && [location.defaultTagItemId isEqualToString:@"id-S-Air"], @"Default retained");
            Check(manager.tags[1].tagItems.count == 0, @"Other category remains empty");
            [manager.tags[1].tagItems addObject:location.tagItems[0]];
            [location.tagItems removeObjectAtIndex:0];
            [manager saveTags];
            [manager loadTags];
            Check(manager.tags[0].tagItems.count == 2 && manager.tags[1].tagItems.count == 1, @"Edits after reload persist in correct categories");
        }
        NSLog(@"PASS: %@", mode);
    }
    return 0;
}
