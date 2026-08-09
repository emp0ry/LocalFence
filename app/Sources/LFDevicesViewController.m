#import "LFDevicesViewController.h"

#import "LFBonjourDiscovery.h"
#import "LFDeviceIdentityResolver.h"
#import "LFIPCClient.h"
#import "LFPermissionManager.h"

static NSString *const LFAuthorizationPreference = @"AuthorizedPrivateLANUse";
static NSString *const LFIntervalPreference = @"PacketIntervalMs";

@interface LFDevicesViewController ()
@property(nonatomic, copy) NSArray<NSDictionary *> *devices;
@property(nonatomic, copy) NSDictionary *network;
@property(nonatomic, strong) UILabel *networkLabel;
@property(nonatomic, strong) LFPermissionManager *permissionManager;
@property(nonatomic, strong) LFBonjourDiscovery *bonjourDiscovery;
@property(nonatomic, strong) LFDeviceIdentityResolver *identityResolver;
@property(nonatomic, assign) BOOL requestInProgress;
@end

@implementation LFDevicesViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self != nil) {
        _devices = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"LocalFence";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.prefersLargeTitles = YES;

    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self
                            action:@selector(refreshDevices)
                  forControlEvents:UIControlEventValueChanged];

    UIBarButtonItem *settings = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(showSettings)];
    UIBarButtonItem *stop = [[UIBarButtonItem alloc]
        initWithTitle:@"Stop All"
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(confirmStopAll)];
    self.navigationItem.rightBarButtonItems = @[ settings, stop ];

    self.networkLabel = [UILabel new];
    self.networkLabel.numberOfLines = 0;
    self.networkLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.networkLabel.textColor = UIColor.secondaryLabelColor;
    self.networkLabel.textAlignment = NSTextAlignmentCenter;
    self.networkLabel.text = @"Pull to discover devices on your private Wi-Fi network.";
    self.networkLabel.frame = CGRectMake(20, 0, self.view.bounds.size.width - 40, 64);
    self.tableView.tableHeaderView = self.networkLabel;
    self.permissionManager = [LFPermissionManager new];
    self.bonjourDiscovery = [LFBonjourDiscovery new];
    self.identityResolver = [LFDeviceIdentityResolver new];
    __weak typeof(self) weakSelf = self;
    self.bonjourDiscovery.updateHandler = ^(NSString *ipAddress) {
        NSUInteger index = [weakSelf.devices indexOfObjectPassingTest:
            ^BOOL(NSDictionary *device, NSUInteger candidate, BOOL *stop) {
                (void)candidate;
                (void)stop;
                return [device[@"ip"] isEqualToString:ipAddress];
            }];
        if (index != NSNotFound) {
            [weakSelf.tableView reloadRowsAtIndexPaths:@[
                [NSIndexPath indexPathForRow:(NSInteger)index inSection:0]
            ] withRowAnimation:UITableViewRowAnimationNone];
        }
    };
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (![[NSUserDefaults standardUserDefaults]
            boolForKey:LFAuthorizationPreference]) {
        [self showAuthorizationNotice];
    } else {
        [self beginIdentityDiscovery];
        if (self.devices.count == 0) [self refreshDevices];
    }
}

- (void)beginIdentityDiscovery {
    __weak typeof(self) weakSelf = self;
    [self.permissionManager requestPermissionsWithCompletion:^{
        [weakSelf.bonjourDiscovery startDiscovery];
    }];
}

- (void)showAuthorizationNotice {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Authorized Networks Only"
                         message:@"LocalFence may interrupt another device's network access. Use it only on private networks you own or are explicitly authorized to administer."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Exit"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
        (void)action;
        exit(0);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"I Understand"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        (void)action;
        [[NSUserDefaults standardUserDefaults]
            setBool:YES forKey:LFAuthorizationPreference];
        [self beginIdentityDiscovery];
        [self refreshDevices];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSUInteger)selectedInterval {
    NSInteger stored = [[NSUserDefaults standardUserDefaults]
        integerForKey:LFIntervalPreference];
    return stored >= 5 && stored <= 5000 ? (NSUInteger)stored : 500;
}

- (void)performRequest:(NSDictionary *)request
             completion:(void (^)(NSDictionary *response))completion {
    if (self.requestInProgress) return;
    self.requestInProgress = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSDictionary *response = [LFIPCClient sendRequest:request error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.requestInProgress = NO;
            [self.refreshControl endRefreshing];
            if (response == nil) {
                [self showError:error.localizedDescription];
                return;
            }
            if (![response[@"ok"] boolValue]) {
                [self showError:response[@"error"] ?: @"The operation failed."];
                return;
            }
            completion(response);
        });
    });
}

