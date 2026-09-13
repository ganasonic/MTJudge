// Standalone Foundation test. All files live in a unique temporary directory.
#import <Foundation/Foundation.h>
#import "FileSaver.h"
@interface TestSaver : FileSaver
@property NSURL *directory;
@end
@implementation TestSaver
- (NSURL *)recordingsDirectoryWithError:(NSError **)error { return self.directory; }
@end
static void Check(BOOL condition) { if (!condition) exit(1); }
int main(void) { @autoreleasepool {
    NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSFileManager *files = NSFileManager.defaultManager;
    Check([files createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSURL *source = [root URLByAppendingPathComponent:@"test.mov"];
    NSData *content = [@"isolated recording fixture" dataUsingEncoding:NSUTF8StringEncoding];
    Check([content writeToURL:source atomically:YES]);
    TestSaver *saver = [TestSaver new]; saver.directory = [root URLByAppendingPathComponent:@"Recordings"];
    Check([files createDirectoryAtURL:saver.directory withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSError *error = nil;
    NSArray *tags = @[@{@"category":@"場所", @"id":@"home", @"name":@"自宅"}];
    NSURL *first = [saver saveVideo:source selections:tags error:&error];
    Check(first && !error && [[NSData dataWithContentsOfURL:first] isEqual:content]);
    NSArray *restored = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[first URLByAppendingPathExtension:@"tags.json"]] options:0 error:&error];
    Check([restored isEqual:tags]);
    NSURL *second = [saver saveVideo:source selections:@[] error:&error];
    Check(second && ![first isEqual:second]);
    Check([[NSData dataWithContentsOfURL:first] isEqual:content]);
    Check([[NSData dataWithContentsOfURL:source] isEqual:content]);
    NSArray *empty = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[second URLByAppendingPathExtension:@"tags.json"]] options:0 error:&error];
    Check(empty.count == 0);
    error = nil;
    Check(![saver saveVideo:[root URLByAppendingPathComponent:@"missing.mov"] selections:@[] error:&error] && error);
    Check([[NSData dataWithContentsOfURL:first] isEqual:content]);
    NSLog(@"PASS: direct save, tag metadata, no tags, collision, missing source");
    [files removeItemAtURL:root error:NULL];
} return 0; }
