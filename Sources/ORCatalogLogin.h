#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Prompt for OPDS HTTP Basic credentials.
///
/// Many catalogs (including lib.rus.ec) protect feeds and files with Basic
/// auth: the server answers 401 and expects the same login/password as the
/// website. The entered pair is stored through ORSettings and can be reused by
/// every request to that catalog.
@interface ORCatalogLogin : NSObject

/// @param completion Called with the updated catalog and YES when the user
///                   saved credentials, or with the original catalog and NO
///                   when the prompt was dismissed.
+ (void)presentIn:(UIViewController *)presenter
          catalog:(NSDictionary *)catalog
       completion:(nullable void (^)(NSDictionary *catalog, BOOL saved))completion;

@end

NS_ASSUME_NONNULL_END
