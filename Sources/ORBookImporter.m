#import "ORBookImporter.h"
#import "ORMetadata.h"
#import "ORText.h"
#import "ORUtil.h"
#import "ORZip.h"


static BOOL looksLikeBookContainer(NSData *data) {
    if (data.length < 4) return NO;
    const uint8_t *b = data.bytes;
    // ZIP (EPUB / FB2.zip / CBZ), RAR, PDF, PalmDB (MOBI), DjVu
    if (b[0] == 'P' && b[1] == 'K') return YES;
    if (b[0] == 'R' && b[1] == 'a') return YES;
    if (memcmp(b, "%PDF", 4) == 0) return YES;
    if (memcmp(b, "AT&T", 4) == 0) return YES;
    if (memcmp(b, "DJVU", 4) == 0) return YES;
    if (memcmp(b, "FORM", 4) == 0) return YES;   // AIFF/audio containers
    if (memcmp(b, "ID3", 3) == 0) return YES;
    if (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) return YES; // MP3 frame
    return NO;
}



@implementation ORBookImporter

+ (instancetype)shared {
    static ORBookImporter *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ORBookImporter alloc] init];
    });
    return instance;
}

- (void)importFileAtURL:(NSURL *)url completion:(ORImportCompletion)completion {
    if (!completion) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        ORBook *book = [self importSynchronouslyAtURL:url error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(book, error);
        });
    });
}

- (ORBook *)importSynchronouslyAtURL:(NSURL *)url error:(NSError **)error {
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (!data) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"OmniReader.Import" code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Не удалось прочитать файл"}];
        }
        return nil;
    }

    NSString *originalName = url.lastPathComponent ?: @"document";
    NSString *extension = originalName.pathExtension.lowercaseString;
    ORBookFormat format = [ORBook formatForExtension:extension];

    // Sniff the payload: .zip can be an EPUB, an FB2 archive or a comic.
    if ([ORText looksLikeZIP:data]) {
        ORZip *zip = [ORZip zipWithURL:url error:NULL];
        if ([zip containsEntry:@"mimetype"] &&
            [ORText looksLikeEPUBMimetype:[zip dataForEntry:@"mimetype" error:NULL]]) {
            format = ORBookFormatEPUB;
            extension = @"epub";
        } else if (format == ORBookFormatUnknown || format == ORBookFormatTXT) {
            BOOL hasFB2 = NO;
            BOOL hasImages = NO;
            for (NSString *name in zip.names) {
                NSString *lower = name.lowercaseString;
                if ([lower hasSuffix:@".fb2"]) hasFB2 = YES;
                if ([lower hasSuffix:@".jpg"] || [lower hasSuffix:@".png"] || [lower hasSuffix:@".webp"]) hasImages = YES;
            }
            if (hasFB2) {
                format = ORBookFormatFB2;
                extension = @"fb2";
            } else if (hasImages) {
                format = ORBookFormatCBZ;
                extension = @"cbz";
            }
        }
    } else if ([ORText looksLikeRAR:data]) {
        format = ORBookFormatCBR;
        extension = @"cbr";
    } else if (format == ORBookFormatUnknown) {
        if (data.length > 5 && [data rangeOfData:[@"<?xml" dataUsingEncoding:NSUTF8StringEncoding]
                                         options:0
                                           range:NSMakeRange(0, MIN(data.length, (NSUInteger)512))].location != NSNotFound) {
            format = ORBookFormatFB2;
            extension = @"fb2";
        } else {
            format = ORBookFormatTXT;
            extension = extension.length > 0 ? extension : @"txt";
        }
    }

    ORBook *book = [[ORBook alloc] init];
    book.format = format;
    book.title = originalName.stringByDeletingPathExtension;
    book.fileName = [NSString stringWithFormat:@"%@.%@", book.bookID, extension.length > 0 ? extension : @"bin"];

    // Some catalogs answer a book request with an HTML page ("log in first",
    // "file not found"). Saving that as a book produced junk TXT entries, so
    // reject it explicitly unless the user really opened an HTML document.
    BOOL htmlPayload = [ORText looksLikeHTML:data] && !looksLikeBookContainer(data);
    BOOL declaresText = (format == ORBookFormatHTML || format == ORBookFormatMarkdown);
    if (htmlPayload && !declaresText) {
        NSString *pageText = [ORText stripHTML:[ORText stringFromData:data]];
        if (pageText.length > 240) pageText = [[pageText substringToIndex:240] stringByAppendingString:@"…"];
        NSString *message = [NSString stringWithFormat:
            @"Вместо файла книги сервер вернул веб-страницу.\n\n%@\n\n"
             "Обычно это значит, что каталог требует входа на своём сайте.",
            pageText];
        if (error) *error = [NSError errorWithDomain:@"OmniReader.Import" code:7
                                            userInfo:@{NSLocalizedDescriptionKey: message}];
        return nil;
    }

    NSString *destination = [[ORPaths booksDirectory] stringByAppendingPathComponent:book.fileName];
    NSError *writeError = nil;
    BOOL written = [data writeToFile:destination options:NSDataWritingAtomic error:&writeError];
    if (!written) {
        if (error) *error = writeError;
        return nil;
    }

    [ORMetadata enrichBook:book atPath:destination];
    [[ORLibrary shared] addBook:book];
    return book;
}

+ (ORBook *)bookFromDictionary:(NSDictionary *)dictionary source:(ORBookSource)source {
    ORBook *book = [[ORBook alloc] init];
    book.title = dictionary[@"title"] ?: @"Без названия";
    book.author = dictionary[@"author"] ?: @"";
    book.source = source;
    book.remoteID = dictionary[@"remoteID"];
    book.audioURL = dictionary[@"audioURL"];
    NSString *formatString = dictionary[@"format"];
    book.format = [ORBook formatForExtension:formatString.lowercaseString];
    if (book.format == ORBookFormatUnknown && book.audioURL.length > 0) {
        book.format = ORBookFormatAudio;
    }
    return book;
}

- (ORBook *)addRemoteAudioWithTitle:(NSString *)title author:(NSString *)author url:(NSString *)url {
    ORBook *book = [[ORBook alloc] init];
    book.title = title.length > 0 ? title : @"Аудиокнига";
    book.author = author ?: @"";
    book.format = ORBookFormatAudio;
    book.audioURL = url;
    book.source = ORBookSourceRemote;
    [[ORLibrary shared] addBook:book];
    return book;
}

- (void)deleteBook:(ORBook *)book {
    [[ORLibrary shared] removeBook:book deleteFiles:YES];
}

@end