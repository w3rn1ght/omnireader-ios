#import <UIKit/UIKit.h>
#import "ORCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface ORReaderFactory : NSObject

/// Builds the right reader for the book. Text formats build their layout on a
/// background queue and call `completion` on the main queue.
+ (void)openBook:(ORBook *)book
      presenter:(UIViewController *)presenter
     completion:(void (^)(UIViewController *_Nullable controller, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END