#import "TagManager.h"
#import "Tag.h"
#import "TagItem.h"

@implementation TagManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static TagManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
        [sharedManager loadTags];
    });
    return sharedManager;
}

#pragma mark - Public Methods

- (void)addTag:(Tag *)newTag {
    if (!self.tags) {
        self.tags = [NSMutableArray array];
    }
    [self.tags addObject:newTag];
    [self saveTags];
}

- (void)removeTag:(Tag *)tag {
    [self.tags removeObject:tag];
    [self saveTags];
}

- (void)reorderTags:(NSArray<Tag *> *)orderedTags {
    self.tags = [orderedTags mutableCopy];
    [self saveTags];
}

- (void)setDefaultTag:(Tag *)tag withItemId:(NSString *)itemId {
    for (Tag *t in self.tags) {
        if ([t isEqual:tag]) {
            t.isDefault = YES;
            t.defaultTagItemId = itemId;
        } else {
            t.isDefault = NO;
            t.defaultTagItemId = nil;
        }
    }
    [self saveTags];
}

#pragma mark - Data Persistence

// タグデータを保存するファイルパスを取得
- (NSString *)tagsFilePath {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    return [documentsURL.path stringByAppendingPathComponent:@"tags.data"];
}

// タグデータをファイルに保存
- (void)saveTags {
    NSError *error = nil;
    NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:self.tags requiringSecureCoding:YES error:&error];
    if (archivedData) {
        if (![archivedData writeToFile:[self tagsFilePath] options:NSDataWritingAtomic error:&error]) {
            NSLog(@"Failed to write tags: %@", error.localizedDescription);
        }
    } else {
        NSLog(@"Failed to archive tags: %@", error.localizedDescription);
    }
}

// タグデータをファイルから読み込み
- (void)loadTags {
    NSString *filePath = [self tagsFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSData *archivedData = [NSData dataWithContentsOfFile:filePath];
        if (archivedData) {
            NSSet *classes = [NSSet setWithObjects:[NSArray class], [NSMutableArray class], [NSString class], [Tag class], [TagItem class], nil];
            NSError *error = nil;
            NSArray *loadedTags = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:archivedData error:&error];
            if (loadedTags) {
                self.tags = [loadedTags mutableCopy];
            } else {
                NSLog(@"Failed to unarchive tags: %@", error.localizedDescription);
                self.tags = [NSMutableArray array];
            }
        }
    } else {
        self.tags = [NSMutableArray array];
    }
}

@end