#import "OROPDS.h"
#import "ORCore.h"
#import "ORHTTP.h"
#import "ORText.h"
#import "ORUtil.h"
#import "ORXML.h"

@interface OROPDS ()
+ (BOOL)isDownloadableType:(NSString *)type;
+ (NSString *)absoluteURL:(NSString *)href base:(NSString *)base;
+ (NSString *)queryURLForBase:(NSString *)base query:(NSString *)query;
+ (NSString *)fillSearchTemplate:(NSString *)template query:(NSString *)query;
+ (void)classifyEntry:(NSMutableDictionary *)entry links:(NSArray<NSDictionary *> *)entryLinks;
+ (nullable NSDictionary *)tolerantFeedFromData:(NSData *)data baseURL:(NSString *)baseURL;
+ (NSString *)attribute:(NSString *)name inTag:(NSString *)tag;
+ (NSString *)unescapeXML:(NSString *)string;
+ (nullable NSError *)validateDownloadedFile:(NSString *)path;
@end

@implementation OROPDS

+ (NSError *)validateDownloadedFile:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    if (!data || data.length == 0) {
        return [NSError errorWithDomain:@"OmniReader.OPDS" code:4
                               userInfo:@{NSLocalizedDescriptionKey: @"Сервер вернул пустой файл."}];
    }
    if (data.length < 64) {
        return [NSError errorWithDomain:@"OmniReader.OPDS" code:4
                               userInfo:@{NSLocalizedDescriptionKey: @"Файл слишком мал — похоже, это не книга."}];
    }
    const uint8_t *b = data.bytes;
    BOOL zip = (b[0] == 'P' && b[1] == 'K');
    BOOL rar = (b[0] == 'R' && b[1] == 'a');
    BOOL pdf = memcmp(b, "%PDF", 4) == 0;
    BOOL mobi = memcmp(b, "AT&T", 4) == 0;
    BOOL djvu = memcmp(b, "DJVU", 4) == 0;
    BOOL audio = memcmp(b, "ID3", 3) == 0 || memcmp(b, "fLaC", 4) == 0 ||
                 (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) ||
                 memcmp(b, "OggS", 4) == 0 || memcmp(b, "RIFF", 4) == 0;
    if (zip || rar || pdf || mobi || djvu || audio) return nil;
    if ([ORText looksLikeHTML:data]) {
        NSString *page = [ORText stripHTML:[ORText stringFromData:data]];
        if (page.length > 200) page = [[page substringToIndex:200] stringByAppendingString:@"…"];
        return [NSError errorWithDomain:@"OmniReader.OPDS" code:5
                               userInfo:@{NSLocalizedDescriptionKey:
                                              [NSString stringWithFormat:
                                               @"Каталог вернул веб-страницу вместо файла:\n\n%@\n\n"
                                                "Обычно требуется вход на сайте каталога или скачивание в браузере.", page]}];
    }
    return [NSError errorWithDomain:@"OmniReader.OPDS" code:6
                           userInfo:@{NSLocalizedDescriptionKey: @"Файл не является книгой в известном формате."}];
}

+ (NSDictionary *)headersForCatalog:(NSDictionary *)catalog {
    if (!catalog) return @{@"Accept": @"application/atom+xml,application/xml,*/*"};
    NSString *user = catalog[@"user"];
    if (user.length == 0) return @{@"Accept": @"application/atom+xml,application/xml,*/*"};
    NSString *password = [[ORSettings shared] passwordForOPDSCatalog:catalog[@"id"] ?: @""] ?: @"";
    NSString *authorization = [ORHTTP basicAuthorizationForUser:user password:password];
    return @{@"Accept": @"application/atom+xml,application/xml,*/*",
             @"Authorization": authorization};
}

+ (void)loadFeedAtURL:(NSString *)urlString
              catalog:(NSDictionary *)catalog
           completion:(OROPDSFeedCompletion)completion {
    if (!completion) return;
    [ORHTTP GET:urlString
        headers:[self headersForCatalog:catalog]
     completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error || !data) {
            completion(nil, error ?: [NSError errorWithDomain:@"OmniReader.OPDS" code:1
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Пустой ответ каталога"}]);
            return;
        }
        NSDictionary *feed = [self parseFeedData:data baseURL:urlString];
        if (!feed) {
            completion(nil, [NSError errorWithDomain:@"OmniReader.OPDS" code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"Не удалось разобрать OPDS-каталог"}]);
            return;
        }
        completion(feed, nil);
    }];
}

