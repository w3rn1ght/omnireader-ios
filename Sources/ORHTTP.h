#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ORHTTP : NSObject

+ (void)GET:(NSString *)urlString
    headers:(nullable NSDictionary<NSString *, NSString *> *)headers
 completion:(void (^)(NSData *_Nullable data, NSHTTPURLResponse *_Nullable response, NSError *_Nullable error))completion;

+ (void)POST:(NSString *)urlString
        body:(nullable NSData *)body
     headers:(nullable NSDictionary<NSString *, NSString *> *)headers
  completion:(void (^)(NSData *_Nullable data, NSHTTPURLResponse *_Nullable response, NSError *_Nullable error))completion;

+ (void)download:(NSString *)urlString
         headers:(nullable NSDictionary<NSString *, NSString *> *)headers
          toPath:(NSString *)path
      completion:(void (^)(NSString *_Nullable path, NSError *_Nullable error))completion;

+ (NSString *)basicAuthorizationForUser:(NSString *)user password:(NSString *)password;

@end

NS_ASSUME_NONNULL_END
