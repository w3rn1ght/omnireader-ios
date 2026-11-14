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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(authChanged)
                                                 name:ORYandexAuthDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)authChanged {
    [self.tableView reloadData];
    if ([ORYandexAuth shared].isSignedIn) {
        [self loadShelf];
    }
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
        // ORHTTP completes off the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.spinner stopAnimating];
        [strongSelf.tableView.refreshControl endRefreshing];
        if (error) {
            NSLog(@"[OmniReader] Yandex shelf failed: %@", error);
            [strongSelf presentShelfError:error];
            return;
        }
        strongSelf.items = items ?: @[];
        [strongSelf.tableView reloadData];
        if (strongSelf.items.count == 0) {
            [ORUtil presentAlertIn:strongSelf title:@"Полка пуста"
                            message:@"Аккаунт подключён, но книг не найдено. Подробности — в Docs/YANDEX.md; купленные файлы можно добавить через «+» → «Импортировать файл»."];
        }
        });
    }];
}

/// A closed shelf is the most common failure, so offer the session login right
/// in the error dialog instead of sending the user to the settings screen.
- (void)presentShelfError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Яндекс Книги"
                                                                  message:error.localizedDescription
                                                           preferredStyle:UIAlertControllerStyleAlert];
    if (error.code == 422 || error.code == 401) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Войти через сайт"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [self signInWithWebSession];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Проверить токен"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [self debugCheckToken];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Закрыть" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)signInWithWebSession {
    __weak typeof(self) weakSelf = self;
    [[ORYandexAuth shared] signInWithWebSessionFrom:self completion:^(BOOL success, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.tableView reloadData];
        if (success) {
            [strongSelf loadShelf];
        } else if (error && error.code != 6) {
            [ORUtil presentAlertIn:strongSelf title:@"Яндекс Книги" message:error.localizedDescription];
        }
    }];
}

- (void)debugCheckToken {
    [ORUtil presentAlertIn:self title:@"Проверка токена" message:@"Отправляю запрос к GraphQL Яндекса…"];
    [[ORYandexAuth shared] debugVerifyToken:^(NSString *info, NSError *error) {
        NSString *text = error ? error.localizedDescription : (info ?: @"OK");
        [ORUtil presentAlertIn:self title:@"Результат" message:text];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (![ORYandexAuth shared].isSignedIn) return 4;
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
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Войти через сайт Яндекса";
            cell.detailTextLabel.text = @"Откроется books.yandex.ru — нужна для полки";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Войти по OAuth";
            cell.detailTextLabel.text = @"Системное окно; нужен Client ID";
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Ссылка для входа на компьютере";
            cell.detailTextLabel.text = @"Скопировать и открыть на ПК, затем вставить токен";
        } else {
            cell.textLabel.text = @"Вставить токен вручную";
            cell.detailTextLabel.text = @"Можно вставить всю callback-ссылку";
        }
        cell.textLabel.textColor = self.view.tintColor;
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
            [self signInWithWebSession];
        } else if (indexPath.row == 1) {
            [self signIn];
        } else if (indexPath.row == 2) {
            [self copyAuthorizationLink];
        } else {
            [[ORYandexAuth shared] promptForManualTokenFrom:self completion:^(BOOL success, NSError *error) {
                [self.tableView reloadData];
                if (success) [self loadShelf];
                else if (error) [ORUtil presentAlertIn:self title:@"Яндекс Книги" message:error.localizedDescription];
            }];
        }
        return;
    }
    if (self.items.count == 0) return;
    [self downloadItem:self.items[(NSUInteger)indexPath.row]];
}

- (void)copyAuthorizationLink {
    NSURL *url = [ORYandexAuth authorizationURL];
    if (!url) {
        [ORUtil presentAlertIn:self title:@"Нужен Client ID"
                        message:@"Сначала укажите Client ID приложения OAuth в настройках: Настройки → Яндекс Книги → Client ID OAuth."];
        return;
    }
    [UIPasteboard generalPasteboard].string = url.absoluteString;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Ссылка скопирована"
                                                                  message:@"1. Откройте ссылку на компьютере.\n2. Войдите в Яндекс и разрешите доступ.\n3. Браузер перенаправит на omnireader://oauth#access_token=… — скопируйте этот адрес целиком.\n4. Вернитесь в приложение и выберите «Вставить токен вручную» — можно вставить всю ссылку."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Вставить токен" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[ORYandexAuth shared] promptForManualTokenFrom:self completion:^(BOOL success, NSError *error) {
            [self.tableView reloadData];
            if (success) [self loadShelf];
            else if (error) [ORUtil presentAlertIn:self title:@"Яндекс Книги" message:error.localizedDescription];
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Закрыть" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)signInWithSafari {
    NSURL *url = [ORYandexAuth authorizationURL];
    if (!url) {
        [ORUtil presentAlertIn:self title:@"Нужен Client ID"
                        message:@"Сначала укажите Client ID приложения OAuth в настройках: Настройки → Яндекс Книги → Client ID OAuth."];
        return;
    }
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)signIn {
    __weak typeof(self) weakSelf = self;
    [[ORYandexAuth shared] signInFrom:self completion:^(BOOL success, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!success) {
            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Яндекс Книги"
                                                                              message:error.localizedDescription
                                                                       preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Войти через Safari" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [strongSelf signInWithSafari];
                }]];
                [alert addAction:[UIAlertAction actionWithTitle:@"Закрыть" style:UIAlertActionStyleCancel handler:nil]];
                [strongSelf presentViewController:alert animated:YES completion:nil];
            }
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
        // ORHTTP completes off the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
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
            // ORHTTP completes on the session's background queue.
            dispatch_async(dispatch_get_main_queue(), ^{
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
            });
        }];
    });
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
