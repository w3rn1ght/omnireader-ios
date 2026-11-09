#import "ORText.h"
#import <CoreFoundation/CoreFoundation.h>

@implementation ORText

+ (NSString *)stringFromData:(NSData *)data {
    return [self stringFromData:data encoding:NULL];
}

+ (NSString *)stringFromData:(NSData *)data encoding:(NSStringEncoding *)outEncoding {
    if (data.length == 0) {
        if (outEncoding) *outEncoding = NSUTF8StringEncoding;
        return @"";
    }

    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;

    // Byte order marks first.
    if (length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
        NSData *payload = [data subdataWithRange:NSMakeRange(3, length - 3)];
        if (outEncoding) *outEncoding = NSUTF8StringEncoding;
        return [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding] ?: @"";
    }
    if (length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        if (outEncoding) *outEncoding = NSUTF16LittleEndianStringEncoding;
        return [[NSString alloc] initWithData:data encoding:NSUTF16LittleEndianStringEncoding] ?: @"";
    }
    if (length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        if (outEncoding) *outEncoding = NSUTF16BigEndianStringEncoding;
        return [[NSString alloc] initWithData:data encoding:NSUTF16BigEndianStringEncoding] ?: @"";
    }

    NSString *utf8 = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (utf8) {
        if (outEncoding) *outEncoding = NSUTF8StringEncoding;
        return [utf8 stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0xFEFF, 1)]];
    }

    NSStringEncoding candidates[] = {
        CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsCyrillic),
        CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingKOI8_R),
        CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingMacCyrillic),
        NSWindowsCP1252StringEncoding,
        NSISOLatin1StringEncoding,
        NSWindowsCP1251StringEncoding
    };
    NSString *best = nil;
    NSInteger bestScore = NSIntegerMin;
    NSStringEncoding bestEncoding = NSUTF8StringEncoding;
    for (NSUInteger i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        NSStringEncoding encoding = candidates[i];
        NSString *candidate = [[NSString alloc] initWithData:data encoding:encoding];
        if (!candidate) continue;
        NSInteger score = [self cyrillicScore:candidate];
        if (score > bestScore) {
            bestScore = score;
            best = candidate;
            bestEncoding = encoding;
        }
    }
    if (best) {
        if (outEncoding) *outEncoding = bestEncoding;
        return best;
    }
    if (outEncoding) *outEncoding = NSUTF8StringEncoding;
    return [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] ?: @"";
}

+ (NSInteger)cyrillicScore:(NSString *)string {
    NSInteger score = 0;
    NSUInteger limit = MIN(string.length, (NSUInteger)6000);
    for (NSUInteger i = 0; i < limit; i++) {
        unichar c = [string characterAtIndex:i];
        if ((c >= 0x0410 && c <= 0x044F) || c == 0x0401 || c == 0x0451) score += 3;
        else if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) score += 1;
        else if (c == 0xFFFD) score -= 8;
        else if (c < 0x20 && c != '\n' && c != '\r' && c != '\t') score -= 5;
        else if (c >= 0x2500 && c <= 0x25FF) score -= 1;
    }
    return score;
}

+ (NSString *)escapeHTML:(NSString *)string {
    if (string.length == 0) return @"";
    NSMutableString *result = [string mutableCopy];
    [result replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, result.length)];
    [result replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, result.length)];
    [result replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, result.length)];
    [result replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, result.length)];
    return result;
}

+ (NSString *)decodeEntities:(NSString *)string {
    if (string.length == 0) return @"";
    NSMutableString *result = [string mutableCopy];
    NSDictionary *named = @{
        @"&nbsp;": @" ", @"&amp;": @"&", @"&lt;": @"<", @"&gt;": @">",
        @"&quot;": @"\"", @"&apos;": @"'", @"&mdash;": @"—", @"&ndash;": @"–",
        @"&laquo;": @"«", @"&raquo;": @"»", @"&hellip;": @"…", @"&copy;": @"©",
        @"&reg;": @"®", @"&trade;": @"™", @"&deg;": @"°", @"&plusmn;": @"±"
    };
    for (NSString *key in named) {
        [result replaceOccurrencesOfString:key withString:named[key] options:NSCaseInsensitiveSearch range:NSMakeRange(0, result.length)];
    }
    NSRegularExpression *numeric = [NSRegularExpression regularExpressionWithPattern:@"&#(x?)([0-9a-fA-F]+);" options:0 error:NULL];
    NSArray<NSTextCheckingResult *> *matches = [numeric matchesInString:result options:0 range:NSMakeRange(0, result.length)];
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSString *hexFlag = [result substringWithRange:[match rangeAtIndex:1]];
        NSString *digits = [result substringWithRange:[match rangeAtIndex:2]];
        unsigned int value = 0;
        if (hexFlag.length > 0) {
            sscanf(digits.UTF8String, "%x", &value);
        } else {
            value = (unsigned int)digits.integerValue;
        }
        if (value > 0 && value <= 0x10FFFF) {
            unichar chars[2];
            NSString *replacement = nil;
            if (value <= 0xFFFF) {
                chars[0] = (unichar)value;
                replacement = [NSString stringWithCharacters:chars length:1];
            } else {
                unsigned int adjusted = value - 0x10000;
                chars[0] = (unichar)(0xD800 + (adjusted >> 10));
                chars[1] = (unichar)(0xDC00 + (adjusted & 0x3FF));
                replacement = [NSString stringWithCharacters:chars length:2];
            }
            [result replaceCharactersInRange:match.range withString:replacement ?: @""];
        }
    }
    return result;
}

