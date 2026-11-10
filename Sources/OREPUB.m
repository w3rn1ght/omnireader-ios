#import "OREPUB.h"
#import "ORText.h"
#import "ORUtil.h"
#import "ORXML.h"
#import "ORZip.h"

static NSString *ORRegexReplaceWithBlock(NSString *source,
                                         NSString *pattern,
                                         NSString *(^builder)(NSTextCheckingResult *match, NSString *source)) {
    if (source.length == 0 || pattern.length == 0) return source ?: @"";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    if (!regex) return source;
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:source options:0 range:NSMakeRange(0, source.length)];
    if (matches.count == 0) return source;
    NSMutableString *result = [source mutableCopy];
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSString *replacement = builder(match, source);
        if (!replacement) continue;
        [result replaceCharactersInRange:match.range withString:replacement];
    }
    return result;
}

static NSString *ORMatchGroup(NSTextCheckingResult *match, NSString *source, NSInteger index) {
    if (index < 0 || index >= (NSInteger)match.numberOfRanges) return @"";
    NSRange range = [match rangeAtIndex:(NSUInteger)index];
    if (range.location == NSNotFound) return @"";
    return [source substringWithRange:range];
}

static NSString *ORSanitiseKey(NSString *key) {
    NSString *safe = [key stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    safe = [safe stringByReplacingOccurrencesOfString:@"\\" withString:@"_"];
    safe = [safe stringByReplacingOccurrencesOfString:@".." withString:@"_"];
    return safe.length > 0 ? safe : @"book";
}

@interface OREPUB ()
@property (nonatomic, strong) ORZip *zip;
@property (nonatomic, copy) NSString *opfPath;
@property (nonatomic, copy) NSString *opfDirectory;
@property (nonatomic, strong) NSDictionary<NSString *, NSDictionary *> *manifest;
@property (nonatomic, copy) NSArray<NSString *> *spinePaths;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *chapterIndexByPath;
@end

@implementation OREPUB

+ (instancetype)bookAtPath:(NSString *)path cacheKey:(NSString *)cacheKey error:(NSError **)error {
    NSError *zipError = nil;
    ORZip *zip = [ORZip zipWithURL:[NSURL fileURLWithPath:path] error:&zipError];
    if (!zip) {
        if (error) *error = zipError ?: [NSError errorWithDomain:@"OmniReader.EPUB" code:1
                                                        userInfo:@{NSLocalizedDescriptionKey: @"Не удалось открыть EPUB"}];
        return nil;
    }

    NSString *root = [[ORPaths extractedDirectory] stringByAppendingPathComponent:ORSanitiseKey(cacheKey)];
    NSString *marker = [root stringByAppendingPathComponent:@".omnireader-ready"];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL ready = [fm fileExistsAtPath:marker] &&
                 [fm fileExistsAtPath:[root stringByAppendingPathComponent:@"META-INF/container.xml"]];

    if (!ready) {
        [fm removeItemAtPath:root error:NULL];
        [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL];
        NSError *extractError = nil;
        if (![zip extractToDirectory:root error:&extractError]) {
            if (error) *error = extractError;
            return nil;
        }
        [[NSDate date].description writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }

    OREPUB *book = [[OREPUB alloc] init];
    book.zip = zip;
    book.rootDirectory = root;
    if (![book loadPackage:error]) return nil;
    [book buildContent];
    return book;
}

- (NSString *)resolvePath:(NSString *)href relativeTo:(NSString *)baseDirectory {
    if (href.length == 0) return @"";
    NSRange hash = [href rangeOfString:@"#"];
    if (hash.location != NSNotFound) href = [href substringToIndex:hash.location];
    NSRange query = [href rangeOfString:@"?"];
    if (query.location != NSNotFound) href = [href substringToIndex:query.location];
    href = [href stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (href.length == 0) return @"";
    NSString *decoded = [href stringByRemovingPercentEncoding] ?: href;
    if ([decoded hasPrefix:@"/"]) decoded = [decoded substringFromIndex:1];
    NSString *combined = baseDirectory.length > 0 ? [baseDirectory stringByAppendingPathComponent:decoded] : decoded;
    combined = [combined stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in [combined componentsSeparatedByString:@"/"]) {
        if (part.length == 0 || [part isEqualToString:@"."]) continue;
        if ([part isEqualToString:@".."]) {
            if (parts.count > 0) [parts removeLastObject];
            continue;
        }
        [parts addObject:part];
    }
    return [parts componentsJoinedByString:@"/"];
}

- (nullable NSData *)dataForPath:(NSString *)path {
    if (path.length == 0) return nil;
    NSString *decoded = [path stringByRemovingPercentEncoding] ?: path;
    NSData *data = [self.zip dataForEntry:decoded error:NULL];
    if (!data && ![decoded isEqualToString:path]) {
        data = [self.zip dataForEntry:path error:NULL];
    }
    return data;
}

- (BOOL)loadPackage:(NSError **)error {
    NSData *containerData = [self dataForPath:@"META-INF/container.xml"];
    if (!containerData) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.EPUB" code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"В EPUB нет META-INF/container.xml"}];
        return NO;
    }
    NSString *containerText = [ORText stringFromData:containerData];
    ORXMLNode *container = [ORXML parseString:containerText error:NULL];
    ORXMLNode *rootfile = [container descendantsNamed:@"rootfile"].firstObject;
    NSString *opfPath = [rootfile attr:@"full-path"];
    if (opfPath.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.EPUB" code:3
                                            userInfo:@{NSLocalizedDescriptionKey: @"Не удалось найти OPF-манифест"}];
        return NO;
    }
    self.opfPath = opfPath;
    self.opfDirectory = [opfPath stringByDeletingLastPathComponent];
    if ([self.opfDirectory isEqualToString:opfPath]) self.opfDirectory = @"";

    NSData *opfData = [self dataForPath:opfPath];
    if (!opfData) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.EPUB" code:4
                                            userInfo:@{NSLocalizedDescriptionKey: @"OPF-файл не найден"}];
        return NO;
    }
    ORXMLNode *package = [ORXML parseString:[ORText stringFromData:opfData] error:NULL];
    if (!package) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.EPUB" code:5
                                            userInfo:@{NSLocalizedDescriptionKey: @"Не удалось разобрать OPF"}];
        return NO;
    }

    ORXMLNode *metadata = [package firstChildNamed:@"metadata"];
    NSString *title = [[metadata firstChildNamed:@"title"] innerText];
    NSArray<ORXMLNode *> *creators = [metadata childrenNamed:@"creator"];
    NSMutableArray<NSString *> *authorParts = [NSMutableArray array];
    for (ORXMLNode *creator in creators) {
        NSString *value = [creator innerText];
        if (value.length > 0) [authorParts addObject:value];
    }
    self.title = title ?: @"";
    self.author = [authorParts componentsJoinedByString:@", "];

    NSMutableDictionary *manifest = [NSMutableDictionary dictionary];
    ORXMLNode *manifestNode = [package firstChildNamed:@"manifest"];
    for (ORXMLNode *item in [manifestNode childrenNamed:@"item"]) {
        NSString *itemID = [item attr:@"id"];
        NSString *href = [item attr:@"href"];
        if (itemID.length == 0 || href.length == 0) continue;
        manifest[itemID] = @{
            @"href": href,
            @"type": [item attr:@"media-type"] ?: @"",
            @"properties": [item attr:@"properties"] ?: @"",
            @"path": [self resolvePath:href relativeTo:self.opfDirectory]
        };
    }
    self.manifest = manifest;

    NSMutableDictionary *pathMap = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *spine = [NSMutableArray array];
    ORXMLNode *spineNode = [package firstChildNamed:@"spine"];
    for (ORXMLNode *itemref in [spineNode childrenNamed:@"itemref"]) {
        NSString *idref = [itemref attr:@"idref"];
        NSDictionary *item = manifest[idref];
        NSString *path = item[@"path"];
        if (path.length == 0) continue;
        pathMap[path.lowercaseString] = @(spine.count);
        [spine addObject:path];
    }
    self.spinePaths = spine;
    self.chapterIndexByPath = pathMap;

    [self resolveCoverUsingMetadata:metadata manifest:manifest package:package];
    self.toc = [self parseTOCWithPackage:package spineNode:spineNode];
    return YES;
}

