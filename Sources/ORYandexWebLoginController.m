#import "ORYandexWebLoginController.h"
#import "ORYandexSession.h"
#import "ORUtil.h"
#import <WebKit/WebKit.h>

/// Start from the Yandex Passport login page with the books origin.
/// The retpath brings the user back to the shelf after successful login.
static NSString *const ORYandexPassportLoginURL = @"https://passport.yandex.ru/auth?origin=books&retpath=https%3A%2F%2Fbooks.yandex.ru%2Fmy%2Fbooks%2Fall";

@interface ORYandexWebLoginController () <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIBarButtonItem *doneItem;
@property (nonatomic, strong) UIBarButtonItem *refreshItem;
@property (nonatomic, strong) UIBarButtonItem *submitFormItem;
@property (nonatomic, strong) UIBarButtonItem *resendCodeItem;
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
    
    self.submitFormItem = [[UIBarButtonItem alloc] initWithTitle:@"Далее ▶"
                                                           style:UIBarButtonItemStylePlain
                                                          target:self
                                                          action:@selector(submitForm)];
    self.submitFormItem.enabled = YES;
    
    self.resendCodeItem = [[UIBarButtonItem alloc] initWithTitle:@"🔁 Код"
                                                          style:UIBarButtonItemStylePlain
                                                         target:self
                                                         action:@selector(resendCode)];
    self.resendCodeItem.enabled = YES;
    
    self.doneItem = [[UIBarButtonItem alloc] initWithTitle:@"Готово"
                                                     style:UIBarButtonItemStyleDone
                                                    target:self
                                                    action:@selector(finish)];
    self.doneItem.enabled = NO;
    self.navigationItem.rightBarButtonItems = @[self.doneItem, self.resendCodeItem, self.submitFormItem, self.refreshItem];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    configuration.preferences.javaScriptEnabled = YES;
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = YES;
    
    // Allow mixed content for embedded resources
    #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (@available(iOS 13.0, *)) {
        // WKWebView doesn't have a direct mixed content setting on iOS, but we can try
    }
    #endif
    
    // Inject comprehensive fix script for Yandex Passport
    NSString *fixScript = @"(function() {"
        "  'use strict';"
        ""
        "  // ===== Style fixes for clickable elements ====="
        "  function injectStyles() {"
        "    if (document.getElementById('omni-fix-styles')) return;"
        "    var style = document.createElement('style');"
        "    style.id = 'omni-fix-styles';"
        "    style.textContent = "
        "      '*[onclick], *[ontouchstart], button, input[type=button], input[type=submit], "
        "       .button, .btn, [role=button], .passport-Button, .Button2, "
        "       [class*=\"Button\"], [class*=\"button\"] { "
        "         cursor: pointer !important; "
        "         -webkit-tap-highlight-color: rgba(0,0,0,0.1) !important; "
        "         touch-action: manipulation !important; "
        "         pointer-events: auto !important; "
        "       }';"
        "    document.head.appendChild(style);"
        "  }"
        ""
        "  // ===== Find and fix form submit buttons ====="
        "  function fixFormSubmits() {"
        "    // Find all forms"
        "    var forms = document.querySelectorAll('form');"
        "    forms.forEach(function(form) {"
        "      if (form.dataset.omniFixed) return;"
        "      form.dataset.omniFixed = '1';"
        "      "
        "      // Find submit buttons in this form"
        "      var submitBtns = form.querySelectorAll('button[type=submit], input[type=submit], "
        "        button:not([type]), button[type=button], "
        "        .passport-Button_type_submit, .Button2_type_submit, "
        "        [class*=\"Button\"][class*=\"submit\"], "
        "        [class*=\"button\"][class*=\"submit\"]');"
        "      "
        "      submitBtns.forEach(function(btn) {"
        "        btn.disabled = false;"
        "        btn.removeAttribute('disabled');"
        "        btn.style.pointerEvents = 'auto';"
        "        "
        "        // Wrap click to ensure form submits"
        "        if (!btn.dataset.omniClickFixed) {"
        "          btn.dataset.omniClickFixed = '1';"
        "          var originalClick = btn.onclick;"
        "          btn.onclick = function(e) {"
        "            if (originalClick) originalClick.call(this, e);"
        "            // If button is in a form, submit it"
        "            var form = this.closest('form');"
        "            if (form && !form.dataset.omniSubmitting) {"
        "              form.dataset.omniSubmitting = '1';"
        "              setTimeout(function() { form.dataset.omniSubmitting = '0'; }, 1000);"
        "              form.dispatchEvent(new Event('submit', {bubbles: true, cancelable: true}));"
        "            }"
        "          };"
        "        }"
        "      });"
        "    });"
        "  }"
        ""
        "  // ===== Fix 'Next' (Далее) button ====="
        "  function fixNextButton() {"
        "    // Multiple selectors for Yandex Passport 'Next' button"
        "    var selectors = ["
        "      'button:contains(\"Далее\"), button:contains(\"Next\"), button:contains(\"Войти\"), button:contains(\"Sign in\")',"
        "      'button[type=submit]', 'input[type=submit]',"
        "      '.passport-Button_type_submit', '.Button2_type_submit',"
        "      '[data-t=\"submit\"]', '[data-t=\"next\"]', '[data-t=\"login\"]',"
        "      'button.passport-Button', 'button.Button2',"
        "      '[class*=\"Button\"][class*=\"submit\"], [class*=\"button\"][class*=\"submit\"]',"
        "      'footer button', '.passport-Form-Footer button', '.Form-Footer button'"
        "    ];"
        "    "
        "    // Since :contains is not standard, use textContent search"
        "    var allButtons = document.querySelectorAll('button, input[type=button], input[type=submit], [role=button]');"
        "    allButtons.forEach(function(btn) {"
        "      var text = (btn.textContent || btn.value || btn.innerText || '').toLowerCase().trim();"
        "      var isNext = text === 'далее' || text === 'next' || text === 'войти' || text === 'sign in' || text === 'продолжить' || text === 'continue';"
        "      var isResend = text.indexOf('повтор') !== -1 || text.indexOf('resend') !== -1 ||"
        "                     text.indexOf('отправ') !== -1 || text.indexOf('смс') !== -1 || text.indexOf('звон') !== -1;"
        "      "
        "      if (isNext || isResend || btn.type === 'submit' || btn.getAttribute('type') === 'submit') {"
        "        btn.disabled = false;"
        "        btn.removeAttribute('disabled');"
        "        btn.style.pointerEvents = 'auto';"
        "        btn.style.cursor = 'pointer';"
        "        btn.dataset.omniIsNext = isNext;"
        "        btn.dataset.omniIsResend = isResend;"
        "        "
        "        if (!btn.dataset.omniClickFixed) {"
        "          btn.dataset.omniClickFixed = '1';"
        "          btn.addEventListener('click', function(e) {"
        "            // Try to submit parent form"
        "            var form = this.closest('form');"
        "            if (form) {"
        "              form.dispatchEvent(new Event('submit', {bubbles: true, cancelable: true}));"
        "            }"
        "            // Also try click on any nested button"
        "            var nestedSubmit = form ? form.querySelector('button[type=submit], input[type=submit]') : null;"
        "            if (nestedSubmit && nestedSubmit !== this) { nestedSubmit.click(); }"
        "          }, true);" // Use capture phase
        "        }"
        "      }"
        "    });"
        "  }"
        ""
        "  // ===== Fix account selection (radio buttons) ====="
        "  function fixAccountSelection() {"
        "    var selectors = ["
        "      'label[for]',"
        "      '.passport-AccountList-Account',"
        "      '.AccountList-Account',"
        "      '[data-t=\"account-list-item\"]',"
        "      '.passport-SelectAccount-item',"
        "      '[class*=\"Account\"][class*=\"item\"]'"
        "    ];"
        "    var items = document.querySelectorAll(selectors.join(', '));"
        "    items.forEach(function(el) {"
        "      el.style.cursor = 'pointer';"
        "      el.style.webkitTapHighlightColor = 'rgba(0,0,0,0.1)';"
        "      if (!el.dataset.omniAccountFixed) {"
        "        el.dataset.omniAccountFixed = '1';"
        "        el.addEventListener('click', function(e) {"
        "          var input = this.querySelector('input[type=radio], input[type=checkbox]') "
        "                    || document.getElementById(this.getAttribute('for'));"
        "          if (input) {"
        "            input.checked = true;"
        "            input.dispatchEvent(new Event('change', {bubbles: true}));"
        "            input.dispatchEvent(new Event('input', {bubbles: true}));"
        "          }"
        "        }, true);"
        "      }"
        "    });"
        "  }"
        ""
        "  // ===== Fix Resend Code button ====="
        "  function fixResendButton() {"
        "    var allButtons = document.querySelectorAll('button, a, [role=button], .button, .btn');"
        "    allButtons.forEach(function(btn) {"
        "      var text = (btn.textContent || btn.innerText || '').toLowerCase();"
        "      if (text.indexOf('повтор') !== -1 || text.indexOf('resend') !== -1 ||"
        "          text.indexOf('отправ') !== -1 || text.indexOf('смс') !== -1 || text.indexOf('звон') !== -1) {"
        "        btn.disabled = false;"
        "        btn.removeAttribute('disabled');"
        "        btn.style.pointerEvents = 'auto';"
        "        btn.style.cursor = 'pointer';"
        "        btn.dataset.omniIsResend = '1';"
        "        if (!btn.dataset.omniClickFixed) {"
        "          btn.dataset.omniClickFixed = '1';"
        "          btn.addEventListener('click', function(e) {"
        "            e.preventDefault();"
        "            e.stopPropagation();"
        "            var form = this.closest('form');"
        "            if (form) { form.dispatchEvent(new Event('submit', {bubbles: true, cancelable: true})); }"
        "            this.click();"
        "          }, true);"
        "        }"
        "      }"
        "    });"
        "  }"
        ""
        "  // ===== Override alert/confirm/prompt ====="
        "  window.alert = function(msg) { window.webkit.messageHandlers.omniAlert.postMessage(msg); };"
        "  window.confirm = function(msg) { window.webkit.messageHandlers.omniConfirm.postMessage(msg); return true; };"
        "  window.prompt = function(msg, def) { window.webkit.messageHandlers.omniPrompt.postMessage({message: msg, default: def}); return def; };"
        ""
        "  // ===== Run all fixes periodically ====="
        "  function runAllFixes() {"
        "    injectStyles();"
        "    fixFormSubmits();"
        "    fixNextButton();"
        "    fixAccountSelection();"
        "    fixResendButton();"
        "  }"
        "  "
        "  // Run immediately and on DOM ready"
        "  if (document.readyState === 'loading') {"
        "    document.addEventListener('DOMContentLoaded', runAllFixes);"
        "  } else {"
        "    runAllFixes();"
        "  }"
        "  // And periodically for SPA navigation"
        "  setInterval(runAllFixes, 1000);"
        "  "
        "  // Also run on any DOM mutation"
        "  var observer = new MutationObserver(function() { runAllFixes(); });"
        "  observer.observe(document.body, { childList: true, subtree: true });"
        "  "
        "  // Expose functions for toolbar buttons"
        "  window.omniSubmitForm = function() {"
        "    var forms = document.querySelectorAll('form');"
        "    var submitted = false;"
        "    forms.forEach(function(form) {"
        "      if (!submitted) {"
        "        var btn = form.querySelector('button[type=submit], input[type=submit], button[data-omni-is-next=\"true\"]');"
        "        if (btn) { btn.click(); submitted = true; }"
        "        else { form.dispatchEvent(new Event('submit', {bubbles: true, cancelable: true})); submitted = true; }"
        "      }"
        "    });"
        "    return submitted;"
        "  };"
        "  "
        "  window.omniResendCode = function() {"
        "    var btns = document.querySelectorAll('button, a, [role=button]');"
        "    var clicked = false;"
        "    btns.forEach(function(btn) {"
        "      var text = (btn.textContent || btn.innerText || '').toLowerCase();"
        "      if (!clicked && (text.indexOf('повтор') !== -1 || text.indexOf('resend') !== -1 ||"
        "          text.indexOf('отправ') !== -1 || text.indexOf('смс') !== -1 || text.indexOf('звон') !== -1)) {"
        "        btn.click(); clicked = true;"
        "      }"
        "    });"
        "    return clicked;"
        "  };"
        "})();";
    
    WKUserScript *userScript = [[WKUserScript alloc] initWithSource:fixScript
                                                    injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                     forMainFrameOnly:NO];
    [configuration.userContentController addUserScript:userScript];
    
    // Add message handlers for JS dialogs and toolbar callbacks
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

- (void)submitForm {
    [self.spinner startAnimating];
    [self.webView evaluateJavaScript:@"window.omniSubmitForm()" completionHandler:^(id result, NSError *error) {
        [self.spinner stopAnimating];
        if (error) {
            NSLog(@"[OmniReader] submitForm error: %@", error);
        } else if (result) {
            NSLog(@"[OmniReader] submitForm result: %@", result);
        }
    }];
}

- (void)resendCode {
    [self.spinner startAnimating];
    [self.webView evaluateJavaScript:@"window.omniResendCode()" completionHandler:^(id result, NSError *error) {
        [self.spinner stopAnimating];
        if (error) {
            NSLog(@"[OmniReader] resendCode error: %@", error);
        } else if (result) {
            NSLog(@"[OmniReader] resendCode result: %@", result);
        }
    }];
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

// Allow all navigation (including redirects to passport, oauth, etc.)
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                                                       decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    // Allow form submissions and all navigation
    decisionHandler(WKNavigationActionPolicyAllow);
}

// Handle navigation response to allow all content
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse
                                                        decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    decisionHandler(WKNavigationResponsePolicyAllow);
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