#import "ORCore.h"
#import "ORUtil.h"
#import <Security/Security.h>

NSNotificationName const ORLibraryDidChangeNotification = @"ORLibraryDidChangeNotification";

static NSString *const ORBundlePreferencesPrefix = @"or.";
static NSString *ORYandexTokenCache = nil;

#pragma mark - Book

@implementation ORBook

- (instancetype)init {
    self = [super init];
    if (self) {
        _bookID = [ORUtil uniqueKey];
        _title = @"Без названия";
        _author = @"";
        _format = ORBookFormatUnknown;
        _fileName = @"";
        _source = ORBookSourceLocal;
        _addedAt = [NSDate date];
        _progress = 0.0;
        _collections = @[];
        _bookmarks = @[];
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [self init];
    if (!self) return nil;

    if (dictionary[@"id"]) _bookID = [dictionary[@"id"] description];
    if (dictionary[@"title"]) _title = [dictionary[@"title"] description];
    if (dictionary[@"author"]) _author = [dictionary[@"author"] description];
    if (dictionary[@"format"]) _format = (ORBookFormat)[dictionary[@"format"] integerValue];
    if (dictionary[@"fileName"]) _fileName = [dictionary[@"fileName"] description];
    if (dictionary[@"coverName"]) _coverName = [dictionary[@"coverName"] description];
    if (dictionary[@"remoteID"]) _remoteID = [dictionary[@"remoteID"] description];
    if (dictionary[@"audioURL"]) _audioURL = [dictionary[@"audioURL"] description];
    if (dictionary[@"source"]) _source = (ORBookSource)[dictionary[@"source"] integerValue];
    if (dictionary[@"addedAt"]) _addedAt = [NSDate dateWithTimeIntervalSince1970:[dictionary[@"addedAt"] doubleValue]];
    if (dictionary[@"lastOpenedAt"]) {
        _lastOpenedAt = [NSDate dateWithTimeIntervalSince1970:[dictionary[@"lastOpenedAt"] doubleValue]];
    }
    if (dictionary[@"progress"]) _progress = [dictionary[@"progress"] doubleValue];
    if ([dictionary[@"collections"] isKindOfClass:[NSArray class]]) {
        _collections = dictionary[@"collections"];
    }
    if ([dictionary[@"bookmarks"] isKindOfClass:[NSArray class]]) {
        _bookmarks = dictionary[@"bookmarks"];
    }
    if (dictionary[@"hidden"]) _hidden = [dictionary[@"hidden"] boolValue];
    if (_title.length == 0) _title = @"Без названия";
    return self;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"id"] = self.bookID ?: [ORUtil uniqueKey];
    dict[@"title"] = self.title ?: @"";
    dict[@"author"] = self.author ?: @"";
    dict[@"format"] = @(self.format);
    dict[@"fileName"] = self.fileName ?: @"";
    dict[@"source"] = @(self.source);
    dict[@"addedAt"] = @([self.addedAt timeIntervalSince1970]);
    dict[@"progress"] = @(self.progress);
    dict[@"collections"] = self.collections ?: @[];
    dict[@"bookmarks"] = self.bookmarks ?: @[];
    if (self.coverName) dict[@"coverName"] = self.coverName;
    if (self.remoteID) dict[@"remoteID"] = self.remoteID;
    if (self.audioURL) dict[@"audioURL"] = self.audioURL;
    if (self.lastOpenedAt) dict[@"lastOpenedAt"] = @([self.lastOpenedAt timeIntervalSince1970]);
    if (self.hidden) dict[@"hidden"] = @YES;
    return dict;
}

- (BOOL)isAudio {
    return self.format == ORBookFormatAudio;
}

- (BOOL)isOffice {
    switch (self.format) {
        case ORBookFormatDOC:
        case ORBookFormatDOCX:
        case ORBookFormatXLS:
        case ORBookFormatXLSX:
        case ORBookFormatPPT:
        case ORBookFormatPPTX:
            return YES;
        default:
            return NO;
    }
}

- (BOOL)isTextBook {
    switch (self.format) {
        case ORBookFormatEPUB:
        case ORBookFormatFB2:
        case ORBookFormatTXT:
        case ORBookFormatHTML:
        case ORBookFormatMarkdown:
        case ORBookFormatMOBI:
        case ORBookFormatAZW3:
            return YES;
        default:
            return NO;
    }
}

