#import <Foundation/Foundation.h>
#import "ORCore.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^ORImportCompletion)(ORBook *_Nullable book, NSError *_Nullable error);

@interface ORBookImporter : NSObject

+ (instancetype)shared;

/// Copies the file into the library, sniffs its real format and extracts metadata.
/// Safe to call from a background queue.
- (void)importFileAtURL:(NSURL *)url
             completion:(ORImportCompletion)completion;

/// Registers an audio track that only has a remote URL.
- (ORBook *)addRemoteAudioWithTitle:(NSString *)title
                             author:(nullable NSString *)author
                                url:(NSString *)url;

- (void)deleteBook:(ORBook *)book;

+ (nullable ORBook *)bookFromDictionary:(NSDictionary *)dictionary source:(ORBookSource)source;

@end

NS_ASSUME_NONNULL_END