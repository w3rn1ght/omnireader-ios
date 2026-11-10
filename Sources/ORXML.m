#import "ORXML.h"
#import "ORText.h"

@implementation ORXMLNode

- (instancetype)init {
    self = [super init];
    if (self) {
        _name = @"";
        _attributes = [NSMutableDictionary dictionary];
        _children = [NSMutableArray array];
        _text = [NSMutableString string];
    }
    return self;
}

- (NSString *)attr:(NSString *)name {
    if (name.length == 0) return nil;
    NSString *lower = name.lowercaseString;
    NSString *value = self.attributes[lower];
    if (value) return value;
    for (NSString *key in self.attributes) {
        if ([key hasSuffix:[@":" stringByAppendingString:lower]]) return self.attributes[key];
    }
    return nil;
}

- (NSArray<ORXMLNode *> *)childrenNamed:(NSString *)name {
    NSString *lower = name.lowercaseString;
    NSMutableArray *result = [NSMutableArray array];
    for (ORXMLNode *child in self.children) {
        if ([child.name isEqualToString:lower]) [result addObject:child];
    }
    return result;
}

- (ORXMLNode *)firstChildNamed:(NSString *)name {
    return [self childrenNamed:name].firstObject;
}

- (NSString *)innerText {
    NSMutableString *result = [NSMutableString string];
    if (self.text.length > 0) [result appendString:self.text];
    for (ORXMLNode *child in self.children) {
        NSString *childText = [child innerText];
        if (childText.length > 0) [result appendString:childText];
    }
    return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSArray<ORXMLNode *> *)descendantsNamed:(NSString *)name {
    NSString *lower = name.lowercaseString;
    NSMutableArray *result = [NSMutableArray array];
    for (ORXMLNode *child in self.children) {
        if ([child.name isEqualToString:lower]) [result addObject:child];
        [result addObjectsFromArray:[child descendantsNamed:lower]];
    }
    return result;
}

@end

@interface ORXMLParserDelegate : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) ORXMLNode *root;
@property (nonatomic, strong) NSMutableArray<ORXMLNode *> *stack;
@property (nonatomic, strong) NSError *parseError;
@end

@implementation ORXMLParserDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _stack = [NSMutableArray array];
    }
    return self;
}

- (NSString *)localName:(NSString *)name {
    NSArray<NSString *> *parts = [name componentsSeparatedByString:@":"];
    return [parts.lastObject lowercaseString];
}

- (void)parser:(NSXMLParser *)parser
didStartElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI
 qualifiedName:(NSString *)qName
    attributes:(NSDictionary<NSString *, NSString *> *)attributeDict {
    ORXMLNode *node = [[ORXMLNode alloc] init];
    node.name = [self localName:elementName];
    for (NSString *key in attributeDict) {
        NSString *localKey = [self localName:key];
        node.attributes[localKey] = attributeDict[key] ?: @"";
    }
    ORXMLNode *parent = self.stack.lastObject;
    if (parent) {
        node.parent = parent;
        [parent.children addObject:node];
    } else if (!self.root) {
        self.root = node;
    }
    [self.stack addObject:node];
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    ORXMLNode *current = self.stack.lastObject;
    if (current && string.length > 0) [current.text appendString:string];
}

