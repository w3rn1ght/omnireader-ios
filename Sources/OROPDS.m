#import "OROPDS.h"
#import "ORCore.h"
#import "ORHTTP.h"
#import "ORText.h"
#import "ORUtil.h"
#import "ORXML.h"

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
            NSString *rel = link[@"rel"];
            if ([rel isEqualToString:@"subsection"] || [rel containsString:@"navigation"]) navigation = YES;
            if ([rel hasPrefix:@"http://opds-spec.org/acquisition"] ||
                [rel isEqualToString:@"http://opds-spec.org/acquisition"] ||
                [rel isEqualToString:@"enclosure"]) acquisition = YES;
        }
        entry[@"navigation"] = @(navigation);
        entry[@"acquisition"] = @(acquisition);
        [entries addObject:entry];
    }
    feed[@"entries"] = entries;
    feed[@"baseURL"] = baseURL;
    return feed;
}

+ (NSString *)absoluteURL:(NSString *)href base:(NSString *)base {
    if ([href hasPrefix:@"http://"] || [href hasPrefix:@"https://"]) return href;
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
    NSDictionary *chosen = nil;
    for (NSDictionary *link in entry[@"links"] ?: @[]) {
        NSString *type = link[@"type"] ?: @"";
        NSString *rel = link[@"rel"] ?: @"";
        if (!([rel hasPrefix:@"http://opds-spec.org/acquisition"] || [rel isEqualToString:@"enclosure"])) continue;
        if ([type containsString:@"epub"] || [type containsString:@"pdf"] ||
            [type containsString:@"text/plain"] || [type containsString:@"fb2"] ||
            [type containsString:@"audio"] || [type containsString:@"mpeg"] ||
            [type containsString:@"zip"]) {
            chosen = link;
            if ([type containsString:@"epub"]) break;
        }
    }
    if (!chosen) {
        for (NSDictionary *link in entry[@"links"] ?: @[]) {
            NSString *rel = link[@"rel"] ?: @"";
            if ([rel hasPrefix:@"http://opds-spec.org/acquisition"] || [rel isEqualToString:@"enclosure"]) {
                chosen = link;
                break;
            }
        }
    }
    if (!chosen) {
        completion(nil, nil, [NSError errorWithDomain:@"OmniReader.OPDS" code:3
                                            userInfo:@{NSLocalizedDescriptionKey: @"У записи нет файла для скачивания"}]);
        return;
    }

    NSString *href = chosen[@"href"];
    NSString *type = chosen[@"type"] ?: @"";
    NSString *extension = @"epub";
    if ([type containsString:@"pdf"]) extension = @"pdf";
    else if ([type containsString:@"text/plain"]) extension = @"txt";
    else if ([type containsString:@"fb2"]) extension = @"fb2";
    else if ([type containsString:@"audio/mpeg"] || [type containsString:@"audio/mp4"]) extension = @"mp3";
    else if ([type containsString:@"zip"]) extension = @"zip";

    // Prefer the extension advertised by the server in the URL.
    NSString *pathExtension = [href pathExtension].lowercaseString;
    NSArray<NSString *> *known = @[@"epub", @"fb2", @"pdf", @"txt", @"zip", @"cbz", @"mobi", @"azw3", @"mp3", @"m4b", @"m4a"];
    if ([known containsObject:pathExtension]) {
        extension = ([pathExtension isEqualToString:@"fb2"] && formatHint.length > 0) ? formatHint : pathExtension;
    }
    if (formatHint.length > 0 && formatHint.length < 6) extension = formatHint;

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
