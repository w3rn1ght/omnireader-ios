#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ORZipErrorDomain;

@interface ORZip : NSObject

+ (nullable instancetype)zipWithURL:(NSURL *)url error:(NSError **)error;

@property (nonatomic, readonly) NSArray<NSString *> *names;

- (BOOL)containsEntry:(NSString *)name;
- (nullable NSData *)dataForEntry:(NSString *)name error:(NSError **)error;
- (BOOL)extractToDirectory:(NSString *)directory error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
