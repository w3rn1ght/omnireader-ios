#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^ORYandexShelfCompletion)(NSArray<NSDictionary *> *_Nullable items, NSError *_Nullable error);
typedef void (^ORYandexProfileCompletion)(NSString *_Nullable name, NSError *_Nullable error);

/// Adapter around the (unofficial) Yandex Books web API.
///
/// Yandex does not publish a public API for Books, so the endpoint list lives in
/// `ORYandexAPI+Endpoints` and the JSON decoding is intentionally tolerant:
/// several known key paths are tried. If the service changes its schema the app
/// degrades to "manual token + import purchased files" instead of crashing.
///
/// DRM protected downloads are never decrypted: the player only opens files the
/// account is allowed to read directly.
@interface ORYandexAPI : NSObject

+ (void)fetchProfile:(ORYandexProfileCompletion)completion;
+ (void)fetchShelf:(ORYandexShelfCompletion)completion;

/// Debug helper used by the app's log: does the current token accept
/// the GraphQL viewer query at all?
+ (void)verifyGraphQLAccess:(void (^)(NSString *_Nullable info, NSError *_Nullable error))completion;

/// Raw GraphQL probe for the "Проверка токена" action in settings.
+ (void)performGraphQLForDebug:(NSString *)query
                    completion:(void (^)(NSString *_Nullable info, NSError *_Nullable error))completion;

/// Probes the GraphQL schema for a working viewer root and reports the result.
+ (void)diagnoseToken:(void (^)(NSString *_Nullable report, NSError *_Nullable error))completion;

/// Resolves a direct download (or streaming) URL for one item.
+ (void)resolveDownloadForItem:(NSDictionary *)item
                    completion:(void (^)(NSURL *_Nullable url, NSString *_Nullable format, NSError *_Nullable error))completion;

+ (NSDictionary *)normaliseBookDictionary:(NSDictionary *)raw;

@end

NS_ASSUME_NONNULL_END
