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
+ (void)diagnoseToken:(void (^)(NSString *_Nullable report, NSError *_Nullable error))completion;
+ (NSString *)libraryPath;
+ (void)graphqlAtPath:(NSString *)path
        operationName:(nullable NSString *)operationName
                query:(NSString *)query
            variables:(nullable NSDictionary *)variables
           completion:(void (^)(id _Nullable data, NSError *_Nullable error))completion;
+ (NSString *)myBooksQuery;
+ (void)fetchViewerProfile:(void (^)(NSDictionary *_Nullable profile, NSError *_Nullable error))completion;
+ (void)fetchLibraryCardsForLogin:(NSString *)login
                            cursor:(NSString *)cursor
                       accumulated:(NSMutableArray *)accumulated
                             pages:(NSInteger)pages
                        completion:(void (^)(NSArray *_Nullable items, NSError *_Nullable error))completion;
+ (NSArray<NSDictionary *> *)itemsFromLibraryCards:(NSArray *)cards;
+ (NSArray<NSDictionary *> *)viewerCandidates;
+ (void)probeViewerWithCandidates:(NSArray<NSDictionary *> *)candidates
                            index:(NSUInteger)index
                            found:(void (^)(NSString *root, NSDictionary *object))found
                         finished:(void (^)(NSArray<NSString *> *tried))finished;
+ (void)fetchProfileWithoutCache:(ORYandexProfileCompletion)completion;
+ (nullable NSString *)cachedViewerRoot;
+ (void)setCachedViewerRoot:(nullable NSString *)root;
@end

@implementation ORYandexAPI

#pragma mark - Endpoints

// Yandex Books web endpoints. They are not part of a documented public API and
// may change at any time; see Docs/YANDEX.md.
+ (NSString *)baseURL { return @"https://books.yandex.ru"; }
+ (NSString *)graphqlPath { return @"/node-api/bff-graphql-api/"; }
// Private (whitelisted) operations: profile, my books, loyalty.
+ (NSString *)libraryPath { return @"/node-api/p-graphql/"; }
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
    [self graphqlAtPath:[self graphqlPath] operationName:nil query:query variables:variables completion:completion];
}

+ (void)graphqlAtPath:(NSString *)path
        operationName:(NSString *)operationName
                query:(NSString *)query
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
    NSURL *url = [self URLWithPath:path ?: [self graphqlPath]];
    NSMutableDictionary *headers = [@{@"Authorization": [NSString stringWithFormat:@"OAuth %@", token],
                                      @"Content-Type": @"application/json",
                                      @"Accept": @"application/json"} mutableCopy];
    if (operationName.length > 0) headers[@"x-apollo-operation-name"] = operationName;
    if ([path isEqualToString:[self libraryPath]]) {
        // p-graphql inspects these headers when resolving the private schema.
        headers[@"App-Language"] = @"ru";
        headers[@"accept-language"] = @"ru,en;q=0.9";
        headers[@"user-is-authorized"] = @"true";
        headers[@"allow-ppd-content"] = @"true";
    }
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


#pragma mark - Schema probe

/// Candidate root fields of the Books GraphQL Query type. Yandex does not
/// expose `me`; the site is served from a persisted whitelist, so the exact
/// root field has to be discovered by probing. The working shape is cached.
+ (NSArray<NSDictionary *> *)viewerCandidates {
    // Verified against the live schema (November 2026):
    //   userProfile -> ProfilePayload { login id name yuid email avatar }
    // There is no `me`, `viewer`, `user` or `profile` root on the BFF endpoint.
    return @[
        @{@"root": @"userProfile", @"name": @[@"login", @"id", @"name"]},
        @{@"root": @"userMeta", @"name": @[@"puid", @"country"]},
        @{@"root": @"notificationsStatus", @"name": @[@"has_unread_notifications"]},
        @{@"root": @"allEmotions", @"name": @[@"__typename"]},
        @{@"root": @"stories", @"name": @[@"__typename"]}
    ];
}

+ (NSString *)cachedViewerRoot {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"or.yandexViewerRoot"];
}

