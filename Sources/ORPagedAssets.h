#import <Foundation/Foundation.h>
#import "ORCore.h"

NS_ASSUME_NONNULL_BEGIN

/// Builds the paginated HTML document (CSS columns + paginator JS) and the
/// JS call used to restyle it live.
@interface ORPagedAssets : NSObject

+ (NSString *)documentHTMLWithBody:(NSString *)body
                          extraCSS:(NSString *)extraCSS
                             title:(NSString *)title
                          settings:(ORSettings *)settings;

+ (NSString *)styleConfigurationForSettings:(ORSettings *)settings;

+ (NSString *)jsString:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
