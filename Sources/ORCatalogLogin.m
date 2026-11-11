#import "ORCatalogLogin.h"
#import "ORCore.h"
#import "ORUtil.h"

@implementation ORCatalogLogin

+ (void)presentIn:(UIViewController *)presenter
          catalog:(NSDictionary *)catalog
       completion:(void (^)(NSDictionary *, BOOL))completion {
    if (!presenter || !catalog) {
        if (completion) completion(catalog, NO);
        return;
    }
    NSString *catalogID = catalog[@"id"] ?: @"";
    NSString *host = [NSURL URLWithString:catalog[@"url"] ?: @""].host ?: @"каталога";
    NSString *message = [NSString stringWithFormat:
        @"Каталог %@ требует входа (HTTP Basic). Это тот же логин и пароль, что и на сайте.\n\n"
         "Если каталог открывается и без входа, просто нажмите «Отмена».",
        host];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Вход в каталог"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Логин";
        field.text = catalog[@"user"] ?: @"";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Пароль";
        field.text = [[ORSettings shared] passwordForOPDSCatalog:catalogID] ?: @"";
        field.secureTextEntry = YES;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Войти" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *login = [alert.textFields.firstObject.text
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
        NSString *password = alert.textFields.lastObject.text ?: @"";
        NSMutableDictionary *updated = [catalog mutableCopy];
        if (login.length > 0) {
            updated[@"user"] = login;
        } else {
            [updated removeObjectForKey:@"user"];
        }
        [[ORSettings shared] addOPDSCatalog:updated];
        [[ORSettings shared] setPassword:(password.length > 0 ? password : nil) forOPDSCatalog:catalogID];
        [[ORSettings shared] synchronize];
        if (completion) completion(updated, YES);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        if (completion) completion(catalog, NO);
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@end
