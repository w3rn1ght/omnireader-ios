#import "ORSettingsViewController.h"
#import "ORCore.h"
#import "OROPDSViewController.h"
#import "ORReaderSettingsController.h"
#import "ORUtil.h"
#import "ORYandexAuth.h"
#import "ORYandexSession.h"
#import "ORCatalogLogin.h"

@implementation ORSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Настройки";
    self.tableView.tableFooterView = [[UIView alloc] init];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2;
        case 1: return 4;
        case 2: return 2;
        case 3: return [ORSettings shared].opdsCatalogs.count + 1;
        default: return 3;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 3) {
        return @"Вход не обязателен: каталоги открываются и книги скачиваются анонимно. "
                "Логин и пароль нужны только если конкретный сервер без них не отдаёт файлы.";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Чтение";
        case 1: return @"Яндекс Книги";
        case 2: return @"Аудио";
        case 3: return @"Каталоги OPDS";
        default: return @"О приложении";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    cell.detailTextLabel.text = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = [UIColor blackColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Оформление и шрифт";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"Не гасить экран при чтении";
            UISwitch *toggle = [[UISwitch alloc] init];
            toggle.on = [ORSettings shared].keepScreenAwake;
            [toggle addTarget:self action:@selector(keepAwakeChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else if (indexPath.section == 1) {
        BOOL signedIn = [ORYandexAuth shared].isSignedIn;
        BOOL hasSession = [ORYandexSession hasSession];
        if (indexPath.row == 0) {
            cell.textLabel.text = signedIn ? @"Выйти из аккаунта" : @"Войти в аккаунт";
            cell.textLabel.textColor = signedIn ? [UIColor redColor] : self.view.tintColor;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = hasSession ? @"Обновить сессию сайта" : @"Войти через сайт Яндекса";
            cell.detailTextLabel.text = hasSession ? @"Сохранена" : @"нужна для полки";
            cell.textLabel.textColor = self.view.tintColor;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Статус";
            cell.detailTextLabel.text = signedIn ? ([ORSettings shared].yandexUserName ?: @"Подключено") : @"Не подключено";
            cell.selectionStyle = signedIn ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
            if (signedIn) {
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
        } else {
            cell.textLabel.text = @"Client ID OAuth";
            cell.detailTextLabel.text = [ORSettings shared].yandexClientID.length > 0 ? @"задан" : @"не задан";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Скорость по умолчанию";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"×%.2g", [ORSettings shared].playbackRate];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Скорость озвучки текста";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", [ORSettings shared].speechRate * 100];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = @"Фоновое воспроизведение";
            cell.detailTextLabel.text = @"включено";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else if (indexPath.section == 3) {
        NSArray *catalogs = [ORSettings shared].opdsCatalogs;
        if (indexPath.row < (NSInteger)catalogs.count) {
            NSDictionary *catalog = catalogs[(NSUInteger)indexPath.row];
            NSString *name = catalog[@"name"] ?: @"Каталог";
            NSString *savedUser = catalog[@"user"];
            cell.textLabel.text = savedUser.length > 0
                ? [NSString stringWithFormat:@"%@ · %@", name, savedUser]
                : name;
            cell.detailTextLabel.text = catalog[@"url"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"Добавить каталог";
            cell.textLabel.textColor = self.view.tintColor;
        }
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Версия";
            cell.detailTextLabel.text = @"1.4.5";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Поддерживаемые форматы";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"Правовая информация";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    return cell;
}

- (void)verifyYandexToken {
    UIAlertController *wait = [ORUtil alertWithTitle:@"Проверка токена" message:@"Запрашиваю данные аккаунта у Яндекса…"];
    [self presentViewController:wait animated:YES completion:nil];
    [[ORYandexAuth shared] diagnose:^(NSString *report) {
        [self dismissViewControllerAnimated:YES completion:^{
            [ORUtil presentAlertIn:self title:@"Проверка токена" message:report ?: @"Нет ответа"];
        }];
    }];
}

- (void)keepAwakeChanged:(UISwitch *)toggle {    [ORSettings shared].keepScreenAwake = toggle.on;
    [[ORSettings shared] synchronize];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0 && indexPath.row == 0) {
        ORReaderSettingsController *reader = [[ORReaderSettingsController alloc] initWithSettings:[ORSettings shared]];
        [self.navigationController pushViewController:reader animated:YES];
        return;
    }

    if (indexPath.section == 1) {
        ORYandexAuth *auth = [ORYandexAuth shared];
        if (indexPath.row == 2 && auth.isSignedIn) {
            [self verifyYandexToken];
            return;
        }
        if (indexPath.row == 1) {
            [auth signInWithWebSessionFrom:self completion:^(BOOL success, NSError *error) {
                [tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
                if (!success && error && error.code != 6) {
                    [ORUtil presentAlertIn:self title:@"Яндекс Книги" message:error.localizedDescription];
                }
            }];
            return;
        }
        if (indexPath.row == 0) {
            if (auth.isSignedIn) {
                [auth signOut];
                [tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
            } else {
                [auth signInFrom:self completion:^(BOOL success, NSError *error) {
                    [tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
                    if (!success && error) {
                        [ORUtil presentAlertIn:self title:@"Яндекс Книги" message:error.localizedDescription];
                    }
                }];
            }
        } else if (indexPath.row == 3) {
            [self editYandexClientID];
        }
        return;
    }

    if (indexPath.section == 3) {
        NSArray *catalogs = [ORSettings shared].opdsCatalogs;
        if (indexPath.row >= (NSInteger)catalogs.count) {
            [self addCatalog];
        } else {
            NSDictionary *catalog = catalogs[(NSUInteger)indexPath.row];
            UIAlertController *sheet = [UIAlertController alertControllerWithTitle:catalog[@"name"]
                                                                          message:catalog[@"url"]
                                                                   preferredStyle:UIAlertControllerStyleActionSheet];
            [sheet addAction:[UIAlertAction actionWithTitle:@"Открыть" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [OROPDSViewController presentCatalog:catalog from:self];
            }]];
            [sheet addAction:[UIAlertAction actionWithTitle:@"Логин и пароль" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [ORCatalogLogin presentIn:self catalog:catalog completion:^(NSDictionary *updated, BOOL saved) {
                    if (!saved) return;
                    [tableView reloadSections:[NSIndexSet indexSetWithIndex:3]
                             withRowAnimation:UITableViewRowAnimationAutomatic];
                    NSString *user = updated[@"user"];
                    [ORUtil presentAlertIn:self
                                     title:@"Каталог"
                                   message:user.length > 0
                                           ? [NSString stringWithFormat:@"Сохранён вход: %@", user]
                                           : @"Логин удалён."];
                }];
            }]];
            [sheet addAction:[UIAlertAction actionWithTitle:@"Удалить" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                [[ORSettings shared] removeOPDSCatalogWithID:catalog[@"id"]];
                [tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationAutomatic];
            }]];
            [sheet addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
            sheet.popoverPresentationController.sourceView = tableView;
            sheet.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
            [self presentViewController:sheet animated:YES completion:nil];
        }
        return;
    }

    if (indexPath.section == 4) {
        if (indexPath.row == 1) {
            [ORUtil presentAlertIn:self title:@"Форматы"
                            message:@"Книги: EPUB, FB2 (в том числе FB2.zip), MOBI, AZW/AZW3 (без DRM), TXT, Markdown, HTML, CBZ, CBR (RAR не встроен).\n\nДокументы: PDF, DOCX, XLSX, PPTX (нативно), DOC/XLS/PPT (через QuickLook), DjVu (текстовый слой; сканы без распознавания открываются во внешнем просмотрщике).\n\nАудио: MP3, M4A, M4B, AAC, FLAC, WAV; потоковые URL."];
        } else if (indexPath.row == 2) {
            [ORUtil presentAlertIn:self title:@"Правовая информация"
                            message:@"OmniReader — локальный просмотрщик. Приложение не содержит контента и не обходит DRM. Яндекc Книги — сторонний сервис: используйте только свой аккаунт и соблюдайте условия сервиса. Все права на книги принадлежат их правообладателям."];
        }
    }
}

- (void)editYandexClientID {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Client ID"
                                                                  message:@"Необязательно. Вставьте client_id приложения OAuth из oauth.yandex.ru. Если пусто — используется вход по токену."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = [ORSettings shared].yandexClientID;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Сохранить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [ORSettings shared].yandexClientID = alert.textFields.firstObject.text ?: @"";
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Вставить токен" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptForYandexToken];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptForYandexToken {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Токен Яндекса"
                                                                  message:@"Вставьте OAuth-токен с правами на Книги (можно получить через официальный OAuth-флоу)."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"y0_Ag…";
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Сохранить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *token = alert.textFields.firstObject.text ?: @"";
        [[ORYandexAuth shared] setManualToken:token completion:^(BOOL success, NSString *message) {
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
            [ORUtil presentAlertIn:self
                             title:success ? @"Яндекс Книги" : @"Токен"
                           message:message ?: (success ? @"Токен сохранён." : @"Не удалось распознать токен.")];
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addCatalog {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Новый каталог OPDS"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Название";
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"https://example.com/opds";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Логин (необязательно)";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Пароль";
        textField.secureTextEntry = YES;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Добавить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields[0].text ?: @"Каталог";
        NSString *url = alert.textFields[1].text ?: @"";
        NSURL *checked = [NSURL URLWithString:url];
        if (!checked || checked.scheme.length == 0) {
            [ORUtil presentAlertIn:self title:@"Каталог" message:@"Нужен полный URL, например https://…/opds"];
            return;
        }
        NSString *catalogID = [ORUtil uniqueKey];
        NSMutableDictionary *catalog = [NSMutableDictionary dictionary];
        catalog[@"id"] = catalogID;
        catalog[@"name"] = name;
        catalog[@"url"] = url;
        if (alert.textFields[2].text.length > 0) catalog[@"user"] = alert.textFields[2].text;
        [[ORSettings shared] addOPDSCatalog:catalog];
        if (alert.textFields[3].text.length > 0) {
            [[ORSettings shared] setPassword:alert.textFields[3].text forOPDSCatalog:catalogID];
        }
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationAutomatic];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end