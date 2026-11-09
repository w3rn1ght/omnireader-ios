#import "ORMOBI.h"
#import "ORText.h"
#import "ORUtil.h"

static uint16_t ORMobiU16(const uint8_t *b, NSUInteger o) { return (uint16_t)(b[o] | (b[o + 1] << 8)); }
static uint32_t ORMobiU32(const uint8_t *b, NSUInteger o) {
    return ((uint32_t)b[o]) | ((uint32_t)b[o + 1] << 8) | ((uint32_t)b[o + 2] << 16) | ((uint32_t)b[o + 3] << 24);
}

static NSData *ORPalmDocDecompress(NSData *input) {
    const uint8_t *bytes = input.bytes;
    NSUInteger length = input.length;
    NSMutableData *output = [NSMutableData dataWithCapacity:length * 3];
    NSUInteger i = 0;
    while (i < length) {
        uint8_t byte = bytes[i++];
        if (byte == 0x00) {
            uint8_t zero = 0;
            [output appendBytes:&zero length:1];
        } else if (byte <= 0x08) {
            NSUInteger count = byte;
            if (i + count > length) count = length - i;
            [output appendBytes:bytes + i length:count];
            i += count;
        } else if (byte <= 0x7F) {
            [output appendBytes:&byte length:1];
        } else if (byte <= 0xBF) {
            if (i >= length) break;
            uint8_t next = bytes[i++];
            uint16_t pair = (uint16_t)(((uint16_t)byte << 8) | next);
            NSUInteger distance = (pair >> 3) & 0x07FF;
            NSUInteger copyLength = (pair & 0x0007) + 3;
            NSUInteger sourceLength = output.length;
            if (distance == 0 || distance > sourceLength) continue;
            for (NSUInteger k = 0; k < copyLength; k++) {
                NSUInteger index = sourceLength - distance + k;
                if (index >= output.length) break;
                uint8_t value = ((const uint8_t *)output.bytes)[index];
                [output appendBytes:&value length:1];
            }
        } else {
            uint8_t space = 0x20;
            uint8_t value = (uint8_t)(byte ^ 0x80);
            [output appendBytes:&space length:1];
            [output appendBytes:&value length:1];
        }
    }
    return output;
}

@implementation ORMOBI