- (NSString *)formatLabel {
    return [ORBook unitNameForFormat:self.format];
}

- (NSString *)displayAuthor {
    if (self.author.length > 0) return self.author;
    if (self.source == ORBookSourceYandex) return @"Яндекс Книги";
    return @"";
}

+ (ORBookFormat)formatForExtension:(NSString *)extension {
    NSString *ext = extension.lowercaseString;
    if ([ext isEqualToString:@"pdf"]) return ORBookFormatPDF;
    if ([ext isEqualToString:@"epub"]) return ORBookFormatEPUB;
    if ([ext isEqualToString:@"fb2"] || [ext isEqualToString:@"fb2.zip"]) return ORBookFormatFB2;
    if ([ext isEqualToString:@"txt"] || [ext isEqualToString:@"text"] || [ext isEqualToString:@"log"]) return ORBookFormatTXT;
    if ([ext isEqualToString:@"doc"]) return ORBookFormatDOC;
    if ([ext isEqualToString:@"docx"] || [ext isEqualToString:@"odt"] || [ext isEqualToString:@"rtf"]) return ORBookFormatDOCX;
    if ([ext isEqualToString:@"xls"]) return ORBookFormatXLS;
    if ([ext isEqualToString:@"xlsx"] || [ext isEqualToString:@"ods"] || [ext isEqualToString:@"csv"]) return ORBookFormatXLSX;
    if ([ext isEqualToString:@"ppt"]) return ORBookFormatPPT;
    if ([ext isEqualToString:@"pptx"] || [ext isEqualToString:@"odp"]) return ORBookFormatPPTX;
    if ([ext isEqualToString:@"cbz"]) return ORBookFormatCBZ;
    if ([ext isEqualToString:@"cbr"] || [ext isEqualToString:@"rar"]) return ORBookFormatCBR;
    if ([ext isEqualToString:@"mobi"] || [ext isEqualToString:@"prc"]) return ORBookFormatMOBI;
    if ([ext isEqualToString:@"azw"] || [ext isEqualToString:@"azw3"]) return ORBookFormatAZW3;
    if ([ext isEqualToString:@"djvu"] || [ext isEqualToString:@"djv"]) return ORBookFormatDJVU;
    if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"] || [ext isEqualToString:@"xhtml"]) return ORBookFormatHTML;
    if ([ext isEqualToString:@"md"] || [ext isEqualToString:@"markdown"]) return ORBookFormatMarkdown;
    if ([ext isEqualToString:@"mp3"] || [ext isEqualToString:@"m4a"] || [ext isEqualToString:@"m4b"] ||
        [ext isEqualToString:@"aac"] || [ext isEqualToString:@"flac"] || [ext isEqualToString:@"ogg"] ||
        [ext isEqualToString:@"opus"] || [ext isEqualToString:@"wav"]) return ORBookFormatAudio;
    return ORBookFormatUnknown;
}

+ (NSString *)preferredExtensionForFormat:(ORBookFormat)format {
    switch (format) {
        case ORBookFormatPDF: return @"pdf";
        case ORBookFormatEPUB: return @"epub";
        case ORBookFormatFB2: return @"fb2";
        case ORBookFormatTXT: return @"txt";
        case ORBookFormatDOC: return @"doc";
        case ORBookFormatDOCX: return @"docx";
        case ORBookFormatXLS: return @"xls";
        case ORBookFormatXLSX: return @"xlsx";
        case ORBookFormatPPT: return @"ppt";
        case ORBookFormatPPTX: return @"pptx";
        case ORBookFormatCBZ: return @"cbz";
        case ORBookFormatCBR: return @"cbr";
        case ORBookFormatMOBI: return @"mobi";
        case ORBookFormatAZW3: return @"azw3";
        case ORBookFormatDJVU: return @"djvu";
        case ORBookFormatHTML: return @"html";
        case ORBookFormatMarkdown: return @"md";
        case ORBookFormatAudio: return @"m4b";
        default: return @"dat";
    }
}

