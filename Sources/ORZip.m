#import "ORZip.h"
#import <zlib.h>

NSString *const ORZipErrorDomain = @"OmniReader.ZipErrorDomain";

typedef NS_ENUM(NSInteger, ORZipErrorCode) {
    ORZipErrorNotZip = 1,
    ORZipErrorZip64 = 2,
    ORZipErrorCorrupted = 3,
    ORZipErrorEncrypted = 4,
    ORZipErrorUnsupportedCompression = 5,
    ORZipErrorInflate = 6
};

@interface ORZipEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) uint16_t flags;
@property (nonatomic) uint16_t method;
@property (nonatomic) uint32_t compressedSize;
@property (nonatomic) uint32_t uncompressedSize;
@property (nonatomic) uint32_t localOffset;
@end

@implementation ORZipEntry
@end

@interface ORZip ()
@property (nonatomic, strong) NSData *archiveData;
@property (nonatomic, strong) NSDictionary<NSString *, ORZipEntry *> *entryMap;
@property (nonatomic, strong) NSArray<NSString *> *entryNames;
@end

static uint16_t ORRead16(const uint8_t *bytes, NSUInteger offset) {
    return (uint16_t)((uint16_t)bytes[offset] | ((uint16_t)bytes[offset + 1] << 8));
}

static uint32_t ORRead32(const uint8_t *bytes, NSUInteger offset) {
    return ((uint32_t)bytes[offset]) |
           ((uint32_t)bytes[offset + 1] << 8) |
           ((uint32_t)bytes[offset + 2] << 16) |
           ((uint32_t)bytes[offset + 3] << 24);
}

static NSError *ORZipError(ORZipErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ORZipErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Zip error"}];
}

static NSString *ORZipDecodeName(const uint8_t *bytes, NSUInteger offset, NSUInteger length, BOOL utf8) {
    if (length == 0) return @"";
    NSData *data = [NSData dataWithBytes:bytes + offset length:length];
    if (utf8) {
        NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (string) return string;
    }
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (string) return string;
    string = [[NSString alloc] initWithData:data encoding:NSWindowsCP1251StringEncoding];
    if (string) return string;
    string = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    return string ?: @"";
}

static NSData *ORInflateData(NSData *input, NSUInteger expectedSize) {
    if (input.length == 0) return [NSData data];
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    int status = inflateInit2(&stream, -MAX_WBITS);
    if (status != Z_OK) return nil;

    NSMutableData *output = [NSMutableData dataWithCapacity:MAX(expectedSize, (NSUInteger)4096)];
    uint8_t *buffer = malloc(64 * 1024);
    if (!buffer) {
        inflateEnd(&stream);
        return nil;
    }
    stream.next_in = (Bytef *)input.bytes;
    stream.avail_in = (uInt)input.length;

    while (1) {
        stream.next_out = buffer;
        stream.avail_out = 64 * 1024;
        status = inflate(&stream, Z_NO_FLUSH);
        NSUInteger produced = 64 * 1024 - stream.avail_out;
        if (produced > 0) [output appendBytes:buffer length:produced];
        if (output.length > 600ULL * 1024ULL * 1024ULL) {
            free(buffer);
            inflateEnd(&stream);
            return nil;
        }
        if (status == Z_STREAM_END) break;
        if (status != Z_OK && status != Z_BUF_ERROR) break;
        if (produced == 0 && stream.avail_in == 0) break;
        if (status == Z_BUF_ERROR && produced == 0) break;
    }
    free(buffer);
    inflateEnd(&stream);
    if (status != Z_STREAM_END && status != Z_OK) return nil;
    return output;
}

@implementation ORZip

+ (instancetype)zipWithURL:(NSURL *)url error:(NSError **)error {
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&readError];
    if (!data) {
        if (error) *error = readError;
        return nil;
    }
    return [[ORZip alloc] initWithData:data error:error];
}

