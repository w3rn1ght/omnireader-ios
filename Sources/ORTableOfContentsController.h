#import <UIKit/UIKit.h>
#import "ORCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface ORTableOfContentsController : UITableViewController

@property (nonatomic, copy, nullable) void (^onSelect)(ORTOCItem *item);

- (instancetype)initWithItems:(NSArray<ORTOCItem *> *)items;

@end

NS_ASSUME_NONNULL_END