+ (NSDictionary *)parseFeedData:(NSData *)data baseURL:(NSString *)baseURL {
    ORXMLNode *root = [ORXML parseData:data error:NULL];
    NSMutableDictionary *feed = nil;
    if (root) {
        feed = [NSMutableDictionary dictionary];
        NSString *title = [[root firstChildNamed:@"title"] innerText];
        feed[@"title"] = title.length > 0 ? title : @"Каталог";

        NSMutableArray *links = [NSMutableArray array];
        for (ORXMLNode *link in [root childrenNamed:@"link"]) {
            NSString *rel = [link attr:@"rel"] ?: @"";
            NSString *href = [link attr:@"href"] ?: @"";
            NSString *type = [link attr:@"type"] ?: @"";
            if (href.length == 0) continue;
            [links addObject:@{@"rel": rel,
                               @"href": [self absoluteURL:href base:baseURL],
                               @"type": type}];
        }
        feed[@"links"] = links;
        feed[@"entries"] = [NSMutableArray array];

        for (ORXMLNode *entryNode in [root childrenNamed:@"entry"]) {
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            NSString *entryTitle = [[entryNode firstChildNamed:@"title"] innerText];
            entry[@"title"] = entryTitle.length > 0 ? entryTitle : @"Без названия";
            NSString *author = [[[entryNode firstChildNamed:@"author"] firstChildNamed:@"name"] innerText];
            if (author.length > 0) entry[@"author"] = author;
            NSString *summary = [[entryNode firstChildNamed:@"content"] innerText];
            if (summary.length == 0) summary = [[entryNode firstChildNamed:@"summary"] innerText];
            if (summary.length > 0) entry[@"summary"] = summary;
            NSString *identifier = [[entryNode firstChildNamed:@"id"] innerText];
            if (identifier.length > 0) entry[@"id"] = identifier;

            NSMutableArray *entryLinks = [NSMutableArray array];
            NSString *imageURL = nil;
            for (ORXMLNode *link in [entryNode childrenNamed:@"link"]) {
                NSString *rel = [link attr:@"rel"] ?: @"";
                NSString *href = [link attr:@"href"] ?: @"";
                NSString *type = [link attr:@"type"] ?: @"";
                if (href.length == 0) continue;
                NSString *absolute = [self absoluteURL:href base:baseURL];
                [entryLinks addObject:@{@"rel": rel, @"href": absolute, @"type": type}];
                if ([rel containsString:@"image"] || [rel containsString:@"thumbnail"]) {
                    imageURL = absolute;
                } else if ([type hasPrefix:@"image/"] && imageURL.length == 0) {
                    imageURL = absolute;
                }
            }
            entry[@"links"] = entryLinks;
            if (imageURL) entry[@"image"] = imageURL;
            [self classifyEntry:entry links:entryLinks];
            [feed[@"entries"] addObject:entry];
        }
        feed[@"baseURL"] = baseURL;
    }

    // A truncated parse still gives the feed title but no entries: recover them
    // from the raw markup so a single broken annotation does not kill the page.
    if (!feed || [feed[@"entries"] count] == 0) {
        NSDictionary *recovered = [self tolerantFeedFromData:data baseURL:baseURL];
        if (recovered) {
            if (feed && [feed[@"title"] length] > 0 && ![feed[@"title"] isEqualToString:@"Каталог"]) {
                NSMutableDictionary *merged = [recovered mutableCopy];
                merged[@"title"] = feed[@"title"];
                return merged;
            }
            return recovered;
        }
    }
    return feed;
}

+ (void)classifyEntry:(NSMutableDictionary *)entry links:(NSArray<NSDictionary *> *)entryLinks {
    BOOL navigation = NO;
    BOOL acquisition = NO;
    for (NSDictionary *link in entryLinks) {
        NSString *rel = [(NSString *)(link[@"rel"] ?: @"") lowercaseString];
        NSString *type = [(NSString *)(link[@"type"] ?: @"") lowercaseString];
        if ([rel containsString:@"subsection"] || [rel containsString:@"navigation"]) navigation = YES;
        // lib.rus.ec marks sections only by MIME type (often with no rel).
        if ([type containsString:@"atom+xml"] || [type containsString:@"opds-catalog"]) navigation = YES;
        if ([rel containsString:@"acquisition"] || [rel isEqualToString:@"enclosure"]) acquisition = YES;
        else if ([self isDownloadableType:type]) acquisition = YES;
    }
    entry[@"navigation"] = @(navigation);
    entry[@"acquisition"] = @(acquisition);
}

