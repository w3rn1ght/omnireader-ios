#import "ORYandexAPI.h"
#import "ORCore.h"
#import "ORHTTP.h"
#import "ORText.h"

@implementation ORYandexAPI

#pragma mark - Endpoints

// Yandex Books web endpoints. They are not part of a documented public API and
// may change at any time; see Docs/YANDEX.md.
+ (NSString *)baseURL { return @"https://books.yandex.ru"; }
+ (NSString *)profilePath { return @"/api/v1/me"; }
+ (NSString *)shelfPath { return @"/api/v1/library"; }
+ (NSString *)itemPathFormat { return @"/api/v1/library/%@"; }

+ (NSDictionary *)authHeaders {
    NSString *token = [ORSettings shared].yandexToken;
    if (token.length == 0) return @{};
    return @{@"Authorization": [NSString stringWithFormat:@"OAuth %@", token],
             @"Accept": @"application/json"};
}

+ (NSURL *)URLWithPath:(NSString *)path {
    return [NSURL URLWithString:[self.baseURL stringByAppendingString:path]];
}

#pragma mark - Requests

+ (void)performGET:(NSString *)path completion:(void (^)(id _Nullable json, NSError *_Nullable error))completion {
    NSString *token = [ORSettings shared].yandexToken;
    if (token.length == 0) {
        completion(nil, [NSError errorWithDomain:@"OmniReader.Yandex" code:401
                                       userInfo:@{NSLocalizedDescriptionKey: @"Нужно войти в аккаунт Яндекса"}]);
        return;
    }
    NSURL *url = [self URLWithPath:path];
    if (!url) {
        completion(nil, [NSError errorWithDomain:@"OmniReader.Yandex" code:400
                                       userInfo:@{NSLocalizedDescriptionKey: @"Некорректный адрес API"}]);
        return;
    }
    [ORHTTP GET:url.absoluteString headers:[self authHeaders] completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        if (data.length == 0) {
            completion(@{}, nil);
            return;
        }
        NSError *jsonError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (!json) {
            // Log the payload: it helps adapting the decoder to a changed schema.
            NSString *preview = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, MIN(data.length, (NSUInteger)800))]
                                                      encoding:NSUTF8StringEncoding];
            NSLog(@"[OmniReader] Yandex non-JSON response: %@", preview);
            completion(nil, jsonError ?: [NSError errorWithDomain:@"OmniReader.Yandex" code:500
                                                        userInfo:@{NSLocalizedDescriptionKey: @"Сервис вернул не JSON"}]);
            return;
        }
        completion(json, nil);
    }];
}

#pragma mark - Profile

+ (void)fetchProfile:(ORYandexProfileCompletion)completion {
    [self performGET:[self profilePath] completion:^(id json, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        NSDictionary *dictionary = [self dictionaryFromJSON:json];
        NSString *name = [self firstStringIn:dictionary keys:@[@"display_name", @"displayName", @"name", @"login", @"email"]];
        if (name.length == 0) {
            NSDictionary *user = [dictionary[@"user"] isKindOfClass:[NSDictionary class]] ? dictionary[@"user"] : nil;
            name = [self firstStringIn:user keys:@[@"display_name", @"name", @"login", @"email"]];
        }
        completion(name, nil);
    }];
}

#pragma mark - Shelf

+ (void)fetchShelf:(ORYandexShelfCompletion)completion {
    [self performGET:[self shelfPath] completion:^(id json, NSError *error) {
        if (error) {
            // Try a couple of alternative shapes before giving up.
            [self performGET:@"/api/library" completion:^(id fallbackJSON, NSError *fallbackError) {
                if (fallbackError) {
                    completion(nil, error);
                    return;
                }
                completion([self itemsFromJSON:fallbackJSON], nil);
            }];
            return;
        }
        completion([self itemsFromJSON:json], nil);
    }];
}

