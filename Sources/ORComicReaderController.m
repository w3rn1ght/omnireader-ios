#import "ORComicReaderController.h"
#import "ORMetadata.h"
#import "ORText.h"
#import "ORUtil.h"
#import "ORZip.h"

@interface ORComicReaderController () <UIScrollViewDelegate>
@property (nonatomic, strong) ORBook *book;
@property (nonatomic, strong) ORZip *archive;
@property (nonatomic, strong) NSArray<NSString *> *pages;
@property (nonatomic) NSInteger index;
@property (nonatomic, strong) UIScrollView *zoomView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) NSCache<NSNumber *, UIImage *> *cache;
@property (nonatomic) CGRect fittedRect;
@property (nonatomic) BOOL chromeVisible;
@end

@implementation ORComicReaderController

- (instancetype)initWithBook:(ORBook *)book {
    self = [super init];
    if (self) _book = book;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.cache = [[NSCache alloc] init];
    self.cache.countLimit = 5;
    [self openArchive];
    [self buildInterface];
    [self showPage:0];
}

- (BOOL)prefersStatusBarHidden { return !self.chromeVisible; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (void)openArchive {
    NSString *path = [ORPaths pathForBook:self.book];
    NSData *head = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    if (![ORText looksLikeZIP:head] && [ORText looksLikeRAR:head]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [ORUtil presentAlertIn:self title:@"CBR не поддерживается"
                            message:@"Формат RAR не встроен в iOS. Перепакуйте архив в CBZ (это обычный ZIP) — приложение откроет его без конвертации страниц."];
        });
        return;
    }
    self.archive = [ORZip zipWithURL:[NSURL fileURLWithPath:path] error:NULL];
    self.pages = [ORMetadata sortedImageNamesInZip:self.archive];
}

- (void)buildInterface {
    self.zoomView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.zoomView.delegate = self;
    self.zoomView.minimumZoomScale = 1.0;
    self.zoomView.maximumZoomScale = 4.0;
    self.zoomView.bouncesZoom = YES;
    self.zoomView.showsHorizontalScrollIndicator = NO;
    self.zoomView.showsVerticalScrollIndicator = NO;
    self.zoomView.backgroundColor = [UIColor blackColor];
    self.zoomView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.zoomView];

    self.imageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.zoomView addSubview:self.imageView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = self.book.title;
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.alpha = 0;
    [self.view addSubview:self.titleLabel];

    self.counterLabel = [[UILabel alloc] init];
    self.counterLabel.textColor = [UIColor whiteColor];
    self.counterLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.counterLabel.textAlignment = NSTextAlignmentCenter;
    self.counterLabel.alpha = 0;
    [self.view addSubview:self.counterLabel];

    UISwipeGestureRecognizer *left = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(nextPage)];
    left.direction = UISwipeGestureRecognizerDirectionLeft;
    [self.view addGestureRecognizer:left];
    UISwipeGestureRecognizer *right = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(previousPage)];
    right.direction = UISwipeGestureRecognizerDirectionRight;
    [self.view addGestureRecognizer:right];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleChrome)];
    [self.zoomView addGestureRecognizer:tap];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    self.zoomView.frame = self.view.bounds;
    self.titleLabel.frame = CGRectMake(56, self.view.safeAreaInsets.top + 8, width - 112, 28);
    self.counterLabel.frame = CGRectMake(56, self.view.bounds.size.height - self.view.safeAreaInsets.bottom - 26,
                                         width - 112, 20);
    [self layoutImage];
}

- (void)layoutImage {
    UIImage *image = self.imageView.image;
    if (!image || image.size.width <= 0 || image.size.height <= 0) return;
    CGSize bounds = self.zoomView.bounds.size;
    if (bounds.width <= 0 || bounds.height <= 0) return;
    CGFloat scale = MIN(bounds.width / image.size.width, bounds.height / image.size.height);
    CGFloat width = image.size.width * scale;
    CGFloat height = image.size.height * scale;
    self.zoomView.minimumZoomScale = 1.0;
    self.zoomView.maximumZoomScale = 4.0;
    self.zoomView.zoomScale = 1.0;
    self.zoomView.contentSize = CGSizeMake(width, height);
    self.imageView.frame = CGRectMake(0, 0, width, height);
    self.zoomView.contentInset = UIEdgeInsetsMake(MAX(0, (bounds.height - height) / 2.0),
                                                  MAX(0, (bounds.width - width) / 2.0),
                                                  MAX(0, (bounds.height - height) / 2.0),
                                                  MAX(0, (bounds.width - width) / 2.0));
}

- (void)showPage:(NSInteger)page {
    if (self.pages.count == 0) {
        self.imageView.image = nil;
        self.counterLabel.text = @"Нет изображений";
        return;
    }
    self.index = MAX(0, MIN((NSInteger)self.pages.count - 1, page));
    [self.zoomView setZoomScale:1.0 animated:NO];
    self.counterLabel.text = [NSString stringWithFormat:@"%ld / %ld", (long)self.index + 1, (long)self.pages.count];
    self.book.progress = self.pages.count > 1 ? (double)self.index / (double)(self.pages.count - 1) : 0;
    [[ORLibrary shared] setProgress:self.book.progress forBookID:self.book.bookID];

    UIImage *cached = [self.cache objectForKey:@(self.index)];
    if (cached) {
        self.imageView.image = cached;
        [self layoutImage];
        return;
    }
    NSString *name = self.pages[(NSUInteger)self.index];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *data = [self.archive dataForEntry:name error:NULL];
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (image) [strongSelf.cache setObject:image forKey:@(strongSelf.index)];
            strongSelf.imageView.image = image;
            [strongSelf layoutImage];
            [strongSelf prefetchNeighbours];
        });
    });
}

- (void)prefetchNeighbours {
    for (NSInteger offset = -1; offset <= 1; offset += 2) {
        NSInteger target = self.index + offset;
        if (target < 0 || target >= (NSInteger)self.pages.count) continue;
        if ([self.cache objectForKey:@(target)]) continue;
        NSString *name = self.pages[(NSUInteger)target];
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSData *data = [weakSelf.archive dataForEntry:name error:NULL];
            UIImage *image = data ? [UIImage imageWithData:data] : nil;
            if (image) [weakSelf.cache setObject:image forKey:@(target)];
        });
    }
}

- (void)nextPage {
    if (self.zoomView.zoomScale > 1.01) return;
    [self showPage:self.index + 1];
}

- (void)previousPage {
    if (self.zoomView.zoomScale > 1.01) return;
    [self showPage:self.index - 1];
}

- (void)toggleChrome {
    self.chromeVisible = !self.chromeVisible;
    [self setNeedsStatusBarAppearanceUpdate];
    [UIView animateWithDuration:0.2 animations:^{
        self.titleLabel.alpha = self.chromeVisible ? 1 : 0;
        self.counterLabel.alpha = self.chromeVisible ? 1 : 0;
    }];
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    CGFloat width = scrollView.bounds.size.width;
    CGFloat height = scrollView.bounds.size.height;
    CGFloat contentWidth = scrollView.contentSize.width;
    CGFloat contentHeight = scrollView.contentSize.height;
    CGFloat offsetX = MAX((width - contentWidth) / 2.0, 0);
    CGFloat offsetY = MAX((height - contentHeight) / 2.0, 0);
    scrollView.contentInset = UIEdgeInsetsMake(offsetY, offsetX, offsetY, offsetX);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.cache = [[NSCache alloc] init];
    self.cache.countLimit = 5;
    [self openArchive];
    [self buildInterface];
    [self showPage:0];
}

@end