#import "ORPagedReaderController.h"
#import "ORPagedAssets.h"
#import "ORReaderSettingsController.h"
#import "ORTableOfContentsController.h"
#import "ORUtil.h"
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>

#pragma mark - Chrome container

/// A bar that forwards taps only on its own controls, so a tap on the empty
/// part of the bar closes the interface instead of being swallowed.
@interface ORChromeBar : UIView
@end

@implementation ORChromeBar
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

#pragma mark - Reader

@interface ORPagedReaderController () <WKScriptMessageHandler, WKNavigationDelegate, UIGestureRecognizerDelegate, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) ORBook *book;
@property (nonatomic, copy) NSString *htmlBody;
@property (nonatomic, copy) NSString *extraCSS;
@property (nonatomic, copy, nullable) NSString *basePath;
@property (nonatomic, strong) NSArray<ORTOCItem *> *toc;

@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) ORChromeBar *topBar;
@property (nonatomic, strong) ORChromeBar *bottomBar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *pageLabel;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UIButton *speechButton;
@property (nonatomic, strong) UIButton *bookmarkButton;
@property (nonatomic, strong) UIView *searchPanel;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *searchResults;
@property (nonatomic, strong) NSArray<NSString *> *searchHits;
@property (nonatomic, strong, nullable) NSTimer *liveSearchTimer;

@property (nonatomic) BOOL chromeVisible;
@property (nonatomic) BOOL needsInitialJump;
@property (nonatomic) double restoreFraction;
@property (nonatomic) NSInteger pageIndex;
@property (nonatomic) NSInteger pageCount;
@property (nonatomic) BOOL isSpeaking;
@property (nonatomic, strong) AVSpeechSynthesizer *speech;
@property (nonatomic, strong) UITapGestureRecognizer *tapRecognizer;

@end

@implementation ORPagedReaderController

- (instancetype)initWithBook:(ORBook *)book
                        body:(NSString *)htmlBody
                    extraCSS:(NSString *)extraCSS
                    basePath:(NSString *)basePath
                         toc:(NSArray<ORTOCItem *> *)toc {
    self = [super init];
    if (self) {
        _book = book;
        _htmlBody = [htmlBody copy] ?: @"";
        _extraCSS = [extraCSS copy] ?: @"";
        _basePath = [basePath copy];
        _toc = toc ?: @[];
        _restoreFraction = MAX(0.0, MIN(1.0, book.progress));
        _needsInitialJump = YES;
        _pageCount = 1;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [[ORSettings shared] themeBackgroundColor];
    [self setupWebView];
    [self setupChrome];
    [self setupSearchPanel];
    [self loadDocument];
    [self installGestures];
}

- (BOOL)prefersStatusBarHidden { return !self.chromeVisible; }

- (UIStatusBarStyle)preferredStatusBarStyle {
    return [[ORSettings shared] theme] == ORReaderThemeNight ? UIStatusBarStyleLightContent : UIStatusBarStyleDefault;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    if ([ORSettings shared].keepScreenAwake) [UIApplication sharedApplication].idleTimerDisabled = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [self stopSpeech];
    [self persistProgress];
}

#pragma mark - Setup

- (void)setupWebView {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.allowsInlineMediaPlayback = YES;
    configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    WKUserContentController *controller = [[WKUserContentController alloc] init];
    [controller addScriptMessageHandler:self name:@"omni"];
    configuration.userContentController = controller;

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    self.webView.navigationDelegate = self;
    self.webView.scrollView.bounces = NO;
    self.webView.opaque = YES;
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.backgroundColor = [[ORSettings shared] themeBackgroundColor];
    self.webView.scrollView.backgroundColor = [[ORSettings shared] themeBackgroundColor];
    // Text selection is needed for notes/highlights; long press stays native.
    self.webView.allowsBackForwardNavigationGestures = NO;
    [self.view addSubview:self.webView];
}

- (void)loadDocument {
    ORSettings *settings = [ORSettings shared];
    NSString *html = [ORPagedAssets documentHTMLWithBody:self.htmlBody
                                                extraCSS:self.extraCSS
                                                   title:self.book.title
                                                settings:settings];
    if (self.basePath.length > 0) {
        NSString *htmlPath = [self.basePath stringByAppendingPathComponent:@"__omnireader.html"];
        NSError *writeError = nil;
        if ([html writeToFile:htmlPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
            [self.webView loadFileURL:[NSURL fileURLWithPath:htmlPath]
              allowingReadAccessToURL:[NSURL fileURLWithPath:self.basePath]];
            return;
        }
        NSLog(@"[OmniReader] html write failed: %@", writeError);
    }
    [self.webView loadHTMLString:html baseURL:nil];
}

- (UIButton *)barButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [button setTitleColor:[[ORSettings shared] themeTextColor] forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.contentEdgeInsets = UIEdgeInsetsMake(2, 6, 2, 6);
    return button;
}

- (void)applyBarAppearance {
    UIColor *text = [[ORSettings shared] themeTextColor];
    UIColor *secondary = [[ORSettings shared] themeSecondaryColor];
    self.topBar.backgroundColor = [secondary colorWithAlphaComponent:0.16];
    self.bottomBar.backgroundColor = [secondary colorWithAlphaComponent:0.16];
    self.titleLabel.textColor = text;
    self.pageLabel.textColor = text;
    self.slider.tintColor = text;
    for (UIView *subview in self.bottomBar.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            [(UIButton *)subview setTitleColor:text forState:UIControlStateNormal];
        }
    }
    for (UIView *subview in self.topBar.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            [(UIButton *)subview setTitleColor:text forState:UIControlStateNormal];
        }
    }
    self.searchPanel.backgroundColor = [[ORSettings shared] themeBackgroundColor];
    self.searchBar.barTintColor = [[ORSettings shared] themeBackgroundColor];
}