- (void)refreshDevices {
    [self.refreshControl beginRefreshing];
    [self performRequest:@{ @"command" : @"scan" }
              completion:^(NSDictionary *response) {
        self.devices = response[@"devices"] ?: @[];
        self.network = response[@"network"] ?: @{};
        [self updateNetworkHeader];
        [self.tableView reloadData];
    }];
}

- (void)updateNetworkHeader {
    NSString *localIP = self.network[@"localIP"] ?: @"Unknown";
    NSString *gateway = self.network[@"gatewayIP"] ?: @"Unknown";
    NSString *interface = self.network[@"interface"] ?: @"Unknown";
    self.networkLabel.text = [NSString stringWithFormat:
        @"%@ • This iPhone: %@ • Router: %@\n%lu device%@ discovered",
        interface, localIP, gateway, (unsigned long)self.devices.count,
        self.devices.count == 1 ? @"" : @"s"];
}

- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"LocalFence"
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showSettings {
    NSUInteger selected = [self selectedInterval];
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:@"Packet Interval"
                         message:@"5–50 ms is an advanced high-traffic setting. The daemon enforces a global traffic ceiling across all selected devices."
                  preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSNumber *> *choices = @[
        @5, @10, @20, @50, @100, @250, @500, @1000, @2000
    ];
    for (NSNumber *choice in choices) {
        NSString *title = [NSString stringWithFormat:@"%@ ms%@",
            choice, choice.unsignedIntegerValue == selected ? @" ✓" : @""];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            (void)action;
            [[NSUserDefaults standardUserDefaults]
                setInteger:choice.integerValue forKey:LFIntervalPreference];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    sheet.popoverPresentationController.barButtonItem =
        self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)confirmStopAll {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Restore All Devices?"
                         message:@"LocalFence will stop every active block and send corrective ARP updates."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Stop All"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        (void)action;
        [self performRequest:@{ @"command" : @"stop" }
                  completion:^(NSDictionary *response) {
            (void)response;
            [self refreshDevices];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)self.devices.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"Device";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                       reuseIdentifier:identifier];
    }

    NSDictionary *device = self.devices[(NSUInteger)indexPath.row];
    BOOL gateway = [device[@"gateway"] boolValue];
    BOOL blocked = [device[@"blocked"] boolValue];
    NSDictionary *evidence = [self.bonjourDiscovery
        evidenceForIPAddress:device[@"ip"] ?: @""];
    NSDictionary *identity = [self.identityResolver identityForDevice:device
                                                              evidence:evidence];
    NSString *friendlyName = identity[@"name"];
    NSString *platform = identity[@"platform"];
    if (gateway) {
        cell.textLabel.text = friendlyName.length > 0 ? friendlyName : @"Router";
    } else if (friendlyName.length > 0) {
        cell.textLabel.text = friendlyName;
    } else if (![platform isEqualToString:@"Unknown device"]) {
        cell.textLabel.text = platform;
    } else {
        cell.textLabel.text = device[@"ip"];
    }
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.text = [NSString stringWithFormat:
        @"%@ • %@\n%@ • %@ (%@ confidence)",
        device[@"ip"] ?: @"Unknown IP", device[@"mac"] ?: @"Unknown MAC",
        identity[@"vendor"], identity[@"platform"], identity[@"confidence"]];
    cell.textLabel.textColor = blocked ? UIColor.systemRedColor : UIColor.labelColor;
    cell.accessoryType = gateway ? UITableViewCellAccessoryDetailButton
                                 : (blocked ? UITableViewCellAccessoryCheckmark
                                            : UITableViewCellAccessoryDisclosureIndicator);
    cell.selectionStyle = gateway ? UITableViewCellSelectionStyleNone
                                  : UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *device = self.devices[(NSUInteger)indexPath.row];
    if ([device[@"gateway"] boolValue]) return;

    BOOL blocked = [device[@"blocked"] boolValue];
    NSString *verb = blocked ? @"Restore" : @"Block";
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"%@ %@?", verb, device[@"ip"]]
                         message:blocked
                            ? @"The daemon will stop blocking this device and restore the router mapping."
                            : @"This will interrupt internet access for the selected device until restored."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:verb
                                              style:blocked ? UIAlertActionStyleDefault
                                                            : UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        (void)action;
        NSDictionary *request = blocked
            ? @{ @"command" : @"unblock", @"ip" : device[@"ip"] }
            : @{ @"command" : @"block",
                 @"ip" : device[@"ip"],
                 @"mac" : device[@"mac"],
                 @"intervalMs" : @([self selectedInterval]) };
        [self performRequest:request completion:^(NSDictionary *response) {
            (void)response;
            [self refreshDevices];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