+ (BOOL)isDownloadableType:(NSString *)type {
    if (type.length == 0) return NO;
    NSString *lower = type.lowercaseString;
    NSArray<NSString *> *needles = @[@"epub", @"fb2", @"pdf", @"text/plain", @"mobi", @"azw",
                                     @"djvu", @"zip", @"cbz", @"cbr", @"audio", @"mpeg",
                                     @"m4b", @"m4a", @"flac", @"ogg", @"octet-stream"];
    for (NSString *needle in needles) {
        if ([lower containsString:needle]) return YES;
    }
    return NO;
}

+ (NSString *)absoluteURL:(NSString *)href base:(NSString *)base {
    if ([href hasPrefix:@"http://"] || [href hasPrefix:@"https://"]) return href;
    // Feeds live at /opds (no extension) — treat them as directories so
    // relative hrefs like "b/123/download" resolve under /opds/, not /.
    if (![base hasSuffix:@"/"]) {
        NSURL *baseURL = [NSURL URLWithString:base];
        if (baseURL.path.pathExtension.length == 0) {
            base = [base stringByAppendingString:@"/"];
        }
    }
    NSURL *baseURL = [NSURL URLWithString:base];
    if (!baseURL) return href;
    NSURL *resolved = [NSURL URLWithString:href relativeToURL:baseURL];
    return resolved.absoluteURL.absoluteString ?: href;
}

+ (void)downloadEntry:(NSDictionary *)entry
              catalog:(NSDictionary *)catalog
           formatHint:(NSString *)formatHint
           completion:(OROPDSDownloadCompletion)completion {
    if (!completion) return;
    NSArray<NSDictionary *> *links = entry[@"links"] ?: @[];

    NSDictionary *chosen = nil;
    // 1. Prefer a real acquisition link with a known book/audio type.
    for (NSDictionary *link in links) {
        NSString *type = (NSString *)(link[@"type"] ?: @"");
        NSString *rel = [(NSString *)(link[@"rel"] ?: @"") lowercaseString];
        BOOL isAcquisition = [rel containsString:@"acquisition"] || [rel isEqualToString:@"enclosure"];
        if (!isAcquisition) continue;
        if (![self isDownloadableType:type]) continue;
        chosen = link;
        if ([type.lowercaseString containsString:@"epub"]) break;
    }
    // 2. Any link with a downloadable MIME type (catalogs with non-standard rel).
    if (!chosen) {
        for (NSDictionary *link in links) {
            NSString *type = link[@"type"] ?: @"";
            if ([self isDownloadableType:type]) {
                chosen = link;
                break;
            }
        }
    }
    // 3. Last resort: a link whose URL clearly points at a book file.
    if (!chosen) {
        NSArray<NSString *> *known = @[@"epub", @"fb2", @"pdf", @"txt", @"zip", @"cbz", @"cbr",
                                       @"mobi", @"azw", @"azw3", @"djvu", @"mp3", @"m4b", @"m4a", @"flac", @"ogg"];
        for (NSDictionary *link in links) {
            NSString *href = link[@"href"] ?: @"";
            NSString *extension = [NSURL URLWithString:href].path.pathExtension.lowercaseString;
            if ([known containsObject:extension]) {
                chosen = link;
                break;
            }
        }
    }

    if (!chosen) {
        // Log what the entry actually offers: this makes adapting to a changed
        // catalog trivial without recompiling angle brackets.
        NSMutableArray<NSString *> *debug = [NSMutableArray array];
        for (NSDictionary *link in links) {
            [debug addObject:[NSString stringWithFormat:@"rel=%@ type=%@ href=%@",
                              link[@"rel"] ?: @"", link[@"type"] ?: @"", link[@"href"] ?: @""]];
        }
        NSLog(@"[OmniReader] OPDS entry '%@' has no downloadable link. Links: %@",
              entry[@"title"] ?: @"?", [debug componentsJoinedByString:@" | "]);
        completion(nil, nil, [NSError errorWithDomain:@"OmniReader.OPDS" code:3
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"У записи нет файла для скачивания. Возможно, это раздел каталога — откройте его, либо каталог не отдаёт файлы без авторизации."}]);
        return;
    }

    NSString *href = (NSString *)(chosen[@"href"] ?: @"");
    NSString *type = [(NSString *)(chosen[@"type"] ?: @"") lowercaseString];
    NSString *extension = @"epub";
    if ([type containsString:@"pdf"]) extension = @"pdf";
    else if ([type containsString:@"text/plain"]) extension = @"txt";
    else if ([type containsString:@"fb2"]) extension = @"fb2";
    else if ([type containsString:@"mobi"]) extension = @"mobi";
    else if ([type containsString:@"azw"]) extension = @"azw3";
    else if ([type containsString:@"djvu"]) extension = @"djvu";
    else if ([type containsString:@"cbz"]) extension = @"cbz";
    else if ([type containsString:@"cbr"]) extension = @"cbr";
    else if ([type containsString:@"audio/mpeg"] || [type containsString:@"mpeg"]) extension = @"mp3";
    else if ([type containsString:@"audio/mp4"] || [type containsString:@"m4b"]) extension = @"m4b";
    else if ([type containsString:@"flac"]) extension = @"flac";
    else if ([type containsString:@"ogg"]) extension = @"ogg";
    else if ([type containsString:@"zip"]) extension = @"zip";

    // The URL extension is the most reliable hint when the MIME type is generic.
    NSString *pathExtension = [NSURL URLWithString:href].path.pathExtension.lowercaseString;
    NSArray<NSString *> *known = @[@"epub", @"fb2", @"pdf", @"txt", @"zip", @"cbz", @"cbr",
                                   @"mobi", @"azw", @"azw3", @"djvu", @"mp3", @"m4b", @"m4a", @"flac", @"ogg"];
    if ([known containsObject:pathExtension]) {
        extension = pathExtension;
    }
    if (formatHint.length > 0 && formatHint.length <= 5) extension = formatHint;

    NSString *destination = [[ORPaths cacheDirectory] stringByAppendingPathComponent:
                                [NSString stringWithFormat:@"opds-%@.%@", [ORUtil uniqueKey], extension]];
    [ORHTTP download:href
             headers:[self headersForCatalog:catalog]
              toPath:destination
          completion:^(NSString *path, NSError *error) {
        if (error) {
            completion(nil, nil, error);
            return;
        }
        // Catalogs often answer with an HTML page instead of the book (login
        // wall, "file moved", anti-leech). Report it instead of importing junk.
        NSError *validationError = [self validateDownloadedFile:path];
        if (validationError) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            completion(nil, nil, validationError);
            return;
        }
        NSString *base = entry[@"title"] ?: @"book";
        NSString *suggested = [NSString stringWithFormat:@"%@.%@", base, extension];
        completion(path, suggested, nil);
    }];
}

