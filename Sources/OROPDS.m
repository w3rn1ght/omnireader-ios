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
+ (nullable NSError *)validateDownloadedFile:(NSString *)path
                            sourceURL:(nullable NSString *)sourceURL
                             catalog:(nullable NSDictionary *)catalog;
+ (nullable NSString *)downloadLinkInHTML:(nullable NSData *)data baseURL:(NSString *)baseURL;
+ (NSArray<NSString *> *)derivedDownloadURLsForURL:(NSString *)entryURL;
+ (NSString *)refererForURL:(NSString *)urlString;
+ (NSString *)browserUserAgent;
+ (NSDictionary *)downloadHeadersForCatalog:(nullable NSDictionary *)catalog
                             referer:(nullable NSString *)referer
                   includeCredentials:(BOOL)includeCredentials;
+ (BOOL)isHTMLCatalogURL:(NSString *)urlString;
+ (nullable NSDictionary *)feedFromHTMLCatalogData:(NSData *)data baseURL:(NSString *)baseURL;
+ (nullable NSDictionary *)elevenklasovFeedFromData:(NSData *)data baseURL:(NSString *)baseURL;
+ (nullable NSString *)elevenklasovTitleFromHTML:(NSString *)html;
+ (NSString *)absoluteImageURL:(NSString *)href base:(NSString *)baseURL;
@end

@implementation OROPDS