- (void)setupChrome {
    self.topBar = [[ORChromeBar alloc] init];
    self.topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.topBar];

    UIButton *back = [self barButtonWithTitle:@"‹" action:@selector(closeBook)];
    back.titleLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightRegular];
    back.tag = 1001;
    [self.topBar addSubview:back];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = self.book.title;
    self.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.titleLabel.userInteractionEnabled = NO;
    [self.topBar addSubview:self.titleLabel];

    UIButton *search = [self barButtonWithTitle:@"🔍" action:@selector(toggleSearch)];
    search.tag = 1002;
    [self.topBar addSubview:search];

    UIButton *toc = [self barButtonWithTitle:@"☰" action:@selector(showContents)];
    toc.tag = 1003;
    [self.topBar addSubview:toc];

    self.bottomBar = [[ORChromeBar alloc] init];
    self.bottomBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.bottomBar];

    self.slider = [[UISlider alloc] init];
    self.slider.minimumValue = 0;
    self.slider.maximumValue = 1;
    self.slider.continuous = YES;
    [self.slider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    [self.slider addTarget:self action:@selector(sliderReleased) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    self.slider.tag = 2001;
    [self.bottomBar addSubview:self.slider];

    self.pageLabel = [[UILabel alloc] init];
    self.pageLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.pageLabel.textAlignment = NSTextAlignmentCenter;
    self.pageLabel.tag = 2002;
    self.pageLabel.userInteractionEnabled = YES;
    [self.pageLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(promptJump)]];
    [self.bottomBar addSubview:self.pageLabel];

    NSArray *titles = @[@"❮", @"❯", @"Aa", @"📑", @"🔊", @"↕"];
    NSArray *selectors = @[NSStringFromSelector(@selector(previousPage)),
                           NSStringFromSelector(@selector(nextPage)),
                           NSStringFromSelector(@selector(showReaderSettings)),
                           NSStringFromSelector(@selector(toggleBookmark)),
                           NSStringFromSelector(@selector(toggleSpeech)),
                           NSStringFromSelector(@selector(toggleDirection))];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *button = [self barButtonWithTitle:titles[i] action:NSSelectorFromString(selectors[i])];
        button.tag = 2100 + (NSInteger)i;
        [self.bottomBar addSubview:button];
        if (i == 3) {
            self.bookmarkButton = button;
            [button addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                     action:@selector(showBookmarks)]];
        }
        if (i == 4) self.speechButton = button;
    }

    self.chromeVisible = NO;
    self.topBar.alpha = 0;
    self.bottomBar.alpha = 0;
    self.topBar.userInteractionEnabled = NO;
    self.bottomBar.userInteractionEnabled = NO;
    [self applyBarAppearance];
}

