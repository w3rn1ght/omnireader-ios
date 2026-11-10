#import "ORUtil.h"
#import "ORText.h"

@implementation ORUtil

+ (NSString *)formatBytes:(long long)bytes {
    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;
    return [formatter stringFromByteCount:bytes];
}

+ (BOOL)ensureDirectoryAtURL:(NSURL *)url error:(NSError **)error {
    return [[NSFileManager defaultManager] createDirectoryAtURL:url
                                    withIntermediateDirectories:YES
                                                     attributes:nil
                                                          error:error];
}

+ (NSString *)createDirectoryAtURL:(NSURL *)url {
    NSError *error = nil;
    [self ensureDirectoryAtURL:url error:&error];
    if (error) {
        NSLog(@"[OmniReader] directory error %@: %@", url.path, error);
    }
    return url.path;
}

+ (void)removeItemAtURL:(nullable NSURL *)url {
    if (!url) return;
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

+ (BOOL)isWebURLString:(NSString *)string {
    NSString *lower = string.lowercaseString;
    return [lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"] ||
           [lower hasPrefix:@"data:"] || [lower hasPrefix:@"mailto:"] ||
           [lower hasPrefix:@"tel:"];
}

+ (NSString *)htmlEscape:(NSString *)string {
    if (string.length == 0) return @"";
    NSMutableString *result = [string mutableCopy];
    [result replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, result.length)];
    [result replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, result.length)];
    [result replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, result.length)];
    [result replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, result.length)];
    return result;
}

+ (NSString *)attributeEscape:(NSString *)string {
    return [self htmlEscape:string];
}

+ (NSString *)cssColorFromUIColor:(UIColor *)color {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        if ([color getWhite:&white alpha:&a]) {
            return [NSString stringWithFormat:@"#%02x%02x%02x", (int)(white * 255), (int)(white * 255), (int)(white * 255)];
        }
        return @"#000000";
    }
    return [NSString stringWithFormat:@"#%02x%02x%02x", (int)(r * 255), (int)(g * 255), (int)(b * 255)];
}

+ (UIViewController *)topViewController {
    UIWindow *window = nil;
    for (UIWindow *candidate in [UIApplication sharedApplication].windows) {
        if (candidate.isKeyWindow) {
            window = candidate;
            break;
        }
    }
    if (!window) window = [UIApplication sharedApplication].keyWindow;
    UIViewController *controller = window.rootViewController;
    while (controller) {
        UIViewController *next = controller.presentedViewController;
        if (!next) break;
        controller = next;
    }
    if ([controller isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)controller;
        UIViewController *visible = nav.visibleViewController;
        if (visible) controller = visible;
    } else if ([controller isKindOfClass:[UITabBarController class]]) {
        UIViewController *visible = ((UITabBarController *)controller).selectedViewController;
        if (visible) controller = visible;
    }
    return controller ?: nil;
}

+ (void)presentAlertIn:(UIViewController *)host title:(NSString *)title message:(nullable NSString *)message {
    if (!host) return;
    UIAlertController *alert = [self alertWithTitle:title message:message];
    [host presentViewController:alert animated:YES completion:nil];
}

+ (UIAlertController *)alertWithTitle:(NSString *)title message:(nullable NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    return alert;
}

+ (void)runOnMain:(dispatch_block_t)block {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

+ (UIImage *)imageWithImage:(UIImage *)image scaledToSize:(CGSize)size {
    if (!image || size.width <= 0 || size.height <= 0) return image;
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result ?: image;
}

+ (UIImage *)scaledImage:(UIImage *)image maxPixelSize:(CGFloat)maxPixelSize {
    if (!image) return nil;
    CGSize size = image.size;
    CGFloat scale = image.scale > 0 ? image.scale : 1.0;
    CGFloat width = size.width * scale;
    CGFloat height = size.height * scale;
    CGFloat longest = MAX(width, height);
    if (longest <= maxPixelSize || longest <= 0) return image;
    CGFloat factor = maxPixelSize / longest;
    CGSize target = CGSizeMake(MAX(1, round(width * factor)), MAX(1, round(height * factor)));
    UIGraphicsBeginImageContextWithOptions(target, NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result ?: image;
}

+ (NSString *)uniqueKey {
    return [[NSUUID UUID] UUIDString].lowercaseString;
}

+ (BOOL)isRTL {
    return [UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
}

+ (NSString *)stripHTML:(NSString *)html {
    return [ORText stripHTML:html];
}

@end