+ (NSArray<NSDictionary *> *)itemsFromJSON:(id)json {
    NSArray *rawItems = nil;
    if ([json isKindOfClass:[NSArray class]]) {
        rawItems = json;
    } else if ([json isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = json;
        NSArray<NSString *> *candidateKeys = @[@"items", @"books", @"library", @"data", @"results"];
        for (NSString *key in candidateKeys) {
            if ([dictionary[key] isKindOfClass:[NSArray class]]) {
                rawItems = dictionary[key];
                break;
            }
        }
        if (!rawItems) {
            for (NSString *key in candidateKeys) {
                NSDictionary *nested = dictionary[key];
                if ([nested isKindOfClass:[NSDictionary class]]) {
                    for (NSString *inner in candidateKeys) {
                        if ([nested[inner] isKindOfClass:[NSArray class]]) {
                            rawItems = nested[inner];
                            break;
                        }
                    }
                }
                if (rawItems) break;
            }
        }
    }
    NSMutableArray *result = [NSMutableArray array];
    for (id item in rawItems ?: @[]) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *normalised = [self normaliseBookDictionary:item];
        if (normalised[@"title"]) [result addObject:normalised];
    }
    return result;
}

+ (NSDictionary *)normaliseBookDictionary:(NSDictionary *)raw {
    NSMutableDictionary *book = [NSMutableDictionary dictionary];

    NSString *identifier = [self firstStringIn:raw keys:@[@"id", @"book_id", @"bookId", @"uuid", @"document_id"]];
    if (identifier) book[@"id"] = identifier;

    NSString *title = [self firstStringIn:raw keys:@[@"title", @"name", @"book_title", @"caption"]];
    if (title.length == 0) {
        NSDictionary *meta = [raw[@"metadata"] isKindOfClass:[NSDictionary class]] ? raw[@"metadata"] : nil;
        title = [self firstStringIn:meta keys:@[@"title", @"name"]];
    }
    if (title.length > 0) book[@"title"] = title;

    NSString *author = [self firstStringIn:raw keys:@[@"author", @"authors", @"author_name"]];
    if (author.length == 0) {
        NSArray *authors = raw[@"authors"];
        if ([authors isKindOfClass:[NSArray class]]) {
            NSMutableArray *names = [NSMutableArray array];
            for (id entry in authors) {
                if ([entry isKindOfClass:[NSString class]]) [names addObject:entry];
                else if ([entry isKindOfClass:[NSDictionary class]]) {
                    NSString *name = [self firstStringIn:entry keys:@[@"name", @"display_name", @"title"]];
                    if (name.length > 0) [names addObject:name];
                }
            }
            author = [names componentsJoinedByString:@", "];
        }
    }
    if (author.length > 0) book[@"author"] = author;

    NSString *cover = [self firstStringIn:raw keys:@[@"cover", @"cover_url", @"coverUrl", @"image", @"thumbnail"]];
    if (cover.length == 0) {
        NSDictionary *images = [raw[@"images"] isKindOfClass:[NSDictionary class]] ? raw[@"images"] : nil;
        cover = [self firstStringIn:images keys:@[@"large", @"medium", @"small", @"original"]];
    }
    if ([cover hasPrefix:@"//"]) cover = [@"https:" stringByAppendingString:cover];
    if (cover.length > 0) book[@"cover"] = cover;

    NSString *format = [self firstStringIn:raw keys:@[@"format", @"file_format", @"type"]];
    if (format.length == 0) {
        NSArray *formats = raw[@"formats"];
        if ([formats isKindOfClass:[NSArray class]] && formats.count > 0) {
            id first = formats.firstObject;
            if ([first isKindOfClass:[NSString class]]) format = first;
            else if ([first isKindOfClass:[NSDictionary class]]) format = [self firstStringIn:first keys:@[@"format", @"type", @"name"]];
        }
    }
    if (format.length > 0) book[@"format"] = format.lowercaseString;

    NSString *download = [self firstStringIn:raw keys:@[@"download_url", @"downloadUrl", @"file_url", @"fileUrl", @"url", @"link"]];
    if ([download hasPrefix:@"//"]) download = [@"https:" stringByAppendingString:download];
    if (download.length > 0) book[@"downloadURL"] = download;

    NSString *audio = [self firstStringIn:raw keys:@[@"audio_url", @"audioUrl", @"audiobook_url", @"stream_url", @"streamUrl"]];
    if ([audio hasPrefix:@"//"]) audio = [@"https:" stringByAppendingString:audio];
    if (audio.length > 0) book[@"audioURL"] = audio;

    BOOL isAudio = [raw[@"is_audio"] boolValue] || [raw[@"audiobook"] boolValue] ||
                   [raw[@"type"] isEqual:@"audio"] || audio.length > 0;
    book[@"isAudio"] = @(isAudio);

    NSString *progressValue = [self firstStringIn:raw keys:@[@"progress", @"reading_progress", @"percent"]];
    if (progressValue.length > 0) {
        double value = progressValue.doubleValue;
        if (value > 1.0) value /= 100.0;
        book[@"progress"] = @(MAX(0.0, MIN(1.0, value)));
    }
    return book;
}

