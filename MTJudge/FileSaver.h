#import <Foundation/Foundation.h>

@interface FileSaver : NSObject

/**
 動画を指定されたフォルダ階層に保存します。
 
 @param videoFileURL 撮影された動画の一時的なURL
 @param folderNames  生成するフォルダ名の配列（タグの順番）
 */
- (void)saveVideo:(NSURL *)videoFileURL withFolderNames:(NSArray<NSString *> *)folderNames;

@end
