#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Small helpers that would otherwise be copy-pasted a dozen times.
@interface ORUtil : NSObject

+ (NSString *)formatBytes:(long long)bytes;
+ (BOOL)ensureDirectoryAtURL:(NSURL *)url error:(NSError **)error;
+ (NSString *)createDirectoryAtURL:(NSURL *)url;
+ (void)removeItemAtURL:(nullable NSURL *)url;
+ (BOOL)isWebURLString:(NSString *)string;

+ (NSString *)htmlEscape:(NSString *)string;
+ (NSString *)attributeEscape:(NSString *)string;

/// Hex-ish color like #RRGGBB for CSS.
+ (NSString *)cssColorFromUIColor:(UIColor *)color;

+ (UIViewController *)topViewController;

+ (void)presentAlertIn:(UIViewController *)host
                  title:(NSString *)title
                message:(nullable NSString *)message;

+ (UIAlertController *)alertWithTitle:(NSString *)title message:(nullable NSString *)message;

/// Runs `block` on the main queue if needed.
+ (void)runOnMain:(dispatch_block_t)block;

+ (UIImage *)scaledImage:(UIImage *)image maxPixelSize:(CGFloat)maxPixelSize;

+ (UIImage *)imageWithImage:(UIImage *)image scaledToSize:(CGSize)size;

+ (NSString *)uniqueKey;

+ (BOOL)isRTL;

@end

NS_ASSUME_NONNULL_END
