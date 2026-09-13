#import "FileSaver.h"

@implementation FileSaver
+ (BOOL)hasDownloadsDirectory {
    return [[NSUserDefaults standardUserDefaults] dataForKey:@"DownloadsDirectoryBookmark"] != nil;
}
+ (void)forgetDownloadsDirectory {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DownloadsDirectoryBookmark"];
}
+ (BOOL)rememberDownloadsDirectory:(NSURL *)directory error:(NSError **)error {
    BOOL access = [directory startAccessingSecurityScopedResource];
    NSData *bookmark = [directory bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:error];
    if (access) [directory stopAccessingSecurityScopedResource];
    if (!bookmark) return NO;
    [[NSUserDefaults standardUserDefaults] setObject:bookmark forKey:@"DownloadsDirectoryBookmark"];
    return YES;
}
- (NSURL *)recordingsDirectoryWithError:(NSError **)error {
    NSData *bookmark = [[NSUserDefaults standardUserDefaults] dataForKey:@"DownloadsDirectoryBookmark"];
    if (!bookmark) {
        if (error) *error = [NSError errorWithDomain:@"MTJudge.Downloads" code:1 userInfo:@{NSLocalizedDescriptionKey: @"初回のみダウンロードフォルダを選択してください。"}];
        return nil;
    }
    BOOL stale = NO;
    NSURL *directory = [NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithoutUI relativeToURL:nil bookmarkDataIsStale:&stale error:error];
    if (directory && stale && ![FileSaver rememberDownloadsDirectory:directory error:error]) return nil;
    return directory;
}
- (NSURL *)saveVideo:(NSURL *)videoFileURL selections:(NSArray<NSDictionary<NSString *, NSString *> *> *)selections error:(NSError **)error {
    NSFileManager *files = [NSFileManager defaultManager];
    NSURL *directory = [self recordingsDirectoryWithError:error];
    if (!directory) return nil;
    BOOL access = [directory startAccessingSecurityScopedResource];
    @try {
    NSNumber *isDirectory = nil;
    if (![directory getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:error] || !isDirectory.boolValue) return nil;
    NSURL *destination = [directory URLByAppendingPathComponent:videoFileURL.lastPathComponent];
    if ([files fileExistsAtPath:destination.path]) {
        destination = [directory URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"mov"]];
    }
    NSData *metadata = [NSJSONSerialization dataWithJSONObject:selections options:NSJSONWritingPrettyPrinted error:error];
    if (!metadata || ![files copyItemAtURL:videoFileURL toURL:destination error:error]) return nil;
    NSURL *metadataURL = [destination URLByAppendingPathExtension:@"tags.json"];
    if (![metadata writeToURL:metadataURL options:NSDataWritingAtomic error:error]) {
        [files removeItemAtURL:destination error:NULL];
        return nil;
    }
    return destination;
    } @finally {
        if (access) [directory stopAccessingSecurityScopedResource];
    }
}
@end
