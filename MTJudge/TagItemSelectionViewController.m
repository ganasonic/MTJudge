#import "TagItemSelectionViewController.h"
#import "Tag.h"
#import "TagItem.h"
#import "TagManager.h"

@interface TagItemSelectionViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) Tag *tag;
@property (nonatomic, strong) UITableView *tableView;

@end

@implementation TagItemSelectionViewController

- (instancetype)initWithTag:(Tag *)tag {
    self = [super init];
    if (self) {
        _tag = tag;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = self.tag.tagName;
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.tag.tagItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"TagItemCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    
    TagItem *tagItem = self.tag.tagItems[indexPath.row];
    cell.textLabel.text = tagItem.itemName;
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    TagItem *selectedTagItem = self.tag.tagItems[indexPath.row];
    
    if ([self.delegate respondsToSelector:@selector(didSelectTagItem:)]) {
        [self.delegate didSelectTagItem:selectedTagItem];
    }
    
    // 選択後に自動で一つ前の画面に戻る
    [self.navigationController popViewControllerAnimated:YES];
}

@end