+ (NSString *)unitNameForFormat:(ORBookFormat)format {
    switch (format) {
        case ORBookFormatPDF: return @"PDF";
        case ORBookFormatEPUB: return @"EPUB";
        case ORBookFormatFB2: return @"FB2";
        case ORBookFormatTXT: return @"TXT";
        case ORBookFormatDOC: return @"DOC";
        case ORBookFormatDOCX: return @"DOCX";
        case ORBookFormatXLS: return @"XLS";
        case ORBookFormatXLSX: return @"XLSX";
        case ORBookFormatPPT: return @"PPT";
        case ORBookFormatPPTX: return @"PPTX";
        case ORBookFormatCBZ: return @"CBZ";
        case ORBookFormatCBR: return @"CBR";
        case ORBookFormatMOBI: return @"MOBI";
        case ORBookFormatAZW3: return @"AZW3";
        case ORBookFormatDJVU: return @"DJVU";
        case ORBookFormatHTML: return @"HTML";
        case ORBookFormatMarkdown: return @"MD";
        case ORBookFormatAudio: return @"АУДИО";
        default: return @"FILE";
    }
}

@end

#pragma mark - Table of contents

@implementation ORTOCItem

+ (instancetype)itemWithTitle:(NSString *)title level:(NSInteger)level anchor:(NSString *)anchor {
    ORTOCItem *item = [[ORTOCItem alloc] init];
    item.title = title.length > 0 ? title : @"Без названия";
    item.level = MAX(0, level);
    item.anchor = anchor ?: @"";
    return item;
}

@end

#pragma mark - Paths

@interface ORPaths ()
+ (NSString *)subdirectory:(NSString *)name;
@end

@implementation ORPaths

+ (NSString *)supportDirectory {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [base stringByAppendingPathComponent:@"OmniReader"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return dir;
}

+ (NSString *)booksDirectory {
    return [self subdirectory:@"Books"];
}

+ (NSString *)coversDirectory {
    return [self subdirectory:@"Covers"];
}

+ (NSString *)extractedDirectory {
    return [self subdirectory:@"Extracted"];
}

+ (NSString *)cacheDirectory {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *base = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [base stringByAppendingPathComponent:@"OmniReader"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return dir;
}

+ (NSString *)subdirectory:(NSString *)name {
    NSString *dir = [[self supportDirectory] stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return dir;
}

+ (NSString *)temporaryDirectoryForBook:(NSString *)bookID {
    NSString *dir = [[self cacheDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"book-%@", bookID]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return dir;
}

+ (NSString *)pathForBook:(ORBook *)book {
    if (book.fileName.length == 0) return @"";
    return [[self booksDirectory] stringByAppendingPathComponent:book.fileName];
}

@end

#pragma mark - Library

@interface ORLibrary ()
@property (nonatomic, strong) NSMutableArray<ORBook *> *mutableBooks;
@property (nonatomic, strong) NSTimer *saveTimer;
@property (nonatomic) BOOL dirty;
@end

@implementation ORLibrary

+ (instancetype)shared {
    static ORLibrary *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ORLibrary alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableBooks = [NSMutableArray array];
        _books = _mutableBooks;
        [self reload];
    }
    return self;
}

- (NSString *)libraryPath {
    return [[ORPaths supportDirectory] stringByAppendingPathComponent:@"library.json"];
}

- (void)reload {
    NSString *path = [self libraryPath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    [self.mutableBooks removeAllObjects];
    if (data.length > 0) {
        NSError *error = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        NSArray *items = nil;
        if ([json isKindOfClass:[NSDictionary class]]) {
            items = json[@"books"];
        } else if ([json isKindOfClass:[NSArray class]]) {
            items = json;
        }
        if ([items isKindOfClass:[NSArray class]]) {
            for (NSDictionary *dict in items) {
                if (![dict isKindOfClass:[NSDictionary class]]) continue;
                ORBook *book = [[ORBook alloc] initWithDictionary:dict];
                if (book.fileName.length > 0 || book.audioURL.length > 0) {
                    [self.mutableBooks addObject:book];
                }
            }
        }
        if (error) NSLog(@"[OmniReader] library read error: %@", error);
    }
    [self notifyChange];
}

- (void)notifyChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ORLibraryDidChangeNotification object:self];
    });
}

- (void)scheduleSave {
    self.dirty = YES;
    [self.saveTimer invalidate];
    self.saveTimer = [NSTimer scheduledTimerWithTimeInterval:0.8
                                                      target:self
                                                    selector:@selector(saveTimerFired:)
                                                    userInfo:nil
                                                     repeats:NO];
}

