#import "ORYandexWebLoginController.h"
#import "ORYandexSession.h"
#import "ORUtil.h"
#import <WebKit/WebKit.h>

/// Start from the Yandex Passport login page with the books origin.
/// The retpath brings the user back to the shelf after successful login.
static NSString *const ORYandexPassportLoginURL = @"https://passport.yandex.ru/auth?origin=books&retpath=https%3A%2F%2Fbooks.yandex.ru%2Fmy%2Fbooks%2Fall";

@interface ORYandexWebLoginController () <WKNavigationDelegate, WKUIDelegate>
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
    configuration.preferences.javaScriptEnabled = YES;
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = YES;
    
    // Inject script to fix click handlers on Yandex Passport pages
    NSString *fixScript = @"(function() {"
        "  // Make all elements with onclick/ontouchstart clickable"
        "  var style = document.createElement('style');"
        "  style.textContent = '*[onclick], *[ontouchstart], button, input[type=button], input[type=submit], .button, .btn, [role=button] { cursor: pointer !important; -webkit-tap-highlight-color: rgba(0,0,0,0.1) !important; touch-action: manipulation !important; }';"
        "  document.head.appendChild(style);"
        ""
        "  // Fix for Yandex Passport account selection - make radio labels clickable"
        "  function fixAccountSelection() {"
        "    var labels = document.querySelectorAll('label[for], .passport-AccountList-Account, .AccountList-Account, [data-t=\"account-list-item\"]');"
        "    labels.forEach(function(el) {"
        "      el.style.cursor = 'pointer';"
        "      el.style.webkitTapHighlightColor = 'rgba(0,0,0,0.1)';"
        "      if (!el.onclick) {"
        "        el.onclick = function(e) {"
        "          var input = this.querySelector('input[type=radio], input[type=checkbox]') || document.getElementById(this.getAttribute('for'));"
        "          if (input) { input.checked = true; input.dispatchEvent(new Event('change', {bubbles: true})); }"
        "        };"
        "      }"
        "    });"
        "  }"
        ""
        "  // Fix for 'Resend code' button"
        "  function fixResendButton() {"
        "    var buttons = document.querySelectorAll('button, .button, .btn, [type=submit], [type=button], a.button');"
        "    buttons.forEach(function(btn) {"
        "      var text = (btn.textContent || btn.innerText || '').toLowerCase();"
        "      if (text.indexOf('resend') !== -1 || text.indexOf('повтор') !== -1 || text.indexOf('отправ') !== -1 || text.indexOf('смс') !== -1 || text.indexOf('звон') !== -1) {"
        "        btn.style.pointerEvents = 'auto';"
        "        btn.style.cursor = 'pointer';"
        "        btn.disabled = false;"
        "        btn.removeAttribute('disabled');"
        "      }"
        "    });"
        "  }"
        ""
        "  // Run fixes periodically because Yandex loads content dynamically"
        "  function runFixes() { fixAccountSelection(); fixResendButton(); }"
        "  runFixes();"
        "  setInterval(runFixes, 1000);"
        ""
        "  // Override alert/confirm/prompt to work in WKWebView"
        "  window.alert = function(msg) { window.webkit.messageHandlers.omniAlert.postMessage(msg); };"
        "  window.confirm = function(msg) { window.webkit.messageHandlers.omniConfirm.postMessage(msg); return true; };"
        "  window.prompt = function(msg, def) { window.webkit.messageHandlers.omniPrompt.postMessage({message: msg, default: def}); return def; };"
        "})();";
    
    WKUserScript *userScript = [[WKUserScript alloc] initWithSource:fixScript
                                                    injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                     forMainFrameOnly:NO];
    [configuration.userContentController addUserScript:userScript];
    
    // Add message handlers for JS dialogs
    [configuration.userContentController addScriptMessageHandler:self name:@"omniAlert"];
    [configuration.userContentController addScriptMessageHandler:self name:@"omniConfirm"];
    [configuration.userContentController addScriptMessageHandler:self name:@"omniPrompt"];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
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

- (void)dealloc {
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"omniAlert"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"omniConfirm"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"omniPrompt"];
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
    // Re-inject fix script in case of SPA navigation
    [self injectFixScript];
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

- (void)injectFixScript {
    NSString *script = @"(function() {"
        "  var style = document.createElement('style');"
        "  style.textContent = '*[onclick], *[ontouchstart], button, input[type=button], input[type=submit], .button, .btn, [role=button] { cursor: pointer !important; -webkit-tap-highlight-color: rgba(0,0,0,0.1) !important; touch-action: manipulation !important; }';"
        "  document.head.appendChild(style);"
        "  var labels = document.querySelectorAll('label[for], .passport-AccountList-Account, .AccountList-Account, [data-t=\"account-list-item\"]');"
        "  labels.forEach(function(el) { el.style.cursor = 'pointer'; el.style.webkitTapHighlightColor = 'rgba(0,0,0,0.1)'; });"
        "  var buttons = document.querySelectorAll('button, .button, .btn, [type=submit], [type=button], a.button');"
        "  buttons.forEach(function(btn) {"
        "    var text = (btn.textContent || btn.innerText || '').toLowerCase();"
        "    if (text.indexOf('resend') !== -1 || text.indexOf('повтор') !== -1 || text.indexOf('отправ') !== -1 || text.indexOf('смс') !== -1 || text.indexOf('звон') !== -1) {"
        "      btn.style.pointerEvents = 'auto'; btn.style.cursor = 'pointer'; btn.disabled = false; btn.removeAttribute('disabled');"
        "    }"
        "  });"
        "})();";
    [self.webView evaluateJavaScript:script completionHandler:nil];
}

#pragma mark - WKUIDelegate (JavaScript dialogs)

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message
                                         initiatedByFrame:(WKFrameInfo *)frame
                                          completionHandler:(void (^)(void))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Яндекс" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        completionHandler();
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message
                                         initiatedByFrame:(WKFrameInfo *)frame
                                          completionHandler:(void (^)(BOOL))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Яндекс" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        completionHandler(NO);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        completionHandler(YES);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
                                          defaultText:(NSString *)defaultText
                                         initiatedByFrame:(WKFrameInfo *)frame
                                          completionHandler:(void (^)(NSString *_Nullable))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Яндекс" message:prompt preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = defaultText;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        completionHandler(nil);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        completionHandler(alert.textFields.firstObject.text);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Handle target="_blank" links and window.open
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
                                                             forNavigationAction:(WKNavigationAction *)navigationAction
                                                              windowFeatures:(WKWindowFeatures *)windowFeatures {
    if (navigationAction.targetFrame == nil || !navigationAction.targetFrame.isMainFrame) {
        [webView loadRequest:navigationAction.request];
    }
    return nil;
}

#pragma mark - WKScriptMessageHandler (for overridden alert/confirm/prompt)

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"omniAlert"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Яндекс" message:message.body preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if ([message.name isEqualToString:@"omniConfirm"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Яндекс" message:message.body preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if ([message.name isEqualToString:@"omniPrompt"]) {
        NSDictionary *dict = message.body;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Яндекс" message:dict[@"message"] preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.text = dict[@"default"];
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end