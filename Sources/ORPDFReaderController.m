#import "ORPDFReaderController.h"
#import "ORReaderSettingsController.h"
#import "ORTableOfContentsController.h"
#import "ORUtil.h"
#import <AVFoundation/AVFoundation.h>
#import <PDFKit/PDFKit.h>

@interface ORPDFReaderController () <PDFViewDelegate>
@property (nonatomic, strong) ORBook *book;
@property (nonatomic, strong) PDFView *pdfView;
@property (nonatomic, strong) PDFDocument *document;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *pageLabel;
@property (nonatomic) BOOL chromeVisible;
@property (nonatomic, strong) AVSpeechSynthesizer *speech;
@property (nonatomic) BOOL isSpeaking;
@property (nonatomic, strong) UIButton *speechButton;
@end

@implementation ORPDFReaderController

- (instancetype)initWithBook:(ORBook *)book {
    self = [super init];
    if (self) _book = book;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self loadDocument];
    [self setupChrome];
    [self setupGestures];
    [self restorePosition];
}

- (BOOL)prefersStatusBarHidden { return !self.chromeVisible; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self persistProgress];
    [self stopSpeech];
}

- (void)loadDocument {
    NSURL *url = [NSURL fileURLWithPath:[ORPaths pathForBook:self.book]];
    self.document = [[PDFDocument alloc] initWithURL:url];
    self.pdfView = [[PDFView alloc] initWithFrame:self.view.bounds];
    self.pdfView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.pdfView.autoScales = YES;
    self.pdfView.displayMode = kPDFDisplaySinglePageContinuous;
    self.pdfView.displayDirection = kPDFDisplayDirectionVertical;
    self.pdfView.document = self.document;
    self.pdfView.backgroundColor = [UIColor colorWithWhite:0.09 alpha:1.0];
    self.pdfView.pageBreakMargins = UIEdgeInsetsMake(6, 0, 6, 0);
    self.pdfView.delegate = self;
    if (@available(iOS 11.0, *)) {
        self.pdfView.pageShadowsEnabled = NO;
    }
    [self.view addSubview:self.pdfView];

    if (!self.document) {
        UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
        label.text = @"Не удалось открыть PDF";
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        [self.view addSubview:label];
    }
}

- (void)setupChrome {
    self.topBar = [[UIView alloc] init];
    self.topBar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.94];
    [self.view addSubview:self.topBar];

    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    [back setTitle:@"Выход" forState:UIControlStateNormal];
    [back setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    back.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    back.tag = 1;
    [self.topBar addSubview:back];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = self.book.title;
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.topBar addSubview:self.titleLabel];

    self.bottomBar = [[UIView alloc] init];
    self.bottomBar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.94];
    [self.view addSubview:self.bottomBar];

    self.pageLabel = [[UILabel alloc] init];
    self.pageLabel.textColor = [UIColor whiteColor];
    self.pageLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.pageLabel.textAlignment = NSTextAlignmentCenter;
    [self.bottomBar addSubview:self.pageLabel];

    NSArray<NSString *> *titles = @[@"☰", @"A⁺", @"A⁻", @"🔊"];
    NSArray<NSString *> *selectors = @[NSStringFromSelector(@selector(showContents)),
                                       NSStringFromSelector(@selector(zoomIn)),
                                       NSStringFromSelector(@selector(zoomOut)),
                                       NSStringFromSelector(@selector(toggleSpeech))];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:titles[i] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        SEL action = NSSelectorFromString(selectors[i]);
        [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        button.tag = 100 + (NSInteger)i;
        [self.bottomBar addSubview:button];
        if (i == 3) self.speechButton = button;
    }

    self.chromeVisible = YES;
    // The bars start hidden until the first tap, matching the reference readers.
    self.topBar.alpha = 0;
    self.bottomBar.alpha = 0;
    self.topBar.userInteractionEnabled = NO;
    self.bottomBar.userInteractionEnabled = NO;
    self.chromeVisible = NO;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    self.topBar.frame = CGRectMake(0, 0, width, self.view.safeAreaInsets.top + 48);
    self.bottomBar.frame = CGRectMake(0, height - self.view.safeAreaInsets.bottom - 86, width,
                                      self.view.safeAreaInsets.bottom + 86);
    UIButton *back = [self.topBar viewWithTag:1];
    back.frame = CGRectMake(8, self.view.safeAreaInsets.top + 4, 60, 40);
    self.titleLabel.frame = CGRectMake(70, self.view.safeAreaInsets.top + 10, MAX(80, width - 140), 28);
    self.pageLabel.frame = CGRectMake(18, 6, width - 36, 18);
    CGFloat buttonWidth = (width - 36) / 4.0;
    NSInteger index = 0;
    for (UIView *subview in self.bottomBar.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            subview.frame = CGRectMake(18 + buttonWidth * index, 30, buttonWidth, 44);
            index++;
        }
    }
    self.pdfView.frame = self.view.bounds;
}

- (void)setupGestures {
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
    [self.view addGestureRecognizer:tap];
}

- (void)handleTap {
    [self setChromeVisible:!self.chromeVisible animated:YES];
}

