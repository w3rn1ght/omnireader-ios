#import <UIKit/UIKit.h>
#import "ORCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface ORReaderSettingsController : UITableViewController

@property (nonatomic, copy, nullable) void (^onChange)(void);

- (instancetype)initWithSettings:(ORSettings *)settings;

@end

NS_ASSUME_NONNULL_END