- (void)saveTimerFired:(NSTimer *)timer {
    [self save];
}

- (void)save {
    [self.saveTimer invalidate];
    self.saveTimer = nil;
    NSMutableArray *items = [NSMutableArray array];
    for (ORBook *book in self.mutableBooks) {
        [items addObject:[book dictionaryRepresentation]];
    }
    NSDictionary *payload = @{ @"version": @1, @"books": items };
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:&error];
    if (error) {
        NSLog(@"[OmniReader] library encode error: %@", error);
        return;
    }
    BOOL ok = [data writeToFile:[self libraryPath] atomically:YES];
    if (!ok) NSLog(@"[OmniReader] library write failed");
    self.dirty = NO;
}

- (void)addBook:(ORBook *)book {
    if (!book) return;
    NSUInteger index = [self indexOfBook:book.bookID];
    if (index != NSNotFound) {
        [self.mutableBooks replaceObjectAtIndex:index withObject:book];
    } else {
        [self.mutableBooks addObject:book];
    }
    [self save];
    [self notifyChange];
}

- (void)removeBook:(ORBook *)book deleteFiles:(BOOL)deleteFiles {
    if (!book) return;
    NSUInteger index = [self indexOfBook:book.bookID];
    if (index != NSNotFound) [self.mutableBooks removeObjectAtIndex:index];
    if (deleteFiles) {
        NSString *path = [ORPaths pathForBook:book];
        if (path.length > 0) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        NSString *cover = [self coverPathForBook:book];
        if (cover.length > 0) [[NSFileManager defaultManager] removeItemAtPath:cover error:NULL];
        NSString *extracted = [[ORPaths extractedDirectory] stringByAppendingPathComponent:book.bookID];
        [[NSFileManager defaultManager] removeItemAtPath:extracted error:NULL];
    }
    [self save];
    [self notifyChange];
}

- (void)updateBook:(ORBook *)book {
    if (!book) return;
    NSUInteger index = [self indexOfBook:book.bookID];
    if (index == NSNotFound) {
        [self.mutableBooks addObject:book];
    } else {
        [self.mutableBooks replaceObjectAtIndex:index withObject:book];
    }
    [self scheduleSave];
    [self notifyChange];
}

- (NSUInteger)indexOfBook:(NSString *)bookID {
    if (bookID.length == 0) return NSNotFound;
    for (NSUInteger i = 0; i < self.mutableBooks.count; i++) {
        if ([self.mutableBooks[i].bookID isEqualToString:bookID]) return i;
    }
    return NSNotFound;
}

- (ORBook *)bookWithID:(NSString *)bookID {
    NSUInteger index = [self indexOfBook:bookID];
    return index == NSNotFound ? nil : self.mutableBooks[index];
}

- (void)setProgress:(double)progress forBookID:(NSString *)bookID {
    ORBook *book = [self bookWithID:bookID];
    if (!book) return;
    book.progress = MAX(0.0, MIN(1.0, progress));
    [self scheduleSave];
}

- (void)markOpened:(ORBook *)book {
    if (!book) return;
    book.lastOpenedAt = [NSDate date];
    [self scheduleSave];
}

- (NSString *)coverPathForBook:(ORBook *)book {
    if (book.coverName.length == 0) return @"";
    return [[ORPaths coversDirectory] stringByAppendingPathComponent:book.coverName];
}

- (void)setCoverImage:(UIImage *)image forBook:(ORBook *)book {
    if (!image || !book) return;
    NSString *name = [NSString stringWithFormat:@"%@.jpg", book.bookID];
    NSString *path = [[ORPaths coversDirectory] stringByAppendingPathComponent:name];
    UIImage *scaled = [ORUtil scaledImage:image maxPixelSize:900];
    NSData *data = UIImageJPEGRepresentation(scaled ?: image, 0.86);
    if ([data writeToFile:path atomically:YES]) {
        book.coverName = name;
        [self scheduleSave];
        [self notifyChange];
    }
}

@end

#pragma mark - Settings

@implementation ORSettings

