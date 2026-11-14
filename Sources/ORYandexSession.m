#import "ORYandexSession.h"
#import "ORCore.h"

static NSString *const ORYandexCookieKey = @"yandex.cookies";

@implementation ORYandexSession

+ (NSString *)cookieHeader {
    return [ORKeychain stringForKey:ORYandexCookieKey];
}

+ (BOOL)hasSession {
    return self.cookieHeader.length > 0;
}

+ (void)setCookieHeader:(NSString *)header {
    if (header.length > 0) {
        [ORKeychain setString:header forKey:ORYandexCookieKey];
    } else {
        [ORKeychain removeKey:ORYandexCookieKey];
    }
}

+ (void)clearSession {
    [ORKeychain removeKey:ORYandexCookieKey];
}

+ (NSString *)loginFromCookies {
    NSString *header = self.cookieHeader;
    if (header.length == 0) return nil;
    // Yandex uses various cookie names for login; try the most common ones
    for (NSString *name in @[@"yandex_login", @"login", @"yandex_login_id", @"Session_id", @"yashr", @"yandexuid"]) {
        NSString *prefix = [name stringByAppendingString:@"="];
        for (NSString *part in [header componentsSeparatedByString:@";"]) {
            NSString *pair = [part stringByTrimmingCharactersInSet:
                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (![pair hasPrefix:prefix]) continue;
            NSString *value = [pair substringFromIndex:prefix.length];
            value = [value stringByRemovingPercentEncoding] ?: value;
            if (value.length > 0) return value;
        }
    }
    return nil;
}

+ (void)captureCookiesFromWebView:(WKWebView *)webView
                   completion:(void (^)(NSString *))completion {
    if (!completion) return;
    WKHTTPCookieStore *store = webView.configuration.websiteDataStore.httpCookieStore;
    [store getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        NSDate *now = [NSDate date];
        NSMutableArray<NSString *> *pairs = [NSMutableArray array];
        for (NSHTTPCookie *cookie in cookies) {
            NSString *domain = cookie.domain.lowercaseString ?: @"";
            // Accept cookies from yandex, passport, books domains
            if (![domain containsString:@"yandex"] && ![domain containsString:@"passport"]) continue;
            if (cookie.expiresDate && [cookie.expiresDate compare:now] != NSOrderedDescending) continue;
            if (cookie.name.length == 0) continue;
            [pairs addObject:[NSString stringWithFormat:@"%@=%@", cookie.name, cookie.value ?: @""]];
        }
        // Also try to get the Yandex Session_id cookie specifically (most important for p-graphql)
        NSString *header = [pairs componentsJoinedByString:@"; "];
        if (header.length > 0) [self setCookieHeader:header];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(header.length > 0 ? header : nil);
        });
    }];
}

@end