+ (instancetype)bookAtPath:(NSString *)path cacheKey:(NSString *)cacheKey error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    if (!data || data.length < 200) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.MOBI" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Файл слишком мал"}];
        return nil;
    }
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;

    uint16_t recordCount = ORMobiU16(bytes, 76);
    if (recordCount < 2) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.MOBI" code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"Повреждённый MOBI-файл"}];
        return nil;
    }
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray arrayWithCapacity:recordCount + 1];
    for (NSUInteger i = 0; i < recordCount; i++) {
        NSUInteger offset = 78 + i * 8;
        if (offset + 4 > length) break;
        uint32_t value = ORMobiU32(bytes, offset);
        if (value >= length) break;
        [offsets addObject:@(value)];
    }
    if (offsets.count < 2) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.MOBI" code:3
                                            userInfo:@{NSLocalizedDescriptionKey: @"Не найдены записи MOBI"}];
        return nil;
    }
    [offsets addObject:@(length)];

    NSUInteger recursiveOffset = offsets[0].unsignedIntegerValue;
    if (recursiveOffset + 16 > length) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.MOBI" code:4
                                            userInfo:@{NSLocalizedDescriptionKey: @"Повреждён заголовок PalmDOC"}];
        return nil;
    }
    uint16_t compression = ORMobiU16(bytes, recursiveOffset);
    uint32_t textLength = ORMobiU32(bytes, recursiveOffset + 4);
    uint16_t textRecordCount = ORMobiU16(bytes, recursiveOffset + 8);
    uint16_t encryption = ORMobiU16(bytes, recursiveOffset + 12);

    if (encryption != 0) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.MOBI" code:5
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"Файл защищён DRM. OmniReader не обходит защиту — удалите DRM легальным способом."}];
        return nil;
    }
    if (compression == 17480) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.MOBI" code:6
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"Сжатие HUFF/CDIC пока не поддерживается. Конвертируйте книгу в EPUB (Calibre)."}];
        return nil;
    }
    if (compression != 1 && compression != 2) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.MOBI" code:7
                                            userInfo:@{NSLocalizedDescriptionKey: @"Неизвестный метод сжатия MOBI"}];
        return nil;
    }

    NSString *title = @"";
    NSString *author = @"";
    uint32_t textEncoding = 65001;
    NSUInteger mobiStart = recursiveOffset + 16;
    if (mobiStart + 16 <= length &&
        bytes[mobiStart] == 'M' && bytes[mobiStart + 1] == 'O' &&
        bytes[mobiStart + 2] == 'B' && bytes[mobiStart + 3] == 'I') {
        uint32_t headerLength = ORMobiU32(bytes, mobiStart + 4);
        textEncoding = ORMobiU32(bytes, mobiStart + 12);
        uint32_t exthFlags = ORMobiU32(bytes, mobiStart + 0x70);

        uint32_t fullNameOffset = 0;
        uint32_t fullNameLength = 0;
        if (headerLength >= 0x4C && mobiStart + 0x48 + 4 <= length) {
            fullNameOffset = ORMobiU32(bytes, mobiStart + 0x44);
            fullNameLength = ORMobiU32(bytes, mobiStart + 0x48);
        }
        if (fullNameLength > 0 && fullNameOffset > 0 && recursiveOffset + fullNameOffset + fullNameLength <= length) {
            NSData *nameData = [data subdataWithRange:NSMakeRange(recursiveOffset + fullNameOffset, fullNameLength)];
            NSString *decoded = [self decodeData:nameData encoding:textEncoding];
            if (decoded.length > 0) title = decoded;
        }
        if (exthFlags & 0x40) {
            NSMutableDictionary<NSNumber *, NSString *> *exth = [NSMutableDictionary dictionary];
            [self parseEXTH:data headerStart:mobiStart + headerLength into:exth encoding:textEncoding];
            if (exth[@100].length > 0) author = exth[@100];
            if (exth[@503].length > 0) title = exth[@503];
        }
    }
    if (title.length == 0) {
        NSUInteger nameLength = 0;
        while (nameLength < 32 && bytes[nameLength] != 0) nameLength++;
        if (nameLength > 0) {
            NSString *pdbName = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, nameLength)]
                                                      encoding:NSUTF8StringEncoding];
            if (!pdbName) pdbName = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, nameLength)]
                                                          encoding:NSWindowsCP1251StringEncoding];
            if (pdbName.length > 0) title = pdbName;
        }
    }

    // Text records start at index 1.
    NSMutableData *textData = [NSMutableData dataWithCapacity:MAX(textLength, (uint32_t)4096)];
    NSUInteger available = offsets.count - 1;
    NSUInteger lastRecord = MIN((NSUInteger)textRecordCount + 1, available);
    for (NSUInteger record = 1; record < lastRecord; record++) {
        NSUInteger start = offsets[record].unsignedIntegerValue;
        NSUInteger end = offsets[record + 1].unsignedIntegerValue;
        if (start >= end || end > length) continue;
        NSData *chunk = [data subdataWithRange:NSMakeRange(start, end - start)];
        if (compression == 2) chunk = ORPalmDocDecompress(chunk);
        [textData appendData:chunk];
    }
    if (textData.length > textLength && textLength > 0) {
        textData = [[textData subdataWithRange:NSMakeRange(0, textLength)] mutableCopy];
    }
    NSString *rawText = [self decodeData:textData encoding:textEncoding];

    ORMOBI *book = [[ORMOBI alloc] init];
    book.title = title.length > 0 ? title : path.lastPathComponent.stringByDeletingPathExtension;
    book.author = author;
    book.plainText = [ORText stripHTML:rawText];
    book.htmlBody = [self sanitiseMobiHTML:rawText];
    book.extraCSS = [self extraCSS];
    book.toc = [self tocFromHTML:book.htmlBody];
    NSString *rootDir = [[ORPaths extractedDirectory] stringByAppendingPathComponent:
                             [cacheKey stringByReplacingOccurrencesOfString:@"/" withString:@"_"]];
    [[NSFileManager defaultManager] createDirectoryAtPath:rootDir withIntermediateDirectories:YES attributes:nil error:NULL];
    book.rootDirectory = rootDir;
    return book;
}

