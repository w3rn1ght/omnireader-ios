#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// One page of a DjVu document.
///
/// The hidden text layer (TXTz/TXTa) is decoded lazily; `html` is a sequence of
/// paragraphs ready for ORPagedReaderController.
@interface ORDJVUPage : NSObject

/// 1-based page number.
@property (nonatomic, readonly) NSInteger index;
/// Page size in pixels (from the INFO chunk), or CGSizeZero when unknown.
@property (nonatomic, readonly) CGSize pixelSize;
@property (nonatomic, readonly) NSInteger dpi;
/// Raw hidden text, newlines preserved.
@property (nonatomic, readonly) NSString *text;
/// Paragraph HTML built from the text/zone tree; empty when there is no text.
@property (nonatomic, readonly) NSString *html;
@property (nonatomic, readonly) BOOL hasText;

@end

/// Minimal, dependency-free DjVu parser.
///
/// It understands the IFF container (single-page DJVU and bundled DJVM) and the
/// hidden text layer. It does not rasterise pages: DjVu images need an IW44 /
/// JB2 decoder, which this project does not ship. Files without a text layer
/// therefore report `hasTextLayer == NO` so the UI can offer another viewer.
@interface ORDJVUDocument : NSObject

/// Parses the container only; text is decoded on demand.
+ (nullable instancetype)documentAtPath:(NSString *)path error:(NSError **)error;

@property (nonatomic, readonly) NSInteger pageCount;
/// "DJVU" for a single page, "DJVM" for a bundle.
@property (nonatomic, readonly) NSString *documentType;
/// YES when at least one page carries a hidden text layer.
@property (nonatomic, readonly) BOOL hasTextLayer;
/// Number of pages that actually contain text.
@property (nonatomic, readonly) NSInteger textPageCount;

/// 0-based lookup; pages are cached after the first access.
- (nullable ORDJVUPage *)pageAtIndex:(NSInteger)index;

/// Concatenated paragraph HTML of every page, as `<section>` blocks.
- (NSString *)combinedHTML;
/// Whole document text, pages separated by blank lines.
- (NSString *)combinedPlainText;

/// Extra CSS used by the DJVU reader (page markers).
+ (NSString *)readerCSS;

@end

NS_ASSUME_NONNULL_END
