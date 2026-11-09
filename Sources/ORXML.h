#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ORXMLNode : NSObject

@property (nonatomic, copy) NSString *name; // lowercase local name
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *attributes;
@property (nonatomic, strong) NSMutableArray<ORXMLNode *> *children;
@property (nonatomic, strong) NSMutableString *text;
@property (nonatomic, weak, nullable) ORXMLNode *parent;

- (nullable NSString *)attr:(NSString *)name;
- (NSArray<ORXMLNode *> *)childrenNamed:(NSString *)name;
- (nullable ORXMLNode *)firstChildNamed:(NSString *)name;
- (NSString *)innerText;
- (NSArray<ORXMLNode *> *)descendantsNamed:(NSString *)name;

@end

@interface ORXML : NSObject

+ (nullable ORXMLNode *)parseData:(NSData *)data error:(NSError **)error;
+ (nullable ORXMLNode *)parseString:(NSString *)string error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
