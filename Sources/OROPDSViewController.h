#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OROPDSViewController : UITableViewController

+ (void)presentPickerFrom:(UIViewController *)presenter;
+ (void)presentCatalog:(NSDictionary *)catalog from:(UIViewController *)presenter;

- (instancetype)initWithURL:(NSString *)url
                      title:(NSString *)title
                    catalog:(nullable NSDictionary *)catalog;

@end

NS_ASSUME_NONNULL_END