- (void)parser:(NSXMLParser *)parser foundCDATA:(NSData *)CDATABlock {
    ORXMLNode *current = self.stack.lastObject;
    if (!current || CDATABlock.length == 0) return;
    NSString *string = [[NSString alloc] initWithData:CDATABlock encoding:NSUTF8StringEncoding];
    if (!string) string = [[NSString alloc] initWithData:CDATABlock encoding:NSWindowsCP1251StringEncoding];
    if (string) [current.text appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if (self.stack.count > 0) [self.stack removeLastObject];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
    if (!self.parseError) self.parseError = parseError;
}

@end

@implementation ORXML

+ (ORXMLNode *)parseDataStrict:(NSData *)data error:(NSError **)error;
+ (nullable NSData *)repairXMLData:(NSData *)data;

+ (ORXMLNode *)parseData:(NSData *)data error:(NSError **)error {
    if (data.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.XML" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Пустые XML-данные"}];
        return nil;
    }
    // First try the document as-is: well-formed feeds parse fast and losslessly.
    NSError *strictError = nil;
    ORXMLNode *root = [self parseDataStrict:data error:&strictError];
    if (root && !strictError) return root;

    // Real catalogs (e.g. lib.rus.ec) send raw '&' or stray quotes inside
    // attribute values. Repair the markup and parse again.
    NSData *repaired = [self repairXMLData:data];
    if (repaired && ![repaired isEqualToData:data]) {
        NSError *repairedError = nil;
        ORXMLNode *fixedRoot = [self parseDataStrict:repaired error:&repairedError];
        if (fixedRoot) {
            NSLog(@"[OmniReader] XML repaired before parsing");
            return fixedRoot;
        }
    }
    // A failed parse still yields a prefix of the tree; prefer it over nothing.
    if (root) return root;
    if (error) *error = strictError ?: [NSError errorWithDomain:@"OmniReader.XML" code:2
                                                       userInfo:@{NSLocalizedDescriptionKey: @"Не удалось разобрать XML"}];
    return nil;
}

+ (ORXMLNode *)parseDataStrict:(NSData *)data error:(NSError **)error {
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    parser.shouldProcessNamespaces = NO;
    parser.shouldReportNamespacePrefixes = NO;
    parser.shouldResolveExternalEntities = NO;
    ORXMLParserDelegate *delegate = [[ORXMLParserDelegate alloc] init];
    parser.delegate = delegate;
    BOOL ok = [parser parse];
    if (!ok || !delegate.root) {
        if (error) *error = delegate.parseError ?: [NSError errorWithDomain:@"OmniReader.XML" code:2
                                                                   userInfo:@{NSLocalizedDescriptionKey: @"Не удалось разобрать XML"}];
        return delegate.root;
    }
    return delegate.root;
}

+ (nullable NSData *)repairXMLData:(NSData *)data {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) text = [[NSString alloc] initWithData:data encoding:NSWindowsCP1251StringEncoding];
    if (text.length == 0) return nil;

    // 1. Escape bare ampersands that do not start a valid entity reference.
    NSRegularExpression *ampersand = [NSRegularExpression regularExpressionWithPattern:
        @"&(?!(?:[a-zA-Z][a-zA-Z0-9]{1,31}|#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6});)"
                                                            options:0 error:NULL];
    text = [ampersand stringByReplacingMatchesInString:text
                                               options:0
                                                 range:NSMakeRange(0, text.length)
                                          withTemplate:@"&amp;"];

    // 2. Replace control characters that XML 1.0 forbids.
    NSMutableString *clean = [text mutableCopy];
    for (NSInteger i = (NSInteger)clean.length - 1; i >= 0; i--) {
        unichar c = [clean characterAtIndex:(NSUInteger)i];
        if (c < 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) {
            [clean replaceCharactersInRange:NSMakeRange((NSUInteger)i, 1) withString:@" "];
        }
    }
    return [clean dataUsingEncoding:NSUTF8StringEncoding];
}

+ (ORXMLNode *)parseString:(NSString *)string error:(NSError **)error {
    if (string.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"OmniReader.XML" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Пустая XML-строка"}];
        return nil;
    }
    // Normalise the declaration so NSXMLParser reads UTF-8 bytes.
    NSString *normalised = [ORText replacePattern:@"(?i)encoding\\s*=\\s*[\"'][^\"']*[\"']"
                                         inString:string
                                     withTemplate:@"encoding=\"utf-8\""];
    NSData *data = [normalised dataUsingEncoding:NSUTF8StringEncoding];
    return [self parseData:data error:error];
}

@end
