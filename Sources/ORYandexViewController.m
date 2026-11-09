#import "ORYandexViewController.h"
#import "ORAudioPlayer.h"
#import "ORAudioPlayerController.h"
#import "ORBookImporter.h"
#import "ORCore.h"
#import "ORHTTP.h"
#import "ORReaderFactory.h"
#import "ORUtil.h"
#import "ORYandexAPI.h"
#import "ORYandexAuth.h"

@interface ORYandexViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIImageView *headerView;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation ORYandexViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Яндекс Книги";
    self.items = @[];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(loadShelf) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;
    self.tableView.rowHeight = 74;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    if ([ORYandexAuth shared].isSignedIn) {
        [self loadShelf];
    }
}

- (void)loadShelf {
    if (![ORYandexAuth shared].isSignedIn) return;
    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    [ORYandexAPI fetchShelf:^(NSArray<NSDictionary *> *items, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.spinner stopAnimating];
        [strongSelf.refreshControl endRefreshing];
        if (error) {
            [ORUtil presentAlertIn:strongSelf title:@"Яндекс Книги"
                            message:error.localizedDescription ?: @"Не удалось загрузить полку."];
            return;
        }
        strongSelf.items = items ?: @[];
        [strongSelf.tableView reloadData];
        if (strongSelf.items.count == 0) {
            [ORUtil presentAlertIn:strongSelf title:@"Полка пуста"
                            message:@"В аккаунте не найдено книг по текущей схеме API. Подробности и способы ручного импорта — в Docs/YANDEX.md."];
        }
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (![ORYandexAuth shared].isSignedIn) return 2;
    return MAX(1, (NSInteger)self.items.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"YandexBook";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.detailTextLabel.numberOfLines = 2;
    }
    cell.imageView.image = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (![ORYandexAuth shared].isSignedIn) {
        cell.textLabel.text = indexPath.row == 0 ? @"Войти в Яндекс" : @"Импортировать купленную книгу";
        cell.textLabel.textColor = self.view.tintColor;
        cell.detailTextLabel.text = indexPath.row == 0
            ? @"Будет открыто окно OAuth Яндекса"
            : @"Используйте «+» → «Импортировать файл» в библиотеке";
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    if (self.items.count == 0) {
        cell.textLabel.text = @"Загрузка полки…";
        cell.textLabel.textColor = [UIColor grayColor];
        cell.detailTextLabel.text = @"Потяните вниз, чтобы обновить";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    NSDictionary *item = self.items[(NSUInteger)indexPath.row];
    cell.textLabel.text = item[@"title"] ?: @"Без названия";
    cell.textLabel.textColor = [UIColor blackColor];
    NSString *author = item[@"author"];
    BOOL audio = [item[@"isAudio"] boolValue];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@", author ?: @"", audio ? @"  ·  аудио" : @""];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    NSString *cover = item[@"cover"];
    if (cover.length > 0) {
        NSURL *url = [NSURL URLWithString:cover];
        if (url) {
            [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (!data) return;
                UIImage *image = [UIImage imageWithData:data];
                if (!image) return;
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSIndexPath *current = [tableView indexPathForCell:cell];
                    if (current && current.row == indexPath.row) {
                        UIImage *scaled = [ORUtil imageWithImage:image scaledToSize:CGSizeMake(44, 60)];
                        cell.imageView.image = scaled;
                    }
                });
            }] resume];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (![ORYandexAuth shared].isSignedIn) {
        if (indexPath.row == 0) {
            [self signIn];
        } else {
            [self.navigationController popViewControllerAnimated:YES];
        }
        return;
    }
    if (self.items.count == 0) return;
    [self downloadItem:self.items[(NSUInteger)indexPath.row]];
}

- (void)signIn {
    __weak typeof(self) weakSelf = self;
    [[ORYandexAuth shared] signInFrom:self completion:^(BOOL success, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!success) {
            if (error) [ORUtil presentAlertIn:strongSelf title:@"Яндекс Книги" message:error.localizedDescription];
            return;
        }
        [strongSelf.tableView reloadData];
        [strongSelf loadShelf];
    }];
}

