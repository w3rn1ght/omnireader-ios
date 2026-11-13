#import <UIKit/UIKit.h>
#import "ORCore.h"

NS_ASSUME_NONNULL_BEGIN

/// Shown for DjVu files that carry no hidden text layer (a plain scan).
///
/// OmniReader decodes the DjVu text layer but does not rasterise IW44/JB2
/// images, so such files cannot be displayed in-app. This controller explains
/// that and hands the file to an installed DjVu viewer instead of failing with
/// a generic alert.
@interface ORDJVUReaderController : UIViewController

- (instancetype)initWithBook:(ORBook *)book pageCount:(NSInteger)pageCount;

@end

NS_ASSUME_NONNULL_END
