#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ORText : NSObject

/// Best-effort text decoding with BOM/VUTF-8 detection and Cyrillic legacy encodings.
+ (NSString *)stringFromData:(NSData *)data;
+ (NSString *)stringFromData:(NSData *)data encoding:(nullable NSStringEncoding *)outEncoding;

+ (NSString *)escapeHTML:(NSString *)string;
+ (NSString *)stripHTML:(NSString *)html;
+ (NSString *)decodeEntities:(NSString *)string;

+ (NSString *)replacePattern:(NSString *)pattern
                    inString:(NSString *)string
                withTemplate:(NSString *)template;

+ (nullable NSString *)firstMatchPattern:(NSString *)pattern
                                inString:(NSString *)string
                                   group:(NSInteger)group;

+ (NSArray<NSString *> *)matchesPattern:(NSString *)pattern
                              inString:(NSString *)string
                                 group:(NSInteger)group;

+ (BOOL)looksLikeZIP:(NSData *)data;
+ (BOOL)looksLikeRAR:(NSData *)data;
+ (BOOL)looksLikeEPUBMimetype:(nullable NSData *)data;

+ (NSString *)fileURLString:(NSString *)path;
+ (NSString *)queryEscape:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
