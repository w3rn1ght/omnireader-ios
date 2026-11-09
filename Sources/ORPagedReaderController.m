#import "ORPagedReaderController.h"
#import "ORPagedAssets.h"
#import "ORReaderSettingsController.h"
#import "ORTableOfContentsController.h"
#import "ORText.h"
#import "ORUtil.h"
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>

@interface ORPagedReaderController () <WKScriptMessageHandler, WKNavigationDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) ORBook *book;
@property (nonatomic, copy) NSString *htmlBody;
@property (nonatomic, copy) NSString *extraCSS;
@property (nonatomic, copy, nullable) NSString *basePath;
@property (nonatomic, strong) NSArray<ORTOCItem *> *toc;

@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *pageLabel;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UIButton *speechButton;
@property (nonatomic) BOOL chromeVisible;
@property (nonatomic) BOOL needsInitialJump;
@property (nonatomic) double restoreFraction;
@property (nonatomic) NSInteger pageIndex;
@property (nonatomic) NSInteger pageCount;
@property (nonatomic) BOOL isSpeaking;
@property (nonatomic, strong) AVSpeechSynthesizer *speech;

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
    [self loadDocument];
    [self installGestures];
}

- (BOOL)prefersStatusBarHidden {
    return !self.chromeVisible;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return [[ORSettings shared] theme] == ORReaderThemeNight ? UIStatusBarStyleLightContent : UIStatusBarStyleDefault;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    if ([ORSettings shared].keepScreenAwake) {
        [UIApplication sharedApplication].idleTimerDisabled = YES;
    }
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
    configuration.suppressesIncrementalRendering = NO;
    WKUserContentController *controller = [[WKUserContentController alloc] init];
    [controller addScriptMessageHandler:self name:@"omni"];
    configuration.userContentController = controller;

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    self.webView.navigationDelegate = self;
    self.webView.scrollView.scrollEnabled = NO;
    self.webView.scrollView.bounces = NO;
    self.webView.opaque = YES;
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.backgroundColor = [[ORSettings shared] themeBackgroundColor];
    self.webView.scrollView.backgroundColor = [[ORSettings shared] themeBackgroundColor];
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
        BOOL written = [html writeToFile:htmlPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
        if (written) {
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
    button.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    [button setTitleColor:[[ORSettings shared] themeTextColor] forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.contentEdgeInsets = UIEdgeInsetsMake(4, 8, 4, 8);
    return button;
}

- (void)setupChrome {
    UIColor *background = [[ORSettings shared] themeBackgroundColor];
    UIColor *text = [[ORSettings shared] themeTextColor];

    self.topBar = [[UIView alloc] init];
    self.topBar.backgroundColor = [[[ORSettings shared] themeSecondaryColor] colorWithAlphaComponent:0.14];
    self.topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.topBar];

    UIButton *back = [self barButtonWithTitle:@"‹" action:@selector(goBack)];
    back.frame = CGRectMake(6, 0, 44, 48);
    back.titleLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightRegular];
    back.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.topBar addSubview:back];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = self.book.title;
    self.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.titleLabel.textColor = text;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.topBar addSubview:self.titleLabel];

    UIButton *tocButton = [self barButtonWithTitle:@"☰" action:@selector(showContents)];
    tocButton.frame = CGRectMake(self.view.bounds.size.width - 52, 0, 44, 48);
    tocButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.topBar addSubview:tocButton];

    self.bottomBar = [[UIView alloc] init];
    self.bottomBar.backgroundColor = [[[ORSettings shared] themeSecondaryColor] colorWithAlphaComponent:0.14];
    self.bottomBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.bottomBar];

    self.slider = [[UISlider alloc] init];
    self.slider.minimumValue = 0;
    self.slider.maximumValue = 1;
    self.slider.continuous = YES;
    self.slider.tintColor = text;
    [self.slider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    [self.slider addTarget:self action:@selector(sliderReleased) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.bottomBar addSubview:self.slider];

    self.pageLabel = [[UILabel alloc] init];
    self.pageLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.pageLabel.textColor = text;
    self.pageLabel.textAlignment = NSTextAlignmentCenter;
    [self.bottomBar addSubview:self.pageLabel];

    NSArray *titles = @[@"Aa", @"☰", @"🔊"];
    SEL actions[] = {@selector(showReaderSettings), @selector(showContents), @selector(toggleSpeech)};
    UIButton *previous = nil;
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *button = [self barButtonWithTitle:titles[i] action:actions[i]];
        button.tag = 100 + (NSInteger)i;
        [self.bottomBar addSubview:button];
        if (i == 2) self.speechButton = button;
        previous = button;
    }
    self.chromeVisible = NO;
    self.topBar.alpha = 0;
    self.bottomBar.alpha = 0;
    self.topBar.userInteractionEnabled = NO;
    self.bottomBar.userInteractionEnabled = NO;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    self.webView.frame = CGRectMake(0, 0, width, height);

    CGFloat topInset = self.view.safeAreaInsets.top;
    self.topBar.frame = CGRectMake(0, 0, width, topInset + 48);
    UIButton *tocButton = nil;
    UIButton *backButton = nil;
    for (UIView *subview in self.topBar.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            if (subview.frame.origin.x < 10) backButton = (UIButton *)subview;
            else tocButton = (UIButton *)subview;
        }
    }
    backButton.frame = CGRectMake(6, topInset + 4, 44, 44);
    tocButton.frame = CGRectMake(width - 50, topInset + 4, 44, 44);
    self.titleLabel.frame = CGRectMake(52, topInset + 11, MAX(80, width - 104), 28);

    CGFloat bottomInset = self.view.safeAreaInsets.bottom;
    CGFloat barHeight = bottomInset + 96;
    self.bottomBar.frame = CGRectMake(0, height - barHeight, width, barHeight);
    self.slider.frame = CGRectMake(18, 8, width - 36, 28);
    self.pageLabel.frame = CGRectMake(18, 36, width - 36, 16);
    CGFloat buttonWidth = (width - 36) / 3.0;
    NSInteger index = 0;
    for (UIView *subview in self.bottomBar.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            subview.frame = CGRectMake(18 + buttonWidth * index, 54, buttonWidth, 34);
            index++;
        }
    }

    // Keep the last line of the page above the bottom bar.
    CGFloat contentBottom = barHeight + 10;
    if (!self.needsInitialJump) {
        NSString *js = [NSString stringWithFormat:
            @"(function(){var c=document.getElementById('content');if(!c)return;"
             "c.style.paddingBottom='%.0fpx';"
             "if(window.Omni){var s=window.Omni.state();window.Omni.relayout(s.fraction);}})();",
            contentBottom];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    }
}

