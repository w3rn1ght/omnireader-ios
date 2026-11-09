#import <Foundation/Foundation.h>
#import "ORCore.h"

NS_ASSUME_NONNULL_BEGIN

/// Extracts readable HTML from OOXML documents (DOCX / XLSX / PPTX).
/// Legacy binary formats (DOC/XLS/PPT) are handled by QuickLook instead.
@interface OROfficeText : NSObject

+ (nullable NSString *)htmlFromDocumentAtPath:(NSString *)path
                                       format:(ORBookFormat)format
                                        error:(NSError **)error;

+ (nullable NSString *)plainTextFromDocumentAtPath:(NSString *)path
                                            format:(ORBookFormat)format;

@end

NS_ASSUME_NONNULL_END