- (instancetype)initWithData:(NSData *)data error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    _archiveData = data;

    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    if (length < 22) {
        if (error) *error = ORZipError(ORZipErrorNotZip, @"Файл слишком мал для ZIP");
        return nil;
    }

    NSInteger eocd = -1;
    NSUInteger back = MIN(length, (NSUInteger)65557);
    NSInteger lowerBound = (NSInteger)length - (NSInteger)back;
    for (NSInteger i = (NSInteger)length - 22; i >= lowerBound; i--) {
        if (bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06) {
            eocd = i;
            break;
        }
    }
    if (eocd < 0) {
        if (error) *error = ORZipError(ORZipErrorNotZip, @"Не найден каталог ZIP");
        return nil;
    }

    uint16_t entryCount = ORRead16(bytes, (NSUInteger)eocd + 10);
    uint32_t directoryOffset = ORRead32(bytes, (NSUInteger)eocd + 16);
    if (entryCount == 0xFFFF || directoryOffset == 0xFFFFFFFF) {
        if (error) *error = ORZipError(ORZipErrorZip64, @"ZIP64 не поддерживается");
        return nil;
    }

    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    NSUInteger cursor = directoryOffset;
    for (uint16_t i = 0; i < entryCount; i++) {
        if (cursor + 46 > length) break;
        if (bytes[cursor] != 0x50 || bytes[cursor + 1] != 0x4B ||
            bytes[cursor + 2] != 0x01 || bytes[cursor + 3] != 0x02) break;

        uint16_t flags = ORRead16(bytes, cursor + 8);
        uint16_t method = ORRead16(bytes, cursor + 10);
        uint32_t compressed = ORRead32(bytes, cursor + 20);
        uint32_t uncompressed = ORRead32(bytes, cursor + 24);
        uint16_t nameLength = ORRead16(bytes, cursor + 28);
        uint16_t extraLength = ORRead16(bytes, cursor + 30);
        uint16_t commentLength = ORRead16(bytes, cursor + 32);
        uint32_t localOffset = ORRead32(bytes, cursor + 42);

        if (compressed == 0xFFFFFFFF || uncompressed == 0xFFFFFFFF || localOffset == 0xFFFFFFFF) {
            if (error) *error = ORZipError(ORZipErrorZip64, @"ZIP64 не поддерживается");
            return nil;
        }
        if (cursor + 46 + nameLength > length) break;

        NSString *name = ORZipDecodeName(bytes, cursor + 46, nameLength, (flags & 0x800) != 0);
        if (name.length > 0) {
            ORZipEntry *entry = [[ORZipEntry alloc] init];
            entry.name = name;
            entry.flags = flags;
            entry.method = method;
            entry.compressedSize = compressed;
            entry.uncompressedSize = uncompressed;
            entry.localOffset = localOffset;
            map[name] = entry;
        }
        cursor += 46 + nameLength + extraLength + commentLength;
    }

    _entryMap = map;
    _entryNames = [map.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    return self;
}

- (NSArray<NSString *> *)names {
    return self.entryNames;
}

- (BOOL)containsEntry:(NSString *)name {
    return self.entryMap[name] != nil;
}

- (ORZipEntry *)entryNamed:(NSString *)name {
    ORZipEntry *entry = self.entryMap[name];
    if (entry) return entry;
    for (NSString *key in self.entryMap) {
        if ([key caseInsensitiveCompare:name] == NSOrderedSame) return self.entryMap[key];
    }
    return nil;
}

- (NSData *)dataForEntry:(NSString *)name error:(NSError **)error {
    ORZipEntry *entry = [self entryNamed:name];
    if (!entry) {
        if (error) *error = ORZipError(ORZipErrorCorrupted, [NSString stringWithFormat:@"Нет файла %@", name]);
        return nil;
    }
    return [self dataForEntryObject:entry error:error];
}