#pragma mark - Chrome

- (void)setChromeVisible:(BOOL)chromeVisible animated:(BOOL)animated {
    _chromeVisible = chromeVisible;
    [self setNeedsStatusBarAppearanceUpdate];
    void (^changes)(void) = ^{
        self.topBar.alpha = chromeVisible ? 1.0 : 0.0;
        self.bottomBar.alpha = chromeVisible ? 1.0 : 0.0;
    };
    self.topBar.userInteractionEnabled = chromeVisible;
    self.bottomBar.userInteractionEnabled = chromeVisible;
    if (animated) {
        [UIView animateWithDuration:0.2 animations:changes];
    } else {
        changes();
    }
}

- (void)toggleChrome {
    [self setChromeVisible:!self.chromeVisible animated:YES];
}

- (void)installGestures {
    UISwipeGestureRecognizer *left = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft)];
    left.direction = UISwipeGestureRecognizerDirectionLeft;
    left.delegate = self;
    [self.view addGestureRecognizer:left];

    UISwipeGestureRecognizer *right = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight)];
    right.direction = UISwipeGestureRecognizerDirectionRight;
    right.delegate = self;
    [self.view addGestureRecognizer:right];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    tap.delegate = self;
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    if (self.chromeVisible) {
        CGPoint point = [tap locationInView:self.view];
        if (CGRectContainsPoint(self.topBar.frame, point) || CGRectContainsPoint(self.bottomBar.frame, point)) {
            return;
        }
    }
    [self toggleChrome];
}

- (void)swipeLeft {
    [self goToPage:self.pageIndex + 1];
}

- (void)swipeRight {
    [self goToPage:self.pageIndex - 1];
}

