#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Opens books.yandex.ru inside the app so the user can sign in with the normal
/// Yandex form. When the session is established the passport cookies are saved
/// for the shelf requests (see ORYandexSession).
///
/// The OAuth consent screen does not render correctly on iOS 12, but the plain
/// passport login form does; that is why the shelf uses this flow.
@interface ORYandexWebLoginController : UIViewController

/// Called after «Готово»: success is YES when a yandex.ru cookie was captured.
@property (nonatomic, copy, nullable) void (^onFinish)(BOOL success, NSString *_Nullable message);

@end

NS_ASSUME_NONNULL_END
