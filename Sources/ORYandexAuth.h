#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const ORYandexAuthDidChangeNotification;

/// Sign-in with Yandex OAuth (implicit flow) or a manually pasted token.
/// The token is kept in the keychain.
@interface ORYandexAuth : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL isSignedIn;
@property (nonatomic, readonly, nullable) NSString *token;

/// URL for the in-app/session login. Nil when no Client ID is configured.
+ (nullable NSURL *)authorizationURL;

/// Extracts an OAuth token from a pasted token or from a full callback URL
/// (`omnireader://oauth#access_token=...`).
+ (nullable NSString *)tokenFromPastedString:(NSString *)string;

/// Handles `omnireader://oauth#access_token=...` coming from Safari or the
/// system, stores the token and returns YES when it was an OAuth callback.
+ (BOOL)handleCallbackURL:(NSURL *)url;

- (void)signInFrom:(UIViewController *)host
        completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

- (void)promptForManualTokenFrom:(UIViewController *)host
                      completion:(nullable void (^)(BOOL success, NSError *_Nullable error))completion;

- (void)setManualToken:(NSString *)token;

- (void)setManualToken:(NSString *)token
            completion:(nullable void (^)(BOOL success, NSString *_Nullable message))completion;

- (void)debugVerifyToken:(void (^)(NSString *_Nullable info, NSError *_Nullable error))completion;
- (void)diagnose:(void (^)(NSString *_Nullable report))completion;
- (void)signOut;

@end

NS_ASSUME_NONNULL_END