- (void)setChromeVisible:(BOOL)visible animated:(BOOL)animated {
    _chromeVisible = visible;
    [self setNeedsStatusBarAppearanceUpdate];
    void (^changes)(void) = ^{
        self.topBar.alpha = visible ? 1.0 : 0.0;
        self.bottomBar.alpha = visible ? 1.0 : 0.0;
    };
    self.topBar.userInteractionEnabled = visible;
    self.bottomBar.userInteractionEnabled = visible;
    if (animated) [UIView animateWithDuration:0.2 animations:changes];
    else changes();
}

#pragma mark - Navigation

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)showContents {
    NSMutableArray<ORTOCItem *> *items = [NSMutableArray array];
    NSUInteger count = MIN((NSUInteger)self.document.pageCount, (NSUInteger)4000);
    for (NSUInteger i = 0; i < count; i++) {
        PDFPage *page = [self.document pageAtIndex:i];
        NSString *label = [page label] ?: [NSString stringWithFormat:@"%lu", (unsigned long)i + 1];
        NSString *title = [page string] ?: @"";
        title = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        title = [title stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        if (title.length > 70) title = [[title substringToIndex:70] stringByAppendingString:@"…"];
        NSString *display = title.length > 0 ? [NSString stringWithFormat:@"%@ · %@", label, title] : label;
        [items addObject:[ORTOCItem itemWithTitle:display level:0 anchor:[NSString stringWithFormat:@"page-%lu", (unsigned long)i]]];
    }
    ORTableOfContentsController *contents = [[ORTableOfContentsController alloc] initWithItems:items];
    contents.onSelect = ^(ORTOCItem *item) {
        NSInteger page = [[item.anchor stringByReplacingOccurrencesOfString:@"page-" withString:@""] integerValue];
        [self dismissViewControllerAnimated:YES completion:nil];
        PDFPage *target = [self.document pageAtIndex:(NSUInteger)MAX(0, page)];
        if (target) {
            [self.pdfView goToPage:target];
            [self setChromeVisible:NO animated:YES];
        }
        [self persistProgress];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:contents];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)zoomIn {
    self.pdfView.scaleFactor = MIN(self.pdfView.maxScaleFactor, self.pdfView.scaleFactor * 1.25);
}

- (void)zoomOut {
    self.pdfView.scaleFactor = MAX(self.pdfView.minScaleFactor, self.pdfView.scaleFactor / 1.25);
}

#pragma mark - Progress

- (NSInteger)currentPageIndex {
    PDFPage *page = self.pdfView.currentPage;
    if (!page) return 0;
    return [self.document indexForPage:page];
}

- (void)persistProgress {
    NSInteger total = self.document.pageCount;
    if (total <= 0) return;
    double fraction = (double)self.currentPageIndex / (double)MAX(1, total - 1);
    self.book.progress = MAX(0.0, MIN(1.0, fraction));
    [[ORLibrary shared] setProgress:self.book.progress forBookID:self.book.bookID];
    self.pageLabel.text = [NSString stringWithFormat:@"%ld / %ld",
                           (long)self.currentPageIndex + 1, (long)total];
}

- (void)restorePosition {
    NSInteger total = self.document.pageCount;
    if (total <= 1) return;
    NSInteger target = (NSInteger)llround(self.book.progress * (double)(total - 1));
    target = MAX(0, MIN(total - 1, target));
    PDFPage *page = [self.document pageAtIndex:(NSUInteger)target];
    if (page) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.pdfView goToPage:page];
            [self persistProgress];
        });
    }
}

#pragma mark - PDFViewDelegate

- (void)pdfViewPageChanged:(NSNotification *)notification {
    [self persistProgress];
}

#pragma mark - Speech

- (void)toggleSpeech {
    if (self.isSpeaking) {
        [self.speech pauseSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        self.isSpeaking = NO;
        [self.speechButton setTitle:@"🔊" forState:UIControlStateNormal];
        return;
    }
    NSInteger index = self.currentPageIndex;
    NSMutableString *text = [NSMutableString string];
    NSInteger limit = MIN(self.document.pageCount, index + 3);
    for (NSInteger i = index; i < limit; i++) {
        NSString *pageText = [[self.document pageAtIndex:(NSUInteger)i] string];
        if (pageText.length > 0) {
            [text appendString:pageText];
            [text appendString:@"\n"];
        }
    }
    if (text.length == 0) {
        [ORUtil presentAlertIn:self title:@"Озвучка" message:@"На этих страницах нет текста (возможно, это сканы)."];
        return;
    }
    if (!self.speech) self.speech = [[AVSpeechSynthesizer alloc] init];
    NSString *remaining = text;
    if (self.speech.isPaused) {
        [self.speech continueSpeaking];
    } else {
        if (self.speech.isSpeaking) [self.speech stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionDuckOthers error:NULL];
        [session setActive:YES error:NULL];
        AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:remaining];
        utterance.rate = [ORSettings shared].speechRate * AVSpeechUtteranceDefaultSpeechRate;
        [self.speech speakUtterance:utterance];
    }
    self.isSpeaking = YES;
    [self.speechButton setTitle:@"⏸" forState:UIControlStateNormal];
}

- (void)stopSpeech {
    [self.speech stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    self.isSpeaking = NO;
}

@end
