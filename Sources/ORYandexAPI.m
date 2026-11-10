#import "ORYandexAPI.h"
#import "ORCore.h"
#import "ORHTTP.h"
#import "ORText.h"

@interface ORYandexAPI ()
+ (void)fetchLoginProfile:(ORYandexProfileCompletion)completion;
+ (void)performGET:(NSString *)path completion:(void (^)(id _Nullable json, NSError *_Nullable error))completion;
+ (NSDictionary *)dictionaryFromJSON:(id)json;
+ (NSString *)firstStringIn:(NSDictionary *)dictionary keys:(NSArray<NSString *> *)keys;
+ (NSURL *)URLWithPath:(NSString *)path;
+ (void)fetchProfileLegacy:(ORYandexProfileCompletion)completion;
+ (void)fetchShelfLegacy:(ORYandexShelfCompletion)completion;
+ (void)graphql:(NSString *)query
      variables:(nullable NSDictionary *)variables
     completion:(void (^)(id _Nullable data, NSError *_Nullable error))completion;
+ (BOOL)isUnknownSchemaError:(NSString *)message code:(nullable NSString *)code;
+ (NSArray<NSDictionary *> *)itemsFromGraphQLData:(id)data;
+ (NSString *)stringValue:(id)value keys:(NSArray<NSString *> *)keys;
+ (void)performGraphQLForDebug:(NSString *)query
                    completion:(void (^)(NSString *_Nullable info, NSError *_Nullable error))completion;
@end

@implementation ORYandexAPI

#pragma mark - Endpoints

// Yandex Books web endpoints. They are not part of a documented public API and
// may change at any time; see Docs/YANDEX.md.
+ (NSString *)baseURL { return @"https://books.yandex.ru"; }
+ (NSString *)graphqlPath { return @"/node-api/bff-graphql-api/"; }
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


#pragma mark - GraphQL

/// POSTs a GraphQL document. Returns the `data` object or an NSError carrying
/// the server message (GRAPHQL_VALIDATION_FAILED = query no longer matches).
+ (void)graphql:(NSString *)query
      variables:(NSDictionary *)variables
     completion:(void (^)(id _Nullable data, NSError *_Nullable error))completion {
    if (!completion) return;
    NSString *token = [ORSettings shared].yandexToken;
    if (token.length == 0) {
        completion(nil, [NSError errorWithDomain:@"OmniReader.Yandex" code:401
                                       userInfo:@{NSLocalizedDescriptionKey: @"Нужно войти в аккаунт Яндекса"}]);
        return;
    }
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"query"] = query;
    if (variables.count > 0) payload[@"variables"] = variables;
    NSError *encodeError = nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&encodeError];
    if (!body) { completion(nil, encodeError); return; }
    NSURL *url = [self URLWithPath:[self graphqlPath]];
    NSDictionary *headers = @{@"Authorization": [NSString stringWithFormat:@"OAuth %@", token],
                              @"Content-Type": @"application/json",
                              @"Accept": @"application/json",
                              };
    [ORHTTP POST:url.absoluteString body:body headers:headers completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        id json = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (![json isKindOfClass:[NSDictionary class]]) {
            NSString *preview = [[NSString alloc] initWithData:data ?: [NSData data]
                                                      encoding:NSUTF8StringEncoding] ?: @"";
            NSLog(@"[OmniReader] Yandex GraphQL non-JSON: %@", [preview substringToIndex:MIN(preview.length, (NSUInteger)300)]);
            completion(nil, error ?: [NSError errorWithDomain:@"OmniReader.Yandex" code:500
                                                    userInfo:@{NSLocalizedDescriptionKey: @"GraphQL вернул не JSON"}]);
            return;
        }
        NSArray *errors = json[@"errors"];
        if ([errors isKindOfClass:[NSArray class]] && errors.count > 0) {
            NSDictionary *first = [errors.firstObject isKindOfClass:[NSDictionary class]] ? errors.firstObject : @{};
            NSString *message = [self firstStringIn:first keys:@[@"message"]] ?: @"Ошибка GraphQL";
            NSString *code = first[@"extensions"][@"code"];
            NSLog(@"[OmniReader] Yandex GraphQL error: %@ (%@)", message, code);
            NSInteger codeValue = [self isUnknownSchemaError:message code:code] ? 422 : 400;
            completion(nil, [NSError errorWithDomain:@"OmniReader.Yandex" code:codeValue
                                           userInfo:@{NSLocalizedDescriptionKey: message}]);
            return;
        }
        completion(json[@"data"], nil);
    }];
}

