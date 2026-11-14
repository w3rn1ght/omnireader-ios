#import "ORYandexWebLoginController.h"
#import "ORYandexSession.h"
#import "ORUtil.h"
#import <WebKit/WebKit.h>

/// Start from the Yandex Passport login page, not the shelf.
/// The shelf URL redirects to passport, but starting at passport directly
/// gives more control and works better in embedded WebViews.
static NSString *const ORYandexPassportLoginURL = @"https://passport.yandex.ru/auth?origin=books&retpath=https%3A%2F%2Fbooks.yandex.ru%2Fmy%2Fbooks%2Fall";

@interface ORYandexWebLoginController () <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIBarButtonItem *doneItem;
@property (nonatomic, strong) UIBarButtonItem *refreshItem;
@property (nonatomic) BOOL captured;
@end

@implementation ORYandexWebLoginController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Вход в Яндекс Книги";
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
    
    self.refreshItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                       target:self
                                                                       action:@selector(refresh)];
    self.doneItem = [[UIBarButtonItem alloc] initWithTitle:@"Готово"
                                                     style:UIBarButtonItemStyleDone
                                                    target:self
                                                    action:@selector(finish)];
    self.doneItem.enabled = NO;
    self.navigationItem.rightBarButtonItems = @[self.doneItem, self.refreshItem];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    // Allow mixed content and third-party cookies for the login flow
    configuration.preferences.javaScriptEnabled = YES;
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

    NSURL *url = [NSURL URLWithString:ORYandexPassportLoginURL];
    if (url) {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        [self.webView loadRequest:req];
    }
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

- (void)refresh {
    [self.webView reload];
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
    // Try to capture cookies on every navigation to a yandex domain
    NSString *host = webView.URL.host.lowercaseString ?: @"";
    if ([host containsString:@"yandex"] || [host containsString:@"passport"]) {
        [ORYandexSession captureCookiesFromWebView:webView completion:^(NSString *header) {
            if (header.length > 0) self.doneItem.enabled = YES;
        }];
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.spinner stopAnimating];
    if (error.code != NSURLErrorCancelled) {
        NSLog(@"[OmniReader] Yandex web login failed: %@", error.localizedDescription);
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.spinner stopAnimating];
    if (error.code != NSURLErrorCancelled) {
        NSLog(@"[OmniReader] Yandex web login error: %@", error.localizedDescription);
    }
}

// Allow all navigation (including redirects to passport, oauth, etc.)
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                                                       decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    decisionHandler(WKNavigationActionPolicyAllow);
}

@end