- (NSData *)dataForEntryObject:(ORZipEntry *)entry error:(NSError **)error {
    if (entry.flags & 0x1) {
        if (error) *error = ORZipError(ORZipErrorEncrypted, @"Зашифрованный ZIP не поддерживается");
        return nil;
    }
    // Some writers (and busybox zip) append a data descriptor, which leaves the
    // sizes in the local header zeroed. The central directory stays authoritative,
    // so the local header is only used to locate the payload.
    const uint8_t *bytes = self.archiveData.bytes;
    NSUInteger length = self.archiveData.length;
    NSUInteger offset = entry.localOffset;
    if (offset + 30 > length) {
        if (error) *error = ORZipError(ORZipErrorCorrupted, @"Повреждённая запись ZIP");
        return nil;
    }
    if (bytes[offset] != 0x50 || bytes[offset + 1] != 0x4B ||
        bytes[offset + 2] != 0x03 || bytes[offset + 3] != 0x04) {
        if (error) *error = ORZipError(ORZipErrorCorrupted, @"Повреждённый локальный заголовок ZIP");
        return nil;
    }
    uint16_t nameLength = ORRead16(bytes, offset + 26);
    uint16_t extraLength = ORRead16(bytes, offset + 28);
    NSUInteger start = offset + 30 + nameLength + extraLength;
    NSUInteger end = start + entry.compressedSize;
    if (end > length) {
        if (error) *error = ORZipError(ORZipErrorCorrupted, @"Данные ZIP выходят за границы файла");
        return nil;
    }
    NSData *payload = [self.archiveData subdataWithRange:NSMakeRange(start, entry.compressedSize)];
    if (entry.method == 0) return payload;
    if (entry.method == 8) {
        NSData *inflated = ORInflateData(payload, entry.uncompressedSize);
        if (!inflated) {
            if (error) *error = ORZipError(ORZipErrorInflate, @"Не удалось распаковать данные");
        }
        return inflated;
    }
    if (error) *error = ORZipError(ORZipErrorUnsupportedCompression,
                                   [NSString stringWithFormat:@"Метод сжатия %d не поддерживается", entry.method]);
    return nil;
}

static BOOL ORZipSafePath(NSString *name, NSString *destination) {
    NSString *normalized = [name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    if (normalized.length == 0) return NO;
    if ([normalized hasPrefix:@"/"]) return NO;
    NSArray<NSString *> *parts = [normalized componentsSeparatedByString:@"/"];
    for (NSString *part in parts) {
        if ([part isEqualToString:@".."]) return NO;
    }
    NSString *full = [destination stringByAppendingPathComponent:normalized];
    NSString *standardizedDestination = [destination stringByStandardizingPath];
    NSString *standardizedFull = [full stringByStandardizingPath];
    return [standardizedFull hasPrefix:standardizedDestination];
}

- (BOOL)extractToDirectory:(NSString *)directory error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *createError = nil;
    [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&createError];
    if (createError) {
        if (error) *error = createError;
        return NO;
    }
    for (NSString *name in self.entryNames) {
        if ([name hasPrefix:@"__MACOSX"] || [name.lastPathComponent isEqualToString:@".DS_Store"]) continue;
        if (!ORZipSafePath(name, directory)) continue;
        NSString *target = [directory stringByAppendingPathComponent:name];
        if ([name hasSuffix:@"/"]) {
            [fm createDirectoryAtPath:target withIntermediateDirectories:YES attributes:nil error:NULL];
            continue;
        }
        NSString *parent = [target stringByDeletingLastPathComponent];
        [fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:NULL];
        NSError *entryError = nil;
        NSData *data = [self dataForEntry:name error:&entryError];
        if (!data) {
            if (entryError) NSLog(@"[OmniReader] zip entry failed: %@ (%@)", name, entryError.localizedDescription);
            continue;
        }
        [data writeToFile:target atomically:YES];
    }
    return YES;
}

@end