- (void)setupSearchPanel {
    self.searchPanel = [[UIView alloc] initWithFrame:CGRectZero];
    self.searchPanel.hidden = YES;
    [self.view addSubview:self.searchPanel];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"Поиск по тексту";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    [self.searchPanel addSubview:self.searchBar];

    self.searchResults = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.searchResults.dataSource = self;
    self.searchResults.delegate = self;
    self.searchResults.rowHeight = 44;
    [self.searchPanel addSubview:self.searchResults];
    self.searchHits = @[];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    self.webView.frame = CGRectMake(0, 0, width, height);

    CGFloat top = self.view.safeAreaInsets.top;
    self.topBar.frame = CGRectMake(0, 0, width, top + 46);
    UIButton *back = [self.topBar viewWithTag:1001];
    UIButton *search = [self.topBar viewWithTag:1002];
    UIButton *toc = [self.topBar viewWithTag:1003];
    back.frame = CGRectMake(4, top, 44, 44);
    toc.frame = CGRectMake(width - 48, top, 44, 44);
    search.frame = CGRectMake(width - 92, top, 44, 44);
    self.titleLabel.frame = CGRectMake(52, top + 10, MAX(60, width - 200), 26);

    CGFloat bottom = self.view.safeAreaInsets.bottom;
    CGFloat barHeight = 104 + bottom;
    self.bottomBar.frame = CGRectMake(0, height - barHeight, width, barHeight);
    self.slider.frame = CGRectMake(16, 4, width - 32, 26);
    self.pageLabel.frame = CGRectMake(16, 28, width - 32, 14);
    CGFloat buttonWidth = (width - 16) / 6.0;
    NSInteger index = 0;
    for (UIView *subview in self.bottomBar.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            subview.frame = CGRectMake(8 + buttonWidth * index, 48, buttonWidth, 42);
            index++;
        }
    }

    self.searchPanel.frame = CGRectMake(0, top + 46, width, MAX(120, height * 0.5));
    self.searchBar.frame = CGRectMake(0, 0, width, 48);
    self.searchResults.frame = CGRectMake(0, 48, width, self.searchPanel.bounds.size.height - 48);

    [self updateContentInsets];
}

- (void)updateContentInsets {
    // The reader reserves space with CSS on the '#viewport', never with padding
    // on '#content': padding on a multicol container breaks column pagination.
    CGFloat top = self.view.safeAreaInsets.top;
    CGFloat bottom = self.view.safeAreaInsets.bottom;
    CGFloat barHeight = 104 + bottom;
    (void)top;
    NSString *js = [NSString stringWithFormat:
        @"(function(){var v=document.getElementById('viewport');if(!v)return;"
         "v.style.paddingTop='8px';"
         "v.style.paddingBottom='%.0fpx';"
         "if(window.Omni){var s=window.Omni.state();window.Omni.relayout(s.fraction||0);}})();",
        MAX(24, barHeight * 0.55)];
    if (!self.needsInitialJump) {
        [self.webView evaluateJavaScript:js completionHandler:nil];
    }
}

#pragma mark - Chrome

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
    [self.view setNeedsLayout];
}

- (void)toggleChrome {
    [self setChromeVisible:!self.chromeVisible animated:YES];
}

- (void)installGestures {
    UISwipeGestureRecognizer *left = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft)];
    left.direction = UISwipeGestureRecognizerDirectionLeft;
    left.delegate = self;
    [self.webView addGestureRecognizer:left];

    UISwipeGestureRecognizer *right = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight)];
    right.direction = UISwipeGestureRecognizerDirectionRight;
    right.delegate = self;
    [self.webView addGestureRecognizer:right];

    self.tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    self.tapRecognizer.delegate = self;
    self.tapRecognizer.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:self.tapRecognizer];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    if (self.searchPanel.hidden == NO) {
        CGPoint point = [tap locationInView:self.view];
        if (CGRectContainsPoint(self.searchPanel.frame, point)) return;
        [self closeSearch];
        return;
    }
    if (self.chromeVisible) {
        CGPoint point = [tap locationInView:self.view];
        if (CGRectContainsPoint(self.topBar.frame, point) || CGRectContainsPoint(self.bottomBar.frame, point)) {
            return;
        }
    }
    [self toggleChrome];
}

