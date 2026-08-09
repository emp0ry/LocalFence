#import "LFAppDelegate.h"

#import "LFDevicesViewController.h"

@implementation LFAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    LFDevicesViewController *devices = [LFDevicesViewController new];
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:devices];
    self.window.rootViewController = navigation;
    [self.window makeKeyAndVisible];
    return YES;
}

@end

