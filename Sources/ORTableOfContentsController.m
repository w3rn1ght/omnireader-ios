#import "ORTableOfContentsController.h"

@implementation ORTableOfContentsController {
    NSArray<ORTOCItem *> *_items;
}

- (instancetype)initWithItems:(NSArray<ORTOCItem *> *)items {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _items = items ?: @[];
        self.title = @"Оглавление";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                          target:self
                                                                                          action:@selector(cancel)];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"TOC";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    }
    ORTOCItem *item = _items[(NSUInteger)indexPath.row];
    cell.textLabel.text = item.title;
    cell.textLabel.numberOfLines = 2;
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    cell.indentationLevel = MIN((NSInteger)item.level, 4);
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ORTOCItem *item = _items[(NSUInteger)indexPath.row];
    if (self.onSelect) self.onSelect(item);
}

@end