- (void)resolveCoverUsingMetadata:(ORXMLNode *)metadata
                        manifest:(NSDictionary<NSString *, NSDictionary *> *)manifest
                         package:(ORXMLNode *)package {
    NSString *coverID = nil;
    for (ORXMLNode *meta in [metadata childrenNamed:@"meta"]) {
        NSString *name = [meta attr:@"name"];
        if ([name.lowercaseString isEqualToString:@"cover"]) {
            coverID = [meta attr:@"content"];
            break;
        }
    }
    NSDictionary *item = coverID ? manifest[coverID] : nil;
    if (!item) {
        for (NSString *key in manifest) {
            NSDictionary *candidate = manifest[key];
            NSString *properties = [candidate[@"properties"] lowercaseString];
            NSString *type = [candidate[@"type"] lowercaseString];
            if ([properties containsString:@"cover-image"] || [key.lowercaseString containsString:@"cover"]) {
                if ([type hasPrefix:@"image/"]) {
                    item = candidate;
                    break;
                }
            }
        }
    }
    if (!item) {
        // EPUB2 guide
        ORXMLNode *guide = [package firstChildNamed:@"guide"];
        for (ORXMLNode *reference in [guide childrenNamed:@"reference"]) {
            if ([[[reference attr:@"type"] lowercaseString] isEqualToString:@"cover"]) {
                NSString *href = [reference attr:@"href"];
                NSString *path = [self resolvePath:href relativeTo:self.opfDirectory];
                item = @{@"path": path, @"type": @"image/jpeg"};
                break;
            }
        }
    }
    if (!item) return;
    NSString *path = item[@"path"];
    NSData *data = [self dataForPath:path];
    if (!data || data.length < 64) return;

    NSString *extension = path.pathExtension.lowercaseString;
    if (extension.length == 0) extension = @"jpg";
    NSString *coverPath = [self.rootDirectory stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"__cover.%@", extension]];
    if ([data writeToFile:coverPath atomically:YES]) {
        self.coverImagePath = coverPath;
    }
}