+ (void)setCachedViewerRoot:(NSString *)root {
    [[NSUserDefaults standardUserDefaults] setObject:root ?: @"" forKey:@"or.yandexViewerRoot"];
}

+ (void)probeViewerWithCandidates:(NSArray<NSDictionary *> *)candidates
                            index:(NSUInteger)index
                             found:(void (^)(NSString *root, NSDictionary *object))found
                          finished:(void (^)(NSArray<NSString *> *tried))finished {
    if (index >= candidates.count) {
        finished(@[]);
        return;
    }
    NSDictionary *candidate = candidates[index];
    NSString *root = candidate[@"root"];
    NSString *query = [NSString stringWithFormat:@"query Probe { %@ { __typename } }", root];
    [self graphql:query variables:nil completion:^(id data, NSError *error) {
        NSDictionary *object = [data isKindOfClass:[NSDictionary class]] ? data[root] : nil;
        if (!error && [object isKindOfClass:[NSDictionary class]]) {
            [self setCachedViewerRoot:root];
            NSLog(@"[OmniReader] Yandex GraphQL viewer root = %@", root);
            found(root, object);
            return;
        }
        NSLog(@"[OmniReader] Yandex GraphQL probe '%@' failed: %@", root, error.localizedDescription ?: @"empty");
        [self probeViewerWithCandidates:candidates index:index + 1 found:found finished:finished];
    }];
}

/// Returns a human readable report for the "Проверить токен" button.
+ (void)diagnoseToken:(void (^)(NSString *report, NSError *error))completion {
    if (!completion) return;
    NSMutableString *report = [NSMutableString string];
    [self fetchViewerProfile:^(NSDictionary *profile, NSError *profileError) {
        if (![profile isKindOfClass:[NSDictionary class]] || profile.count == 0) {
            [report appendFormat:@"Профиль Книг недоступен: %@\n", profileError.localizedDescription ?: @"пусто"];
            [report appendString:@"Перебираю остальные корни запроса…\n"];
            [self probeViewerWithCandidates:[self viewerCandidates]
                                      index:0
                                      found:^(NSString *root, NSDictionary *object) {
                [report appendFormat:@"Найден корень: %@\n%@\n", root, object];
                completion(report, nil);
            }
                                  finished:^(NSArray<NSString *> *unused) {
                [report appendString:@"Ни один корень не подошёл: схема снова изменилась.\n"];
                completion(report, nil);
            }];
            return;
        }
        NSString *login = [self firstStringIn:profile keys:@[@"login"]];
        NSString *name = [self firstStringIn:profile keys:@[@"name", @"login"]];
        [report appendFormat:@"Аккаунт: %@ (login: %@)\n", name.length > 0 ? name : @"—", login.length > 0 ? login : @"—"];
        if (login.length == 0) {
            [report appendString:@"Сервер не вернул login — полка недоступна.\n"];
            completion(report, nil);
            return;
        }
        [self fetchLibraryCardsForLogin:login
                                  cursor:@""
                             accumulated:[NSMutableArray array]
                                   pages:0
                              completion:^(NSArray *items, NSError *error) {
            if (items) [report appendFormat:@"Полка: %lu книг(и)\n", (unsigned long)items.count];
            if (error) [report appendFormat:@"Полка недоступна: %@\n", error.localizedDescription ?: @"неизвестная ошибка"];
            completion(report, nil);
        }];
    }];
}

#pragma mark - Profile


+ (void)fetchProfile:(ORYandexProfileCompletion)completion {
    [self fetchViewerProfile:^(NSDictionary *profile, NSError *error) {
        NSString *name = [self firstStringIn:profile keys:@[@"name", @"login"]];
        if (name.length > 0) {
            completion(name, nil);
            return;
        }
        [self fetchProfileLegacy:completion];
    }];
}

