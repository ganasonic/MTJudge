#import "TagListViewController.h"
#import "TagManager.h"
#import "Tag.h"
#import "TagItemsViewController.h"

@interface TagListViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;

@end

@implementation TagListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"タグを管理";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    
    self.navigationItem.leftBarButtonItem = self.editButtonItem;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addTag)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
    self.navigationItem.rightBarButtonItem.enabled = !editing;
}

#pragma mark - Action

- (void)addTag {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"カテゴリを追加" message:@"カテゴリ名を入力してください" preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"カテゴリ名";
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"追加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *tagNameTextField = alert.textFields.firstObject;
        NSString *tagName = tagNameTextField.text;
        if (tagName && tagName.length > 0) {
            Tag *newTag = [[Tag alloc] initWithTagName:tagName];
            [[TagManager sharedManager] addTag:newTag];
            [self.tableView reloadData];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [TagManager sharedManager].tags.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TagCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"TagCell"];
    }
    
    Tag *tag = [TagManager sharedManager].tags[indexPath.row];
    cell.textLabel.text = tag.tagName;
    
    cell.showsReorderControl = tableView.isEditing;
    cell.accessoryType = tableView.isEditing ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;

    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        Tag *tagToRemove = [TagManager sharedManager].tags[indexPath.row];
        [[TagManager sharedManager] removeTag:tagToRemove];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    Tag *movedTag = [TagManager sharedManager].tags[sourceIndexPath.row];
    [[TagManager sharedManager].tags removeObjectAtIndex:sourceIndexPath.row];
    [[TagManager sharedManager].tags insertObject:movedTag atIndex:destinationIndexPath.row];
    [[TagManager sharedManager] saveTags];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    Tag *selectedTag = [TagManager sharedManager].tags[indexPath.row];
    
    if (tableView.isEditing) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"カテゴリ名を編集" message:nil preferredStyle:UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.text = selectedTag.tagName;
        }];

        [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UITextField *textField = alert.textFields.firstObject;
            if (textField.text.length > 0) {
                selectedTag.tagName = textField.text;
                [[TagManager sharedManager] saveTags];
                [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            }
        }]];

        [self presentViewController:alert animated:YES completion:nil];
    } else {
        TagItemsViewController *tagItemsVC = [[TagItemsViewController alloc] initWithTag:selectedTag];
        [self.navigationController pushViewController:tagItemsVC animated:YES];
    }
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

@end