+ (void)resolveSearchURLForFeed:(NSDictionary *)feed
                        catalog:(NSDictionary *)catalog
                          query:(NSString *)query
                     completion:(void (^)(NSString *, NSError *))completion {
    if (!completion) return;
    NSString *base = feed[@"baseURL"] ?: @"";
    NSString *searchHref = nil;
    for (NSDictionary *link in feed[@"links"] ?: @[]) {
        NSString *rel = [(NSString *)(link[@"rel"] ?: @"") lowercaseString];
        NSString *type = [(NSString *)(link[@"type"] ?: @"") lowercaseString];
        if ([rel containsString:@"search"] || [type containsString:@"opensearchdescription"]) {
            searchHref = (NSString *)(link[@"href"] ?: @"");
            break;
        }
    }
    if (searchHref.length == 0) {
        completion([self queryURLForBase:base query:query], nil);
        return;
    }
    // Some catalogs publish the OpenSearch template directly as a link
    // (lib.rus.ec: href="...searchopds?ask={searchTerms}").
    if ([searchHref containsString:@"{searchTerms}"]) {
        NSString *filled = [self fillSearchTemplate:[self absoluteURL:searchHref base:base] query:query];
        completion(filled, nil);
        return;
    }
    searchHref = [self absoluteURL:searchHref base:base];
    [ORHTTP GET:searchHref
        headers:[self headersForCatalog:catalog]
     completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        ORXMLNode *root = data ? [ORXML parseData:data error:NULL] : nil;
        NSString *template = nil;
        if (root) {
            for (ORXMLNode *node in [root childrenNamed:@"url"]) {
                NSString *type = [[node attr:@"type"] lowercaseString];
                NSString *candidate = [node attr:@"template"];
                if (candidate.length == 0) continue;
                if ([type containsString:@"atom"]) { template = candidate; break; }
                if (!template) template = candidate;
            }
            if (!template) {
                template = [[[root descendantsNamed:@"url"] firstObject] attr:@"template"];
            }
        }
        if (template.length == 0) {
            completion([self queryURLForBase:base query:query], nil);
            return;
        }
        NSString *filled = [self fillSearchTemplate:template query:query];
        completion([self absoluteURL:filled base:base], nil);
    }];
}

