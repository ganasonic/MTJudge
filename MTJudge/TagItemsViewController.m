#import "TagItemsViewController.h"
#import "Tag.h"
#import "TagItem.h"
#import "TagManager.h"

@interface TagItemsViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) Tag *tag;
@property (nonatomic, strong) UITableView *tableView;

@end

@implementation TagItemsViewController

- (instancetype)initWithTag:(Tag *)tag {
    self = [super init];
    if (self) {
        _tag = tag;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // カテゴリ名をタイトルに設定
    self.title = self.tag.tagName;
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    
    // ナビゲーションバーに複数のボタンを追加するための準備
    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addTagItem)];
    UIBarButtonItem *editButton = [[UIBarButtonItem alloc] initWithTitle:@"編集" style:UIBarButtonItemStylePlain target:self action:@selector(editTagName)];
    
    // 右上のボタンを配列で設定
    self.navigationItem.rightBarButtonItems = @[addButton, editButton];
}

#pragma mark - Action

// カテゴリ名を編集するアクション
- (void)editTagName {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"カテゴリ名を編集" message:nil preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = self.tag.tagName;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *textField = alert.textFields.firstObject;
        if (textField.text.length > 0) {
            self.tag.tagName = textField.text;
            [[TagManager sharedManager] saveTags];
            self.title = self.tag.tagName; // タイトルを更新
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// タグアイテムを追加するアクション
- (void)addTagItem {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"タグアイテムを追加" message:@"アイテム名を入力してください" preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"アイテム名";
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"追加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *itemNameTextField = alert.textFields.firstObject;
        NSString *itemName = itemNameTextField.text;
        if (itemName && itemName.length > 0) {
            TagItem *newItem = [[TagItem alloc] init];
            newItem.tagItemId = [[NSUUID UUID] UUIDString];
            newItem.itemName = itemName;
            [self.tag.tagItems addObject:newItem];
            [[TagManager sharedManager] saveTags];
            [self.tableView reloadData];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.tag.tagItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TagItemCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"TagItemCell"];
    }
    
    TagItem *item = self.tag.tagItems[indexPath.row];
    cell.textLabel.text = item.itemName;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.tag.tagItems removeObjectAtIndex:indexPath.row];
        [[TagManager sharedManager] saveTags];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

@end
