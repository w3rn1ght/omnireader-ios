#import "OROPDSViewController.h"
#import "ORBookImporter.h"
#import "ORCore.h"
#import "OROPDS.h"
#import "ORSettingsViewController.h"
#import "ORUtil.h"

@interface OROPDSViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSString *feedURL;
@property (nonatomic, copy) NSString *feedTitle;
@property (nonatomic, strong, nullable) NSDictionary *catalog;
@property (nonatomic, strong) NSArray<NSDictionary *> *entries;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic) BOOL loading;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong, nullable) NSDictionary *lastFeed;
@property (nonatomic, copy) NSString *baseFeedURL;
@property (nonatomic, strong, nullable) NSDictionary *searchBaseFeed;
@property (nonatomic) BOOL searching;
@property (nonatomic, strong, nullable) NSTimer *searchTimer;
@end

@implementation OROPDSViewController

+ (void)presentPickerFrom:(UIViewController *)presenter {
    if (!presenter) return;
    NSArray<NSDictionary *> *catalogs = [ORSettings shared].opdsCatalogs;
    if (catalogs.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Каталоги OPDS"
                                                                      message:@"Сначала добавьте каталог в настройках. Подойдёт любой OPDS-каталог, например Project Gutenberg или ваш Calibre-сервер."
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Настройки" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            ORSettingsViewController *settings = [[ORSettingsViewController alloc] init];
            [presenter.navigationController pushViewController:settings animated:YES];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Каталоги OPDS"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *catalog in catalogs) {
        NSString *name = catalog[@"name"] ?: catalog[@"url"] ?: @"Каталог";
        [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self presentCatalog:catalog from:presenter];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Добавить каталог" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        ORSettingsViewController *settings = [[ORSettingsViewController alloc] init];
        [presenter.navigationController pushViewController:settings animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = presenter.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(presenter.view.bounds.size.width / 2,
                                                               presenter.view.bounds.size.height / 2, 1, 1);
    [presenter presentViewController:sheet animated:YES completion:nil];
}

+ (void)presentCatalog:(NSDictionary *)catalog from:(UIViewController *)presenter {
    NSString *url = catalog[@"url"];
    if (url.length == 0) return;
    OROPDSViewController *browser = [[OROPDSViewController alloc] initWithURL:url
                                                                       title:catalog[@"name"] ?: @"Каталог"
                                                                     catalog:catalog];
    [presenter.navigationController pushViewController:browser animated:YES];
}

- (instancetype)initWithURL:(NSString *)url
                      title:(NSString *)title
                    catalog:(NSDictionary *)catalog {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _feedURL = [url copy];
        _feedTitle = [title copy] ?: @"Каталог";
        _catalog = catalog;
        _entries = @[];
        self.title = _feedTitle;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 68;
    self.baseFeedURL = self.feedURL;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    UIBarButtonItem *spinnerItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
    self.navigationItem.rightBarButtonItems = @[spinnerItem];
    self.tableView.refreshControl = [[UIRefreshControl alloc] init];
    [self.tableView.refreshControl addTarget:self action:@selector(loadFeed) forControlEvents:UIControlEventValueChanged];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Поиск в каталоге";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    [self loadFeed];
}

- (void)loadFeed {
    [self loadFeedURL:self.baseFeedURL searchQuery:nil];
}

- (void)loadFeedURL:(NSString *)url searchQuery:(NSString *)query {
    if (self.loading) return;
    self.loading = YES;
    self.searching = query.length > 0;
    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    [OROPDS loadFeedAtURL:url catalog:self.catalog completion:^(NSDictionary *feed, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.loading = NO;
        [strongSelf.spinner stopAnimating];
        [strongSelf.tableView.refreshControl endRefreshing];
        if (!feed) {
            [strongSelf handleCatalogError:error entry:nil];
            return;
        }
        strongSelf.lastFeed = feed;
        NSString *feedName = feed[@"title"] ?: strongSelf.feedTitle;
        strongSelf.title = query.length > 0
            ? [NSString stringWithFormat:@"Поиск: %@", query]
            : feedName;
        strongSelf.entries = feed[@"entries"] ?: @[];
        [strongSelf.tableView reloadData];
    }];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self.searchTimer invalidate];
    NSString *query = searchController.searchBar.text ?: @"";
    self.searchTimer = [NSTimer scheduledTimerWithTimeInterval:0.6
                                                        target:self
                                                      selector:@selector(searchTimerFired:)
                                                      userInfo:query
                                                       repeats:NO];
}

- (void)searchTimerFired:(NSTimer *)timer {
    [self performSearch:(NSString *)(timer.userInfo ?: @"")];
}

- (void)performSearch:(NSString *)query {
    if (query.length == 0) {
        self.searchBaseFeed = nil;
        [self loadFeedURL:self.baseFeedURL searchQuery:nil];
        return;
    }
    if (!self.searchBaseFeed) self.searchBaseFeed = self.lastFeed;
    if (!self.searchBaseFeed) {
        [self loadFeedURL:self.baseFeedURL searchQuery:query];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [OROPDS resolveSearchURLForFeed:self.searchBaseFeed
                            catalog:self.catalog
                              query:query
                         completion:^(NSString *url, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!url) {
            [ORUtil presentAlertIn:strongSelf title:@"Поиск"
                            message:error.localizedDescription ?: @"Каталог не поддерживает поиск."];
            return;
        }
        [strongSelf loadFeedURL:url searchQuery:query];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"OPDSEntry";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.detailTextLabel.numberOfLines = 2;
        cell.textLabel.numberOfLines = 2;
    }
    NSDictionary *entry = self.entries[(NSUInteger)indexPath.row];
    cell.textLabel.text = entry[@"title"];
    NSString *author = entry[@"author"];
    NSString *summary = entry[@"summary"];
    if (author.length > 0) {
        cell.detailTextLabel.text = author;
    } else if (summary.length > 0) {
        cell.detailTextLabel.text = summary;
    } else {
        cell.detailTextLabel.text = [entry[@"navigation"] boolValue] ? @"Раздел" : @"Скачать";
    }
    cell.accessoryType = [entry[@"navigation"] boolValue] ? UITableViewCellAccessoryDisclosureIndicator
                                                          : UITableViewCellAccessoryNone;
    cell.imageView.image = nil;
    NSString *imageURL = entry[@"image"];
    if (imageURL.length > 0) {
        cell.imageView.image = [UIImage imageNamed:@"book"];
        NSURL *url = [NSURL URLWithString:imageURL];
        if (url) {
            [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (!data) return;
                UIImage *image = [UIImage imageWithData:data];
                if (!image) return;
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSIndexPath *current = [tableView indexPathForCell:cell];
                    if (current && current.row == indexPath.row) {
                        cell.imageView.image = image;
                        [cell setNeedsLayout];
                    }
                });
            }] resume];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *entry = self.entries[(NSUInteger)indexPath.row];

    // A book entry may also carry navigation links; a real download wins.
    if ([entry[@"acquisition"] boolValue]) {
        [self downloadEntry:entry];
        return;
    }

    if ([entry[@"navigation"] boolValue]) {
        NSString *next = nil;
        for (NSDictionary *link in entry[@"links"] ?: @[]) {
            NSString *rel = [(NSString *)(link[@"rel"] ?: @"") lowercaseString];
            if ([rel containsString:@"subsection"] || [rel containsString:@"navigation"]) {
                next = link[@"href"];
                break;
            }
        }
        if (next.length == 0) {
            for (NSDictionary *link in entry[@"links"] ?: @[]) {
                NSString *type = [(NSString *)(link[@"type"] ?: @"") lowercaseString];
                if ([type containsString:@"atom"] || [type containsString:@"xml"]) {
                    next = link[@"href"];
                    break;
                }
            }
        }
        if (next.length > 0) {
            OROPDSViewController *browser = [[OROPDSViewController alloc] initWithURL:next
                                                                               title:entry[@"title"]
                                                                             catalog:self.catalog];
            [self.navigationController pushViewController:browser animated:YES];
            return;
        }
    }

    NSMutableArray<NSString *> *kinds = [NSMutableArray array];
    for (NSDictionary *link in entry[@"links"] ?: @[]) {
        NSString *type = link[@"type"] ?: @"";
        if (type.length > 0) [kinds addObject:type];
    }
    NSString *detail = kinds.count > 0
        ? [NSString stringWithFormat:@"Каталог предлагает только: %@", [kinds componentsJoinedByString:@", "]]
        : @"В записи нет ссылок на файл.";
    [ORUtil presentAlertIn:self
                     title:@"Нет файла"
                   message:[NSString stringWithFormat:@"%@\n\nЕсли это раздел — откройте его. Если сайт не отдаёт файлы через OPDS, откройте книгу в Safari.", detail]];
}