#pragma mark - Navigation

- (void)closeBook {
    [self stopSpeech];
    [self persistProgress];
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)goToPage:(NSInteger)page {
    NSString *js = [NSString stringWithFormat:@"window.Omni&&window.Omni.goTo(%ld,true);", (long)page];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)nextPage { [self goToPage:self.pageIndex + 1]; }
- (void)previousPage { [self goToPage:self.pageIndex - 1]; }

- (void)swipeLeft {
    if ([ORSettings shared].pageDirection == ORPageDirectionHorizontal) [self nextPage];
}

- (void)swipeRight {
    if ([ORSettings shared].pageDirection == ORPageDirectionHorizontal) [self previousPage];
}

- (void)sliderChanged {
    double target = self.slider.value;
    NSInteger page = (NSInteger)llround(target * (double)MAX(0, self.pageCount - 1));
    [self goToPage:page];
}

- (void)sliderReleased {
    [self persistProgress];
}

- (void)toggleDirection {
    ORSettings *settings = [ORSettings shared];
    settings.pageDirection = settings.pageDirection == ORPageDirectionHorizontal
        ? ORPageDirectionVertical
        : ORPageDirectionHorizontal;
    [settings synchronize];
    [self applyStyle];
    self.pageLabel.text = settings.pageDirection == ORPageDirectionVertical
        ? @"Режим: прокрутка вниз"
        : @"Режим: страницы вбок";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updatePageLabel];
    });
}

- (void)showContents {
    if (self.toc.count == 0) {
        [ORUtil presentAlertIn:self title:@"Оглавление" message:@"В этом документе нет оглавления."];
        return;
    }
    ORTableOfContentsController *contents = [[ORTableOfContentsController alloc] initWithItems:self.toc];
    __weak typeof(self) weakSelf = self;
    contents.onSelect = ^(ORTOCItem *item) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf dismissViewControllerAnimated:YES completion:nil];
        [strongSelf jumpToAnchor:item.anchor];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:contents];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)jumpToAnchor:(NSString *)anchor {
    if (anchor.length == 0) return;
    NSString *js = [NSString stringWithFormat:@"window.Omni&&window.Omni.goToAnchor(%@);",
                    [ORPagedAssets jsString:anchor]];
    [self.webView evaluateJavaScript:js completionHandler:nil];
    [self setChromeVisible:NO animated:YES];
}

- (void)showReaderSettings {
    ORReaderSettingsController *controller = [[ORReaderSettingsController alloc] initWithSettings:[ORSettings shared]];
    __weak typeof(self) weakSelf = self;
    controller.onChange = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf applyStyle];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)applyStyle {
    ORSettings *settings = [ORSettings shared];
    self.view.backgroundColor = [settings themeBackgroundColor];
    self.webView.backgroundColor = [settings themeBackgroundColor];
    self.webView.scrollView.backgroundColor = [settings themeBackgroundColor];
    [self applyBarAppearance];
    [self setNeedsStatusBarAppearanceUpdate];

    double fraction = self.pageCount > 1 ? (double)self.pageIndex / (double)(self.pageCount - 1) : self.restoreFraction;
    NSString *config = [ORPagedAssets styleConfigurationForSettings:settings];
    NSString *js = [NSString stringWithFormat:
        @"if(window.Omni){window.Omni.applyStyle(%@);}", config];
    [self.webView evaluateJavaScript:js completionHandler:nil];
    self.restoreFraction = fraction;
}

#pragma mark - Bookmarks

