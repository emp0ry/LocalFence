#import "LFPermissionManager.h"

#import <CoreLocation/CoreLocation.h>

@interface LFPermissionManager ()
    <CLLocationManagerDelegate>
@property(nonatomic, strong) CLLocationManager *locationManager;
@property(nonatomic, copy) dispatch_block_t permissionCompletion;
@end

@implementation LFPermissionManager

- (void)requestPermissions {
    [self requestPermissionsWithCompletion:nil];
}

- (void)requestPermissionsWithCompletion:(dispatch_block_t)completion {
    self.permissionCompletion = completion;
    if (self.locationManager == nil) {
        self.locationManager = [CLLocationManager new];
        self.locationManager.delegate = self;
    }

    CLAuthorizationStatus status = self.locationManager.authorizationStatus;
    if (status == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
    } else {
        [self finishLocationPermissionStep];
    }
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if (manager.authorizationStatus != kCLAuthorizationStatusNotDetermined) {
        [self finishLocationPermissionStep];
    }
}

- (void)finishLocationPermissionStep {
    dispatch_block_t completion = self.permissionCompletion;
    self.permissionCompletion = nil;
    if (completion != nil) completion();
}

@end