- (void)downloadEntry:(NSDictionary *)entry {
    [self.spinner startAnimating];
    self.view.userInteractionEnabled = NO;
    __weak typeof(self) weakSelf = self;
    [OROPDS downloadEntry:entry catalog:self.catalog formatHint:nil completion:^(NSString *path, NSString *suggestedName, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.view.userInteractionEnabled = YES;
        [strongSelf.spinner stopAnimating];
        if (!path) {
            [strongSelf handleCatalogError:error entry:entry];
            return;
        }
        // Give the temporary file a human readable name before importing.
        NSString *extension = path.pathExtension.length > 0 ? path.pathExtension : @"epub";
        NSString *base = suggestedName.length > 0 ? suggestedName.stringByDeletingPathExtension : @"book";
        base = [base stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        base = [base stringByReplacingOccurrencesOfString:@":" withString:@"_"];
        if (base.length > 80) base = [base substringToIndex:80];
        if (base.length == 0) base = @"book";
        NSString *named = [[ORPaths cacheDirectory] stringByAppendingPathComponent:
                              [NSString stringWithFormat:@"%@.%@", base, extension]];
        [[NSFileManager defaultManager] removeItemAtPath:named error:NULL];
        NSError *moveError = nil;
        BOOL moved = [[NSFileManager defaultManager] moveItemAtPath:path toPath:named error:&moveError];
        NSString *sourcePath = moved ? named : path;
        [[ORBookImporter shared] importFileAtURL:[NSURL fileURLWithPath:sourcePath] completion:^(ORBook *book, NSError *importError) {
            [[NSFileManager defaultManager] removeItemAtPath:sourcePath error:NULL];
            if (importError || !book) {
                [ORUtil presentAlertIn:strongSelf title:@"Импорт"
                                message:importError.localizedDescription ?: @"Не удалось добавить книгу."];
                return;
            }
            [ORUtil presentAlertIn:strongSelf title:@"Готово"
                            message:[NSString stringWithFormat:@"«%@» добавлена в библиотеку.", book.title]];
        }];
    }];
}

#pragma mark - Errors

- (void)handleCatalogError:(nullable NSError *)error entry:(nullable NSDictionary *)entry {
    NSError *failure = error ?: [NSError errorWithDomain:@"OmniReader.OPDS" code:1
                                               userInfo:@{NSLocalizedDescriptionKey: @"Не удалось загрузить каталог."}];
    BOOL page = [failure.domain isEqualToString:@"OmniReader.OPDS"] && failure.code == 5;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:(page ? @"Каталог вернул страницу" : @"OPDS")
                                                                   message:failure.localizedDescription
                                                            preferredStyle:UIAlertControllerStyleAlert];
    if (entry) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Повторить"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [self downloadEntry:entry];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Открыть в Safari"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self openEntryInSafari:entry];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)pageURLForEntry:(nullable NSDictionary *)entry {
    for (NSDictionary *link in entry[@"links"] ?: @[]) {
        NSString *type = [(NSString *)(link[@"type"] ?: @"") lowercaseString];
        NSString *rel = [(NSString *)(link[@"rel"] ?: @"") lowercaseString];
        if ([type containsString:@"html"] || [rel containsString:@"alternate"]) {
            return link[@"href"];
        }
    }
    for (NSDictionary *link in entry[@"links"] ?: @[]) {
        NSString *href = link[@"href"];
        if (href.length > 0) return href;
    }
    return self.catalog[@"url"] ?: self.feedURL;
}

- (void)openEntryInSafari:(nullable NSDictionary *)entry {
    NSURL *url = [NSURL URLWithString:[self pageURLForEntry:entry] ?: @""];
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end
