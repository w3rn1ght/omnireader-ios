#import <UIKit/UIKit.h>
#import "ORCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface ORAudioPlayerController : UIViewController

- (instancetype)initWithBook:(ORBook *)book localPath:(nullable NSString *)localPath;

@end

NS_ASSUME_NONNULL_END