/// Scans an HTML landing page for the actual book file. Catalogs reply with
/// interstitials for anonymous downloads ("file starts in a moment", anti-leech
/// pages, JS buttons); all of them expose the real URL in markup or script.
+ (NSString *)downloadLinkInHTML:(NSData *)data baseURL:(NSString *)baseURL {
    if (data.length == 0) return nil;
    NSString *html = [ORText stringFromData:data];
    if (html.length == 0) return nil;

    NSArray<NSString *> *known = @[@"epub", @"fb2", @"pdf", @"txt", @"zip", @"cbz", @"cbr",
                                   @"mobi", @"azw", @"azw3", @"djvu", @"mp3", @"m4b", @"m4a",
                                   @"flac", @"ogg"];
    // Advert networks wrap book pages too; never hand their links to the downloader.
    NSArray<NSString *> *adHosts = @[@"litres.ru", @"24day.ru", @"adfox", @"yandex", @"google",
                                     @"doubleclick", @"ozon.ru", @"wildberries", @"bookmate.com"];
    NSString *baseHost = [NSURL URLWithString:baseURL].host.lowercaseString ?: @"";

    NSMutableArray<NSString *> *raw = [NSMutableArray array];
    void (^collect)(NSString *, NSRegularExpressionOptions) = ^(NSString *pattern, NSRegularExpressionOptions options) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                              options:options
                                                                                error:NULL];
        if (!regex) return;
        NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:html
                                                                  options:0
                                                                    range:NSMakeRange(0, html.length)];
        for (NSTextCheckingResult *match in matches) {
            if (match.numberOfRanges < 2) continue;
            NSString *value = [html substringWithRange:[match rangeAtIndex:1]];
            if (value.length > 0) [raw addObject:value];
        }
    };

    // Plain links, JS buttons and redirects used by OPDS book pages.
    collect(@"<a[^>]+href\\s*=\\s*[\"']([^\"']+)[\"']", NSRegularExpressionCaseInsensitive);
    // Some Drupal templates render unquoted attributes; keep those too.
    collect(@"<a[^>]+href\\s*=\\s*([^\\s>\"']+)(?=[\\s>])", NSRegularExpressionCaseInsensitive);
    // Download forms post to the real file endpoint.
    collect(@"<form[^>]+action\\s*=\\s*[\"']([^\"']+)[\"']", NSRegularExpressionCaseInsensitive);
    collect(@"window\\.open\\s*\\(\\s*[\"']([^\"']+)[\"']", NSRegularExpressionCaseInsensitive);
    collect(@"window\\.open\\s*\\(\\s*&quot;([^&]+)&quot;", NSRegularExpressionCaseInsensitive);
    collect(@"(?:window\\.)?location(?:\\.href)?\\s*=\\s*[\"']([^\"']+)[\"']", NSRegularExpressionCaseInsensitive);
    collect(@"location\\.(?:replace|assign)\\s*\\(\\s*[\"']([^\"']+)[\"']", NSRegularExpressionCaseInsensitive);
    collect(@"document\\.location\\s*=\\s*[\"']([^\"']+)[\"']", NSRegularExpressionCaseInsensitive);
    collect(@"<meta[^>]+content\\s*=\\s*[\"'][^\"']*url=([^\"';]+)", NSRegularExpressionCaseInsensitive);
    // Any quoted URL that already looks like a book file.
    collect(@"[\"']((?:https?:)?//[^\"']+\\.(?:fb2|epub|pdf|txt|zip|mobi|azw3?))[\"']", NSRegularExpressionCaseInsensitive);
    collect(@"[\"'](/[^\"']+\\.(?:fb2|epub|pdf|txt|zip|mobi|azw3?))[\"']", NSRegularExpressionCaseInsensitive);
    // Flibusta-style endpoints, also when hidden inside an onclick handler.
    collect(@"((?:https?://[^\"'\\s]+)?/b/\\d+/download/\\?format=[a-z0-9.]+)", NSRegularExpressionCaseInsensitive);
    collect(@"((?:https?://[^\"'\\s&]+)?/b/\\d+/download/\\?format=[a-z0-9.]+)", NSRegularExpressionCaseInsensitive);
    collect(@"((?:https?://[^\"'\\s]+)?/b/\\d+/download/?)(?=[\"'\\s])", NSRegularExpressionCaseInsensitive);

    NSString *best = nil;
    NSInteger bestScore = 0;
    for (NSString *href in raw) {
        // Anchors often carry &amp; in the query string; resolving it verbatim
        // sends the server a parameter literally named "amp;format".
        NSString *decodedHref = [self unescapeXML:href];
        NSString *lower = decodedHref.lowercaseString;
        if (lower.length == 0 || [lower hasPrefix:@"#"] || [lower hasPrefix:@"javascript:"] ||
            [lower hasPrefix:@"mailto:"] || [lower hasPrefix:@"data:"]) {
            continue;
        }
        NSString *absolute = [self absoluteURL:decodedHref base:baseURL];
        if (absolute.length == 0 || [absolute isEqualToString:baseURL]) continue;
        NSURL *url = [NSURL URLWithString:absolute];
        NSString *host = url.host.lowercaseString ?: @"";
        // Never send the downloader to an advert network, but a link on the
        // catalog's own host is always legitimate (some hosts contain words
        // like "yandex" in their name).
        BOOL advert = NO;
        if (!(host.length > 0 && [host isEqualToString:baseHost])) {
            for (NSString *needle in adHosts) {
                if (host.length > 0 && [host containsString:needle]) { advert = YES; break; }
            }
        }
        if (advert) continue;
        NSString *extension = url.path.pathExtension.lowercaseString;
        NSInteger score = 0;
        if ([known containsObject:extension]) score += 4;
        if ([lower containsString:@"/download"] || [lower containsString:@"getfile"] ||
            [lower containsString:@"format="] || [lower containsString:@"/files/"] ||
            [lower containsString:@"skach"]) {
            score += 3;
        }
        if (host.length > 0 && [host isEqualToString:baseHost]) score += 2;
        if ([lower containsString:@"fb2"] || [lower containsString:@"epub"]) score += 1;
        if (score > bestScore) {
            bestScore = score;
            best = absolute;
        }
    }
    return bestScore >= 4 ? best : nil;
}

