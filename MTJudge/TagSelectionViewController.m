#import "TagSelectionViewController.h"
#import "TagManager.h"
#import "Tag.h"
#import "TagItem.h"
#import "TagListViewController.h"

@interface TagSelectionViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<Tag *> *categories;
@end

@implementation TagSelectionViewController

- (instancetype)initWithVideoFileURL:(NSURL *)fileURL {
    self = [super init];
    if (self) { _videoFileURL = fileURL; _selections = @[]; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"タグを選択";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
    UIBarButtonItem *save = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down"] style:UIBarButtonItemStyleDone target:self action:@selector(saveRecording)];
    save.accessibilityLabel = @"ダウンロードに保存";
    self.toolbarItems = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil], save];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.categories = [[TagManager sharedManager].tags copy];
    // 編集で削除されたタグは解除し、名称変更はIDを使って反映する。
    NSMutableArray *valid = [NSMutableArray array];
    for (Tag *category in self.categories) {
        for (TagItem *item in category.tagItems) {
            for (NSDictionary *selection in self.selections) {
                if ([selection[@"id"] isEqualToString:item.tagItemId]) {
                    [valid addObject:@{@"category": category.tagName ?: @"", @"id": item.tagItemId, @"name": item.itemName ?: @""}];
                }
            }
        }
    }
    self.selections = valid;
    [self.navigationController setToolbarHidden:NO animated:NO];
    [self.tableView reloadData];
}

- (void)editTags {
    TagListViewController *editor = [[TagListViewController alloc] init];
    editor.navigationItem.leftItemsSupplementBackButton = YES;
    [self.navigationController pushViewController:editor animated:YES];
    [self.navigationController setToolbarHidden:YES animated:NO];
}

- (NSString *)selectedIDForCategory:(Tag *)category {
    for (TagItem *item in category.tagItems) {
        for (NSDictionary *selection in self.selections) {
            if ([selection[@"id"] isEqualToString:item.tagItemId]) return item.tagItemId;
        }
    }
    return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return MAX(self.categories.count, 1); }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.categories.count ? self.categories[section].tagItems.count + 1 : 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.categories.count ? self.categories[section].tagName : @"タグカテゴリ未登録";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == MAX(self.categories.count, 1) - 1 ? @"右下の保存ボタンでダウンロードに保存します。" : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    Tag *category = self.categories.count ? self.categories[indexPath.section] : nil;
    NSString *selectedID = [self selectedIDForCategory:category];
    BOOL selected = NO;
    if (indexPath.row == 0) {
        cell.textLabel.text = @"タグなし";
        selected = selectedID == nil;
    } else {
        TagItem *item = category.tagItems[indexPath.row - 1];
        cell.textLabel.text = item.itemName;
        selected = [item.tagItemId isEqualToString:selectedID];
    }
    cell.textLabel.textColor = self.view.tintColor;
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.categories.count) return;
    Tag *category = self.categories[indexPath.section];
    NSString *oldID = [self selectedIDForCategory:category];
    NSMutableArray *updated = [NSMutableArray array];
    for (NSDictionary *selection in self.selections) {
        if (![selection[@"id"] isEqualToString:oldID]) [updated addObject:selection];
    }
    if (indexPath.row > 0) {
        TagItem *item = category.tagItems[indexPath.row - 1];
        [updated addObject:@{@"category": category.tagName ?: @"", @"id": item.tagItemId ?: @"", @"name": item.itemName ?: @""}];
    }
    self.selections = updated;
    [tableView reloadData];
}
- (NSArray *)orderedSelections {
    NSMutableArray *ordered = [NSMutableArray array];
    for (Tag *category in self.categories) {
        NSString *selectedID = [self selectedIDForCategory:category];
        for (NSDictionary *selection in self.selections) {
            if ([selection[@"id"] isEqualToString:selectedID]) [ordered addObject:selection];
        }
    }
    return ordered;
}
- (void)saveRecording { if (self.saveHandler) self.saveHandler([self orderedSelections]); }
- (void)exportRecording { if (self.exportHandler) self.exportHandler([self orderedSelections]); }
@end
