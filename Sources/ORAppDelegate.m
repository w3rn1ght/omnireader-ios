#import "ORAppDelegate.h"
#import "ORAudioPlayer.h"
#import "ORCore.h"
#import "ORLibraryViewController.h"
#import "ORUtil.h"
#import "ORYandexAuth.h"
#import <AVFoundation/AVFoundation.h>

@interface ORAppDelegate ()
@property (nonatomic, strong) UINavigationController *navigationController;
@end

@implementation ORAppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [ORPaths supportDirectory];
    [self configureAppearance];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    ORLibraryViewController *library = [[ORLibraryViewController alloc] init];
    self.navigationController = [[UINavigationController alloc] initWithRootViewController:library];
    self.window.rootViewController = self.navigationController;
    [self.window makeKeyAndVisible];

    // Keep audio alive when the app goes to background.
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:NULL];

    [self handleLaunchOptions:launchOptions];
    return YES;
}

- (void)configureAppearance {
    UINavigationBar *navigationBar = [UINavigationBar appearance];
    navigationBar.tintColor = [UIColor colorWithRed:0.72 green:0.34 blue:0.16 alpha:1.0];
    [UITableView appearance].sectionIndexColor = [UIColor darkGrayColor];
}

- (void)handleLaunchOptions:(NSDictionary *)launchOptions {
    NSURL *url = launchOptions[UIApplicationLaunchOptionsURLKey];
    if (url) {
        [self openURL:url];
    }
}

- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    if ([url.scheme isEqualToString:@"omnireader"]) {
        if ([ORYandexAuth handleCallbackURL:url]) {
            UIViewController *top = [ORUtil topViewController];
            [ORUtil presentAlertIn:top
                             title:@"Яндекс Книги"
                           message:@"Вход выполнен. Откройте «Яндекс Книги» в библиотеке."];
        }
        return YES;
    }
    return [self openURL:url];
}

- (BOOL)openURL:(NSURL *)url {
    if (!url.isFileURL) return NO;
    ORLibraryViewController *library = (ORLibraryViewController *)self.navigationController.viewControllers.firstObject;
    [self.navigationController popToRootViewControllerAnimated:NO];
    [library handleIncomingFileURL:url];
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [[ORLibrary shared] save];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [[ORLibrary shared] save];
}

@end