+ (instancetype)shared {
    static ORSettings *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ORSettings alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSDictionary *defaults = @{
            @"or.theme": @(ORReaderThemePaper),
            @"or.font": @(ORReaderFontSerif),
            @"or.fontSize": @19,
            @"or.lineHeight": @1.55,
            @"or.margin": @18,
            @"or.justify": @YES,
            @"or.hyphenate": @YES,
            @"or.animatePages": @YES,
            @"or.pageDirection": @(ORPageDirectionHorizontal),
            @"or.speechRate": @0.5,
            @"or.playbackRate": @1.0,
            @"or.keepScreenAwake": @YES,
            @"or.syncProgress": @YES,
            @"or.simpleLayout": @NO,
            @"or.yandexClientID": @"",
            @"or.opdsCatalogs": @[]
        };
        [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
    }
    return self;
}

- (NSUserDefaults *)defaults {
    return [NSUserDefaults standardUserDefaults];
}

- (ORReaderTheme)theme { return (ORReaderTheme)[self.defaults integerForKey:@"or.theme"]; }
- (void)setTheme:(ORReaderTheme)value { [self.defaults setInteger:value forKey:@"or.theme"]; }
- (ORReaderFont)font { return (ORReaderFont)[self.defaults integerForKey:@"or.font"]; }
- (void)setFont:(ORReaderFont)value { [self.defaults setInteger:value forKey:@"or.font"]; }
- (NSInteger)fontSize { return [self.defaults integerForKey:@"or.fontSize"]; }
- (void)setFontSize:(NSInteger)value { [self.defaults setInteger:value forKey:@"or.fontSize"]; }
- (double)lineHeight { return [self.defaults doubleForKey:@"or.lineHeight"]; }
- (void)setLineHeight:(double)value { [self.defaults setDouble:value forKey:@"or.lineHeight"]; }
- (NSInteger)margin { return [self.defaults integerForKey:@"or.margin"]; }
- (void)setMargin:(NSInteger)value { [self.defaults setInteger:value forKey:@"or.margin"]; }
- (BOOL)justify { return [self.defaults boolForKey:@"or.justify"]; }
- (void)setJustify:(BOOL)value { [self.defaults setBool:value forKey:@"or.justify"]; }
- (BOOL)hyphenate { return [self.defaults boolForKey:@"or.hyphenate"]; }
- (void)setHyphenate:(BOOL)value { [self.defaults setBool:value forKey:@"or.hyphenate"]; }
- (BOOL)animatePages { return [self.defaults boolForKey:@"or.animatePages"]; }
- (void)setAnimatePages:(BOOL)value { [self.defaults setBool:value forKey:@"or.animatePages"]; }
- (ORPageDirection)pageDirection { return (ORPageDirection)[self.defaults integerForKey:@"or.pageDirection"]; }
- (void)setPageDirection:(ORPageDirection)value { [self.defaults setInteger:value forKey:@"or.pageDirection"]; }
- (float)speechRate { return [self.defaults floatForKey:@"or.speechRate"]; }
- (void)setSpeechRate:(float)value { [self.defaults setFloat:value forKey:@"or.speechRate"]; }
- (float)playbackRate { return [self.defaults floatForKey:@"or.playbackRate"]; }
- (void)setPlaybackRate:(float)value { [self.defaults setFloat:value forKey:@"or.playbackRate"]; }
- (BOOL)keepScreenAwake { return [self.defaults boolForKey:@"or.keepScreenAwake"]; }
- (void)setKeepScreenAwake:(BOOL)value { [self.defaults setBool:value forKey:@"or.keepScreenAwake"]; }
- (BOOL)syncProgress { return [self.defaults boolForKey:@"or.syncProgress"]; }
- (void)setSyncProgress:(BOOL)value { [self.defaults setBool:value forKey:@"or.syncProgress"]; }
- (BOOL)simpleLayout { return [self.defaults boolForKey:@"or.simpleLayout"]; }
- (void)setSimpleLayout:(BOOL)value { [self.defaults setBool:value forKey:@"or.simpleLayout"]; }

- (NSString *)yandexClientID { return [self.defaults stringForKey:@"or.yandexClientID"] ?: @""; }
- (void)setYandexClientID:(NSString *)value { [self.defaults setObject:value ?: @"" forKey:@"or.yandexClientID"]; }

