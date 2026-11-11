#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const ORLibraryDidChangeNotification;

typedef NS_ENUM(NSInteger, ORBookFormat) {
    ORBookFormatUnknown = 0,
    ORBookFormatPDF,
    ORBookFormatEPUB,
    ORBookFormatFB2,
    ORBookFormatTXT,
    ORBookFormatDOC,
    ORBookFormatDOCX,
    ORBookFormatXLS,
    ORBookFormatXLSX,
    ORBookFormatPPT,
    ORBookFormatPPTX,
    ORBookFormatCBZ,
    ORBookFormatCBR,
    ORBookFormatMOBI,
    ORBookFormatAZW3,
    ORBookFormatDJVU,
    ORBookFormatHTML,
    ORBookFormatMarkdown,
    ORBookFormatAudio
};

typedef NS_ENUM(NSInteger, ORBookSource) {
    ORBookSourceLocal = 0,
    ORBookSourceYandex,
    ORBookSourceOPDS,
    ORBookSourceRemote
};

typedef NS_ENUM(NSInteger, ORReaderTheme) {
    ORReaderThemePaper = 0,
    ORReaderThemeSepia,
    ORReaderThemeGray,
    ORReaderThemeNight
};

typedef NS_ENUM(NSInteger, ORReaderFont) {
    ORReaderFontSerif = 0,
    ORReaderFontSans,
    ORReaderFontMono
};

typedef NS_ENUM(NSInteger, ORPageDirection) {
    ORPageDirectionHorizontal = 0,
    ORPageDirectionVertical
};

#pragma mark - Book

@interface ORBook : NSObject

@property (nonatomic, copy) NSString *bookID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *author;
@property (nonatomic) ORBookFormat format;
@property (nonatomic, copy) NSString *fileName;      // relative to Books/
@property (nonatomic, copy, nullable) NSString *coverName;
@property (nonatomic, copy, nullable) NSString *remoteID;
@property (nonatomic, copy, nullable) NSString *audioURL;
@property (nonatomic) ORBookSource source;
@property (nonatomic, strong) NSDate *addedAt;
@property (nonatomic, strong, nullable) NSDate *lastOpenedAt;
@property (nonatomic) double progress;                // 0...1
@property (nonatomic, copy) NSArray<NSString *> *collections;
@property (nonatomic, copy) NSArray<NSDictionary *> *bookmarks;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;

- (BOOL)isAudio;
- (BOOL)isOffice;
- (BOOL)isTextBook;
- (NSString *)formatLabel;
- (NSString *)displayAuthor;

+ (ORBookFormat)formatForExtension:(NSString *)extension;
+ (NSString *)preferredExtensionForFormat:(ORBookFormat)format;
+ (NSString *)unitNameForFormat:(ORBookFormat)format;

@end

#pragma mark - Table of contents

@interface ORTOCItem : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic) NSInteger level;
@property (nonatomic, copy) NSString *anchor;

+ (instancetype)itemWithTitle:(NSString *)title level:(NSInteger)level anchor:(NSString *)anchor;

@end

#pragma mark - Paths

@interface ORPaths : NSObject

+ (NSString *)supportDirectory;
+ (NSString *)booksDirectory;
+ (NSString *)coversDirectory;
+ (NSString *)extractedDirectory;
+ (NSString *)cacheDirectory;
+ (NSString *)temporaryDirectoryForBook:(NSString *)bookID;
+ (NSString *)pathForBook:(ORBook *)book;

@end

#pragma mark - Library

@interface ORLibrary : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSArray<ORBook *> *books;

- (void)reload;
- (void)addBook:(ORBook *)book;
- (void)removeBook:(ORBook *)book deleteFiles:(BOOL)deleteFiles;
- (void)updateBook:(ORBook *)book;
- (nullable ORBook *)bookWithID:(NSString *)bookID;
- (void)setProgress:(double)progress forBookID:(NSString *)bookID;
- (void)markOpened:(ORBook *)book;
- (void)save;

- (NSString *)coverPathForBook:(ORBook *)book;
- (void)setCoverImage:(UIImage *)image forBook:(ORBook *)book;

@end

#pragma mark - Settings

@interface ORSettings : NSObject

+ (instancetype)shared;

@property (nonatomic) ORReaderTheme theme;
@property (nonatomic) ORReaderFont font;
@property (nonatomic) NSInteger fontSize;
@property (nonatomic) double lineHeight;
@property (nonatomic) NSInteger margin;
@property (nonatomic) BOOL justify;
@property (nonatomic) BOOL hyphenate;
@property (nonatomic) BOOL animatePages;
@property (nonatomic) ORPageDirection pageDirection;
@property (nonatomic) float speechRate;
@property (nonatomic) float playbackRate;
@property (nonatomic) BOOL keepScreenAwake;
@property (nonatomic) BOOL syncProgress;
/// Ignore the book's own CSS (broken EPUBs with overlapping text).
@property (nonatomic) BOOL simpleLayout;

@property (nonatomic, copy) NSString *yandexClientID;
@property (nonatomic, copy, nullable) NSString *yandexToken;
@property (nonatomic, copy, nullable) NSString *yandexUserName;

- (UIColor *)themeBackgroundColor;
- (UIColor *)themeTextColor;
- (UIColor *)themeSecondaryColor;
- (NSString *)cssFontFamily;
- (NSString *)cssBackgroundColor;
- (NSString *)cssTextColor;

- (NSArray<NSDictionary *> *)opdsCatalogs;
- (void)addOPDSCatalog:(NSDictionary *)catalog;
- (void)removeOPDSCatalogWithID:(NSString *)catalogID;
- (void)setPassword:(nullable NSString *)password forOPDSCatalog:(NSString *)catalogID;
- (nullable NSString *)passwordForOPDSCatalog:(NSString *)catalogID;

- (void)synchronize;

@end

#pragma mark - Keychain

@interface ORKeychain : NSObject

+ (BOOL)setString:(NSString *)value forKey:(NSString *)key;
+ (nullable NSString *)stringForKey:(NSString *)key;
+ (BOOL)removeKey:(NSString *)key;
+ (BOOL)isUsingFallbackStorage;

@end

NS_ASSUME_NONNULL_END
