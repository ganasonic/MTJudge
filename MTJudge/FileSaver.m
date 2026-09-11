#import "FileSaver.h"
#import <Photos/Photos.h>

@implementation FileSaver

- (void)saveVideo:(NSURL *)videoFileURL withFolderNames:(NSArray<NSString *> *)folderNames {
    
    // アプリのドキュメントディレクトリのURLを取得
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
#if 0
    // フォルダ階層のパスを生成
    NSURL *destinationFolderURL = documentsURL;
    for (NSString *folderName in folderNames) {
        destinationFolderURL = [destinationFolderURL URLByAppendingPathComponent:folderName];
    }
    
    // フォルダの作成
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:destinationFolderURL withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"Failed to create directory: %@", error.localizedDescription);
        return;
    }
    
    // 最終的な保存先のURLを生成
    NSString *fileName = [NSString stringWithFormat:@"%@.mov", [[NSUUID UUID] UUIDString]];
    NSURL *destinationFileURL = [destinationFolderURL URLByAppendingPathComponent:fileName];
#else
    // 最終的な保存先のURLを生成（サブフォルダなし）
    NSString *fileName = [NSString stringWithFormat:@"%@.mov", [[NSUUID UUID] UUIDString]];
    NSURL *destinationFileURL = [documentsURL URLByAppendingPathComponent:fileName];
    
    // 動画ファイルを一時ファイルから指定の場所に移動
    NSError *error = nil;
#endif
    
    // 動画ファイルを一時ファイルから指定の場所に移動
    if (![[NSFileManager defaultManager] moveItemAtURL:videoFileURL toURL:destinationFileURL error:&error]) {
        NSLog(@"Failed to move video file: %@", error.localizedDescription);
    }
}

@end