- (NSString *)yandexToken {
    if (ORYandexTokenCache) return ORYandexTokenCache;
    ORYandexTokenCache = [ORKeychain stringForKey:@"yandex.token"];
    return ORYandexTokenCache;
}
- (void)setYandexToken:(NSString *)value {
    ORYandexTokenCache = [value copy];
    if (value.length > 0) {
        [ORKeychain setString:value forKey:@"yandex.token"];
    } else {
        [ORKeychain removeKey:@"yandex.token"];
    }
}

- (NSString *)yandexUserName { return [self.defaults stringForKey:@"or.yandexUserName"]; }
- (void)setYandexUserName:(NSString *)value { [self.defaults setObject:value forKey:@"or.yandexUserName"]; }

- (UIColor *)themeBackgroundColor {
    switch (self.theme) {
        case ORReaderThemeSepia: return [UIColor colorWithRed:0.953 green:0.906 blue:0.812 alpha:1.0];
        case ORReaderThemeGray: return [UIColor colorWithRed:0.906 green:0.906 blue:0.898 alpha:1.0];
        case ORReaderThemeNight: return [UIColor colorWithRed:0.071 green:0.071 blue:0.078 alpha:1.0];
        default: return [UIColor colorWithRed:0.969 green:0.957 blue:0.925 alpha:1.0];
    }
}

- (UIColor *)themeTextColor {
    switch (self.theme) {
        case ORReaderThemeSepia: return [UIColor colorWithRed:0.227 green:0.180 blue:0.125 alpha:1.0];
        case ORReaderThemeGray: return [UIColor colorWithRed:0.145 green:0.145 blue:0.145 alpha:1.0];
        case ORReaderThemeNight: return [UIColor colorWithRed:0.788 green:0.776 blue:0.753 alpha:1.0];
        default: return [UIColor colorWithRed:0.125 green:0.122 blue:0.118 alpha:1.0];
    }
}

- (UIColor *)themeSecondaryColor {
    switch (self.theme) {
        case ORReaderThemeSepia: return [UIColor colorWithRed:0.541 green:0.451 blue:0.341 alpha:1.0];
        case ORReaderThemeGray: return [UIColor colorWithRed:0.435 green:0.435 blue:0.435 alpha:1.0];
        case ORReaderThemeNight: return [UIColor colorWithRed:0.541 green:0.541 blue:0.541 alpha:1.0];
        default: return [UIColor colorWithRed:0.478 green:0.463 blue:0.427 alpha:1.0];
    }
}

- (NSString *)cssFontFamily {
    switch (self.font) {
        case ORReaderFontSans: return @"-apple-system, 'Helvetica Neue', 'Segoe UI', sans-serif";
        case ORReaderFontMono: return @"Menlo, 'Courier New', monospace";
        default: return @"Georgia, 'Times New Roman', 'Noto Serif', serif";
    }
}

- (NSString *)cssBackgroundColor { return [ORUtil cssColorFromUIColor:[self themeBackgroundColor]]; }
- (NSString *)cssTextColor { return [ORUtil cssColorFromUIColor:[self themeTextColor]]; }

