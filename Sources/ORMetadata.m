#import "ORMetadata.h"
#import "ORMOBI.h"
#import "ORText.h"
#import "ORUtil.h"
#import "ORXML.h"
#import "ORZip.h"
#import <PDFKit/PDFKit.h>

@implementation ORMetadata

+ (void)enrichBook:(ORBook *)book atPath:(NSString *)path {
    if (!book || path.length == 0) return;

    __block NSString *title = nil;
    __block NSString *author = nil;
    __block UIImage *cover = nil;

    switch (book.format) {
        case ORBookFormatPDF: {
            PDFDocument *document = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:path]];
            if (document) {
                id pdfTitle = document.documentAttributes[PDFDocumentTitleAttribute];
                id pdfAuthor = document.documentAttributes[PDFDocumentAuthorAttribute];
                if ([pdfTitle isKindOfClass:[NSString class]]) title = pdfTitle;
                if ([pdfAuthor isKindOfClass:[NSString class]]) author = pdfAuthor;
                PDFPage *page = [document pageAtIndex:0];
                if (page) {
                    cover = [page thumbnailOfSize:CGSizeMake(700, 1000) forBox:kPDFDisplayBoxMediaBox];
                }
            }
            break;
        }
        case ORBookFormatEPUB: {
            NSDictionary *info = [self epubMetadataAtPath:path];
            title = info[@"title"];
            author = info[@"author"];
            cover = info[@"cover"];
            break;
        }
        case ORBookFormatFB2: {
            NSDictionary *info = [self fb2MetadataAtPath:path];
            title = info[@"title"];
            author = info[@"author"];
            cover = info[@"cover"];
            break;
        }
        case ORBookFormatMOBI:
        case ORBookFormatAZW3: {
            ORMOBI *mobi = [ORMOBI bookAtPath:path cacheKey:book.bookID error:NULL];
            title = mobi.title;
            author = mobi.author;
            break;
        }
        case ORBookFormatCBZ: {
            ORZip *zip = [ORZip zipWithURL:[NSURL fileURLWithPath:path] error:NULL];
            NSArray<NSString *> *images = [self sortedImageNamesInZip:zip];
            if (images.count > 0) {
                NSData *data = [zip dataForEntry:images.firstObject error:NULL];
                if (data) cover = [UIImage imageWithData:data];
            }
            break;
        }
        case ORBookFormatDOCX:
        case ORBookFormatXLSX:
        case ORBookFormatPPTX: {
            NSDictionary *info = [self officeCoreMetadataAtPath:path];
            title = info[@"title"];
            author = info[@"author"];
            break;
        }
        default:
            break;
    }

    if (title.length > 0) book.title = title;
    if (author.length > 0) book.author = author;

    if (cover) {
        NSString *name = [book.bookID stringByAppendingString:@".jpg"];
        NSString *coverPath = [[ORPaths coversDirectory] stringByAppendingPathComponent:name];
        UIImage *scaled = [ORUtil scaledImage:cover maxPixelSize:900];
        NSData *jpeg = UIImageJPEGRepresentation(scaled ?: cover, 0.86);
        if ([jpeg writeToFile:coverPath atomically:YES]) {
            book.coverName = name;
        }
    }
}

+ (UIImage *)coverImageForBook:(ORBook *)book {
    if (book.coverName.length == 0) return nil;
    NSString *path = [[ORPaths coversDirectory] stringByAppendingPathComponent:book.coverName];
    return [UIImage imageWithContentsOfFile:path];
}

+ (UIImage *)imageWithImage:(UIImage *)image scaledToSize:(CGSize)size {
    return [ORUtil imageWithImage:image scaledToSize:size];
}

#pragma mark - EPUB

+ (NSDictionary *)epubMetadataAtPath:(NSString *)path {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    ORZip *zip = [ORZip zipWithURL:[NSURL fileURLWithPath:path] error:NULL];
    if (!zip) return result;

    NSData *containerData = [zip dataForEntry:@"META-INF/container.xml" error:NULL];
    if (!containerData) return result;
    ORXMLNode *container = [ORXML parseData:containerData error:NULL];
    NSString *opfPath = [[container descendantsNamed:@"rootfile"].firstObject attr:@"full-path"];
    if (opfPath.length == 0) return result;

    NSData *opfData = [zip dataForEntry:opfPath error:NULL];
    if (!opfData) return result;
    ORXMLNode *package = [ORXML parseData:opfData error:NULL];
    ORXMLNode *metadata = [package firstChildNamed:@"metadata"];
    NSString *title = [[metadata firstChildNamed:@"title"] innerText];
    if (title.length > 0) result[@"title"] = title;
    NSMutableArray *authors = [NSMutableArray array];
    for (ORXMLNode *creator in [metadata childrenNamed:@"creator"]) {
        NSString *value = [creator innerText];
        if (value.length > 0) [authors addObject:value];
    }
    if (authors.count > 0) result[@"author"] = [authors componentsJoinedByString:@", "];

    NSString *opfDir = opfPath.stringByDeletingLastPathComponent;
    NSString *coverID = nil;
    for (ORXMLNode *meta in [metadata childrenNamed:@"meta"]) {
        if ([[[meta attr:@"name"] lowercaseString] isEqualToString:@"cover"]) {
            coverID = [meta attr:@"content"];
            break;
        }
    }
    ORXMLNode *manifest = [package firstChildNamed:@"manifest"];
    NSString *coverHref = nil;
    for (ORXMLNode *item in [manifest childrenNamed:@"item"]) {
        NSString *itemID = [item attr:@"id"];
        NSString *properties = [[item attr:@"properties"] lowercaseString];
        if (coverID && [itemID isEqualToString:coverID]) {
            coverHref = [item attr:@"href"];
            break;
        }
        if (!coverHref && [properties containsString:@"cover-image"]) {
            coverHref = [item attr:@"href"];
        }
    }
    if (!coverHref) {
        ORXMLNode *guide = [package firstChildNamed:@"guide"];
        for (ORXMLNode *reference in [guide childrenNamed:@"reference"]) {
            if ([[[reference attr:@"type"] lowercaseString] isEqualToString:@"cover"]) {
                coverHref = [reference attr:@"href"];
                break;
            }
        }
    }
    if (coverHref.length > 0) {
        NSString *resolved = [self resolve:coverHref relativeTo:opfDir];
        NSData *coverData = [zip dataForEntry:resolved error:NULL];
        if (!coverData) coverData = [zip dataForEntry:coverHref error:NULL];
        UIImage *image = coverData ? [UIImage imageWithData:coverData] : nil;
        if (image) result[@"cover"] = image;
    }
    return result;
}