/// Derives the direct file endpoints used by common OPDS engines when an entry
/// points at a book page (`/b/123/fb2`) instead of a file.
+ (NSArray<NSString *> *)derivedDownloadURLsForURL:(NSString *)entryURL {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    if (entryURL.length == 0) return result;
    NSURL *url = [NSURL URLWithString:entryURL];
    NSString *path = url.path ?: @"";
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:@"^(.*?/b/\\d+)(?:/[a-z0-9]+)?/?$"
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:NULL];
    NSTextCheckingResult *match = [regex firstMatchInString:path
                                                    options:0
                                                      range:NSMakeRange(0, path.length)];
    if (match) {
        NSString *root = [path substringWithRange:[match rangeAtIndex:1]];
        // Flibusta/Coollib/lib.rus.ec serve the file at /b/<id>/<format>; this
        // is the endpoint their own «Скачать» button points at. The older
        // /download/?format= form is tried afterwards as a fallback.
        for (NSString *format in @[@"fb2", @"epub", @"pdf", @"txt", @"mobi", @"djvu"]) {
            NSString *candidate = [NSString stringWithFormat:@"%@/%@", root, format];
            NSString *absolute = [self absoluteURL:candidate base:entryURL];
            if (absolute.length > 0) [result addObject:absolute];
        }
        for (NSString *format in @[@"fb2.zip", @"epub", @"pdf", @"txt.zip"]) {
            NSString *candidate = [NSString stringWithFormat:@"%@/download/?format=%@", root, format];
            NSString *absolute = [self absoluteURL:candidate base:entryURL];
            if (absolute.length > 0) [result addObject:absolute];
        }
        NSString *downloadPage = [self absoluteURL:[root stringByAppendingString:@"/download"] base:entryURL];
        if (downloadPage.length > 0) [result addObject:downloadPage];
    }
    if ([path hasSuffix:@"/download"]) {
        for (NSString *format in @[@"fb2.zip", @"epub"]) {
            NSString *separator = [entryURL containsString:@"?"] ? @"&" : @"?";
            [result addObject:[entryURL stringByAppendingFormat:@"%@format=%@", separator, format]];
        }
    }
    return result;
}

/// Books servers often reject anonymous files unless the request looks like it
/// came from the book page.
+ (NSString *)refererForURL:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *path = url.path ?: @"";
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:@"(/b/\\d+)" options:0 error:NULL];
    NSTextCheckingResult *match = [regex firstMatchInString:path
                                                    options:0
                                                      range:NSMakeRange(0, path.length)];
    if (match) {
        NSString *bookPath = [path substringWithRange:[match rangeAtIndex:1]];
        return [NSString stringWithFormat:@"%@://%@%@", url.scheme ?: @"https", url.host ?: @"", bookPath];
    }
    return urlString;
}

+ (NSError *)validateDownloadedFile:(NSString *)path
                            sourceURL:(nullable NSString *)sourceURL
                             catalog:(nullable NSDictionary *)catalog {
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
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"]) return nil;
    if ([ext isEqualToString:@"txt"] || [ext isEqualToString:@"md"]) {
        if (![ORText looksLikeHTML:data]) return nil;
    }
    if ([ext isEqualToString:@"fb2"] || [ext isEqualToString:@"xml"]) {
        NSData *marker = [@"<FictionBook" dataUsingEncoding:NSUTF8StringEncoding];
        if ([data rangeOfData:marker options:0 range:NSMakeRange(0, MIN(data.length, (NSUInteger)4096))].location != NSNotFound) {
            return nil;
        }
    }
    if (zip || rar || pdf || mobi || djvu || audio) return nil;
    if ([ORText looksLikeHTML:data]) {
        NSString *page = [ORText stripHTML:[ORText stringFromData:data]];
        if (page.length > 200) page = [[page substringToIndex:200] stringByAppendingString:@"..."];

        // Check for known catalogs that require login
        NSString *host = [NSURL URLWithString:sourceURL].host.lowercaseString ?: @"";
        if ([host containsString:@"lib.rus.ec"] || [host containsString:@"flibusta.is"]) {
            return [NSError errorWithDomain:@"OmniReader.OPDS" code:5
                               userInfo:@{NSLocalizedDescriptionKey:
                                           [NSString stringWithFormat:
                                            @"Каталог %@ требует входа в аккаунт для скачивания.\n\n"
                                            "Этот каталог больше не отдаёт книги анонимно. "
                                            "Рекомендуем использовать зеркало coollib.in (добавьте его в каталоги: https://coollib.in/opds), "
                                            "которое работает без авторизации.", host ?: @"lib.rus.ec/flibusta.is"]}];
        }

        return [NSError errorWithDomain:@"OmniReader.OPDS" code:5
                               userInfo:@{NSLocalizedDescriptionKey:
                                           [NSString stringWithFormat:
                                            @"Каталог вернул веб-страницу вместо файла:\n\n%@\n\n"
                                             "Скорее всего, сайт показывает кнопку или обратный отсчёт. "
                                             "Можно повторить загрузку или открыть книгу в Safari.", page]}];
    }
    return [NSError errorWithDomain:@"OmniReader.OPDS" code:6
                           userInfo:@{NSLocalizedDescriptionKey: @"Файл не является книгой в известном формате."}];
}

