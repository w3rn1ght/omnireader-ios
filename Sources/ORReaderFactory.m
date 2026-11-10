#import "ORReaderFactory.h"
#import "ORAudioPlayerController.h"
#import "ORComicReaderController.h"
#import "OREPUB.h"
#import "ORFB2.h"
#import "ORMOBI.h"
#import "OROfficeReaderController.h"
#import "OROfficeText.h"
#import "ORPDFReaderController.h"
#import "ORPagedReaderController.h"
#import "ORPlainTextBook.h"
#import "ORText.h"
#import "ORUtil.h"

@implementation ORReaderFactory

+ (void)openBook:(ORBook *)book
       presenter:(UIViewController *)presenter
      completion:(void (^)(UIViewController *, NSError *))completion {
    if (!completion) return;
    if (!book) {
        completion(nil, [NSError errorWithDomain:@"OmniReader.Reader" code:0
                                       userInfo:@{NSLocalizedDescriptionKey: @"Книга не найдена"}]);
        return;
    }
    NSString *path = [ORPaths pathForBook:book];
    [[ORLibrary shared] markOpened:book];

    switch (book.format) {
        case ORBookFormatAudio: {
            NSURL *url = book.audioURL.length > 0 ? [NSURL URLWithString:book.audioURL] : [NSURL fileURLWithPath:path];
            if (!url) {
                completion(nil, [NSError errorWithDomain:@"OmniReader.Reader" code:1
                                               userInfo:@{NSLocalizedDescriptionKey: @"Не найден аудиофайл"}]);
                return;
            }
            ORAudioPlayerController *player = [[ORAudioPlayerController alloc]
                initWithBook:book
                   localPath:book.audioURL.length > 0 ? nil : path];
            completion(player, nil);
            return;
        }
        case ORBookFormatPDF: {
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                completion(nil, [self missingFileError]);
                return;
            }
            completion([[ORPDFReaderController alloc] initWithBook:book], nil);
            return;
        }
        case ORBookFormatCBZ:
        case ORBookFormatCBR: {
            completion([[ORComicReaderController alloc] initWithBook:book], nil);
            return;
        }
        case ORBookFormatDOC:
        case ORBookFormatXLS:
        case ORBookFormatPPT: {
            completion([[OROfficeReaderController alloc] initWithBook:book], nil);
            return;
        }
        case ORBookFormatDJVU: {
            completion(nil, [NSError errorWithDomain:@"OmniReader.Reader" code:2
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                          @"DJVU пока не поддерживается. Можно конвертировать в PDF или открыть в другом приложении."}]);
            return;
        }
        default:
            break;
    }

    // Heavy text formats build their HTML off the main queue.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        UIViewController *controller = nil;
        switch (book.format) {
            case ORBookFormatEPUB: {
                OREPUB *epub = [OREPUB bookAtPath:path cacheKey:book.bookID error:&error];
                if (epub) {
                    if (book.title.length == 0 || [book.title isEqualToString:@"Без названия"]) {
                        if (epub.title.length > 0) book.title = epub.title;
                    }
                    if (book.author.length == 0 && epub.author.length > 0) book.author = epub.author;
                    [self adoptCoverForBook:book fromPath:epub.coverImagePath];
                    controller = [[ORPagedReaderController alloc] initWithBook:book
                                                                          body:epub.htmlBody
                                                                      extraCSS:epub.extraCSS
                                                                      basePath:epub.rootDirectory
                                                                           toc:epub.toc];
                }
                break;
            }
            case ORBookFormatFB2: {
                ORFB2 *fb2 = [ORFB2 bookAtPath:path cacheKey:book.bookID error:&error];
                if (fb2) {
                    if (fb2.title.length > 0) book.title = fb2.title;
                    if (fb2.author.length > 0) book.author = fb2.author;
                    [self adoptCoverForBook:book fromPath:fb2.coverImagePath];
                    controller = [[ORPagedReaderController alloc] initWithBook:book
                                                                          body:fb2.htmlBody
                                                                      extraCSS:fb2.extraCSS
                                                                      basePath:fb2.rootDirectory
                                                                           toc:fb2.toc];
                }
                break;
            }
            case ORBookFormatMOBI:
            case ORBookFormatAZW3: {
                ORMOBI *mobi = [ORMOBI bookAtPath:path cacheKey:book.bookID error:&error];
                if (mobi) {
                    if (mobi.title.length > 0) book.title = mobi.title;
                    if (mobi.author.length > 0) book.author = mobi.author;
                    controller = [[ORPagedReaderController alloc] initWithBook:book
                                                                          body:mobi.htmlBody
                                                                      extraCSS:mobi.extraCSS
                                                                      basePath:mobi.rootDirectory
                                                                           toc:mobi.toc];
                }
                break;
            }
            case ORBookFormatDOCX:
            case ORBookFormatXLSX:
            case ORBookFormatPPTX: {
                NSString *html = [OROfficeText htmlFromDocumentAtPath:path format:book.format error:&error];
                if (html.length > 0) {
                    NSString *base = [[ORPaths extractedDirectory] stringByAppendingPathComponent:book.bookID];
                    [[NSFileManager defaultManager] createDirectoryAtPath:base
                                             withIntermediateDirectories:YES
                                                              attributes:nil
                                                                   error:NULL];
                    controller = [[ORPagedReaderController alloc] initWithBook:book
                                                                          body:html
                                                                      extraCSS:@""
                                                                      basePath:base
                                                                           toc:@[]];
                } else {
                    // Fall back to QuickLook for shapes the text extractor does not understand.
                    controller = [[OROfficeReaderController alloc] initWithBook:book];
                    error = nil;
                }
                break;
            }
            default: {
                ORPlainTextBook *plain = [ORPlainTextBook bookAtPath:path
                                                               format:book.format
                                                             cacheKey:book.bookID
                                                                error:&error];
                if (plain) {
                    controller = [[ORPagedReaderController alloc] initWithBook:book
                                                                          body:plain.htmlBody
                                                                      extraCSS:plain.extraCSS
                                                                      basePath:plain.rootDirectory
                                                                           toc:plain.toc];
                }
                break;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(controller, error);
        });
    });
}

+ (NSError *)missingFileError {
    return [NSError errorWithDomain:@"OmniReader.Reader" code:3
                           userInfo:@{NSLocalizedDescriptionKey: @"Файл книги не найден в библиотеке."}];
}

+ (void)adoptCoverForBook:(ORBook *)book fromPath:(NSString *)path {
    if (!book || book.coverName.length > 0 || path.length == 0) return;
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (!image) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[ORLibrary shared] setCoverImage:image forBook:book];
    });
}

@end