- (NSArray<NSDictionary *> *)opdsCatalogs {
    id value = [self.defaults arrayForKey:@"or.opdsCatalogs"];
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

- (void)addOPDSCatalog:(NSDictionary *)catalog {
    if (!catalog) return;
    NSMutableArray *items = [[self opdsCatalogs] mutableCopy];
    NSString *catalogID = catalog[@"id"] ?: [ORUtil uniqueKey];
    NSMutableDictionary *copy = [catalog mutableCopy];
    copy[@"id"] = catalogID;
    NSUInteger existing = NSNotFound;
    for (NSUInteger i = 0; i < items.count; i++) {
        if ([items[i][@"id"] isEqualToString:catalogID]) { existing = i; break; }
    }
    if (existing == NSNotFound) [items addObject:copy];
    else [items replaceObjectAtIndex:existing withObject:copy];
    [self.defaults setObject:items forKey:@"or.opdsCatalogs"];
}

- (void)removeOPDSCatalogWithID:(NSString *)catalogID {
    if (catalogID.length == 0) return;
    NSMutableArray *items = [[self opdsCatalogs] mutableCopy];
    NSMutableArray *keep = [NSMutableArray array];
    for (NSDictionary *item in items) {
        if (![item[@"id"] isEqualToString:catalogID]) [keep addObject:item];
    }
    [self.defaults setObject:keep forKey:@"or.opdsCatalogs"];
    [ORKeychain removeKey:[NSString stringWithFormat:@"opds.%@", catalogID]];
}

- (void)setPassword:(NSString *)password forOPDSCatalog:(NSString *)catalogID {
    if (catalogID.length == 0) return;
    NSString *key = [NSString stringWithFormat:@"opds.%@", catalogID];
    if (password.length > 0) [ORKeychain setString:password forKey:key];
    else [ORKeychain removeKey:key];
}

- (NSString *)passwordForOPDSCatalog:(NSString *)catalogID {
    if (catalogID.length == 0) return nil;
    return [ORKeychain stringForKey:[NSString stringWithFormat:@"opds.%@", catalogID]];
}

#pragma mark Book folders

- (NSArray<NSString *> *)bookFolders {
    id value = [self.defaults arrayForKey:@"or.bookFolders"];
    if (![value isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray<NSString *> *folders = [NSMutableArray array];
    for (id entry in (NSArray *)value) {
        if (![entry isKindOfClass:[NSString class]] || [entry length] == 0) continue;
        if (![folders containsObject:entry]) [folders addObject:entry];
    }
    return folders;
}

- (void)addBookFolder:(NSString *)name {
    if (name.length == 0) return;
    NSMutableArray<NSString *> *folders = [[self bookFolders] mutableCopy];
    if (![folders containsObject:name]) {
        [folders addObject:name];
        [self.defaults setObject:folders forKey:@"or.bookFolders"];
    }
}

- (void)removeBookFolder:(NSString *)name {
    if (name.length == 0) return;
    NSMutableArray<NSString *> *folders = [[self bookFolders] mutableCopy];
    [folders removeObject:name];
    [self.defaults setObject:folders forKey:@"or.bookFolders"];
}

- (void)synchronize {
    [self.defaults synchronize];
}

@end

#pragma mark - Keychain

@implementation ORKeychain

+ (BOOL)fallbackUsed {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"or.keychainFallbackUsed"];
}

+ (BOOL)isUsingFallbackStorage {
    return [self fallbackUsed];
}

+ (NSMutableDictionary *)baseQueryForKey:(NSString *)key {
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge id)kSecAttrService] = @"com.w3rn1ght.omnireader";
    query[(__bridge id)kSecAttrAccount] = key;
    return query;
}

+ (NSString *)fallbackKey:(NSString *)key {
    return [NSString stringWithFormat:@"or.secure.%@", key];
}

+ (BOOL)setString:(NSString *)value forKey:(NSString *)key {
    if (key.length == 0) return NO;
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSMutableDictionary *query = [self baseQueryForKey:key];
    NSDictionary *attributes = @{ (__bridge id)kSecValueData: data };
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
    if (status == errSecItemNotFound) {
        NSMutableDictionary *insert = [query mutableCopy];
        insert[(__bridge id)kSecValueData] = data;
        insert[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
        status = SecItemAdd((__bridge CFDictionaryRef)insert, NULL);
    }
    if (status == errSecSuccess) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[self fallbackKey:key]];
        return YES;
    }
    // Jailbroken/ad-hoc signed apps often lack keychain-access-groups and get
    // errSecMissingEntitlement (-34018). Persisting in the app container keeps
    // the feature usable; the file never leaves the sandbox.
    NSLog(@"[OmniReader] Keychain unavailable (%d), using app container", (int)status);
    [[NSUserDefaults standardUserDefaults] setObject:value ?: @"" forKey:[self fallbackKey:key]];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"or.keychainFallbackUsed"];
    return YES;
}

+ (NSString *)stringForKey:(NSString *)key {
    if (key.length == 0) return nil;
    NSMutableDictionary *query = [self baseQueryForKey:key];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess && result != NULL) {
        NSData *data = (__bridge_transfer NSData *)result;
        NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (value.length > 0) return value;
    }
    return [[NSUserDefaults standardUserDefaults] stringForKey:[self fallbackKey:key]];
}

+ (BOOL)removeKey:(NSString *)key {
    if (key.length == 0) return NO;
    SecItemDelete((__bridge CFDictionaryRef)[self baseQueryForKey:key]);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:[self fallbackKey:key]];
    return YES;
}

@end