+ (BOOL)isUnknownSchemaError:(NSString *)message code:(NSString *)code {
    if ([code isEqualToString:@"GRAPHQL_VALIDATION_FAILED"]) return YES;
    if ([code isEqualToString:@"BAD_USER_INPUT"]) return YES;
    NSString *lower = message.lowercaseString ?: @"";
    return [lower containsString:@"cannot query field"] ||
           [lower containsString:@"not found"] ||
           [lower containsString:@"whitelist"];
}

+ (void)performGraphQLForDebug:(NSString *)query
                    completion:(void (^)(NSString *, NSError *))completion {
    [self graphql:query variables:nil completion:^(id data, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSData *json = [NSJSONSerialization dataWithJSONObject:data ?: @{} options:0 error:NULL];
        NSString *text = [[NSString alloc] initWithData:json ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"{}";
        if (text.length > 600) text = [[text substringToIndex:600] stringByAppendingString:@"…"];
        completion(text, nil);
    }];
}

#pragma mark - Profile


+ (void)fetchProfile:(ORYandexProfileCompletion)completion {
    NSString *query = @"query Viewer { me { id login displayName } }";
    [self graphql:query variables:nil completion:^(id data, NSError *error) {
        NSDictionary *viewer = [data isKindOfClass:[NSDictionary class]] ? data[@"me"] : nil;
        NSString *name = [self firstStringIn:viewer keys:@[@"displayName", @"login", @"id"]];
        if (name.length > 0) { completion(name, nil); return; }
        [self fetchProfileLegacy:completion];
    }];
}

+ (void)fetchProfileLegacy:(ORYandexProfileCompletion)completion {
    [self performGET:[self profilePath] completion:^(id json, NSError *error) {
        NSDictionary *dictionary = [self dictionaryFromJSON:json];
        NSString *name = [self firstStringIn:dictionary keys:@[@"display_name", @"displayName", @"name", @"login", @"email"]];
        if (name.length == 0 && !error) {
            NSDictionary *user = [dictionary[@"user"] isKindOfClass:[NSDictionary class]] ? dictionary[@"user"] : nil;
            name = [self firstStringIn:user keys:@[@"display_name", @"name", @"login", @"email"]];
        }
        if (name.length > 0) {
            completion(name, nil);
            return;
        }
        // Books API may be unofficial or unavailable; login.yandex.ru is stable
        // and works with the same OAuth token (login:info scope).
        [self fetchLoginProfile:completion];
    }];
}

+ (void)fetchLoginProfile:(ORYandexProfileCompletion)completion {
    NSString *token = [ORSettings shared].yandexToken;
    if (token.length == 0) {
        completion(nil, [NSError errorWithDomain:@"OmniReader.Yandex" code:401
                                       userInfo:@{NSLocalizedDescriptionKey: @"Токен не задан"}]);
        return;
    }
    NSDictionary *headers = @{@"Authorization": [NSString stringWithFormat:@"OAuth %@", token],
                              @"Accept": @"application/json"};
    [ORHTTP GET:@"https://login.yandex.ru/info?format=json"
        headers:headers
     completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error || data.length == 0) {
            completion(nil, error ?: [NSError errorWithDomain:@"OmniReader.Yandex" code:401
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Яндекс не подтвердил токен"}]);
            return;
        }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSDictionary *dictionary = [json isKindOfClass:[NSDictionary class]] ? json : @{};
        NSString *name = [self firstStringIn:dictionary keys:@[@"display_name", @"real_name", @"login"]];
        completion(name, nil);
    }];
}

#pragma mark - Shelf

+ (void)fetchShelf:(ORYandexShelfCompletion)completion {
    if (!completion) return;
    NSString *query =
        @"query Library($first: Int) { me { id login displayName "
         "library(first: $first) { items { __typename "
         "... on UserLibraryBook { id title author { name } cover { url } "
         "book { id title author { name } cover { url } } } } } } }";
    [self graphql:query variables:@{@"first": @40} completion:^(id data, NSError *error) {
        NSArray *items = [self itemsFromGraphQLData:data];
        if (items.count > 0) { completion(items, nil); return; }
        if (error.code == 401 || error.code == 403) { completion(nil, error); return; }
        NSLog(@"[OmniReader] Yandex GraphQL library unusable: %@", error.localizedDescription ?: @"empty");
        [self fetchShelfLegacy:completion];
    }];
}

+ (void)fetchShelfLegacy:(ORYandexShelfCompletion)completion {
    [self performGET:[self shelfPath] completion:^(id json, NSError *error) {
        if (!error) { completion([self itemsFromJSON:json], nil); return; }
        [self performGET:@"/api/library" completion:^(id fallbackJSON, NSError *fallbackError) {
            if (!fallbackError) { completion([self itemsFromJSON:fallbackJSON], nil); return; }
            completion(nil, [NSError errorWithDomain:@"OmniReader.Yandex" code:404
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                          @"Яндекс Книги не отдают полку по известным адресам (404): сайт работает через GraphQL, схема изменилась. См. Docs/YANDEX.md; купленные файлы можно добавить через «+» → «Импортировать файл»."}]);
        }];
    }];
}

