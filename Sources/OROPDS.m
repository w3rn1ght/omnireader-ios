#import "OROPDS.h"
#import "ORCore.h"
#import "ORHTTP.h"
#import "ORText.h"
#import "ORUtil.h"
#import "ORXML.h"

@interface OROPDS ()
+ (BOOL)isDownloadableType:(NSString *)type;
+ (NSString *)absoluteURL:(NSString *)href base:(NSString *)base;
@end

@implementation OROPDS

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
    if (!root) return nil;

    NSMutableDictionary *feed = [NSMutableDictionary dictionary];
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

    NSMutableArray *entries = [NSMutableArray array];
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

        BOOL navigation = NO;
        BOOL acquisition = NO;
        for (NSDictionary *link in entryLinks) {
            NSString *rel = link[@"rel"] ?: @"";
            NSString *type = link[@"type"] ?: @"";
            NSString *lowerRel = rel.lowercaseString;
            if ([lowerRel containsString:@"subsection"] || [lowerRel containsString:@"navigation"]) {
                navigation = YES;
            }
            // Some catalogs use the short "acquisition" rel, some use the full
            // opds-spec URI, and some only advertise the MIME type.
            if ([lowerRel containsString:@"acquisition"] || [lowerRel isEqualToString:@"enclosure"]) {
                acquisition = YES;
            } else if ([self isDownloadableType:type]) {
                acquisition = YES;
            }
        }
        entry[@"navigation"] = @(navigation);
        entry[@"acquisition"] = @(acquisition);
        [entries addObject:entry];
    }
    feed[@"entries"] = entries;
    feed[@"baseURL"] = baseURL;
    return feed;
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
        NSString *type = link[@"type"] ?: @"";
        NSString *rel = (link[@"rel"] ?: @"").lowercaseString;
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

    NSString *href = chosen[@"href"] ?: @"";
    NSString *type = (chosen[@"type"] ?: @"").lowercaseString;
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
        NSString *base = entry[@"title"] ?: @"book";
        NSString *suggested = [NSString stringWithFormat:@"%@.%@", base, extension];
        completion(path, suggested, nil);
    }];
}

@end