+ (NSString *)queryURLForBase:(NSString *)base query:(NSString *)query {
    NSString *escaped = [ORText queryEscape:query];
    // Common conventions: /search?q=, /searchopds?ask=. Prefer the one the
    // server already uses in its own URLs.
    if ([base containsString:@"searchopds"] || [base containsString:@"ask="]) {
        NSString *separator = [base containsString:@"?"] ? @"&" : @"?";
        return [base stringByAppendingFormat:@"%@ask=%@", separator, escaped];
    }
    NSString *separator = [base containsString:@"?"] ? @"&" : @"?";
    return [base stringByAppendingFormat:@"%@q=%@", separator, escaped];
}

+ (NSString *)fillSearchTemplate:(NSString *)template query:(NSString *)query {
    NSString *escaped = [ORText queryEscape:query];
    NSString *result = template;
    result = [result stringByReplacingOccurrencesOfString:@"{searchTerms}" withString:escaped];
    result = [result stringByReplacingOccurrencesOfString:@"{startIndex}" withString:@"1"];
    result = [result stringByReplacingOccurrencesOfString:@"{count}" withString:@"25"];
    result = [ORText replacePattern:@"\\{[^}]+\\}" inString:result withTemplate:@""];
    return result;
}

#pragma mark - Malformed feed recovery

