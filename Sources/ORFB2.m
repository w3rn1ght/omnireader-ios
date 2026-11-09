#import "ORFB2.h"
#import "ORText.h"
#import "ORUtil.h"
#import "ORXML.h"
#import "ORZip.h"

static NSData *ORFB2LoadPayload(NSString *path, NSError **error) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.FB2" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Не удалось прочитать файл"}];
        return nil;
    }
    if (![ORText looksLikeZIP:data]) return data;
    ORZip *zip = [ORZip zipWithURL:[NSURL fileURLWithPath:path] error:error];
    if (!zip) return nil;
    NSString *target = nil;
    for (NSString *name in zip.names) {
        NSString *lower = name.lowercaseString;
        if ([lower hasSuffix:@".fb2"] || [lower hasSuffix:@".xml"]) {
            target = name;
            break;
        }
    }
    if (!target) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.FB2" code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"В архиве нет FB2-файла"}];
        return nil;
    }
    return [zip dataForEntry:target error:error];
}

static NSString *ORFB2Decode(NSData *data) {
    NSData *head = [data subdataWithRange:NSMakeRange(0, MIN(data.length, (NSUInteger)4096))];
    NSString *peek = [[NSString alloc] initWithData:head encoding:NSISOLatin1StringEncoding] ?: @"";
    NSString *declared = [ORText firstMatchPattern:@"(?i)encoding\\s*=\\s*[\"']([^\"']+)[\"']" inString:peek group:1];
    NSString *lower = declared.lowercaseString;
    NSStringEncoding encoding = 0;
    if ([lower containsString:@"1251"]) encoding = NSWindowsCP1251StringEncoding;
    else if ([lower containsString:@"koi8"]) encoding = 0x0C02;
    else if ([lower containsString:@"utf-16"]) encoding = NSUTF16StringEncoding;
    else if ([lower containsString:@"utf-8"] || [lower containsString:@"utf8"]) encoding = NSUTF8StringEncoding;

    NSString *text = nil;
    if (encoding == 0x0C02) {
        encoding = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingKOI8_R);
    }
    if (encoding != 0) {
        text = [[NSString alloc] initWithData:data encoding:encoding];
    }
    if (!text || [text rangeOfString:@"\uFFFD"].location != NSNotFound) {
        text = [ORText stringFromData:data];
    }
    return text ?: @"";
}

static NSString *ORFB2CleanXML(NSString *text) {
    if (text.length == 0) return @"";
    NSMutableString *clean = [NSMutableString stringWithCapacity:text.length];
    NSUInteger length = MIN(text.length, (NSUInteger)20000000);
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [text characterAtIndex:i];
        if ((c < 0x20 && c != '\t' && c != '\n' && c != '\r') || c == 0xFFFE || c == 0xFFFF) continue;
        [clean appendFormat:@"%C", c];
    }
    NSString *result = [ORText replacePattern:@"&(?!(#\\d+|#x[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);)"
                                     inString:clean
                                 withTemplate:@"&amp;"];
    return result;
}

#pragma mark - Builder

@interface ORFB2Builder : NSObject
@property (nonatomic, strong) NSMutableString *html;
@property (nonatomic, strong) NSMutableArray<ORTOCItem *> *toc;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *images; // id -> file URL
@property (nonatomic, copy) NSString *rootDirectory;
@property (nonatomic) NSInteger sectionCounter;
@property (nonatomic) NSInteger chapterCounter;
@end

@implementation ORFB2Builder

- (instancetype)init {
    self = [super init];
    if (self) {
        _html = [NSMutableString string];
        _toc = [NSMutableArray array];
        _images = @{};
    }
    return self;
}

