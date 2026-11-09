#import <Foundation/Foundation.h>
#import "ORCore.h"

NS_ASSUME_NONNULL_BEGIN

/// Turns TXT / HTML / Markdown files into paginated HTML with chapter anchors.
@interface ORPlainTextBook : NSObject

+ (nullable instancetype)bookAtPath:(NSString *)path
                             format:(ORBookFormat)format
                           cacheKey:(NSString *)cacheKey
                              error:(NSError **)error;

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *rootDirectory;
@property (nonatomic, copy) NSString *extraCSS;
@property (nonatomic, copy) NSString *htmlBody;
@property (nonatomic, copy) NSString *plainText;
@property (nonatomic, copy) NSArray<ORTOCItem *> *toc;

@end

NS_ASSUME_NONNULL_END
