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

/// Handles `omnireader://oauth#access_token=...` coming from Safari or the
/// system, stores the token and returns YES when it was an OAuth callback.
+ (BOOL)handleCallbackURL:(NSURL *)url;

- (void)signInFrom:(UIViewController *)host
        completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

- (void)setManualToken:(NSString *)token;
- (void)signOut;

@end

NS_ASSUME_NONNULL_END