#pragma mark - Download

+ (void)resolveDownloadForItem:(NSDictionary *)item
                    completion:(void (^)(NSURL *, NSString *, NSError *))completion {
    NSString *direct = item[@"audioURL"] ?: item[@"downloadURL"];
    if (direct.length > 0) {
        NSURL *url = [NSURL URLWithString:direct];
        if (url) {
            NSString *format = [item[@"isAudio"] boolValue] ? @"audio" : (item[@"format"] ?: @"epub");
            completion(url, format, nil);
            return;
        }
    }
    NSString *identifier = item[@"id"];
    if (identifier.length == 0) {
        completion(nil, nil, [NSError errorWithDomain:@"OmniReader.Yandex" code:404
                                            userInfo:@{NSLocalizedDescriptionKey: @"У книги нет идентификатора"}]);
        return;
    }
    NSString *path = [NSString stringWithFormat:[self itemPathFormat], [ORText queryEscape:identifier]];
    [self performGET:path completion:^(id json, NSError *error) {
        if (error) {
            completion(nil, nil, error);
            return;
        }
        NSDictionary *dictionary = [self dictionaryFromJSON:json];
        NSDictionary *normalised = [self normaliseBookDictionary:dictionary];
        NSString *urlString = normalised[@"downloadURL"] ?: normalised[@"audioURL"];
        if (!urlString) {
            NSDictionary *files = dictionary[@"files"];
            if ([files isKindOfClass:[NSDictionary class]]) {
                urlString = [self firstStringIn:files keys:@[@"epub", @"pdf", @"audio", @"url"]];
            }
        }
        NSURL *url = urlString ? [NSURL URLWithString:urlString] : nil;
        if (!url) {
            completion(nil, nil, [NSError errorWithDomain:@"OmniReader.Yandex" code:404
                                                userInfo:@{NSLocalizedDescriptionKey:
                                                               @"Ссылка на файл не найдена. Схема API могла измениться — см. Docs/YANDEX.md."}]);
            return;
        }
        completion(url, normalised[@"format"], nil);
    }];
}

#pragma mark - Helpers

+ (NSDictionary *)dictionaryFromJSON:(id)json {
    if (![json isKindOfClass:[NSDictionary class]]) return @{};
    NSDictionary *dictionary = json;
    for (NSString *key in @[@"data", @"result", @"book", @"item"]) {
        if ([dictionary[key] isKindOfClass:[NSDictionary class]]) return dictionary[key];
    }
    return dictionary;
}

+ (NSString *)firstStringIn:(NSDictionary *)dictionary keys:(NSArray<NSString *> *)keys {
    if (!dictionary) return nil;
    for (NSString *key in keys) {
        id value = dictionary[key];
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
        if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    }
    return nil;
}

@end