#pragma mark - TOC

- (NSArray<ORTOCItem *> *)parseTOCWithPackage:(ORXMLNode *)package spineNode:(ORXMLNode *)spineNode {
    // EPUB3 navigation document
    for (NSString *key in self.manifest) {
        NSDictionary *item = self.manifest[key];
        NSString *properties = [item[@"properties"] lowercaseString];
        if (![properties containsString:@"nav"]) continue;
        NSData *data = [self dataForPath:item[@"path"]];
        if (!data) continue;
        ORXMLNode *navDoc = [ORXML parseString:[ORText stringFromData:data] error:NULL];
        ORXMLNode *nav = nil;
        for (ORXMLNode *candidate in [navDoc descendantsNamed:@"nav"]) {
            NSString *type = [candidate attr:@"type"];
            if (type.length == 0 || [type.lowercaseString containsString:@"toc"]) {
                nav = candidate;
                break;
            }
        }
        if (!nav) continue;
        NSMutableArray *items = [NSMutableArray array];
        NSString *navDir = [item[@"path"] stringByDeletingLastPathComponent];
        ORXMLNode *list = [nav firstChildNamed:@"ol"];
        [self appendNavigationList:list directory:navDir level:0 into:items];
        if (items.count > 0) return items;
    }

    // EPUB2 NCX
    NSString *tocID = [spineNode attr:@"toc"];
    NSDictionary *ncxItem = tocID ? self.manifest[tocID] : nil;
    if (!ncxItem) {
        for (NSString *key in self.manifest) {
            if ([key.lowercaseString isEqualToString:@"ncx"] ||
                [self.manifest[key][@"type"] isEqualToString:@"application/x-dtbncx+xml"]) {
                ncxItem = self.manifest[key];
                break;
            }
        }
    }
    if (ncxItem) {
        NSData *data = [self dataForPath:ncxItem[@"path"]];
        if (data) {
            ORXMLNode *ncx = [ORXML parseString:[ORText stringFromData:data] error:NULL];
            ORXMLNode *navMap = [ncx firstChildNamed:@"navmap"];
            NSMutableArray *items = [NSMutableArray array];
            NSString *ncxDir = [ncxItem[@"path"] stringByDeletingLastPathComponent];
            for (ORXMLNode *point in [navMap childrenNamed:@"navpoint"]) {
                [self appendNavPoint:point directory:ncxDir level:0 into:items];
            }
            if (items.count > 0) return items;
        }
    }

    // Fallback: one entry per spine document.
    NSMutableArray *fallback = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.spinePaths.count; i++) {
        [fallback addObject:[ORTOCItem itemWithTitle:[NSString stringWithFormat:@"Раздел %lu", (unsigned long)i + 1]
                                               level:0
                                              anchor:[NSString stringWithFormat:@"ch-%lu", (unsigned long)i]]];
    }
    return fallback;
}

