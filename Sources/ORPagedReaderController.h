#import <UIKit/UIKit.h>
#import "ORCore.h"

NS_ASSUME_NONNULL_BEGIN

@class ORPagedReaderController;

@protocol ORPagedReaderDelegate <NSObject>
@optional
- (void)pagedReader:(ORPagedReaderController *)reader didChangeProgress:(double)fraction;
@end

@interface ORPagedReaderController : UIViewController

- (instancetype)initWithBook:(ORBook *)book
                        body:(NSString *)htmlBody
                    extraCSS:(NSString *)extraCSS
                    basePath:(nullable NSString *)basePath
                         toc:(NSArray<ORTOCItem *> *)toc;

@property (nonatomic, weak, nullable) id<ORPagedReaderDelegate> delegate;
@property (nonatomic, readonly) ORBook *book;

@end

NS_ASSUME_NONNULL_END