- (void)downloadItem:(NSDictionary *)item {
    [self.spinner startAnimating];
    self.view.userInteractionEnabled = NO;
    __weak typeof(self) weakSelf = self;
    [ORYandexAPI resolveDownloadForItem:item completion:^(NSURL *url, NSString *format, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!url) {
            strongSelf.view.userInteractionEnabled = YES;
            [strongSelf.spinner stopAnimating];
            [ORUtil presentAlertIn:strongSelf title:@"Яндекс Книги"
                            message:error.localizedDescription ?: @"Не удалось получить файл."];
            return;
        }

        if ([format.lowercaseString containsString:@"audio"] || [item[@"isAudio"] boolValue]) {
            ORBook *placeholder = [self placeholderBookFor:item];
            placeholder.audioURL = url.absoluteString;
            NSString *headers = [NSString stringWithFormat:@"OAuth %@", [ORSettings shared].yandexToken ?: @""];
            [[ORAudioPlayer shared] playURL:url
                                     title:item[@"title"] ?: @"Аудиокнига"
                                    author:item[@"author"]
                                    bookID:placeholder.bookID
                                   headers:@{@"Authorization": headers}];
            ORAudioPlayerController *player = [[ORAudioPlayerController alloc] initWithBook:placeholder
                                                                                  localPath:nil];
            strongSelf.view.userInteractionEnabled = YES;
            [strongSelf.spinner stopAnimating];
            [strongSelf.navigationController pushViewController:player animated:YES];
            return;
        }

        NSString *extension = format.length > 0 ? format : @"epub";
        NSString *destination = [[ORPaths cacheDirectory] stringByAppendingPathComponent:
                                    [NSString stringWithFormat:@"yandex-%@.%@", [ORUtil uniqueKey], extension]];
        [ORHTTP download:url.absoluteString
                 headers:@{@"Authorization": [NSString stringWithFormat:@"OAuth %@", [ORSettings shared].yandexToken ?: @""]}
                  toPath:destination
              completion:^(NSString *path, NSError *downloadError) {
            strongSelf.view.userInteractionEnabled = YES;
            [strongSelf.spinner stopAnimating];
            if (!path) {
                [ORUtil presentAlertIn:strongSelf title:@"Скачивание"
                                message:downloadError.localizedDescription ?: @"Не удалось скачать файл."];
                return;
            }
            NSString *safeTitle = [item[@"title"] ?: @"yandex-book" stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
            NSString *named = [[ORPaths cacheDirectory] stringByAppendingPathComponent:
                                  [NSString stringWithFormat:@"%@.%@", safeTitle, extension]];
            [[NSFileManager defaultManager] removeItemAtPath:named error:NULL];
            [[NSFileManager defaultManager] moveItemAtPath:path toPath:named error:NULL];
            [[ORBookImporter shared] importFileAtURL:[NSURL fileURLWithPath:named] completion:^(ORBook *book, NSError *importError) {
                [[NSFileManager defaultManager] removeItemAtPath:named error:NULL];
                if (importError || !book) {
                    [ORUtil presentAlertIn:strongSelf title:@"Импорт"
                                    message:importError.localizedDescription ?: @"Не удалось добавить книгу."];
                    return;
                }
                book.source = ORBookSourceYandex;
                book.remoteID = item[@"id"];
                [[ORLibrary shared] updateBook:book];
                [ORUtil presentAlertIn:strongSelf title:@"Добавлено"
                                message:[NSString stringWithFormat:@"«%@» в библиотеке.", book.title]];
            }];
        }];
    }];
}

- (ORBook *)placeholderBookFor:(NSDictionary *)item {
    ORBook *book = [[ORBook alloc] init];
    book.title = item[@"title"] ?: @"Аудиокнига";
    book.author = item[@"author"] ?: @"";
    book.format = ORBookFormatAudio;
    book.source = ORBookSourceYandex;
    book.remoteID = item[@"id"];
    book.audioURL = item[@"audioURL"] ?: item[@"downloadURL"];
    return book;
}

@end