+ (void)fetchProfileWithoutCache:(ORYandexProfileCompletion)completion {
    NSArray<NSDictionary *> *candidates = [self viewerCandidates];
    [self probeViewerWithCandidates:candidates index:0 found:^(NSString *root, NSDictionary *object) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [self graphql:[NSString stringWithFormat:@"query Viewer { %@ { displayName login id } }", root]
                variables:nil
               completion:^(id data, NSError *error) {
                NSDictionary *viewer = [data isKindOfClass:[NSDictionary class]] ? data[root] : nil;
                NSString *name = [self firstStringIn:viewer keys:@[@"displayName", @"login", @"id"]];
                completion(name, nil);
            }];
        });
    } finished:^(NSArray<NSString *> *unused) {
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

+ (NSString *)myBooksQuery {
    // Exact document used by https://books.yandex.ru/my/books/all.
    // p-graphql validates structure, so keep fragments and field order.
    return            @"query MyBooksLibraryCards($login: String!, $cursor: String!, $limit: Int!, $sort: UserLibrarySortType!, $filters: UserLibraryFiltersInput!) {\n"
           @"  user(login: $login) {\n"
           @"    library {\n"
           @"      libraryCards(params: {cursor: $cursor, limit: $limit, sort: $sort, filters: $filters}) {\n"
           @"        cursor\n"
           @"        page {\n"
           @"          ...FMyBooksLibraryCard\n"
           @"        }\n"
           @"      }\n"
           @"    }\n"
           @"  }\n"
           @"}\n"
           @"\n"
           @"fragment FMyBooksCardCover on Cover {\n"
           @"  url\n"
           @"  ratio\n"
           @"  backgroundColorHex\n"
           @"}\n"
           @"\n"
           @"fragment FMyBooksCardPerson on Person {\n"
           @"  uuid\n"
           @"  name\n"
           @"  hidden\n"
           @"}\n"
           @"\n"
           @"fragment FMyBooksCardBook on Book {\n"
           @"  initUuid\n"
           @"  name\n"
           @"  cover {\n"
           @"    ...FMyBooksCardCover\n"
           @"  }\n"
           @"  authors {\n"
           @"    ...FMyBooksCardPerson\n"
           @"  }\n"
           @"  auditory {\n"
           @"    total\n"
           @"  }\n"
           @"}\n"
           @"\n"
           @"fragment FMyBooksCardProgress on Progress {\n"
           @"  progress\n"
           @"}\n"
           @"\n"
           @"fragment FMyBooksCardAvailability on Availability {\n"
           @"  ageRestriction {\n"
           @"    value\n"
           @"  }\n"
           @"  state {\n"
           @"    ... on Available {\n"
           @"      full\n"
           @"      expiredAt\n"
           @"      availableUntilWithGracePeriod\n"
           @"    }\n"
           @"    ... on Unavailable {\n"
           @"      reason\n"
           @"    }\n"
           @"  }\n"
           @"}\n"
           @"\n"
           @"fragment FMyBooksTextBook on TextBook {\n"
           @"  book {\n"
           @"    ...FMyBooksCardBook\n"
           @"  }\n"
           @"  progress {\n"
           @"    ...FMyBooksCardProgress\n"
           @"  }\n"
           @"  availability {\n"
           @"    ...FMyBooksCardAvailability\n"
           @"  }\n"
           @"}\n"
           @"\n"
           @"fragment FMyBooksCardNarrator on Person {\n"
           @"  uuid\n"
           @"  name\n"
           @"}\n"
           @"\n"
           @"fragment FMyBooksAudioBook on AudioBook {\n"
           @"  book {\n"
           @"    ...FMyBooksCardBook\n"
           @"  }\n"
           @"  progress {\n"
           @"    ...FMyBooksCardProgress\n"
           @"  }\n"
           @"  availability {\n"
           @"    ...FMyBooksCardAvailability\n"
           @"  }\n"
           @"  narrators {\n"
           @"    ...FMyBooksCardNarrator\n"
           @"  }\n"
           @"}\n"
           @"\n"
           @"fragment FMyBooksComicBook on ComicBook {\n"
           @"  book {\n"
           @"    ...FMyBooksCardBook\n"
           @"  }\n"
           @"  progress {\n"
           @"    ...FMyBooksCardProgress\n"
           @"  }\n"
           @"  availability {\n"
           @"    ...FMyBooksCardAvailability\n"
           @"  }\n"
           @"}\n"
           @"\n"
           @"fragment FMyBooksTextSerial on TextSerial {\n"
           @"  book {\n"
           @"    ...FMyBooksCardBook\n"
           @"  }\n"
           @"  progress {\n"
           @"    ...FMyBooksCardProgress\n"
           @"  }\n"
           @"  availability {\n"
           @"    ...FMyBooksCardAvailability\n"
           @"  }\n"
           @"}\n"
           @"\n"
           @"fragment FMyBooksLibraryCard on LibraryCard {\n"
           @"  uuid\n"
           @"  progress\n"
           @"  status\n"
           @"  items {\n"
           @"    __typename\n"
           @"    ...FMyBooksTextBook\n"
           @"    ...FMyBooksAudioBook\n"
           @"    ...FMyBooksComicBook\n"
           @"    ...FMyBooksTextSerial\n"
           @"  }\n"
           @"}\n";
}

#pragma mark - Shelf

+ (void)fetchShelf:(ORYandexShelfCompletion)completion {
    if (!completion) return;
    [self fetchViewerProfile:^(NSDictionary *profile, NSError *error) {
        NSString *login = [self firstStringIn:profile keys:@[@"login"]];
        if (login.length == 0) {
            NSLog(@"[OmniReader] Yandex shelf: profile unavailable (%@)", error.localizedDescription ?: @"empty");
            completion(nil, error ?: [NSError errorWithDomain:@"OmniReader.Yandex" code:401
                                                    userInfo:@{NSLocalizedDescriptionKey:
                                                                   @"Яндекс не вернул профиль Книг. Проверьте токен."}]);
            return;
        }
        [self fetchLibraryCardsForLogin:login
                                  cursor:@""
                             accumulated:[NSMutableArray array]
                                   pages:0
                              completion:^(NSArray *items, NSError *error) {
            if (items.count > 0) {
                completion(items, nil);
                return;
            }
            if (error) {
                completion(nil, error);
                return;
            }
            completion(@[], nil);
        }];
    }];
}

+ (void)fetchViewerProfile:(void (^)(NSDictionary *, NSError *))completion {
    NSString *query = @"query Viewer { userProfile { login id name yuid email avatar { small large } } }";
    [self graphql:query variables:nil completion:^(id data, NSError *error) {
        NSDictionary *profile = [data isKindOfClass:[NSDictionary class]] ? data[@"userProfile"] : nil;
        if ([profile isKindOfClass:[NSDictionary class]] && profile.count > 0) {
            [self setCachedViewerRoot:@"userProfile"];
            completion(profile, nil);
            return;
        }
        completion(nil, error ?: [NSError errorWithDomain:@"OmniReader.Yandex" code:401
                                                userInfo:@{NSLocalizedDescriptionKey:
                                                               @"Токен принят, но профиль Книг пуст (нет доступа к аккаунту Books)."}]);
    }];
}

+ (void)fetchLibraryCardsForLogin:(NSString *)login
                            cursor:(NSString *)cursor
                       accumulated:(NSMutableArray *)accumulated
                             pages:(NSInteger)pages
                        completion:(void (^)(NSArray *, NSError *))completion {
    NSDictionary *variables = @{
        @"login": login,
        @"cursor": cursor ?: @"",
        @"limit": @24,
        @"sort": @"UPDATED_AT",
        @"filters": @{@"advancedFilters": @[], @"contentTypeFilters": @[]}
    };
    [self graphqlAtPath:[self libraryPath]
          operationName:@"MyBooksLibraryCards"
                  query:[self myBooksQuery]
              variables:variables
             completion:^(id data, NSError *error) {
        if (error) {
            NSString *lower = (error.localizedDescription ?: @"").lowercaseString;
            if ([lower containsString:@"whitelist"]) {
                completion(nil, [NSError errorWithDomain:@"OmniReader.Yandex" code:422
                                                userInfo:@{NSLocalizedDescriptionKey:
                                                               @"Яндекс принял токен, но не отдаёт полку OAuth-клиенту: "
                                                                "личная библиотека доступна только веб-сессии (закрытый "
                                                                "whitelist запросов). Купленные книги можно открыть "
                                                                "файлом: «+» → «Импортировать файл»."}]);
                return;
            }
            completion(nil, error);
            return;
        }
        NSDictionary *user = [data isKindOfClass:[NSDictionary class]] ? data[@"user"] : nil;
        NSDictionary *library = [user isKindOfClass:[NSDictionary class]] ? user[@"library"] : nil;
        NSDictionary *cards = [library isKindOfClass:[NSDictionary class]] ? library[@"libraryCards"] : nil;
        NSArray *page = [cards isKindOfClass:[NSDictionary class]] ? cards[@"page"] : nil;
        if ([page isKindOfClass:[NSArray class]]) {
            [accumulated addObjectsFromArray:[self itemsFromLibraryCards:page]];
        }
        id nextValue = [cards isKindOfClass:[NSDictionary class]] ? cards[@"cursor"] : nil;
        NSString *next = [nextValue isKindOfClass:[NSString class]] ? nextValue : nil;
        if (next.length > 0 && pages < 2) {
            [self fetchLibraryCardsForLogin:login
                                     cursor:next
                                accumulated:accumulated
                                      pages:pages + 1
                                 completion:completion];
            return;
        }
        completion(accumulated, nil);
    }];
}

/// Flattens `libraryCards.page[]` into the flat dictionaries the UI expects.
+ (NSArray<NSDictionary *> *)itemsFromLibraryCards:(NSArray *)cards {
    NSMutableArray *result = [NSMutableArray array];
    for (id rawCard in cards) {
        if (![rawCard isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *card = rawCard;
        NSArray *items = card[@"items"];
        if (![items isKindOfClass:[NSArray class]]) continue;
        NSDictionary *chosen = nil;
        for (id rawItem in items) {
            if (![rawItem isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *item = rawItem;
            if (![item[@"book"] isKindOfClass:[NSDictionary class]]) continue;
            // Prefer the audio edition when a card carries several formats.
            if (!chosen || [item[@"__typename"] isEqualToString:@"AudioBook"]) chosen = item;
            if ([item[@"__typename"] isEqualToString:@"AudioBook"]) break;
        }
        if (!chosen) continue;
        NSDictionary *book = chosen[@"book"];
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        id title = book[@"name"];
        entry[@"title"] = [title isKindOfClass:[NSString class]] && [title length] > 0 ? title : @"Без названия";
        id identifier = book[@"initUuid"] ?: card[@"uuid"];
        if ([identifier isKindOfClass:[NSString class]] && [identifier length] > 0) entry[@"id"] = identifier;
        BOOL audio = [chosen[@"__typename"] isEqualToString:@"AudioBook"];
        entry[@"isAudio"] = @(audio);
        entry[@"format"] = audio ? @"audio" : @"epub";

        NSMutableArray<NSString *> *names = [NSMutableArray array];
        id rawAuthors = book[@"authors"];
        if ([rawAuthors isKindOfClass:[NSArray class]]) {
            for (id rawAuthor in rawAuthors) {
                if (![rawAuthor isKindOfClass:[NSDictionary class]]) continue;
                id name = rawAuthor[@"name"];
                if ([name isKindOfClass:[NSString class]] && [name length] > 0) [names addObject:name];
            }
        }
        if (names.count > 0) entry[@"author"] = [names componentsJoinedByString:@", "];

        NSDictionary *cover = [book[@"cover"] isKindOfClass:[NSDictionary class]] ? book[@"cover"] : nil;
        id coverURL = cover[@"url"];
        if ([coverURL isKindOfClass:[NSString class]] && [coverURL length] > 0) entry[@"cover"] = coverURL;

        id progress = nil;
        NSDictionary *progressObject = [chosen[@"progress"] isKindOfClass:[NSDictionary class]] ? chosen[@"progress"] : nil;
        if (progressObject) progress = progressObject[@"progress"];
        if (![progress isKindOfClass:[NSNumber class]]) progress = card[@"progress"];
        if ([progress isKindOfClass:[NSNumber class]]) entry[@"progress"] = progress;

        [result addObject:entry];
    }
    return result;
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
