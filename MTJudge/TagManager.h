#import <Foundation/Foundation.h>

@class Tag;

@interface TagManager : NSObject

// タグの種類を保持する配列。この配列の順番がフォルダ階層の順番になります。
@property (nonatomic, strong) NSMutableArray<Tag *> *tags;

// シングルトンインスタンスを返すクラスメソッド
+ (instancetype)sharedManager;

// タグの追加、削除、順番の変更
- (void)addTag:(Tag *)newTag;
- (void)removeTag:(Tag *)tag;
- (void)reorderTags:(NSArray<Tag *> *)orderedTags;

// デフォルトタグの設定
- (void)setDefaultTag:(Tag *)tag withItemId:(NSString *)itemId;

// タグデータの保存と読み込み
- (void)saveTags;
- (void)loadTags;

@end
