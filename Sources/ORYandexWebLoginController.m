#import "ORYandexWebLoginController.h"
#import "ORYandexSession.h"
#import "ORUtil.h"
#import <WebKit/WebKit.h>

static NSString *const ORYandexShelfURL = @"https://books.yandex.ru/my/books/all";

@interface ORYandexWebLoginController () <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIBarButtonItem *doneItem;
@property (nonatomic) BOOL captured;
@end

@implementation ORYandexWebLoginController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Вход в Яндекс";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(cancel)];
    self.doneItem = [[UIBarButtonItem alloc] initWithTitle:@"Готово"
                                                     style:UIBarButtonItemStyleDone
                                                    target:self
                                                    action:@selector(finish)];
    self.doneItem.enabled = NO;
    self.navigationItem.rightBarButtonItem = self.doneItem;

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    [self.view addSubview:self.webView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.center = self.view.center;
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
                                    UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.spinner];

    NSURL *url = [NSURL URLWithString:ORYandexShelfURL];
    if (url) [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

#pragma mark - Actions

- (void)cancel {
    if (self.onFinish) self.onFinish(NO, @"Вход отменён.");
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)finish {
    [self.spinner startAnimating];
    [ORYandexSession captureCookiesFromWebView:self.webView completion:^(NSString *header) {
        [self.spinner stopAnimating];
        if (header.length == 0) {
            [ORUtil presentAlertIn:self
                             title:@"Вход не завершён"
                           message:@"Яндекс не выдал cookie сессии. Войдите в аккаунт на странице и нажмите «Готово» ещё раз."];
            return;
        }
        self.doneItem.enabled = YES;
        if (self.onFinish) self.onFinish(YES, nil);
        [self dismissViewControllerAnimated:YES completion:nil];
    }];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [self.spinner startAnimating];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.spinner stopAnimating];
    // The passport may redirect through several hosts; the shelf page itself is
    // the first moment the session cookies are guaranteed to be in place.
    NSString *host = webView.URL.host.lowercaseString ?: @"";
    if ([host containsString:@"books.yandex"] || [host containsString:@"yandex.ru"]) {
        [ORYandexSession captureCookiesFromWebView:webView completion:^(NSString *header) {
            if (header.length > 0) self.doneItem.enabled = YES;
        }];
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.spinner stopAnimating];
    NSLog(@"[OmniReader] Yandex web login failed: %@", error.localizedDescription);
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.spinner stopAnimating];
}

@end