+ (NSString *)browserUserAgent {
    return @"Mozilla/5.0 (iPhone; CPU iPhone OS 12_5 like Mac OS X) "
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1 Mobile/15E148 Safari/604.1";
}

+ (NSDictionary *)headersForCatalog:(NSDictionary *)catalog {
    NSMutableDictionary *headers =
        [@{@"Accept": @"application/atom+xml,application/xml,*/*",
           @"User-Agent": [self browserUserAgent]} mutableCopy];
    NSString *user = catalog[@"user"];
    if (user.length > 0) {
        NSString *password = [[ORSettings shared] passwordForOPDSCatalog:catalog[@"id"] ?: @""] ?: @"";
        headers[@"Authorization"] = [ORHTTP basicAuthorizationForUser:user password:password];
    }
    return headers;
}

/// Downloads are attempted anonymously by default; saved credentials are only
/// attached when the user entered them explicitly for this catalog.
+ (NSDictionary *)downloadHeadersForCatalog:(NSDictionary *)catalog
                                      referer:(NSString *)referer
                            includeCredentials:(BOOL)includeCredentials {
    NSMutableDictionary *headers =
        [@{@"Accept": @"application/octet-stream,application/fb2+xml,application/epub+zip,"
                       "application/zip,text/plain,*/*",
           @"Accept-Language": @"ru,en;q=0.9",
           @"User-Agent": [self browserUserAgent]} mutableCopy];
    NSString *user = catalog[@"user"];
    if (includeCredentials && user.length > 0) {
        NSString *password = [[ORSettings shared] passwordForOPDSCatalog:catalog[@"id"] ?: @""] ?: @"";
        headers[@"Authorization"] = [ORHTTP basicAuthorizationForUser:user password:password];
    }
    if (referer.length > 0) {
        headers[@"Referer"] = referer;
    } else if ([catalog[@"url"] isKindOfClass:[NSString class]]) {
        headers[@"Referer"] = catalog[@"url"];
    }
    return headers;
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
        NSDictionary *feed = [self isHTMLCatalogURL:urlString]
            ? [self feedFromHTMLCatalogData:data baseURL:urlString]
            : [self parseFeedData:data baseURL:urlString];
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
            // Flibusta/lib.rus.ec publish <rights>Заблокировано!</rights> for
            // books the catalogue refuses to serve; knowing this up front keeps
            // the downloader from chasing a landing page that has no file.
            NSString *rights = [[entryNode firstChildNamed:@"rights"] innerText];
            if (rights.length > 0) entry[@"rights"] = rights;

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

    // Some catalogues advertise a book but refuse to hand out the file. The
    // feed says so in <rights>; fail with that text instead of downloading a
    // landing page and reporting a generic "server returned a web page".
    NSString *rights = entry[@"rights"];
    if (rights.length > 0) {
        NSString *lower = rights.lowercaseString;
        if ([lower containsString:@"заблок"] || [lower containsString:@"blocked"] ||
            [lower containsString:@"недоступ"] || [lower containsString:@"unavailable"] ||
            [lower containsString:@"нет файла"]) {
            completion(nil, nil, [NSError errorWithDomain:@"OmniReader.OPDS" code:8
                                                userInfo:@{NSLocalizedDescriptionKey:
                                                               [NSString stringWithFormat:
                                                                @"Каталог не отдаёт эту книгу: %@\n\n"
                                                                 "Это ограничение самого каталога, а не приложения. "
                                                                 "Можно открыть страницу книги в Safari и скачать вручную.",
                                                                rights]}]);
            return;
        }
    }

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
    // 3. A link whose URL clearly points at a book file.
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
    // 4. A book page: download it once, then follow the file link it contains.
    //    lib.rus.ec/flibusta OPDS entries often point at /b/<id>, not at the file.
    if (!chosen) {
        for (NSDictionary *link in links) {
            NSString *href = link[@"href"] ?: @"";
            NSString *path = [NSURL URLWithString:href].path ?: @"";
            NSRange range = [path rangeOfString:@"/b/\\d+"
                                        options:NSRegularExpressionSearch];
            if (range.location != NSNotFound) {
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

    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    NSArray<NSString *> *derived = [self derivedDownloadURLsForURL:href];
    BOOL bookPage = [href rangeOfString:@"/b/\\d+" options:NSRegularExpressionSearch].location != NSNotFound;
    if (bookPage) {
        // Try the direct endpoints first: it avoids the Flibusta/lib.rus.ec
        // interstitial page the anonymous downloader would otherwise have to
        // parse (and which sometimes contains only a countdown script).
        [candidates addObjectsFromArray:derived];
        [candidates addObject:href];
    } else {
        [candidates addObject:href];
        [candidates addObjectsFromArray:derived];
    }

    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    __block NSInteger hops = 0;
    __block BOOL finished = NO;
    __block NSError *lastError = nil;
    __block void (^tryCandidate)(void) = nil;
    __block void (^attempt)(NSString *url, NSString *ext, BOOL includeCredentials) = nil;

    attempt = ^(NSString *url, NSString *ext, BOOL includeCredentials) {
        if (finished || url.length == 0) return;
        // The credential retry targets the same URL, so key the visited set by
        // authentication mode to let it through exactly once.
        NSString *visitKey = includeCredentials ? [@"auth:" stringByAppendingString:url] : url;
        if ([visited containsObject:visitKey]) {
            if (tryCandidate) tryCandidate();
            return;
        }
        [visited addObject:visitKey];
        NSString *destination = [[ORPaths cacheDirectory] stringByAppendingPathComponent:
                                    [NSString stringWithFormat:@"opds-%@.%@", [ORUtil uniqueKey], ext]];
        [ORHTTP download:url
                 headers:[self downloadHeadersForCatalog:catalog
                                                  referer:[self refererForURL:url]
                                        includeCredentials:includeCredentials]
                  toPath:destination
              completion:^(NSString *path, NSError *error) {
            if (finished) return;
            if (error) {
                // Anonymous attempt failed with an auth status: retry once with
                // saved credentials if the user actually entered them.
                NSString *user = catalog[@"user"];
                BOOL authFailure = (error.code == 401 || error.code == 403);
                if (authFailure && !includeCredentials && user.length > 0) {
                    attempt(url, ext, YES);
                    return;
                }
                lastError = error;
                if (tryCandidate) tryCandidate();
                return;
            }
            // Catalogs often answer with an HTML page instead of the book (login
            // wall, "file moved", anti-leech, countdown). Follow the real link.
            NSError *validationError = [self validateDownloadedFile:path
                                                           sourceURL:url
                                                            catalog:catalog];
            if (!validationError) {
                finished = YES;
                NSString *base = entry[@"title"] ?: @"book";
                completion(path, [NSString stringWithFormat:@"%@.%@", base, ext], nil);
                return;
            }
            lastError = validationError;
            NSData *payload = [NSData dataWithContentsOfFile:path
                                                     options:NSDataReadingMappedIfSafe
                                                       error:NULL];
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            NSString *next = [self downloadLinkInHTML:payload baseURL:url];
            if (next.length > 0 && hops < 5 && ![visited containsObject:next]) {
                hops += 1;
                NSString *nextExtension = [NSURL URLWithString:next].path.pathExtension.lowercaseString;
                attempt(next, [known containsObject:nextExtension] ? nextExtension : ext, includeCredentials);
                return;
            }
            if (tryCandidate) tryCandidate();
        }];
    };

    tryCandidate = ^{
        if (finished) return;
        if (candidates.count == 0) {
            finished = YES;
            completion(nil, nil, lastError ?: [NSError errorWithDomain:@"OmniReader.OPDS" code:3
                                                             userInfo:@{NSLocalizedDescriptionKey:
                                                                            @"Не удалось скачать файл из каталога."}]);
            return;
        }
        NSString *nextURL = candidates.firstObject;
        [candidates removeObjectAtIndex:0];
        NSString *nextExtension = [NSURL URLWithString:nextURL].path.pathExtension.lowercaseString;
        attempt(nextURL, [known containsObject:nextExtension] ? nextExtension : extension, NO);
    };

    attempt(href, extension, NO);
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
        NSString *rights = [ORText firstMatchPattern:@"(?is)<rights[^>]*>(.*?)</rights>"
                                            inString:chunk
                                               group:1];
        rights = [[self unescapeXML:[ORText stripHTML:rights ?: @""]]
                  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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
        if (rights.length > 0) entry[@"rights"] = rights;
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

#pragma mark - HTML catalogs (so.11klasov.net)

/// so.11klasov.net publishes no OPDS feed: it is a plain PHP/JS site. The app
/// turns its class and subject pages into the same feed dictionaries the rest
/// of the OPDS browser consumes, so covers, downloading and navigation work
/// without a server-side proxy.
+ (BOOL)isHTMLCatalogURL:(NSString *)urlString {
    NSString *host = [NSURL URLWithString:urlString].host.lowercaseString ?: @"";
    return [host isEqualToString:@"so.11klasov.net"] || [host hasSuffix:@".11klasov.net"];
}

+ (NSString *)absoluteImageURL:(NSString *)href base:(NSString *)baseURL {
    if (href.length == 0) return nil;
    if ([href hasPrefix:@"//"]) return [@"https:" stringByAppendingString:href];
    if ([href hasPrefix:@"http://"] || [href hasPrefix:@"https://"]) return href;
    return [self absoluteURL:href base:baseURL];
}

+ (NSString *)elevenklasovTitleFromHTML:(NSString *)html {
    NSString *heading = [ORText firstMatchPattern:@"(?is)<h1[^>]*>(.*?)</h1>" inString:html group:1];
    heading = [ORText decodeEntities:[ORText stripHTML:heading ?: @""]];
    heading = [heading stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (heading.length > 0) return heading;
    NSString *title = [ORText firstMatchPattern:@"(?is)<title[^>]*>(.*?)</title>" inString:html group:1];
    title = [ORText decodeEntities:[ORText stripHTML:title ?: @""]];
    return [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSDictionary *)elevenklasovFeedFromData:(NSData *)data baseURL:(NSString *)baseURL {
    NSString *html = [ORText stringFromData:data];
    if (html.length == 0) return nil;
    NSURL *base = [NSURL URLWithString:baseURL];
    NSString *host = base.host ?: @"so.11klasov.net";
    NSString *scheme = base.scheme ?: @"https";
    NSString *origin = [NSString stringWithFormat:@"%@://%@", scheme, host];
    NSString *path = base.path ?: @"/";

    NSMutableDictionary *feed = [NSMutableDictionary dictionary];
    feed[@"baseURL"] = baseURL;
    feed[@"links"] = @[];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];

    BOOL root = (path.length == 0 || [path isEqualToString:@"/"]);

    if (root) {
        feed[@"title"] = @"Школьные учебники";
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:
            @"<a\\b[^>]*href=\"(/[a-z0-9-]+/)\"[^>]*>([\\s\\S]*?)</a>"
            options:NSRegularExpressionCaseInsensitive
              error:NULL];
        NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:html
                                                                  options:0
                                                                    range:NSMakeRange(0, html.length)];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        NSMutableArray<NSDictionary *> *classes = [NSMutableArray array];
        NSMutableArray<NSDictionary *> *exams = [NSMutableArray array];
        NSMutableArray<NSDictionary *> *subjects = [NSMutableArray array];

        for (NSTextCheckingResult *match in matches) {
            if (match.numberOfRanges < 3) continue;
            NSString *href = [html substringWithRange:[match rangeAtIndex:1]];
            if ([seen containsObject:href]) continue;
            [seen addObject:href];
            NSString *slug = [href stringByTrimmingCharactersInSet:
                                  [NSCharacterSet characterSetWithCharactersInString:@"/"]];
            NSString *label = [ORText stripHTML:[html substringWithRange:[match rangeAtIndex:2]]];
            label = [ORText decodeEntities:label ?: @""];
            BOOL isClass = [slug hasSuffix:@"-klass"] &&
                [slug rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location == 0;
            // Subject anchors carry the number of books in <i>, so the stripped
            // label reads "Математика1348"; drop that counter. Class labels are
            // pure digits, and they stay untouched.
            if (!isClass) {
                label = [ORText replacePattern:@"\\s*\\d+\\s*$" inString:label withTemplate:@""];
            }
            label = [label stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (label.length == 0) label = slug;

            NSString *title = label;
            NSInteger group = 2; // 0 = classes, 1 = exam categories, 2 = subjects
            if (isClass) {
                title = [NSString stringWithFormat:@"%@ класс", label];
                group = 0;
            } else if ([slug isEqualToString:@"giaoge"] || [slug isEqualToString:@"ege"] ||
                       [slug isEqualToString:@"vpr"] || [slug isEqualToString:@"gdz"]) {
                group = 1;
            }
            NSString *absolute = [self absoluteURL:href base:origin] ?: href;
            NSDictionary *entry = @{
                @"title": title.length > 0 ? title : slug,
                @"id": absolute,
                @"navigation": @YES,
                @"acquisition": @NO,
                @"links": @[@{@"rel": @"subsection", @"type": @"application/atom+xml", @"href": absolute}]
            };
            if (group == 0) [classes addObject:entry];
            else if (group == 1) [exams addObject:entry];
            else [subjects addObject:entry];
        }

        [classes sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSInteger left = [(NSString *)a[@"title"] integerValue];
            NSInteger right = [(NSString *)b[@"title"] integerValue];
            if (left == right) return NSOrderedSame;
            return left < right ? NSOrderedAscending : NSOrderedDescending;
        }];
        [entries addObjectsFromArray:classes];
        [entries addObjectsFromArray:exams];
        [entries addObjectsFromArray:subjects];
        if (entries.count == 0) return nil;
        feed[@"entries"] = entries;
        return feed;
    }

    // A class or subject page: 24 book cards per page.
    NSString *title = [self elevenklasovTitleFromHTML:html];
    feed[@"title"] = title.length > 0 ? title : @"Учебники";

    NSArray<NSString *> *cards = [ORText matchesPattern:
        @"(?is)<article\\b[^>]*class=\"card\"[^>]*>(.*?)</article>"
                                               inString:html
                                                  group:1];
    for (NSString *chunk in cards) {
        NSString *bookHref = [ORText firstMatchPattern:@"href=\"([^\"]+)\"" inString:chunk group:1];
        if (bookHref.length == 0) continue;
        bookHref = [self absoluteURL:[ORText decodeEntities:bookHref] base:baseURL];

        NSString *cover = [ORText firstMatchPattern:@"<img[^>]+src=\"([^\"]+)\"" inString:chunk group:1];
        cover = [self absoluteImageURL:cover base:baseURL];

        NSString *rawTitle = [ORText firstMatchPattern:
            @"class=\"name th-title\"><a[^>]*>([\\s\\S]*?)</a>" inString:chunk group:1];
        rawTitle = [ORText decodeEntities:[ORText stripHTML:rawTitle ?: @""]];
        rawTitle = [rawTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (rawTitle.length == 0) continue;

        NSString *year = [ORText firstMatchPattern:@"class=\"yr\">([^<]*)<" inString:chunk group:1];
        NSString *fmt = [ORText firstMatchPattern:@"class=\"fmt\">([^<]*)<" inString:chunk group:1];
        year = [year stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        fmt = [fmt stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        // Cards use «Название - Автор»; split at the last dash.
        NSString *bookTitle = rawTitle;
        NSString *author = @"";
        NSRange dash = [rawTitle rangeOfString:@" - " options:NSBackwardsSearch];
        if (dash.location != NSNotFound) {
            NSString *tail = [[rawTitle substringFromIndex:dash.location + dash.length]
                              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (tail.length > 1 && tail.length < 90) {
                author = tail;
                bookTitle = [[rawTitle substringToIndex:dash.location]
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        }

        NSMutableArray<NSString *> *summaryParts = [NSMutableArray array];
        if (fmt.length > 0) [summaryParts addObject:fmt.uppercaseString];
        if (year.length > 0) [summaryParts addObject:year];
        NSString *summary = [summaryParts componentsJoinedByString:@" · "];

        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"title"] = bookTitle.length > 0 ? bookTitle : rawTitle;
        if (author.length > 0) entry[@"author"] = author;
        if (summary.length > 0) entry[@"summary"] = summary;
        entry[@"id"] = bookHref;
        if (cover.length > 0) entry[@"image"] = cover;
        entry[@"navigation"] = @NO;
        entry[@"acquisition"] = @YES;
        // The list page has no direct file link: the downloader opens the book
        // page (HTML) and follows its «Скачать» button.
        entry[@"links"] = @[
            @{@"rel": @"alternate", @"type": @"text/html", @"href": bookHref},
            @{@"rel": @"acquisition", @"type": @"application/octet-stream", @"href": bookHref}
        ];
        [entries addObject:entry];
    }

    // Pagination: expose the next page as a navigation entry.
    NSInteger currentPage = 1;
    NSString *pageValue = [ORText firstMatchPattern:@"(?i)/page/(\\d+)/?$" inString:path group:1];
    if (pageValue.length > 0) currentPage = pageValue.integerValue;

    NSRegularExpression *pageRegex = [NSRegularExpression regularExpressionWithPattern:
        @"href=\"([^\"]*/page/(\\d+)/?)\"" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSArray<NSTextCheckingResult *> *pageMatches = [pageRegex matchesInString:html
                                                                     options:0
                                                                       range:NSMakeRange(0, html.length)];
    NSString *nextHref = nil;
    for (NSTextCheckingResult *match in pageMatches) {
        if (match.numberOfRanges < 3) continue;
        NSString *href = [html substringWithRange:[match rangeAtIndex:1]];
        NSInteger number = [html substringWithRange:[match rangeAtIndex:2]].integerValue;
        if (number == currentPage + 1) {
            nextHref = [self absoluteURL:[ORText decodeEntities:href] base:baseURL];
            break;
        }
    }
    if (nextHref.length > 0) {
        [entries addObject:@{
            @"title": @"Следующая страница →",
            @"id": nextHref,
            @"navigation": @YES,
            @"acquisition": @NO,
            @"links": @[@{@"rel": @"subsection", @"type": @"application/atom+xml", @"href": nextHref}]
        }];
    }

    if (entries.count == 0) return nil;
    feed[@"entries"] = entries;
    return feed;
}

+ (NSDictionary *)feedFromHTMLCatalogData:(NSData *)data baseURL:(NSString *)baseURL {
    return [self elevenklasovFeedFromData:data baseURL:baseURL];
}

@end
