#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Sign-in with Yandex OAuth (implicit flow) or a manually pasted token.
/// The token is kept in the keychain.
@interface ORYandexAuth : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL isSignedIn;
@property (nonatomic, readonly, nullable) NSString *token;

- (void)signInFrom:(UIViewController *)host
        completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

- (void)setManualToken:(NSString *)token;
- (void)signOut;

@end

NS_ASSUME_NONNULL_END