+ (NSString *)decodeData:(NSData *)data encoding:(uint32_t)encoding {
    NSStringEncoding nsEncoding = NSUTF8StringEncoding;
    if (encoding == 1252) nsEncoding = NSWindowsCP1252StringEncoding;
    else if (encoding == 1251) nsEncoding = NSWindowsCP1251StringEncoding;
    else if (encoding == 65001 || encoding == 0) nsEncoding = NSUTF8StringEncoding;
    NSString *text = [[NSString alloc] initWithData:data encoding:nsEncoding];
    if (!text) text = [ORText stringFromData:data];
    return text ?: @"";
}

+ (void)parseEXTH:(NSData *)data
      headerStart:(NSUInteger)start
             into:(NSMutableDictionary<NSNumber *, NSString *> *)result
         encoding:(uint32_t)encoding {
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSUInteger search = start;
    NSUInteger limit = MIN(length, start + 16);
    BOOL found = NO;
    while (search + 4 <= limit) {
        if (bytes[search] == 'E' && bytes[search + 1] == 'X' && bytes[search + 2] == 'T' && bytes[search + 3] == 'H') {
            found = YES;
            break;
        }
        search++;
    }
    if (!found || search + 12 > length) return;
    uint32_t recordCount = ORMobiU32(bytes, search + 8);
    NSUInteger cursor = search + 12;
    for (uint32_t i = 0; i < recordCount; i++) {
        if (cursor + 8 > length) break;
        uint32_t type = ORMobiU32(bytes, cursor);
        uint32_t size = ORMobiU32(bytes, cursor + 4);
        if (size < 8 || cursor + size > length) break;
        NSData *valueData = [data subdataWithRange:NSMakeRange(cursor + 8, size - 8)];
        NSString *value = [self decodeData:valueData encoding:encoding];
        if (value.length > 0 && !result[@(type)]) result[@(type)] = value;
        cursor += size;
    }
}

+ (NSString *)sanitiseMobiHTML:(NSString *)raw {
    if (raw.length == 0) return @"";
    NSString *text = raw;
    text = [ORText replacePattern:@"(?is)<script\\b[^>]*>.*?</script>" inString:text withTemplate:@""];
    text = [ORText replacePattern:@"(?is)<style\\b[^>]*>.*?</style>" inString:text withTemplate:@""];
    text = [ORText replacePattern:@"(?i)<mbp:pagebreak[^>]*>" inString:text withTemplate:@"<hr class=\"mobi-pagebreak\"/>"];
    text = [ORText replacePattern:@"(?i)<(/?)(mbp:[a-z0-9]+)[^>]*>" inString:text withTemplate:@""];
    text = [ORText replacePattern:@"(?i)<img\\b[^>]*>" inString:text withTemplate:@""];
    text = [ORText replacePattern:@"(?i)\\sfilepos\\s*=\\s*\"[^\"]*\"" inString:text withTemplate:@""];
    text = [ORText replacePattern:@"(?i)\\srecindex\\s*=\\s*\"[^\"]*\"" inString:text withTemplate:@""];
    NSString *body = [ORText firstMatchPattern:@"(?is)<body\\b[^>]*>(.*?)</body>" inString:text group:1];
    if (body.length > 0) text = body;
    return [NSString stringWithFormat:@"<section id=\"ch-0\" data-chapter=\"0\" class=\"mobi\">%@</section>", text];
}

+ (NSArray<ORTOCItem *> *)tocFromHTML:(NSString *)html {
    // MOBI files rarely expose a machine readable TOC; keep a stable start entry.
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[ORTOCItem itemWithTitle:@"Начало" level:0 anchor:@"ch-0"]];
    return items;
}

+ (NSString *)extraCSS {
    return @".mobi{text-align:left;}"
           "hr.mobi-pagebreak{border:none;border-top:1px solid rgba(128,128,128,.35);margin:1.2em 0;}";
}

@end