+ (NSString *)resolve:(NSString *)href relativeTo:(NSString *)base {
    NSString *path = href;
    NSRange hash = [path rangeOfString:@"#"];
    if (hash.location != NSNotFound) path = [path substringToIndex:hash.location];
    path = [path stringByRemovingPercentEncoding] ?: path;
    if ([path hasPrefix:@"/"]) path = [path substringFromIndex:1];
    NSString *combined = base.length > 0 ? [base stringByAppendingPathComponent:path] : path;
    NSMutableArray *parts = [NSMutableArray array];
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

#pragma mark - FB2

+ (NSDictionary *)fb2MetadataAtPath:(NSString *)path {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return result;
    if ([ORText looksLikeZIP:data]) {
        ORZip *zip = [ORZip zipWithURL:[NSURL fileURLWithPath:path] error:NULL];
        NSString *target = nil;
        for (NSString *name in zip.names) {
            if ([name.lowercaseString hasSuffix:@".fb2"]) { target = name; break; }
        }
        if (!target) return result;
        data = [zip dataForEntry:target error:NULL];
    }
    if (!data) return result;
    NSString *text = [ORText stringFromData:data];
    if (text.length == 0) return result;
    ORXMLNode *root = [ORXML parseString:text error:NULL];
    if (!root) return result;

    ORXMLNode *titleInfo = [[root firstChildNamed:@"description"] firstChildNamed:@"title-info"];
    NSString *title = [[titleInfo firstChildNamed:@"book-title"] innerText];
    if (title.length > 0) result[@"title"] = title;

    ORXMLNode *authorNode = [titleInfo firstChildNamed:@"author"];
    if (authorNode) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *key in @[@"first-name", @"middle-name", @"last-name", @"nickname"]) {
            NSString *value = [[authorNode firstChildNamed:key] innerText];
            if (value.length > 0) [parts addObject:value];
        }
        if (parts.count > 0) result[@"author"] = [parts componentsJoinedByString:@" "];
    }

    NSString *coverRef = [[[titleInfo firstChildNamed:@"coverpage"] firstChildNamed:@"image"] attr:@"href"];
    if ([coverRef hasPrefix:@"#"]) coverRef = [coverRef substringFromIndex:1];
    if (coverRef.length > 0) {
        for (ORXMLNode *binary in [root childrenNamed:@"binary"]) {
            if (![[binary attr:@"id"] isEqualToString:coverRef]) continue;
            NSString *base64 = [[binary innerText] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSData *imageData = [[NSData alloc] initWithBase64EncodedString:base64
                                                                    options:NSDataBase64DecodingIgnoreUnknownCharacters];
            UIImage *image = imageData ? [UIImage imageWithData:imageData] : nil;
            if (image) result[@"cover"] = image;
            break;
        }
    }
    return result;
}

#pragma mark - Office

+ (NSDictionary *)officeCoreMetadataAtPath:(NSString *)path {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    ORZip *zip = [ORZip zipWithURL:[NSURL fileURLWithPath:path] error:NULL];
    if (!zip) return result;
    NSData *data = [zip dataForEntry:@"docProps/core.xml" error:NULL];
    if (!data) return result;
    ORXMLNode *root = [ORXML parseData:data error:NULL];
    NSString *title = [[root firstChildNamed:@"title"] innerText];
    NSString *creator = [[root firstChildNamed:@"creator"] innerText];
    if (title.length > 0) result[@"title"] = title;
    if (creator.length > 0) result[@"author"] = creator;
    return result;
}

+ (NSArray<NSString *> *)sortedImageNamesInZip:(ORZip *)zip {
    if (!zip) return @[];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *name in zip.names) {
        NSString *lower = name.lowercaseString;
        if ([lower hasSuffix:@".jpg"] || [lower hasSuffix:@".jpeg"] || [lower hasSuffix:@".png"] ||
            [lower hasSuffix:@".webp"] || [lower hasSuffix:@".gif"]) {
            if ([lower containsString:@"__macosx"]) continue;
            [names addObject:name];
        }
    }
    [names sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b options:NSNumericSearch | NSCaseInsensitiveSearch];
    }];
    return names;
}

@end