- (void)appendNavigationList:(ORXMLNode *)list
                   directory:(NSString *)directory
                       level:(NSInteger)level
                        into:(NSMutableArray<ORTOCItem *> *)items {
    if (!list) return;
    for (ORXMLNode *item in [list childrenNamed:@"li"]) {
        ORXMLNode *link = [item firstChildNamed:@"a"];
        NSString *href = [link attr:@"href"];
        NSString *title = [link innerText];
        if (title.length == 0) title = [[item firstChildNamed:@"span"] innerText];
        NSString *anchor = [self anchorForHref:href directory:directory];
        if (anchor.length > 0) {
            [items addObject:[ORTOCItem itemWithTitle:title level:level anchor:anchor]];
        }
        ORXMLNode *nested = [item firstChildNamed:@"ol"];
        if (nested) {
            [self appendNavigationList:nested directory:directory level:level + 1 into:items];
        }
    }
}

- (void)appendNavPoint:(ORXMLNode *)point
             directory:(NSString *)directory
                 level:(NSInteger)level
                  into:(NSMutableArray<ORTOCItem *> *)items {
    ORXMLNode *label = [point firstChildNamed:@"navlabel"];
    NSString *title = [[label firstChildNamed:@"text"] innerText];
    ORXMLNode *content = [point firstChildNamed:@"content"];
    NSString *anchor = [self anchorForHref:[content attr:@"src"] directory:directory];
    if (anchor.length > 0) {
        [items addObject:[ORTOCItem itemWithTitle:title level:level anchor:anchor]];
    }
    for (ORXMLNode *child in [point childrenNamed:@"navpoint"]) {
        [self appendNavPoint:child directory:directory level:level + 1 into:items];
    }
}

- (NSString *)anchorForHref:(NSString *)href directory:(NSString *)directory {
    if (href.length == 0) return @"";
    NSString *fragment = @"";
    NSRange hash = [href rangeOfString:@"#"];
    if (hash.location != NSNotFound) {
        fragment = [href substringFromIndex:hash.location + 1];
        href = [href substringToIndex:hash.location];
    }
    if (href.length == 0) {
        // Same-document anchor — cannot reliably map, ignore.
        return @"";
    }
    NSString *resolved = [self resolvePath:href relativeTo:directory];
    NSNumber *index = self.chapterIndexByPath[resolved.lowercaseString];
    if (!index) return @"";
    NSString *decodedFragment = [fragment stringByRemovingPercentEncoding] ?: fragment;
    if (decodedFragment.length > 0) {
        return [NSString stringWithFormat:@"ch-%ld--%@", (long)index.integerValue, decodedFragment];
    }
    return [NSString stringWithFormat:@"ch-%ld", (long)index.integerValue];
}

#pragma mark - Content

