#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^OROPDSFeedCompletion)(NSDictionary *_Nullable feed, NSError *_Nullable error);
typedef void (^OROPDSDownloadCompletion)(NSString *_Nullable path, NSString *_Nullable suggestedName, NSError *_Nullable error);

@interface OROPDS : NSObject

/// Fetches and parses an OPDS acquisition/navigation feed.
+ (void)loadFeedAtURL:(NSString *)urlString
              catalog:(nullable NSDictionary *)catalog
           completion:(OROPDSFeedCompletion)completion;

+ (void)downloadEntry:(NSDictionary *)entry
              catalog:(nullable NSDictionary *)catalog
           formatHint:(nullable NSString *)formatHint
           completion:(OROPDSDownloadCompletion)completion;

/// Resolves an OpenSearch template from the feed (or falls back to ?q=).
+ (void)resolveSearchURLForFeed:(NSDictionary *)feed
                        catalog:(nullable NSDictionary *)catalog
                          query:(NSString *)query
                     completion:(void (^)(NSString *_Nullable url, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
