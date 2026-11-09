#import "ORPlainTextBook.h"
#import "ORText.h"
#import "ORUtil.h"

static BOOL ORLooksLikeHeading(NSString *line) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (trimmed.length == 0 || trimmed.length > 80) return NO;
    NSString *lower = trimmed.lowercaseString;
    NSArray<NSString *> *keywords = @[@"глава", @"часть", @"раздел", @"пролог", @"эпилог",
                                     @"chapter", @"part ", @"prologue", @"epilogue", @"book "];
    for (NSString *keyword in keywords) {
        if ([lower hasPrefix:keyword]) return YES;
    }
    unichar first = [trimmed characterAtIndex:0];
    if (first >= '0' && first <= '9') {
        if ([trimmed rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].location != NSNotFound) return NO;
    }
    // ALL CAPS lines with letters are usually headings in Russian plain text books.
    NSUInteger letters = 0;
    NSUInteger uppercase = 0;
    for (NSUInteger i = 0; i < trimmed.length; i++) {
        unichar c = [trimmed characterAtIndex:i];
        if ([[NSCharacterSet letterCharacterSet] characterIsMember:c]) {
            letters++;
            if ([[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c]) uppercase++;
        }
    }
    return letters >= 4 && uppercase == letters;
}

static NSString *ORMarkdownToHTML(NSString *markdown) {
    NSArray<NSString *> *lines = [markdown componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableString *html = [NSMutableString string];
    BOOL inCode = NO;
    BOOL inQuote = NO;
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"```"]) {
            [html appendString:inCode ? @"</pre>" : @"<pre>"];
            inCode = !inCode;
            continue;
        }
        if (inCode) {
            [html appendFormat:@"%@\n", [ORText escapeHTML:line]];
            continue;
        }
        if ([trimmed hasPrefix:@">"]) {
            if (!inQuote) { [html appendString:@"<blockquote>"]; inQuote = YES; }
            [html appendFormat:@"<p>%@</p>", [ORText escapeHTML:[trimmed substringFromIndex:1]]];
            continue;
        }
        if (inQuote) { [html appendString:@"</blockquote>"]; inQuote = NO; }
        if (trimmed.length == 0) {
            [html appendString:@"<div class=\"md-blank\"></div>"];
            continue;
        }
        NSInteger level = 0;
        while (level < trimmed.length && [trimmed characterAtIndex:level] == '#') level++;
        if (level > 0 && level <= 6) {
            NSString *content = [trimmed substringFromIndex:level];
            content = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            [html appendFormat:@"<h%ld>%@</h%ld>", (long)level, [ORText escapeHTML:content], (long)level];
            continue;
        }
        if ([trimmed hasPrefix:@"- "] || [trimmed hasPrefix:@"* "]) {
            [html appendFormat:@"<p class=\"md-item\">• %@</p>", [ORText escapeHTML:[trimmed substringFromIndex:2]]];
            continue;
        }
        NSString *escaped = [ORText escapeHTML:trimmed];
        escaped = [ORText replacePattern:@"\\*\\*([^*]+)\\*\\*" inString:escaped withTemplate:@"<strong>$1</strong>"];
        escaped = [ORText replacePattern:@"(?<!\\*)\\*([^*]+)\\*(?!\\*)" inString:escaped withTemplate:@"<em>$1</em>"];
        escaped = [ORText replacePattern:@"`([^`]+)`" inString:escaped withTemplate:@"<code>$1</code>"];
        [html appendFormat:@"<p>%@</p>", escaped];
    }
    if (inQuote) [html appendString:@"</blockquote>"];
    if (inCode) [html appendString:@"</pre>"];
    return html;
}

@implementation ORPlainTextBook

+ (instancetype)bookAtPath:(NSString *)path
                    format:(ORBookFormat)format
                  cacheKey:(NSString *)cacheKey
                     error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.Text" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Не удалось прочитать файл"}];
        return nil;
    }
    NSString *text = [ORText stringFromData:data];
    if (text.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.Text" code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"Файл пуст"}];
        return nil;
    }

    NSString *root = [[ORPaths extractedDirectory] stringByAppendingPathComponent:
                         [cacheKey stringByReplacingOccurrencesOfString:@"/" withString:@"_"]];
    [[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL];

    ORPlainTextBook *book = [[ORPlainTextBook alloc] init];
    book.rootDirectory = root;
    book.title = path.lastPathComponent.stringByDeletingPathExtension;
    book.author = @"";
    book.extraCSS = [self extraCSS];

    if (format == ORBookFormatHTML) {
        NSString *body = [ORText firstMatchPattern:@"(?is)<body\\b[^>]*>(.*?)</body>" inString:text group:1];
        if (body.length == 0) body = text;
        body = [ORText replacePattern:@"(?is)<script\\b[^>]*>.*?</script>" inString:body withTemplate:@""];
        body = [self absolutiseResourcesInHTML:body basePath:path.stringByDeletingLastPathComponent];
        book.htmlBody = [NSString stringWithFormat:@"<section id=\"ch-0\" data-chapter=\"0\">%@</section>", body];
        book.plainText = [ORText stripHTML:body];
        NSString *title = [ORText firstMatchPattern:@"(?is)<title[^>]*>(.*?)</title>" inString:text group:1];
        if (title.length > 0) book.title = [ORText decodeEntities:title];
        book.toc = [self tocFromHTML:book.htmlBody];
        return book;
    }

    if (format == ORBookFormatMarkdown) {
        NSString *html = ORMarkdownToHTML(text);
        book.htmlBody = [self wrapChapters:html];
        book.plainText = [ORText stripHTML:html];
        book.toc = [self tocFromHTML:book.htmlBody];
        return book;
    }

    book.htmlBody = [self htmlFromPlainText:text];
    book.plainText = text;
    book.toc = [self tocFromHTML:book.htmlBody];
    return book;
}