- (void)toggleBookmark {
    if (self.pageCount <= 1 && self.pageIndex <= 0) return;
    double fraction = self.pageCount > 1 ? (double)self.pageIndex / (double)(self.pageCount - 1) : 0;
    NSMutableArray<NSDictionary *> *bookmarks = [self.book.bookmarks mutableCopy] ?: [NSMutableArray array];
    NSInteger existing = -1;
    for (NSUInteger i = 0; i < bookmarks.count; i++) {
        if (fabs([bookmarks[i][@"fraction"] doubleValue] - fraction) < 0.005) {
            existing = (NSInteger)i;
            break;
        }
    }
    BOOL added = NO;
    NSNumber *createdAt = @([[NSDate date] timeIntervalSince1970]);
    if (existing >= 0) {
        [bookmarks removeObjectAtIndex:(NSUInteger)existing];
    } else {
        [bookmarks addObject:@{@"fraction": @(fraction),
                               @"page": @(self.pageIndex + 1),
                               @"createdAt": createdAt}];
        added = YES;
    }
    [bookmarks sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"fraction"] compare:b[@"fraction"]];
    }];
    self.book.bookmarks = bookmarks;
    [[ORLibrary shared] updateBook:self.book];
    [self.bookmarkButton setTitle:added ? @"🔖" : @"📑" forState:UIControlStateNormal];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:added ? @"Закладка добавлена" : @"Закладка удалена"
                                                                  message:added
                                                                       ? @"Можно добавить заметку."
                                                                       : nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    if (added) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Добавить заметку" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self promptNoteForFraction:fraction];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Показать закладки" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self showBookmarks];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Закрыть" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.bookmarkButton;
    sheet.popoverPresentationController.sourceRect = self.bookmarkButton.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptNoteForFraction:(double)fraction {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Заметка"
                                                                  message:@"Текст заметки к закладке"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Например: вернуться к этой сцене";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Сохранить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *note = alert.textFields.firstObject.text ?: @"";
        NSMutableArray *bookmarks = [self.book.bookmarks mutableCopy] ?: [NSMutableArray array];
        for (NSUInteger i = 0; i < bookmarks.count; i++) {
            if (fabs([bookmarks[i][@"fraction"] doubleValue] - fraction) < 0.005) {
                NSMutableDictionary *updated = [bookmarks[i] mutableCopy];
                updated[@"note"] = note;
                bookmarks[i] = updated;
                break;
            }
        }
        self.book.bookmarks = bookmarks;
        [[ORLibrary shared] updateBook:self.book];
        [ORUtil presentAlertIn:self title:@"Заметка" message:@"Сохранено."];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptJump {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Быстрый переход"
                                                                  message:[NSString stringWithFormat:@"Страница 1–%ld или процент, например 42%%", (long)self.pageCount]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"42 или 42%";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Перейти" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *rawValue = alert.textFields.firstObject.text ?: @"";
        NSString *value = [rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (value.length == 0) return;
        BOOL percent = [value containsString:@"%"] || [value containsString:@"."];
        double number = [[value stringByReplacingOccurrencesOfString:@"%" withString:@""] doubleValue];
        NSInteger target;
        if (percent) {
            double fraction = MAX(0, MIN(1, number / 100.0));
            target = (NSInteger)llround(fraction * (double)MAX(0, self.pageCount - 1));
        } else {
            target = (NSInteger)llround(number) - 1;
        }
        target = MAX(0, MIN(self.pageCount - 1, target));
        [self goToPage:target];
        [self setChromeVisible:NO animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showBookmarks {
    NSArray<NSDictionary *> *bookmarks = self.book.bookmarks;
    if (bookmarks.count == 0) {
        [ORUtil presentAlertIn:self title:@"Закладки" message:@"Закладок пока нет. Нажмите 📑 внизу, чтобы добавить."];
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Закладки" message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *bookmark in bookmarks) {
        NSInteger page = [bookmark[@"page"] integerValue];
        double fraction = [bookmark[@"fraction"] doubleValue];
        NSString *note = bookmark[@"note"];
        NSString *title = note.length > 0
            ? [NSString stringWithFormat:@"%@ · стр. %ld", note, (long)page]
            : [NSString stringWithFormat:@"Стр. %ld · %ld%%", (long)page, (long)llround(fraction * 100)];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *js = [NSString stringWithFormat:@"window.Omni&&window.Omni.prepare(%f);", fraction];
            [self.webView evaluateJavaScript:js completionHandler:nil];
            [self setChromeVisible:NO animated:YES];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.bookmarkButton;
    sheet.popoverPresentationController.sourceRect = self.bookmarkButton.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Search

- (void)toggleSearch {
    if (self.searchPanel.hidden) {
        self.searchPanel.hidden = NO;
        self.searchHits = @[];
        [self.searchResults reloadData];
        [self.searchBar becomeFirstResponder];
        [self setChromeVisible:NO animated:YES];
    } else {
        [self closeSearch];
    }
}

- (void)closeSearch {
    [self.searchBar resignFirstResponder];
    self.searchPanel.hidden = YES;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self.liveSearchTimer invalidate];
    self.liveSearchTimer = nil;
    if (searchText.length < 2) {
        self.searchHits = @[];
        [self.searchResults reloadData];
        return;
    }
    self.liveSearchTimer = [NSTimer scheduledTimerWithTimeInterval:0.4
                                                            target:self
                                                          selector:@selector(liveSearchFired:)
                                                          userInfo:searchText
                                                           repeats:NO];
}

- (void)liveSearchFired:(NSTimer *)timer {
    [self performLiveSearch:(NSString *)(timer.userInfo ?: @"")];
}

- (void)performLiveSearch:(NSString *)query {
    if (query.length < 2) return;
    NSMutableArray<NSString *> *hits = [NSMutableArray array];
    NSString *pattern = [NSString stringWithFormat:
        @"(?i)(.{0,40})(%@)(.{0,60})", [self escapedRegex:query]];
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
    if (!regex) return;
    NSString *corpus = [self plainTextCache];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:corpus options:0 range:NSMakeRange(0, corpus.length)];
    for (NSTextCheckingResult *match in matches) {
        if (hits.count >= 60) break;
        NSString *snippet = [corpus substringWithRange:match.range];
        snippet = [snippet stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        snippet = [snippet stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (snippet.length > 0) [hits addObject:snippet];
    }
    self.searchHits = hits;
    [self.searchResults reloadData];
    if (hits.count == 0 && query.length >= 2) {
        // Fall back to the live document text.
        NSString *js = [NSString stringWithFormat:
            @"window.Omni?window.Omni.find(%@).found:0", [ORPagedAssets jsString:query]];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    }
}

- (NSString *)escapedRegex:(NSString *)text {
    NSCharacterSet *special = [NSCharacterSet characterSetWithCharactersInString:@"\\^$.*+?()[]{}|"];
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if ([special characterIsMember:c]) [result appendString:@"\\"];
        [result appendFormat:@"%C", c];
    }
    return result;
}

- (NSString *)plainTextCache {
    static NSMutableDictionary<NSString *, NSString *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    NSString *key = [NSString stringWithFormat:@"%@-%lu", self.book.bookID ?: @"book", (unsigned long)self.htmlBody.length];
    NSString *cached = cache[key];
    if (cached) return cached;
    NSString *text = [ORUtil stripHTML:self.htmlBody];
    if (!text) text = @"";
    if (cache.count > 2) [cache removeAllObjects];
    cache[key] = text;
    return text;
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    NSString *js = [NSString stringWithFormat:
        @"window.Omni?window.Omni.find(%@):{found:0}", [ORPagedAssets jsString:searchBar.text ?: @""]];
    [self.webView evaluateJavaScript:js completionHandler:nil];
    [self closeSearch];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(1, (NSInteger)self.searchHits.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"SearchHit";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
        cell.textLabel.numberOfLines = 2;
        cell.textLabel.font = [UIFont systemFontOfSize:13];
    }
    if (self.searchHits.count == 0) {
        cell.textLabel.text = @"Введите запрос от 2 символов";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        UILabel *label = cell.textLabel;
        NSString *snippet = self.searchHits[(NSUInteger)indexPath.row];
        label.text = snippet;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.searchHits.count == 0) return;
    NSString *snippet = self.searchHits[(NSUInteger)indexPath.row];
    NSString *js = [NSString stringWithFormat:
        @"window.Omni?window.Omni.find(%@):{found:0}", [ORPagedAssets jsString:snippet]];
    [self.webView evaluateJavaScript:js completionHandler:nil];
    [self closeSearch];
}

#pragma mark - Progress

- (void)persistProgress {
    double fraction = self.pageCount > 1 ? (double)self.pageIndex / (double)(self.pageCount - 1) : 0.0;
    fraction = MAX(0.0, MIN(1.0, fraction));
    self.book.progress = fraction;
    [[ORLibrary shared] setProgress:fraction forBookID:self.book.bookID];
    [self.delegate pagedReader:self didChangeProgress:fraction];
}

- (void)updatePageLabel {
    if (self.pageCount <= 1) {
        self.pageLabel.text = @"";
        return;
    }
    double percent = 100.0 * (double)self.pageIndex / (double)(self.pageCount - 1);
    self.pageLabel.text = [NSString stringWithFormat:@"%ld / %ld · %.0f%%", (long)(self.pageIndex + 1), (long)self.pageCount, percent];
}

- (void)updateState:(NSDictionary *)payload {
    NSInteger page = [payload[@"page"] integerValue];
    NSInteger total = MAX(1, [payload[@"total"] integerValue]);
    self.pageIndex = page;
    self.pageCount = total;

    if (self.needsInitialJump) {
        self.needsInitialJump = NO;
        NSInteger target = (NSInteger)llround(self.restoreFraction * (double)MAX(0, total - 1));
        if (target > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self goToPage:target]; });
        }
    }

    if (!self.slider.isTracking) {
        self.slider.value = total > 1 ? (double)page / (double)(total - 1) : 0;
    }
    [self updatePageLabel];
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
    [self.webView evaluateJavaScript:@"window.Omni?window.Omni.text():''" completionHandler:^(id result, NSError *error) {
        NSString *text = [result isKindOfClass:[NSString class]] ? result : @"";
        if (text.length == 0) {
            [ORUtil presentAlertIn:self title:@"Озвучка" message:@"Текст ещё не загрузился."];
            return;
        }
        [self speakText:text];
    }];
}

- (void)speakText:(NSString *)text {
    if (!self.speech) self.speech = [[AVSpeechSynthesizer alloc] init];
    if (self.speech.isPaused) {
        [self.speech continueSpeaking];
        self.isSpeaking = YES;
        [self.speechButton setTitle:@"⏸" forState:UIControlStateNormal];
        return;
    }
    if (self.speech.isSpeaking) return;

    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                     withOptions:AVAudioSessionCategoryOptionDuckOthers
                                           error:NULL];
    [[AVAudioSession sharedInstance] setActive:YES error:NULL];

    double fraction = self.pageCount > 1 ? (double)self.pageIndex / (double)(self.pageCount - 1) : 0.0;
    NSUInteger offset = (NSUInteger)((double)text.length * MAX(0.0, MIN(1.0, fraction)));
    if (offset > 0 && offset < text.length) {
        NSRange search = [text rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]
                                               options:0
                                                 range:NSMakeRange(offset, MIN((NSUInteger)200, text.length - offset))];
        if (search.location != NSNotFound) offset = search.location;
        offset = MIN(offset, text.length - 1);
        text = [text substringFromIndex:offset];
    }

    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
    utterance.rate = [ORSettings shared].speechRate * AVSpeechUtteranceDefaultSpeechRate;
    utterance.pitchMultiplier = 1.0;
    [self.speech speakUtterance:utterance];
    self.isSpeaking = YES;
    [self.speechButton setTitle:@"⏸" forState:UIControlStateNormal];
}

- (void)stopSpeech {
    if (self.speech.isSpeaking || self.speech.isPaused) {
        [self.speech stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
    self.isSpeaking = NO;
    [self.speechButton setTitle:@"🔊" forState:UIControlStateNormal];
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"omni"]) return;
    if (![message.body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *payload = message.body;
    NSString *type = payload[@"type"];
    if ([type isEqualToString:@"state"] || [type isEqualToString:@"ready"]) {
        [self updateState:payload];
    } else if ([type isEqualToString:@"log"]) {
        NSLog(@"[OmniReader JS] %@", payload[@"message"]);
    }
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSString *js = [NSString stringWithFormat:@"window.Omni&&window.Omni.prepare(%f);", self.restoreFraction];
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (error) NSLog(@"[OmniReader] prepare error: %@", error);
    }];
    [self applyStyle];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"[OmniReader] navigation failed: %@", error);
}

#pragma mark - Rotation

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    double fraction = self.pageCount > 1 ? (double)self.pageIndex / (double)(self.pageCount - 1) : 0.0;
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        NSString *js = [NSString stringWithFormat:@"window.Omni&&window.Omni.relayout(%f);", fraction];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    }];
}

@end
