#import "TagSelectionViewController.h"
#import "TagManager.h"
#import "Tag.h"
#import "TagItem.h"
#import "FileSaver.h"
#import "TagItemSelectionViewController.h"

@interface TagSelectionViewController () <TagItemSelectionDelegate>

@property (nonatomic, strong) TagManager *tagManager;
@property (nonatomic, strong) NSMutableArray<TagItem *> *selectedTagItems;
@property (nonatomic, assign) NSInteger currentTagIndex;
@property (nonatomic, strong) UIBarButtonItem *saveButton;
@property (nonatomic, strong) UILabel *statusLabel;

@end

@implementation TagSelectionViewController

- (instancetype)initWithVideoFileURL:(NSURL *)fileURL {
    self = [super init];
    if (self) {
        _videoFileURL = fileURL;
        _tagManager = [TagManager sharedManager];
        _selectedTagItems = [NSMutableArray array];
        _currentTagIndex = 0;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    
    self.saveButton = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(saveButtonTapped)];
    self.navigationItem.rightBarButtonItem = self.saveButton;
    
    [self setupUI];
    
    [self showNextTagSelection];
}

- (void)setupUI {
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, self.view.bounds.size.width - 40, 50)];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.text = @"タグを選択中です...";
    [self.view addSubview:self.statusLabel];
    
    // UIを初期状態に戻す
    self.navigationItem.rightBarButtonItem = nil;
}

- (void)showNextTagSelection {
    if (self.currentTagIndex >= self.tagManager.tags.count) {
        self.title = @"保存準備完了";
        self.statusLabel.text = @"すべてのタグが選択されました。保存ボタンをタップして動画を保存してください。";
        self.navigationItem.rightBarButtonItem = self.saveButton;
        self.navigationItem.leftBarButtonItem = nil;
        return;
    }
    
    Tag *currentTag = self.tagManager.tags[self.currentTagIndex];
    
    if (currentTag.isDefault && currentTag.defaultTagItemId) {
        // デフォルト設定がある場合、自動選択して次のカテゴリへ
        TagItem *defaultItem = [self findTagItemWithId:currentTag.defaultTagItemId inTag:currentTag];
        if (defaultItem) {
            [self.selectedTagItems addObject:defaultItem];
        }
        self.currentTagIndex++;
        [self showNextTagSelection];
    } else {
        // デフォルト設定がない場合、ユーザーに選択させる
        self.title = currentTag.tagName;
        TagItemSelectionViewController *tagItemSelectionVC = [[TagItemSelectionViewController alloc] initWithTag:currentTag];
        tagItemSelectionVC.delegate = self;
        [self.navigationController pushViewController:tagItemSelectionVC animated:YES];
    }
}

#pragma mark - TagItemSelectionDelegate

- (void)didSelectTagItem:(TagItem *)tagItem {
    [self.selectedTagItems addObject:tagItem];
    self.currentTagIndex++;
    [self showNextTagSelection];
}

#pragma mark - Action

- (void)saveButtonTapped {
    if (self.selectedTagItems.count != self.tagManager.tags.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"エラー"
                                                                       message:@"すべてのカテゴリのタグを選択してください。"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSMutableArray *folderNames = [NSMutableArray array];
    for (TagItem *item in self.selectedTagItems) {
        [folderNames addObject:item.itemName];
    }
    
    FileSaver *fileSaver = [[FileSaver alloc] init];
    [fileSaver saveVideo:self.videoFileURL withFolderNames:folderNames];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存完了"
                                                                   message:@"動画が保存されました。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Helper

- (TagItem *)findTagItemWithId:(NSString *)itemId inTag:(Tag *)tag {
    for (TagItem *item in tag.tagItems) {
        if ([item.tagItemId isEqualToString:itemId]) {
            return item;
        }
    }
    return nil;
}

@end