+ (NSString *)htmlFromPlainText:(NSString *)text {
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableString *html = [NSMutableString string];
    NSMutableString *paragraph = [NSMutableString string];
    NSInteger chapterIndex = 0;
    __block BOOL hasAnyContent = NO;

    void (^flushParagraph)(void) = ^{
        NSString *value = [paragraph stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (value.length == 0) {
            [paragraph setString:@""];
            return;
        }
        NSString *escaped = [ORText escapeHTML:value];
        escaped = [escaped stringByReplacingOccurrencesOfString:@"\t" withString:@"&nbsp;&nbsp;&nbsp;&nbsp;"];
        [html appendFormat:@"<p>%@</p>\n", escaped];
        [paragraph setString:@""];
    };

    [html appendString:@"<section id=\"ch-0\" data-chapter=\"0\">"];
    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByReplacingOccurrencesOfString:@"\r" withString:@""];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) {
            flushParagraph();
            continue;
        }
        if (ORLooksLikeHeading(trimmed)) {
            flushParagraph();
            if (hasAnyContent) {
                [html appendString:@"</section>"];
                [html appendFormat:@"<section id=\"ch-%ld\" data-chapter=\"%ld\">", (long)chapterIndex + 1, (long)chapterIndex + 1];
                chapterIndex++;
            }
            hasAnyContent = YES;
            [html appendFormat:@"<h2 class=\"txt-heading\">%@</h2>\n", [ORText escapeHTML:trimmed]];
            continue;
        }
        hasAnyContent = YES;
        if (paragraph.length > 0) [paragraph appendString:@" "];
        [paragraph appendString:trimmed];
    }
    flushParagraph();
    [html appendString:@"</section>"];
    return html;
}

+ (NSString *)wrapChapters:(NSString *)html {
    NSMutableString *result = [NSMutableString stringWithString:@"<section id=\"ch-0\" data-chapter=\"0\">"];
    NSInteger chapterIndex = 0;
    NSArray<NSString *> *parts = [html componentsSeparatedByString:@"<h1>"];
    if (parts.count <= 1) {
        [result appendString:html];
    } else {
        [result appendString:parts[0]];
        for (NSUInteger i = 1; i < parts.count; i++) {
            [result appendString:@"</section>"];
            chapterIndex++;
            [result appendFormat:@"<section id=\"ch-%ld\" data-chapter=\"%ld\"><h1>", (long)chapterIndex, (long)chapterIndex];
            [result appendString:parts[i]];
        }
    }
    [result appendString:@"</section>"];
    return result;
}

+ (NSArray<ORTOCItem *> *)tocFromHTML:(NSString *)html {
    NSMutableArray *items = [NSMutableArray array];
    NSArray<NSString *> *sections = [ORText matchesPattern:@"(?is)<section\\b[^>]*id=\"(ch-\\d+)\"[^>]*>(.*?)(?=<section\\b|$)" inString:html group:0];
    NSArray<NSString *> *anchors = [ORText matchesPattern:@"(?is)<section\\b[^>]*id=\"(ch-\\d+)\"" inString:html group:1];
    for (NSUInteger i = 0; i < sections.count && i < anchors.count; i++) {
        NSString *chunk = sections[i];
        NSString *heading = [ORText firstMatchPattern:@"(?is)<h[1-3][^>]*>(.*?)</h[1-3]>" inString:chunk group:1];
        NSString *title = [ORText stripHTML:heading];
        if (title.length == 0) title = [NSString stringWithFormat:@"Фрагмент %lu", (unsigned long)i + 1];
        if (title.length > 90) title = [[title substringToIndex:90] stringByAppendingString:@"…"];
        [items addObject:[ORTOCItem itemWithTitle:title level:0 anchor:anchors[i]]];
    }
    if (items.count <= 1) {
        return @[[ORTOCItem itemWithTitle:@"Начало" level:0 anchor:@"ch-0"]];
    }
    return items;
}

+ (NSString *)absolutiseResourcesInHTML:(NSString *)html basePath:(NSString *)basePath {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?i)(src|href)\\s*=\\s*\"([^\"]+)\"" options:0 error:NULL];
    if (!regex) return html;
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    NSMutableString *result = [html mutableCopy];
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSString *attribute = [html substringWithRange:[match rangeAtIndex:1]];
        NSString *value = [html substringWithRange:[match rangeAtIndex:2]];
        if ([ORUtil isWebURLString:value] || [value hasPrefix:@"#"]) continue;
        NSString *decoded = [value stringByRemovingPercentEncoding] ?: value;
        NSString *absolute = [basePath stringByAppendingPathComponent:decoded];
        NSString *replacement = [NSString stringWithFormat:@"%@=\"%@\"", attribute, [ORText fileURLString:absolute]];
        [result replaceCharactersInRange:match.range withString:replacement];
    }
    return result;
}

+ (NSString *)extraCSS {
    return @".txt-heading{text-align:center;margin:1.6em 0 1em;font-size:1.15em;}"
           ".md-blank{height:.8em;}"
           ".md-item{text-indent:0;margin:.25em 0 .25em 1em;}"
           "pre{white-space:pre-wrap;font-size:.85em;padding:.6em;background:rgba(128,128,128,.12);border-radius:6px;}";
}

@end
