#import "ORDJVUReaderController.h"
#import "ORUtil.h"

@interface ORDJVUReaderController () <UIDocumentInteractionControllerDelegate>
@property (nonatomic, strong) ORBook *book;
@property (nonatomic) NSInteger pageCount;
@property (nonatomic, strong, nullable) UIDocumentInteractionController *interaction;
@end

@implementation ORDJVUReaderController

- (instancetype)initWithBook:(ORBook *)book pageCount:(NSInteger)pageCount {
    self = [super init];
    if (self) {
        _book = book;
        _pageCount = pageCount;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.book.title.length > 0 ? self.book.title : @"DjVu";
    self.view.backgroundColor = [UIColor whiteColor];
    [self buildInterface];
}

- (void)buildInterface {
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 14;
    [scroll addSubview:stack];

    UILabel *badge = [[UILabel alloc] init];
    badge.text = @"DJVU";
    badge.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    badge.textColor = [UIColor darkGrayColor];
    badge.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:badge];

    UILabel *heading = [[UILabel alloc] init];
    heading.text = @"Этот файл — скан без текстового слоя";
    heading.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    heading.textAlignment = NSTextAlignmentCenter;
    heading.numberOfLines = 0;
    [stack addArrangedSubview:heading];

    NSMutableString *detail = [NSMutableString string];
    if (self.pageCount > 0) {
        [detail appendFormat:@"Страниц: %ld.\n\n", (long)self.pageCount];
    }
    [detail appendString:
        @"OmniReader читает встроенный текстовый слой DjVu, но не декодирует "
         "саму картинку страницы. В этом файле текстового слоя нет — обычно так "
         "бывает со сканами без распознавания.\n\n"
         "Файл можно открыть в любом установленном просмотрщике DjVu. "
         "Книга останется в библиотеке."];
    UILabel *body = [[UILabel alloc] init];
    body.text = detail;
    body.font = [UIFont systemFontOfSize:15];
    body.textColor = [UIColor darkGrayColor];
    body.numberOfLines = 0;
    [stack addArrangedSubview:body];

    UIButton *open = [UIButton buttonWithType:UIButtonTypeSystem];
    [open setTitle:@"Открыть в другом приложении" forState:UIControlStateNormal];
    open.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    open.backgroundColor = self.view.tintColor;
    [open setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    open.layer.cornerRadius = 10;
    open.contentEdgeInsets = UIEdgeInsetsMake(14, 18, 14, 18);
    [open addTarget:self action:@selector(openExternally:) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:open];

    UIButton *share = [UIButton buttonWithType:UIButtonTypeSystem];
    [share setTitle:@"Поделиться файлом" forState:UIControlStateNormal];
    share.titleLabel.font = [UIFont systemFontOfSize:16];
    share.contentEdgeInsets = UIEdgeInsetsMake(10, 16, 10, 16);
    [share addTarget:self action:@selector(shareFile:) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:share];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:28],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-24],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-28],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-48]
    ]];
}

- (void)openExternally:(UIButton *)sender {
    NSString *path = [ORPaths pathForBook:self.book];
    if (path.length == 0) {
        [ORUtil presentAlertIn:self title:@"DjVu" message:@"Файл книги не найден."];
        return;
    }
    self.interaction = [UIDocumentInteractionController interactionControllerWithURL:
                            [NSURL fileURLWithPath:path]];
    self.interaction.delegate = self;
    BOOL shown = [self.interaction presentOpenInMenuFromRect:sender.bounds
                                                     inView:sender
                                                   animated:YES];
    if (!shown) {
        [ORUtil presentAlertIn:self title:@"Нет просмотрщика DjVu"
                        message:@"На устройстве не установлено приложение, которое открывает файлы DjVu. "
                                 "Можно сохранить файл и открыть его на компьютере."];
    }
}

- (void)shareFile:(UIButton *)sender {
    NSString *path = [ORPaths pathForBook:self.book];
    if (path.length == 0) {
        [ORUtil presentAlertIn:self title:@"DjVu" message:@"Файл книги не найден."];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:path]]
        applicationActivities:nil];
    share.popoverPresentationController.sourceView = sender;
    share.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:share animated:YES completion:nil];
}

#pragma mark - UIDocumentInteractionControllerDelegate

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    return self;
}

- (CGRect)documentInteractionControllerRectForPreview:(UIDocumentInteractionController *)controller {
    return self.view.bounds;
}

- (UIView *)documentInteractionControllerViewForPreview:(UIDocumentInteractionController *)controller {
    return self.view;
}

@end