#pragma mark - Navigation

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)goToPage:(NSInteger)page {
    NSString *js = [NSString stringWithFormat:@"window.Omni&&window.Omni.goTo(%ld,true);", (long)page];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)sliderChanged {
    double target = self.slider.value;
    NSInteger page = (NSInteger)llround(target * (double)MAX(0, self.pageCount - 1));
    NSString *js = [NSString stringWithFormat:@"window.Omni&&window.Omni.goTo(%ld,false);", (long)page];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)sliderReleased {
    [self persistProgress];
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
    ORReaderSettingsController *settingsController = [[ORReaderSettingsController alloc] initWithSettings:[ORSettings shared]];
    __weak typeof(self) weakSelf = self;
    settingsController.onChange = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf applyStyle];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsController];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)applyStyle {
    ORSettings *settings = [ORSettings shared];
    self.view.backgroundColor = [settings themeBackgroundColor];
    self.webView.backgroundColor = [settings themeBackgroundColor];
    self.webView.scrollView.backgroundColor = [settings themeBackgroundColor];
    self.titleLabel.textColor = [settings themeTextColor];
    self.pageLabel.textColor = [settings themeTextColor];
    self.slider.tintColor = [settings themeTextColor];
    self.topBar.backgroundColor = [[settings themeSecondaryColor] colorWithAlphaComponent:0.14];
    self.bottomBar.backgroundColor = [[settings themeSecondaryColor] colorWithAlphaComponent:0.14];
    [self setNeedsStatusBarAppearanceUpdate];

    double fraction = self.pageCount > 1 ? (double)self.pageIndex / (double)(self.pageCount - 1) : self.restoreFraction;
    NSString *config = [ORPagedAssets styleConfigurationForSettings:settings];
    NSString *js = [NSString stringWithFormat:
        @"if(window.Omni){window.Omni.applyStyle(%@);window.Omni.relayout(%f);}", config, fraction];
    [self.webView evaluateJavaScript:js completionHandler:nil];
    self.restoreFraction = fraction;
}

#pragma mark - Progress

- (void)persistProgress {
    if (self.pageCount <= 1) {
        if (self.book.progress < 0.999) return;
    }
    double fraction = self.pageCount > 1 ? (double)self.pageIndex / (double)(self.pageCount - 1) : 0.0;
    fraction = MAX(0.0, MIN(1.0, fraction));
    self.book.progress = fraction;
    [[ORLibrary shared] setProgress:fraction forBookID:self.book.bookID];
    [self.delegate pagedReader:self didChangeProgress:fraction];
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
            dispatch_async(dispatch_get_main_queue(), ^{
                [self goToPage:target];
            });
        }
    }

    if (!self.slider.isTracking) {
        self.slider.value = total > 1 ? (double)page / (double)(total - 1) : 0;
    }
    self.pageLabel.text = [NSString stringWithFormat:@"%ld / %ld · %.0f%%",
                           (long)(page + 1), (long)total,
                           total > 1 ? 100.0 * (double)page / (double)(total - 1) : 0.0];
}

#pragma mark - Speech

- (void)toggleSpeech {
    if (self.isSpeaking) {
        [self pauseSpeech];
        return;
    }
    [self startSpeech];
}

- (void)startSpeech {
    [self.webView evaluateJavaScript:@"(function(){var c=document.getElementById('content');return c?c.innerText:'';})()"
                   completionHandler:^(id result, NSError *error) {
        NSString *text = [result isKindOfClass:[NSString class]] ? result : @"";
        if (text.length == 0) {
            [ORUtil presentAlertIn:self title:@"Озвучка" message:@"Текст ещё не загрузился."];
            return;
        }
        [self speakText:text];
    }];
}

- (void)speakText:(NSString *)text {
    if (!self.speech) {
        self.speech = [[AVSpeechSynthesizer alloc] init];
    }
    if (self.speech.isPaused) {
        [self.speech continueSpeaking];
        self.isSpeaking = YES;
        [self.speechButton setTitle:@"⏸" forState:UIControlStateNormal];
        return;
    }
    if (self.speech.isSpeaking) return;

    NSError *audioError = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                     withOptions:AVAudioSessionCategoryOptionDuckOthers
                                           error:&audioError];
    [[AVAudioSession sharedInstance] setActive:YES error:NULL];

    // Start from the current page rather than from the very beginning.
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
    utterance.preUtteranceDelay = 0;
    utterance.postUtteranceDelay = 0;
    [self.speech speakUtterance:utterance];
    self.isSpeaking = YES;
    [self.speechButton setTitle:@"⏸" forState:UIControlStateNormal];
}

- (void)pauseSpeech {
    [self.speech pauseSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    self.isSpeaking = NO;
    [self.speechButton setTitle:@"🔊" forState:UIControlStateNormal];
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
    if ([type isEqualToString:@"state"]) {
        [self updateState:payload];
    } else if ([type isEqualToString:@"ready"]) {
        [self updateState:payload];
    } else if ([type isEqualToString:@"log"]) {
        NSLog(@"[OmniReader JS] %@", payload[@"message"]);
    }
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    double fraction = self.restoreFraction;
    NSString *js = [NSString stringWithFormat:@"window.Omni&&window.Omni.prepare(%f);", fraction];
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (error) NSLog(@"[OmniReader] prepare error: %@", error);
    }];
    [self applyStyle];
}

- (void)webView:(WKWebView *)webView
didFailNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
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
