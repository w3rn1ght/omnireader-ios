#import "OROfficeText.h"
#import "ORText.h"
#import "ORUtil.h"
#import "ORXML.h"
#import "ORZip.h"

@implementation OROfficeText

+ (NSString *)htmlFromDocumentAtPath:(NSString *)path
                             format:(ORBookFormat)format
                              error:(NSError **)error {
    ORZip *zip = [ORZip zipWithURL:[NSURL fileURLWithPath:path] error:error];
    if (!zip) return nil;

    NSString *html = nil;
    switch (format) {
        case ORBookFormatDOCX:
            html = [self htmlFromDOCXZip:zip];
            break;
        case ORBookFormatXLSX:
            html = [self htmlFromXLSXZip:zip];
            break;
        case ORBookFormatPPTX:
            html = [self htmlFromPPTXZip:zip];
            break;
        default:
            if (error) *error = [NSError errorWithDomain:@"OmniReader.Office" code:1
                                                userInfo:@{NSLocalizedDescriptionKey:
                                                               @"Этот формат открывается через QuickLook"}];
            return nil;
    }
    if (!html) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.Office" code:2
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"Не удалось извлечь текст из документа"}];
        return nil;
    }
    return [NSString stringWithFormat:@"<section id=\"ch-0\" data-chapter=\"0\" class=\"office\">%@</section>", html];
}

+ (NSString *)plainTextFromDocumentAtPath:(NSString *)path format:(ORBookFormat)format {
    NSString *html = [self htmlFromDocumentAtPath:path format:format error:NULL];
    return html ? [ORText stripHTML:html] : nil;
}

#pragma mark - Shared rendering

+ (void)appendTextOfNode:(ORXMLNode *)node into:(NSMutableString *)output {
    if (node.children.count == 0) {
        NSString *text = node.text;
        if (text.length > 0) {
            [output appendString:[ORText escapeHTML:text]];
        }
        return;
    }
    if (node.text.length > 0) {
        [output appendString:[ORText escapeHTML:node.text]];
    }
    for (ORXMLNode *child in node.children) {
        [self appendTextOfNode:child into:output];
    }
}

#pragma mark - DOCX

+ (NSString *)htmlFromDOCXZip:(ORZip *)zip {
    NSData *data = [zip dataForEntry:@"word/document.xml" error:NULL];
    if (!data) return nil;
    ORXMLNode *root = [ORXML parseData:data error:NULL];
    ORXMLNode *body = [root firstChildNamed:@"body"];
    if (!body) return nil;

    NSMutableString *html = [NSMutableString string];
    [self renderDOCXNode:body into:html];
    return html;
}

+ (void)renderDOCXNode:(ORXMLNode *)node into:(NSMutableString *)html {
    NSString *name = node.name;

    if ([name isEqualToString:@"p"]) {
        ORXMLNode *properties = [node firstChildNamed:@"ppr"];
        NSString *style = [[properties firstChildNamed:@"pstyle"] attr:@"val"];
        BOOL heading = [style.lowercaseString hasPrefix:@"heading"] || [style.lowercaseString isEqualToString:@"title"];
        NSMutableString *content = [NSMutableString string];
        [self appendTextOfNode:node into:content];
        NSString *trimmed = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            [html appendString:@"<div class=\"docx-empty\"></div>"];
        } else if (heading) {
            [html appendFormat:@"<h2>%@</h2>", trimmed];
        } else {
            [html appendFormat:@"<p>%@</p>", trimmed];
        }
        return;
    }
    if ([name isEqualToString:@"tbl"]) {
        [html appendString:@"<table class=\"office-table\">"];
        for (ORXMLNode *child in node.children) {
            if ([child.name isEqualToString:@"tr"]) {
                [html appendString:@"<tr>"];
                for (ORXMLNode *cell in child.children) {
                    if ([cell.name isEqualToString:@"tc"]) {
                        NSMutableString *content = [NSMutableString string];
                        [self appendTextOfNode:cell into:content];
                        [html appendFormat:@"<td>%@</td>", content];
                    }
                }
                [html appendString:@"</tr>"];
            }
        }
        [html appendString:@"</table>"];
        return;
    }
    if ([name isEqualToString:@"tab"]) {
        [html appendString:@"&nbsp;&nbsp;&nbsp;&nbsp;"];
        return;
    }
    if ([name isEqualToString:@"br"]) {
        [html appendString:@"<br/>"];
        return;
    }
    if ([name isEqualToString:@"t"]) {
        [html appendString:[ORText escapeHTML:node.text]];
        return;
    }
    for (ORXMLNode *child in node.children) {
        // Skip style/property containers entirely.
        if ([child.name hasSuffix:@"pr"] || [child.name isEqualToString:@"ppr"] || [child.name isEqualToString:@"rpr"]) continue;
        [self renderDOCXNode:child into:html];
    }
}

#pragma mark - XLSX

