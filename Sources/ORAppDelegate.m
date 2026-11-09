#import "ORAppDelegate.h"
#import "ORAudioPlayer.h"
#import "ORCore.h"
#import "ORLibraryViewController.h"
#import "ORUtil.h"
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
    if (@available(iOS 13.0, *)) {
        // The app has its own light palette; do not flip it with the system theme.
        navigationBar.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    }
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
        // OAuth callback is handled by ASWebAuthenticationSession.
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