+ (NSString *)stripHTML:(NSString *)html {
    if (html.length == 0) return @"";
    NSString *work = html;
    work = [self replacePattern:@"(?is)<(script|style)[^>]*>.*?</\\1>" inString:work withTemplate:@" "];
    work = [self replacePattern:@"(?i)<br\\s*/?>" inString:work withTemplate:@"\n"];
    work = [self replacePattern:@"(?i)</(p|div|li|tr|h[1-6]|blockquote|section|article)>" inString:work withTemplate:@"\n"];
    work = [self replacePattern:@"(?i)</td>" inString:work withTemplate:@"\t"];
    work = [self replacePattern:@"(?s)<[^>]+>" inString:work withTemplate:@""];
    work = [self decodeEntities:work];
    work = [work stringByReplacingOccurrencesOfString:@"\u00a0" withString:@" "];
    NSArray<NSString *> *lines = [work componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [clean addObject:trimmed];
    }
    return [clean componentsJoinedByString:@"\n"];
}

+ (NSString *)replacePattern:(NSString *)pattern
                    inString:(NSString *)string
                withTemplate:(NSString *)template {
    if (string.length == 0 || pattern.length == 0) return string ?: @"";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:0
                                                                             error:NULL];
    if (!regex) return string;
    return [regex stringByReplacingMatchesInString:string
                                           options:0
                                             range:NSMakeRange(0, string.length)
                                      withTemplate:template];
}

+ (NSString *)firstMatchPattern:(NSString *)pattern
                       inString:(NSString *)string
                          group:(NSInteger)group {
    if (string.length == 0 || pattern.length == 0) return nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:0
                                                                             error:NULL];
    if (!regex) return nil;
    NSTextCheckingResult *match = [regex firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
    if (!match || group >= (NSInteger)match.numberOfRanges) return nil;
    NSRange range = [match rangeAtIndex:group];
    if (range.location == NSNotFound) return nil;
    return [string substringWithRange:range];
}

+ (NSArray<NSString *> *)matchesPattern:(NSString *)pattern
                              inString:(NSString *)string
                                 group:(NSInteger)group {
    if (string.length == 0 || pattern.length == 0) return @[];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:0
                                                                             error:NULL];
    if (!regex) return @[];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:string options:0 range:NSMakeRange(0, string.length)];
    NSMutableArray<NSString *> *results = [NSMutableArray array];
    for (NSTextCheckingResult *match in matches) {
        if (group >= (NSInteger)match.numberOfRanges) continue;
        NSRange range = [match rangeAtIndex:group];
        if (range.location == NSNotFound) continue;
        [results addObject:[string substringWithRange:range]];
    }
    return results;
}

+ (BOOL)looksLikeZIP:(NSData *)data {
    if (data.length < 4) return NO;
    const uint8_t *b = data.bytes;
    return b[0] == 'P' && b[1] == 'K' && (b[2] == 3 || b[2] == 5 || b[2] == 7);
}

+ (BOOL)looksLikeRAR:(NSData *)data {
    if (data.length < 7) return NO;
    const uint8_t *b = data.bytes;
    return b[0] == 'R' && b[1] == 'a' && b[2] == 'r' && b[3] == '!' && b[4] == 0x1A && b[5] == 0x07;
}

+ (BOOL)looksLikeEPUBMimetype:(NSData *)data {
    if (!data) return NO;
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!string) string = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    return [string.lowercaseString containsString:@"application/epub+zip"];
}

+ (NSString *)fileURLString:(NSString *)path {
    if (path.length == 0) return @"";
    NSURL *url = [NSURL fileURLWithPath:path];
    return url.absoluteString ?: @"";
}

+ (NSString *)queryEscape:(NSString *)string {
    NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
    NSMutableCharacterSet *set = [allowed mutableCopy];
    [set removeCharactersInString:@"&+=?#"];
    return [string stringByAddingPercentEncodingWithAllowedCharacters:set] ?: @"";
}

@end