- (NSString *)escapedText:(NSString *)text {
    if (text.length == 0) return @"";
    NSString *flat = [text stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    flat = [flat stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    flat = [flat stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
    return [ORText escapeHTML:flat];
}

- (NSString *)titleTextOfNode:(ORXMLNode *)node {
    ORXMLNode *title = [node firstChildNamed:@"title"];
    if (!title) return @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (ORXMLNode *child in title.children) {
        NSString *value = [child innerText];
        if (value.length > 0) [parts addObject:value];
    }
    if (parts.count == 0) return [title innerText];
    return [parts componentsJoinedByString:@" "];
}

- (void)renderNode:(ORXMLNode *)node depth:(NSInteger)depth topLevel:(BOOL)topLevel {
    NSString *name = node.name;
    if (name.length == 0) return;
    if ([name isEqualToString:@"binary"] || [name isEqualToString:@"coverpage"] || [name isEqualToString:@"stylesheet"]) return;

    if ([name isEqualToString:@"section"]) {
        [self renderSection:node depth:depth topLevel:topLevel];
        return;
    }

    if ([name isEqualToString:@"title"]) {
        [self.html appendString:depth > 1 ? @"<h3 class=\"fb-title\">" : @"<h2 class=\"fb-title\">"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:depth > 1 ? @"</h3>" : @"</h2>"];
        return;
    }
    if ([name isEqualToString:@"subtitle"]) {
        [self.html appendString:@"<h3 class=\"fb-subtitle\">"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</h3>"];
        return;
    }
    if ([name isEqualToString:@"p"]) {
        [self.html appendString:@"<p>"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</p>"];
        return;
    }
    if ([name isEqualToString:@"empty-line"]) {
        [self.html appendString:@"<div class=\"fb-empty\"></div>"];
        return;
    }
    if ([name isEqualToString:@"emphasis"]) {
        [self.html appendString:@"<em>"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</em>"];
        return;
    }
    if ([name isEqualToString:@"strong"]) {
        [self.html appendString:@"<strong>"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</strong>"];
        return;
    }
    if ([name isEqualToString:@"strikethrough"]) {
        [self.html appendString:@"<s>"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</s>"];
        return;
    }
    if ([name isEqualToString:@"sub"]) {
        [self.html appendString:@"<sub>"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</sub>"];
        return;
    }
    if ([name isEqualToString:@"sup"]) {
        [self.html appendString:@"<sup>"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</sup>"];
        return;
    }
    if ([name isEqualToString:@"code"]) {
        [self.html appendString:@"<code>"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</code>"];
        return;
    }
    if ([name isEqualToString:@"epigraph"]) {
        [self.html appendString:@"<blockquote class=\"fb-epigraph\">"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</blockquote>"];
        return;
    }
    if ([name isEqualToString:@"cite"]) {
        [self.html appendString:@"<blockquote class=\"fb-cite\">"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</blockquote>"];
        return;
    }
    if ([name isEqualToString:@"poem"]) {
        [self.html appendString:@"<div class=\"fb-poem\">"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</div>"];
        return;
    }
    if ([name isEqualToString:@"stanza"]) {
        [self.html appendString:@"<div class=\"fb-stanza\">"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</div>"];
        return;
    }
    if ([name isEqualToString:@"v"]) {
        [self.html appendString:@"<p class=\"fb-verse\">"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</p>"];
        return;
    }
    if ([name isEqualToString:@"text-author"]) {
        [self.html appendString:@"<p class=\"fb-text-author\">"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</p>"];
        return;
    }
    if ([name isEqualToString:@"date"]) {
        [self.html appendString:@"<p class=\"fb-date\">"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</p>"];
        return;
    }
    if ([name isEqualToString:@"annotation"]) {
        [self.html appendString:@"<div class=\"fb-annotation\">"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</div>"];
        return;
    }
    if ([name isEqualToString:@"table"]) {
        [self.html appendString:@"<table class=\"fb-table\"><tbody>"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</tbody></table>"];
        return;
    }
    if ([name isEqualToString:@"tr"]) {
        [self.html appendString:@"<tr>"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</tr>"];
        return;
    }
    if ([name isEqualToString:@"td"]) {
        [self.html appendString:@"<td>"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</td>"];
        return;
    }
    if ([name isEqualToString:@"th"]) {
        [self.html appendString:@"<th>"];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</th>"];
        return;
    }
    if ([name isEqualToString:@"image"]) {
        [self renderImage:node];
        return;
    }
    if ([name isEqualToString:@"a"]) {
        NSString *href = [node attr:@"href"];
        NSString *target = href;
        if ([href hasPrefix:@"#"]) {
            target = [@"#fb-" stringByAppendingString:[href substringFromIndex:1]];
        }
        [self.html appendFormat:@"<a href=\"%@\">", [ORText escapeHTML:target]];
        [self renderChildren:node depth:depth topLevel:NO];
        [self.html appendString:@"</a>"];
        return;
    }

    [self renderChildren:node depth:depth topLevel:NO];
}

- (void)renderSection:(ORXMLNode *)node depth:(NSInteger)depth topLevel:(BOOL)topLevel {
    NSInteger sectionIndex = self.sectionCounter++;
    NSString *originalID = [node attr:@"id"];
    NSString *elementID = originalID.length > 0 ? [@"fb-" stringByAppendingString:originalID]
                                                : [NSString stringWithFormat:@"sec-%ld", (long)sectionIndex];
    NSString *title = [self titleTextOfNode:node];
    if (title.length > 0) {
        [self.toc addObject:[ORTOCItem itemWithTitle:title level:depth anchor:elementID]];
    }
    NSString *chapterAttribute = @"";
    if (topLevel) {
        chapterAttribute = [NSString stringWithFormat:@" data-chapter=\"%ld\"", (long)self.chapterCounter];
        self.chapterCounter += 1;
    }
    [self.html appendFormat:@"<section id=\"%@\" class=\"fb-section\"%@>", elementID, chapterAttribute];
    [self renderChildren:node depth:depth topLevel:topLevel];
    [self.html appendString:@"</section>"];
}

- (void)renderChildren:(ORXMLNode *)node depth:(NSInteger)depth topLevel:(BOOL)topLevel {
    NSString *text = node.text;
    if (text.length > 0) {
        NSString *escaped = [self escapedText:text];
        if (escaped.length > 0) [self.html appendString:escaped];
    }
    for (ORXMLNode *child in node.children) {
        BOOL childTop = [child.name isEqualToString:@"section"] && !topLevel && depth == 0;
        [self renderNode:child depth:depth + ([child.name isEqualToString:@"section"] ? 1 : 0) topLevel:childTop];
    }
}

- (void)renderImage:(ORXMLNode *)node {
    NSString *href = [node attr:@"href"];
    if (href.length == 0) return;
    NSString *identifier = [href hasPrefix:@"#"] ? [href substringFromIndex:1] : href;
    NSString *source = self.images[identifier];
    if (source.length == 0) return;
    [self.html appendFormat:@"<img class=\"fb-image\" src=\"%@\" alt=\"\"/>", source];
}

@end

#pragma mark - FB2

@interface ORFB2 ()
@property (nonatomic, copy) NSString *opfDirectory;
@end

@implementation ORFB2

+ (instancetype)bookAtPath:(NSString *)path cacheKey:(NSString *)cacheKey error:(NSError **)error {
    NSError *payloadError = nil;
    NSData *payload = ORFB2LoadPayload(path, &payloadError);
    if (!payload) {
        if (error) *error = payloadError;
        return nil;
    }
    NSString *text = ORFB2CleanXML(ORFB2Decode(payload));
    ORXMLNode *root = [ORXML parseString:text error:NULL];
    if (!root) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.FB2" code:3
                                            userInfo:@{NSLocalizedDescriptionKey: @"Не удалось разобрать FB2"}];
        return nil;
    }

    NSString *rootDir = [[ORPaths extractedDirectory] stringByAppendingPathComponent:
                             [cacheKey stringByReplacingOccurrencesOfString:@"/" withString:@"_"]];
    [[NSFileManager defaultManager] createDirectoryAtPath:rootDir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *imagesDir = [rootDir stringByAppendingPathComponent:@"images"];
    [[NSFileManager defaultManager] createDirectoryAtPath:imagesDir withIntermediateDirectories:YES attributes:nil error:NULL];

    ORFB2Builder *builder = [[ORFB2Builder alloc] init];
    builder.rootDirectory = rootDir;

    // Binary resources.
    NSMutableDictionary<NSString *, NSString *> *imageMap = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *coverCandidates = [NSMutableDictionary dictionary];
    for (ORXMLNode *binary in [root childrenNamed:@"binary"]) {
        NSString *identifier = [binary attr:@"id"];
        if (identifier.length == 0) continue;
        NSString *contentType = [[binary attr:@"content-type"] lowercaseString];
        NSString *base64 = [binary.text stringByReplacingOccurrencesOfString:@"\n" withString:@""];
        base64 = [base64 stringByReplacingOccurrencesOfString:@"\r" withString:@""];
        base64 = [base64 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (base64.length == 0) continue;
        NSData *decoded = [[NSData alloc] initWithBase64EncodedString:base64
                                                              options:NSDataBase64DecodingIgnoreUnknownCharacters];
        if (decoded.length < 32) continue;
        NSString *extension = @"jpg";
        if ([contentType containsString:@"png"]) extension = @"png";
        else if ([contentType containsString:@"gif"]) extension = @"gif";
        else if ([contentType containsString:@"webp"]) extension = @"webp";
        else if ([contentType containsString:@"svg"]) extension = @"svg";
        else if ([contentType containsString:@"bmp"]) extension = @"bmp";

        NSString *safeName = [[identifier stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
                              stringByReplacingOccurrencesOfString:@":" withString:@"_"];
        NSString *filePath = [imagesDir stringByAppendingPathComponent:
                                 [NSString stringWithFormat:@"%@.%@", safeName, extension]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            [decoded writeToFile:filePath atomically:YES];
        }
        imageMap[identifier] = [ORText fileURLString:filePath];
        coverCandidates[identifier] = filePath;
    }
    builder.images = imageMap;

    // Description.
    NSString *title = @"";
    NSString *author = @"";
    NSString *coverID = nil;
    ORXMLNode *description = [root firstChildNamed:@"description"];
    ORXMLNode *titleInfo = [description firstChildNamed:@"title-info"];
    if (titleInfo) {
        title = [[titleInfo firstChildNamed:@"book-title"] innerText] ?: @"";
        ORXMLNode *authorNode = [titleInfo firstChildNamed:@"author"];
        if (authorNode) {
            NSMutableArray *parts = [NSMutableArray array];
            for (NSString *key in @[@"first-name", @"middle-name", @"last-name", @"nickname"]) {
                NSString *value = [[authorNode firstChildNamed:key] innerText];
                if (value.length > 0) [parts addObject:value];
            }
            author = [parts componentsJoinedByString:@" "];
        }
        ORXMLNode *coverpage = [titleInfo firstChildNamed:@"coverpage"];
        NSString *href = [[coverpage firstChildNamed:@"image"] attr:@"href"];
        if ([href hasPrefix:@"#"]) coverID = [href substringFromIndex:1];
    }
    if (!titleInfo) {
        ORXMLNode *publishInfo = [description firstChildNamed:@"publish-info"];
        title = [[publishInfo firstChildNamed:@"book-name"] innerText] ?: @"";
    }

    // Bodies.
    NSArray<ORXMLNode *> *bodies = [root childrenNamed:@"body"];
    for (ORXMLNode *body in bodies) {
        BOOL topLevel = YES;
        for (ORXMLNode *child in body.children) {
            if ([child.name isEqualToString:@"section"]) {
                [builder renderNode:child depth:0 topLevel:topLevel];
                topLevel = NO;
            } else if (![child.name isEqualToString:@"title"]) {
                [builder renderNode:child depth:0 topLevel:NO];
            } else {
                ORXMLNode *titleNode = child;
                [builder.html appendString:@"<h1 class=\"fb-book-title\">"];
                [builder renderChildren:titleNode depth:0 topLevel:NO];
                [builder.html appendString:@"</h1>"];
            }
        }
    }

    ORFB2 *book = [[ORFB2 alloc] init];
    book.title = title;
    book.author = author;
    book.rootDirectory = rootDir;
    book.htmlBody = builder.html;
    book.toc = builder.toc;
    book.plainText = [ORText stripHTML:builder.html];
    book.extraCSS = [self extraCSS];
    if (coverID && coverCandidates[coverID]) {
        book.coverImagePath = coverCandidates[coverID];
    }
    return book;
}

+ (NSString *)extraCSS {
    return @".fb-book-title{text-align:center;margin:1.2em 0 .8em;}"
           ".fb-title{text-align:center;margin:1.4em 0 .7em;}"
           ".fb-subtitle{text-align:center;font-weight:600;margin:1em 0 .5em;}"
           ".fb-empty{height:.9em;}"
           ".fb-epigraph{font-style:italic;margin:1em 1.2em;padding-left:.8em;border-left:3px solid rgba(128,128,128,.35);}"
           ".fb-cite{font-style:italic;margin:1em 1.2em;}"
           ".fb-poem{margin:1em 0 1em 1.2em;}"
           ".fb-stanza{margin:0 0 .9em 0;}"
           ".fb-verse{margin:0;text-indent:0;line-height:1.35;}"
           ".fb-text-author{text-align:right;font-style:italic;margin:.2em 0 .8em;}"
           ".fb-date{text-align:right;font-size:.9em;opacity:.8;}"
           ".fb-annotation{margin:1em 0;padding:.6em .8em;border:1px solid rgba(128,128,128,.25);border-radius:6px;}"
           ".fb-image{display:block;max-width:100%;height:auto;margin:1em auto;}"
           ".fb-table{border-collapse:collapse;margin:1em 0;width:100%;}"
           ".fb-table td,.fb-table th{border:1px solid rgba(128,128,128,.4);padding:.3em .4em;}";
}

@end