/// Scans raw markup for <entry>/<link> tags. Used when a server emits invalid
/// XML (lib.rus.ec does: raw '&' inside summaries and attribute values).
+ (NSDictionary *)tolerantFeedFromData:(NSData *)data baseURL:(NSString *)baseURL {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) text = [[NSString alloc] initWithData:data encoding:NSWindowsCP1251StringEncoding];
    if (text.length == 0 || ![text containsString:@"<entry"]) return nil;

    NSMutableDictionary *feed = [NSMutableDictionary dictionary];
    NSString *feedTitle = [ORText firstMatchPattern:@"(?is)<title[^>]*>(.*?)</title>" inString:text group:1];
    feedTitle = [self unescapeXML:[ORText stripHTML:feedTitle ?: @""]];
    feed[@"title"] = feedTitle.length > 0 ? feedTitle : @"Каталог";

    NSMutableArray *links = [NSMutableArray array];
    NSArray<NSString *> *entryChunks = [ORText matchesPattern:@"(?is)<entry\\b[^>]*>(.*?)</entry>" inString:text group:1];
    NSMutableArray *entries = [NSMutableArray array];

    for (NSString *chunk in entryChunks) {
        NSString *title = nil;
        NSString *author = nil;
        NSString *summary = nil;
        NSString *identifier = nil;
        NSMutableArray *entryLinks = [NSMutableArray array];

        NSRange titleRange = [chunk rangeOfString:@"<title" options:NSCaseInsensitiveSearch];
        if (titleRange.location != NSNotFound) {
            NSString *tail = [chunk substringFromIndex:titleRange.location];
            NSString *raw = [ORText firstMatchPattern:@"(?is)<title[^>]*>(.*?)</title>" inString:tail group:1];
            title = [self unescapeXML:[ORText stripHTML:raw ?: @""]];
        }
        NSRange authorRange = [chunk rangeOfString:@"<author" options:NSCaseInsensitiveSearch];
        if (authorRange.location != NSNotFound) {
            NSString *tail = [chunk substringFromIndex:authorRange.location];
            NSString *name = [ORText firstMatchPattern:@"(?is)<name[^>]*>(.*?)</name>" inString:tail group:1];
            author = [self unescapeXML:[ORText stripHTML:name ?: @""]];
        }
        NSRange summaryRange = [chunk rangeOfString:@"<summary" options:NSCaseInsensitiveSearch];
        if (summaryRange.location == NSNotFound) {
            summaryRange = [chunk rangeOfString:@"<content" options:NSCaseInsensitiveSearch];
        }
        if (summaryRange.location != NSNotFound) {
            NSString *tail = [chunk substringFromIndex:summaryRange.location];
            NSString *raw = [ORText firstMatchPattern:@"(?is)<summary[^>]*>(.*?)</summary>" inString:tail group:1];
            if (raw.length == 0) {
                raw = [ORText firstMatchPattern:@"(?is)<content[^>]*>(.*?)</content>" inString:tail group:1];
            }
            summary = [self unescapeXML:raw ?: @""];
        }
        NSRange idRange = [chunk rangeOfString:@"<id" options:NSCaseInsensitiveSearch];
        if (idRange.location != NSNotFound) {
            NSString *tail = [chunk substringFromIndex:idRange.location];
            identifier = [ORText firstMatchPattern:@"(?is)<id[^>]*>(.*?)</id>" inString:tail group:1];
        }

        NSArray<NSString *> *tags = [ORText matchesPattern:@"(?is)<link\\b[^>]*>" inString:chunk group:0];
        NSString *imageURL = nil;
        for (NSString *tag in tags) {
            NSString *href = [self attribute:@"href" inTag:tag];
            if (href.length == 0) continue;
            NSString *rel = [self attribute:@"rel" inTag:tag] ?: @"";
            NSString *type = [self attribute:@"type" inTag:tag] ?: @"";
            NSString *absolute = [self absoluteURL:[self unescapeXML:href] base:baseURL];
            [entryLinks addObject:@{@"rel": rel, @"href": absolute, @"type": type}];
            if ([rel containsString:@"image"] || [type hasPrefix:@"image/"]) {
                if (imageURL.length == 0 || [rel containsString:@"thumbnail"]) imageURL = absolute;
            }
        }

        if (identifier.length == 0) identifier = [self attribute:@"id" inTag:
            (tags.firstObject ?: @"")];
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        if (title.length > 0) entry[@"title"] = title;
        if (author.length > 0) entry[@"author"] = author;
        if (summary.length > 0) {
            NSString *flat = [summary stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            flat = [flat stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (flat.length > 400) flat = [[flat substringToIndex:400] stringByAppendingString:@"…"];
            entry[@"summary"] = flat;
        }
        entry[@"id"] = identifier ?: @"";
        entry[@"links"] = entryLinks;
        if (imageURL.length > 0) entry[@"image"] = imageURL;

        BOOL navigation = NO;
        BOOL acquisition = NO;
        for (NSDictionary *link in entryLinks) {
            NSString *rel = [(NSString *)(link[@"rel"] ?: @"") lowercaseString];
            NSString *type = [(NSString *)(link[@"type"] ?: @"") lowercaseString];
            if ([rel containsString:@"subsection"] || [rel containsString:@"navigation"]) navigation = YES;
            if ([type containsString:@"atom+xml"] || [type containsString:@"opds-catalog"]) navigation = YES;
            if ([rel containsString:@"acquisition"] || [rel isEqualToString:@"enclosure"]) acquisition = YES;
            else if ([self isDownloadableType:type]) acquisition = YES;
        }
        entry[@"navigation"] = @(navigation);
        entry[@"acquisition"] = @(acquisition);
        [entries addObject:entry];
    }

    // Feed level navigation (rel=start/next and the search template).
    for (NSString *tag in [ORText matchesPattern:@"(?is)<link\\b[^>]*>" inString:
                               [ORText firstMatchPattern:@"(?is)<feed\\b[^>]*>(.*?)<entry" inString:text group:1] ?: @"" group:0]) {
        NSString *href = [self attribute:@"href" inTag:tag];
        if (href.length == 0) continue;
        NSString *rel = [self attribute:@"rel" inTag:tag] ?: @"";
        NSString *type = [self attribute:@"type" inTag:tag] ?: @"";
        NSString *absolute = [self absoluteURL:[self unescapeXML:href] base:baseURL];
        [links addObject:@{@"rel": rel, @"href": absolute, @"type": type}];
    }
    feed[@"links"] = links;
    feed[@"entries"] = entries;
    feed[@"baseURL"] = baseURL;
    if (entries.count == 0) return nil;
    NSLog(@"[OmniReader] OPDS recovered %lu entries from malformed XML",
          (unsigned long)entries.count);
    return feed;
}

+ (NSString *)attribute:(NSString *)name inTag:(NSString *)tag {
    if (tag.length == 0) return @"";
    NSString *pattern = [NSString stringWithFormat:@"(?is)\\b%@\\s*=\\s*\"([^\"]*)\"", name];
    NSString *value = [ORText firstMatchPattern:pattern inString:tag group:1];
    if (value.length == 0) {
        pattern = [NSString stringWithFormat:@"(?is)\\b%@\\s*=\\s*'([^']*)'", name];
        value = [ORText firstMatchPattern:pattern inString:tag group:1];
    }
    return value ?: @"";
}

+ (NSString *)unescapeXML:(NSString *)string {
    if (string.length == 0) return @"";
    return [ORText decodeEntities:string];
}

@end