+ (NSArray<NSDictionary *> *)itemsFromGraphQLData:(id)data {
    NSMutableArray *result = [NSMutableArray array];
    if (![data isKindOfClass:[NSDictionary class]]) return result;
    NSDictionary *me = data[@"me"];
    NSDictionary *library = [me isKindOfClass:[NSDictionary class]] ? me[@"library"] : nil;
    NSArray *items = [library isKindOfClass:[NSDictionary class]] ? library[@"items"] : nil;
    if (![items isKindOfClass:[NSArray class]]) return result;
    for (id raw in items) {
        if (![raw isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *node = [raw[@"book"] isKindOfClass:[NSDictionary class]] ? raw[@"book"] : raw;
        NSMutableDictionary *normalised = [NSMutableDictionary dictionaryWithDictionary:[self normaliseBookDictionary:node]];
        NSString *title = normalised[@"title"];
        if (![title isKindOfClass:[NSString class]] || title.length == 0) continue;
        if (normalised[@"id"] == nil && raw[@"id"]) normalised[@"id"] = raw[@"id"];
        [result addObject:normalised];
    }
    return result;
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

/// GraphQL wraps authors and covers: { author: { name } }, { cover: { url } }.
+ (NSString *)stringValue:(id)value keys:(NSArray<NSString *> *)keys {
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (id entry in value) {
            NSString *name = [self stringValue:entry keys:keys];
            if (name.length > 0) [parts addObject:name];
        }
        return [parts componentsJoinedByString:@", "];
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        return [self firstStringIn:value keys:keys] ?: @"";
    }
    return @"";
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

    NSString *author = [self firstStringIn:raw keys:@[@"author_name"]];
    if (author.length == 0) author = [self stringValue:raw[@"author"] keys:@[@"name", @"title"]];
    if (author.length == 0) author = [self stringValue:raw[@"authors"] keys:@[@"name", @"title"]];
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

    NSString *cover = [self stringValue:raw[@"cover"] keys:@[@"url", @"medium", @"large", @"original"]];
    if (cover.length == 0) cover = [self stringValue:raw[@"image"] keys:@[@"url", @"medium", @"large"]];
    if (cover.length == 0) cover = [self firstStringIn:raw keys:@[@"cover_url", @"coverUrl", @"thumbnail"]];
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