- (void)buildContent {
    NSMutableString *body = [NSMutableString string];
    NSMutableString *css = [NSMutableString string];
    NSMutableSet<NSString *> *seenCSS = [NSMutableSet set];

    for (NSUInteger index = 0; index < self.spinePaths.count; index++) {
        @autoreleasepool {
            NSString *docPath = self.spinePaths[index];
            NSData *data = [self dataForPath:docPath];
            if (!data) continue;
            NSString *html = [ORText stringFromData:data];
            NSString *docDirectory = [docPath stringByDeletingLastPathComponent];
            if ([docDirectory isEqualToString:docPath]) docDirectory = @"";

            // Collect <style> blocks.
            for (NSString *style in [ORText matchesPattern:@"(?is)<style[^>]*>(.*?)</style>" inString:html group:1]) {
                if (style.length > 0 && ![seenCSS containsObject:style]) {
                    [seenCSS addObject:style];
                    [css appendString:style];
                    [css appendString:@"\n"];
                }
            }
            // Collect linked stylesheets.
            NSString *linkPattern = @"(?is)<link\\b[^>]*>";
            NSArray<NSString *> *links = [ORText matchesPattern:linkPattern inString:html group:0];
            for (NSString *link in links) {
                NSString *rel = [ORText firstMatchPattern:@"(?i)rel\\s*=\\s*[\"']([^\"']*)[\"']" inString:link group:1];
                if (![rel.lowercaseString containsString:@"stylesheet"]) continue;
                NSString *href = [ORText firstMatchPattern:@"(?i)href\\s*=\\s*[\"']([^\"']*)[\"']" inString:link group:1];
                if (href.length == 0) continue;
                NSString *cssPath = [self resolvePath:href relativeTo:docDirectory];
                NSData *cssData = [self dataForPath:cssPath];
                if (!cssData) continue;
                NSString *cssText = [self rewriteCSS:[ORText stringFromData:cssData] directory:cssPath.stringByDeletingLastPathComponent];
                if (cssText.length > 0 && ![seenCSS containsObject:cssText]) {
                    [seenCSS addObject:cssText];
                    [css appendString:cssText];
                    [css appendString:@"\n"];
                }
            }

            NSString *chapter = html;
            NSString *bodyMatch = [ORText firstMatchPattern:@"(?is)<body\\b[^>]*>(.*?)</body>" inString:html group:1];
            if (bodyMatch.length > 0) chapter = bodyMatch;
            chapter = [ORText replacePattern:@"(?is)<script\\b[^>]*>.*?</script>" inString:chapter withTemplate:@""];
            chapter = [ORText replacePattern:@"(?is)<style\\b[^>]*>.*?</style>" inString:chapter withTemplate:@""];
            chapter = [self rewriteChapter:chapter index:index docDirectory:docDirectory];

            [body appendFormat:@"<section id=\"ch-%lu\" data-chapter=\"%lu\" class=\"or-chapter\">%@</section>\n",
                               (unsigned long)index, (unsigned long)index, chapter];
        }
    }

    self.htmlBody = body;
    self.extraCSS = css;
    self.plainText = [ORText stripHTML:body];
}

