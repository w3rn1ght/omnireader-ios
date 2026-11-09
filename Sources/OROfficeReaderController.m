#import "OROfficeReaderController.h"
#import "OROfficeText.h"
#import "ORPagedReaderController.h"
#import "ORUtil.h"
#import <QuickLook/QuickLook.h>

@interface OROfficeReaderController () <QLPreviewControllerDataSource>
@property (nonatomic, strong) ORBook *book;
@property (nonatomic, strong) QLPreviewController *previewController;
@property (nonatomic, strong) UIView *previewContainer;
@property (nonatomic, strong) UIView *topBar;
@end

@implementation OROfficeReaderController

- (instancetype)initWithBook:(ORBook *)book {
    self = [super init];
    if (self) _book = book;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    [self buildTopBar];
    [self buildQuickLook];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat height = self.view.bounds.size.height;
    self.topBar.frame = CGRectMake(0, 0, self.view.bounds.size.width, self.view.safeAreaInsets.top + 46);
    [self.view bringSubviewToFront:self.topBar];

    UIButton *backButton = nil;
    UIButton *textButton = nil;
    UILabel *titleLabel = nil;
    for (UIView *subview in self.topBar.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            if (subview.frame.origin.x < 10) backButton = (UIButton *)subview;
            else textButton = (UIButton *)subview;
        } else if ([subview isKindOfClass:[UILabel class]]) {
            titleLabel = (UILabel *)subview;
        }
    }
    CGFloat top = self.view.safeAreaInsets.top;
    backButton.frame = CGRectMake(8, top + 3, 70, 40);
    textButton.frame = CGRectMake(self.view.bounds.size.width - 78, top + 3, 70, 40);
    titleLabel.frame = CGRectMake(84, top + 9, self.view.bounds.size.width - 168, 28);

    CGFloat width = self.view.bounds.size.width;
    self.previewContainer.frame = CGRectMake(0, self.view.safeAreaInsets.top + 46,
                                             width,
                                             height - self.view.safeAreaInsets.top - 46);
    [self.previewController.view setFrame:self.previewContainer.bounds];
}

- (void)buildQuickLook {
    self.previewContainer = [[UIView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:self.previewContainer];

    self.previewController = [[QLPreviewController alloc] init];
    self.previewController.dataSource = self;
    [self addChildViewController:self.previewController];
    self.previewController.view.frame = self.previewContainer.bounds;
    [self.previewContainer addSubview:self.previewController.view];
    [self.previewController didMoveToParentViewController:self];
}

- (void)buildTopBar {
    self.topBar = [[UIView alloc] init];
    self.topBar.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.topBar];

    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    [back setTitle:@"Назад" forState:UIControlStateNormal];
    [back setTitleColor:self.view.tintColor forState:UIControlStateNormal];
    [back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    back.frame = CGRectMake(8, self.view.safeAreaInsets.top + 4, 70, 40);
    [self.topBar addSubview:back];

    UIButton *text = [UIButton buttonWithType:UIButtonTypeSystem];
    [text setTitle:@"Текст" forState:UIControlStateNormal];
    [text setTitleColor:self.view.tintColor forState:UIControlStateNormal];
    [text addTarget:self action:@selector(showText) forControlEvents:UIControlEventTouchUpInside];
    text.frame = CGRectMake(self.view.bounds.size.width - 78, self.view.safeAreaInsets.top + 4, 70, 40);
    text.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.topBar addSubview:text];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(84, self.view.safeAreaInsets.top + 10,
                                                               self.view.bounds.size.width - 168, 28)];
    title.text = self.book.title;
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    title.textAlignment = NSTextAlignmentCenter;
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.topBar addSubview:title];
}

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)showText {
    NSString *path = [ORPaths pathForBook:self.book];
    NSError *error = nil;
    NSString *html = [OROfficeText htmlFromDocumentAtPath:path format:self.book.format error:&error];
    if (html.length == 0) {
        [ORUtil presentAlertIn:self title:@"Извлечение текста"
                        message:error.localizedDescription ?: @"Из этого документа нельзя извлечь текст."];
        return;
    }
    NSString *basePath = [[ORPaths extractedDirectory] stringByAppendingPathComponent:
                             [self.book.bookID stringByReplacingOccurrencesOfString:@"/" withString:@"_"]];
    [[NSFileManager defaultManager] createDirectoryAtPath:basePath withIntermediateDirectories:YES attributes:nil error:NULL];
    ORPagedReaderController *reader = [[ORPagedReaderController alloc] initWithBook:self.book
                                                                              body:html
                                                                          extraCSS:@""
                                                                          basePath:basePath
                                                                               toc:@[]];
    [self.navigationController pushViewController:reader animated:YES];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return 1;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return [NSURL fileURLWithPath:[ORPaths pathForBook:self.book]];
}

@end