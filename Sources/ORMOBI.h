#import <Foundation/Foundation.h>
#import "ORCore.h"

NS_ASSUME_NONNULL_BEGIN

/// Minimal Mobipocket reader: PalmDB records + PalmDOC decompression.
/// HUFF/CDIC compressed and DRM protected files are rejected with a clear error.
@interface ORMOBI : NSObject

+ (nullable instancetype)bookAtPath:(NSString *)path
                           cacheKey:(NSString *)cacheKey
                              error:(NSError **)error;

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *rootDirectory;
@property (nonatomic, copy, nullable) NSString *coverImagePath;
@property (nonatomic, copy) NSString *extraCSS;
@property (nonatomic, copy) NSString *htmlBody;
@property (nonatomic, copy) NSString *plainText;
@property (nonatomic, copy) NSArray<ORTOCItem *> *toc;

@end

NS_ASSUME_NONNULL_END