- (NSString *)rewriteChapter:(NSString *)chapter index:(NSUInteger)index docDirectory:(NSString *)docDirectory {
    NSString *text = chapter;
    NSString *chapterPrefix = [NSString stringWithFormat:@"ch-%lu--", (unsigned long)index];

    // 1. Local fragment links.
    text = ORRegexReplaceWithBlock(text, @"(?i)href\\s*=\\s*\"#([^\"]*)\"", ^NSString *(NSTextCheckingResult *match, NSString *source) {
        NSString *fragment = ORMatchGroup(match, source, 1);
        return [NSString stringWithFormat:@"href=\"#%@%@\"", chapterPrefix, fragment];
    });
    text = ORRegexReplaceWithBlock(text, @"(?i)href\\s*=\\s*'#([^']*)'", ^NSString *(NSTextCheckingResult *match, NSString *source) {
        NSString *fragment = ORMatchGroup(match, source, 1);
        return [NSString stringWithFormat:@"href=\"#%@%@\"", chapterPrefix, fragment];
    });

    // 2. Links to other spine documents.
    NSString *crossPattern = @"(?i)href\\s*=\\s*\"([^\"#]+\\.(?:x?html?|xml))(?:#([^\"]*))?\"";
    text = ORRegexReplaceWithBlock(text, crossPattern, ^NSString *(NSTextCheckingResult *match, NSString *source) {
        NSString *path = ORMatchGroup(match, source, 1);
        NSString *fragment = ORMatchGroup(match, source, 2);
        NSString *resolved = [self resolvePath:path relativeTo:docDirectory];
        NSNumber *target = self.chapterIndexByPath[resolved.lowercaseString];
        if (!target) return nil;
        if (fragment.length > 0) {
            return [NSString stringWithFormat:@"href=\"#ch-%ld--%@\"", (long)target.integerValue, fragment];
        }
        return [NSString stringWithFormat:@"href=\"#ch-%ld\"", (long)target.integerValue];
    });

    // 3. Prefix element ids to keep the merged document valid.
    text = ORRegexReplaceWithBlock(text, @"(?i)(\\s)id\\s*=\\s*\"([^\"]*)\"", ^NSString *(NSTextCheckingResult *match, NSString *source) {
        NSString *spacing = ORMatchGroup(match, source, 1);
        NSString *identifier = ORMatchGroup(match, source, 2);
        return [NSString stringWithFormat:@"%@id=\"%@%@\"", spacing, chapterPrefix, identifier];
    });
    text = ORRegexReplaceWithBlock(text, @"(?i)(\\s)id\\s*=\\s*'([^']*)'", ^NSString *(NSTextCheckingResult *match, NSString *source) {
        NSString *spacing = ORMatchGroup(match, source, 1);
        NSString *identifier = ORMatchGroup(match, source, 2);
        return [NSString stringWithFormat:@"%@id=\"%@%@\"", spacing, chapterPrefix, identifier];
    });

    // 3b. Inline styles that pin text over the cover break pagination.
    text = ORRegexReplaceWithBlock(text, @"(?i)(\\s)style\\s*=\\s*\"([^\"]*)\"", ^NSString *(NSTextCheckingResult *match, NSString *source) {
        NSString *spacing = ORMatchGroup(match, source, 1);
        NSString *value = ORMatchGroup(match, source, 2);
        NSMutableArray<NSString *> *kept = [NSMutableArray array];
        for (NSString *rule in [value componentsSeparatedByString:@";"]) {
            NSString *trimmed = [rule stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length == 0) continue;
            NSString *lower = trimmed.lowercaseString;
            if ([lower hasPrefix:@"position"] || [lower hasPrefix:@"top"] ||
                [lower hasPrefix:@"left"] || [lower hasPrefix:@"right"] ||
                [lower hasPrefix:@"bottom"] || [lower hasPrefix:@"z-index"] ||
                [lower hasPrefix:@"float"] || [lower hasPrefix:@"margin-top"]) {
                continue;
            }
            [kept addObject:trimmed];
        }
        if (kept.count == 0) return @"";
        return [NSString stringWithFormat:@"%@style=\"%@\"", spacing, [kept componentsJoinedByString:@";"]];
    });

    // 4. Resources.
    text = ORRegexReplaceWithBlock(text, @"(?i)(src|poster)\\s*=\\s*\"([^\"]+)\"", ^NSString *(NSTextCheckingResult *match, NSString *source) {
        NSString *attribute = ORMatchGroup(match, source, 1);
        NSString *value = ORMatchGroup(match, source, 2);
        if ([ORUtil isWebURLString:value] || [value hasPrefix:@"#"] || [value hasPrefix:@"data:"]) return nil;
        NSString *path = [self resolvePath:value relativeTo:docDirectory];
        NSString *absolute = [self.rootDirectory stringByAppendingPathComponent:path];
        return [NSString stringWithFormat:@"%@=\"%@\"", attribute, [ORText fileURLString:absolute]];
    });
    text = ORRegexReplaceWithBlock(text, @"(?i)xlink:href\\s*=\\s*\"([^\"]+)\"", ^NSString *(NSTextCheckingResult *match, NSString *source) {
        NSString *value = ORMatchGroup(match, source, 1);
        if ([ORUtil isWebURLString:value] || [value hasPrefix:@"#"]) return nil;
        NSString *path = [self resolvePath:value relativeTo:docDirectory];
        if (path.length == 0) return nil;
        NSString *absolute = [self.rootDirectory stringByAppendingPathComponent:path];
        return [NSString stringWithFormat:@"xlink:href=\"%@\"", [ORText fileURLString:absolute]];
    });

    return text;
}

- (NSString *)rewriteCSS:(NSString *)css directory:(NSString *)directory {
    return ORRegexReplaceWithBlock(css, @"(?i)url\\(\\s*['\"]?([^'\")]+)['\"]?\\s*\\)", ^NSString *(NSTextCheckingResult *match, NSString *source) {
        NSString *value = [ORMatchGroup(match, source, 1) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (value.length == 0 || [ORUtil isWebURLString:value] || [value hasPrefix:@"#"] || [value hasPrefix:@"data:"]) return nil;
        NSString *path = [self resolvePath:value relativeTo:directory];
        if (path.length == 0) return nil;
        NSString *absolute = [self.rootDirectory stringByAppendingPathComponent:path];
        return [NSString stringWithFormat:@"url(\"%@\")", [ORText fileURLString:absolute]];
    });
}

@end
