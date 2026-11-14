#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Stores the Yandex Passport cookies captured from the in-app web view.
///
/// The Books GraphQL endpoint (p-graphql) answers OAuth clients with
/// "Whitelist: query not found": its allow-list is bound to a browser session,
/// not to a bearer token. A logged-in web session is therefore the only way to
/// read the personal shelf; the cookies never leave the device and are kept in
/// the Keychain next to the OAuth token.
@interface ORYandexSession : NSObject

+ (BOOL)hasSession;
+ (nullable NSString *)cookieHeader;
+ (void)setCookieHeader:(nullable NSString *)header;
+ (void)clearSession;

/// Best-effort login name from the passport cookies (yandex_login / login).
+ (nullable NSString *)loginFromCookies;

/// Reads every non-expired cookie for yandex.ru domains and stores the
/// resulting Cookie header value.
+ (void)captureCookiesFromWebView:(WKWebView *)webView
                       completion:(void (^)(NSString *_Nullable header))completion;

@end

NS_ASSUME_NONNULL_END
