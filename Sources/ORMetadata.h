#import <Foundation/Foundation.h>
#import "ORCore.h"

@class ORZip;

NS_ASSUME_NONNULL_BEGIN

@interface ORMetadata : NSObject

/// Fills title/author/cover without building the full reading layout.
+ (void)enrichBook:(ORBook *)book atPath:(NSString *)path;

+ (nullable UIImage *)coverImageForBook:(ORBook *)book;

+ (NSArray<NSString *> *)sortedImageNamesInZip:(nullable ORZip *)zip;

@end

NS_ASSUME_NONNULL_END
