#import <Foundation/Foundation.h>

@interface FileSaver : NSObject
// 初回に選択した「ダウンロード」フォルダへのアクセスを記憶する。
+ (BOOL)hasDownloadsDirectory;
+ (BOOL)rememberDownloadsDirectory:(NSURL *)directory error:(NSError **)error;
+ (void)forgetDownloadsDirectory;
// 選択済みフォルダへ動画とカテゴリ・タグIDを保存する。成功時だけURLを返す。
- (NSURL *)saveVideo:(NSURL *)videoFileURL selections:(NSArray<NSDictionary<NSString *, NSString *> *> *)selections error:(NSError **)error;
@end