+ (NSString *)htmlFromXLSXZip:(ORZip *)zip {
    NSMutableArray<NSString *> *shared = [NSMutableArray array];
    NSData *sharedData = [zip dataForEntry:@"xl/sharedStrings.xml" error:NULL];
    if (sharedData) {
        ORXMLNode *root = [ORXML parseData:sharedData error:NULL];
        for (ORXMLNode *item in [root childrenNamed:@"si"]) {
            [shared addObject:[item innerText] ?: @""];
        }
    }

    NSMutableArray<NSString *> *sheetNames = [NSMutableArray array];
    NSData *workbookData = [zip dataForEntry:@"xl/workbook.xml" error:NULL];
    if (workbookData) {
        ORXMLNode *workbook = [ORXML parseData:workbookData error:NULL];
        ORXMLNode *sheets = [workbook firstChildNamed:@"sheets"];
        for (ORXMLNode *sheet in [sheets childrenNamed:@"sheet"]) {
            NSString *name = [sheet attr:@"name"];
            if (name.length > 0) [sheetNames addObject:name];
        }
    }

    NSMutableArray<NSString *> *sheetPaths = [NSMutableArray array];
    for (NSString *entry in zip.names) {
        if ([entry hasPrefix:@"xl/worksheets/sheet"] && [entry hasSuffix:@".xml"]) {
            [sheetPaths addObject:entry];
        }
    }
    [sheetPaths sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b options:NSNumericSearch];
    }];
    if (sheetPaths.count == 0) return nil;

    NSMutableString *html = [NSMutableString string];
    NSUInteger sheetLimit = MIN(sheetPaths.count, (NSUInteger)12);
    for (NSUInteger s = 0; s < sheetLimit; s++) {
        NSData *data = [zip dataForEntry:sheetPaths[s] error:NULL];
        if (!data) continue;
        ORXMLNode *root = [ORXML parseData:data error:NULL];
        ORXMLNode *sheetData = [root firstChildNamed:@"sheetdata"];
        if (!sheetData) continue;
        NSString *name = s < sheetNames.count ? sheetNames[s] : [NSString stringWithFormat:@"Лист %lu", (unsigned long)s + 1];
        [html appendFormat:@"<h2 class=\"xlsx-sheet\">%@</h2>", [ORText escapeHTML:name]];
        [html appendString:@"<table class=\"office-table\">"];
        NSUInteger rowCount = 0;
        for (ORXMLNode *row in [sheetData childrenNamed:@"row"]) {
            if (rowCount++ > 2000) {
                [html appendString:@"<tr><td>… строки обрезаны …</td></tr>"];
                break;
            }
            [html appendString:@"<tr>"];
            for (ORXMLNode *cell in [row childrenNamed:@"c"]) {
                NSString *type = [cell attr:@"t"] ?: @"";
                NSString *value = @"";
                if ([type isEqualToString:@"s"]) {
                    NSInteger index = [[cell firstChildNamed:@"v"] innerText].integerValue;
                    if (index >= 0 && index < (NSInteger)shared.count) value = shared[index];
                } else if ([type isEqualToString:@"inlineStr"]) {
                    value = [[cell firstChildNamed:@"is"] innerText] ?: @"";
                } else if ([type isEqualToString:@"b"]) {
                    value = [[[cell firstChildNamed:@"v"] innerText] isEqualToString:@"1"] ? @"TRUE" : @"FALSE";
                } else {
                    value = [[cell firstChildNamed:@"v"] innerText] ?: @"";
                }
                if (value.length > 4000) value = [value substringToIndex:4000];
                [html appendFormat:@"<td>%@</td>", [ORText escapeHTML:value]];
            }
            [html appendString:@"</tr>"];
        }
        [html appendString:@"</table>"];
    }
    return html;
}

#pragma mark - PPTX

+ (NSString *)htmlFromPPTXZip:(ORZip *)zip {
    NSMutableArray<NSString *> *slides = [NSMutableArray array];
    for (NSString *entry in zip.names) {
        if ([entry hasPrefix:@"ppt/slides/slide"] && [entry hasSuffix:@".xml"]) {
            [slides addObject:entry];
        }
    }
    [slides sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b options:NSNumericSearch];
    }];
    if (slides.count == 0) return nil;

    NSMutableString *html = [NSMutableString string];
    for (NSUInteger i = 0; i < slides.count; i++) {
        NSData *data = [zip dataForEntry:slides[i] error:NULL];
        if (!data) continue;
        ORXMLNode *root = [ORXML parseData:data error:NULL];
        [html appendFormat:@"<h2 class=\"pptx-slide\">Слайд %lu</h2><div class=\"pptx-body\">", (unsigned long)i + 1];
        BOOL hasText = NO;
        for (ORXMLNode *paragraph in [root descendantsNamed:@"p"]) {
            NSMutableString *content = [NSMutableString string];
            for (ORXMLNode *textNode in [paragraph descendantsNamed:@"t"]) {
                [content appendString:[ORText escapeHTML:textNode.innerText]];
            }
            NSString *trimmed = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length == 0) continue;
            hasText = YES;
            [html appendFormat:@"<p>%@</p>", trimmed];
        }
        if (!hasText) [html appendString:@"<p class=\"pptx-empty\">(без текста)</p>"];
        [html appendString:@"</div>"];
    }
    return html;
}

@end
