#import "ORYandexAuth.h"
#import "ORCore.h"
#import "ORYandexAPI.h"
#import "ORText.h"
#import "ORUtil.h"
#import <AuthenticationServices/AuthenticationServices.h>

NSNotificationName const ORYandexAuthDidChangeNotification = @"ORYandexAuthDidChangeNotification";

@interface ORYandexAuth ()
@property (nonatomic, strong) ASWebAuthenticationSession *session;
+ (NSString *)valueForParameter:(NSString *)name inQuery:(NSString *)query;
- (void)refreshProfile;
- (void)promptForTokenIn:(UIViewController *)host
              completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
@end

@implementation ORYandexAuth

+ (instancetype)shared {
    static ORYandexAuth *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ORYandexAuth alloc] init];
    });
    return instance;
}

- (BOOL)isSignedIn {
    return [ORSettings shared].yandexToken.length > 0;
}

- (NSString *)token {
    return [ORSettings shared].yandexToken;
}

- (void)setManualToken:(NSString *)token {
    [ORSettings shared].yandexToken = token;
    [self refreshProfile];
    [[NSNotificationCenter defaultCenter] postNotificationName:ORYandexAuthDidChangeNotification object:self];
}

- (void)signOut {
    [ORSettings shared].yandexToken = nil;
    [ORSettings shared].yandexUserName = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:ORYandexAuthDidChangeNotification object:self];
}

+ (NSURL *)authorizationURL {
    NSString *clientID = [ORSettings shared].yandexClientID;
    if (clientID.length == 0) return nil;
    NSString *urlString = [NSString stringWithFormat:
        @"https://oauth.yandex.ru/authorize?response_type=token&client_id=%@&redirect_uri=%@&state=%@",
        [ORText queryEscape:clientID], @"omnireader%3A%2F%2Foauth", [ORUtil uniqueKey]];
    return [NSURL URLWithString:urlString];
}

+ (BOOL)handleCallbackURL:(NSURL *)url {
    if (![url.scheme.lowercaseString isEqualToString:@"omnireader"]) return NO;
    NSString *fragment = url.fragment ?: @"";
    NSString *query = url.query ?: @"";
    NSString *token = [self valueForParameter:@"access_token" inQuery:fragment];
    if (token.length == 0) token = [self valueForParameter:@"access_token" inQuery:query];
    if (token.length == 0) return NO;
    [ORSettings shared].yandexToken = token;
    [[ORYandexAuth shared] refreshProfile];
    [[NSNotificationCenter defaultCenter] postNotificationName:ORYandexAuthDidChangeNotification object:self];
    return YES;
}

- (void)signInFrom:(UIViewController *)host completion:(void (^)(BOOL, NSError *))completion {
    NSURL *url = [ORYandexAuth authorizationURL];
    if (!url) {
        // No registered OAuth app: fall back to a pasted token.
        [self promptForTokenIn:host completion:completion];
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.session = [[ASWebAuthenticationSession alloc] initWithURL:url
                                                 callbackURLScheme:@"omnireader"
                                                 completionHandler:^(NSURL *callbackURL, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.session = nil;
        if (error) {
            completion(NO, error);
            return;
        }
        if (!callbackURL) {
            completion(NO, [NSError errorWithDomain:@"OmniReader.Yandex" code:2
                                           userInfo:@{NSLocalizedDescriptionKey: @"Ошибка авторизации"}]);
            return;
        }
        if ([ORYandexAuth handleCallbackURL:callbackURL]) {
            completion(YES, nil);
            return;
        }
        NSString *fragment = callbackURL.fragment ?: @"";
        NSString *errorDescription = [ORYandexAuth valueForParameter:@"error_description" inQuery:fragment] ?: @"Токен не получен";
        completion(NO, [NSError errorWithDomain:@"OmniReader.Yandex" code:3
                                       userInfo:@{NSLocalizedDescriptionKey: errorDescription}]);
    }];
    BOOL started = [self.session start];
    if (!started) {
        completion(NO, [NSError errorWithDomain:@"OmniReader.Yandex" code:4
                                       userInfo:@{NSLocalizedDescriptionKey: @"Не удалось открыть окно авторизации"}]);
    }
}

+ (NSString *)valueForParameter:(NSString *)name inQuery:(NSString *)query {
    NSArray<NSString *> *pairs = [query componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        NSArray<NSString *> *parts = [pair componentsSeparatedByString:@"="];
        if (parts.count == 2 && [parts[0] isEqualToString:name]) {
            NSString *value = [parts[1] stringByRemovingPercentEncoding];
            return value ?: @"";
        }
    }
    return @"";
}

- (void)promptForTokenIn:(UIViewController *)host completion:(void (^)(BOOL, NSError *))completion {
    if (!host) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Токен Яндекс Книг"
                                                                  message:@"Вставьте OAuth-токен. Чтобы входить через браузер, укажите Client ID приложения в настройках."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"y0_Ag…";
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Сохранить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *token = alert.textFields.firstObject.text ?: @"";
        if (token.length < 8) {
            completion(NO, [NSError errorWithDomain:@"OmniReader.Yandex" code:5
                                           userInfo:@{NSLocalizedDescriptionKey: @"Токен слишком короткий"}]);
            return;
        }
        [ORSettings shared].yandexToken = token;
        [self refreshProfile];
        completion(YES, nil);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:alert animated:YES completion:nil];
}

- (void)refreshProfile {
    [ORYandexAPI fetchProfile:^(NSString *name, NSError *error) {
        if (name.length > 0) {
            [ORSettings shared].yandexUserName = name;
        }
    }];
}

@end
