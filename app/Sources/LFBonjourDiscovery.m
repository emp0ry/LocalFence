#import "LFBonjourDiscovery.h"

#include <arpa/inet.h>
#include <netinet/in.h>

static NSArray<NSString *> *LFServiceTypes(void) {
    return @[
        @"_airplay._tcp.", @"_raop._tcp.", @"_companion-link._tcp.",
        @"_apple-mobdev2._tcp.", @"_googlecast._tcp.",
        @"_androidtvremote2._tcp.", @"_smb._tcp.", @"_rdp._tcp.",
        @"_ssh._tcp.", @"_workstation._tcp.", @"_device-info._tcp.",
        @"_http._tcp.", @"_ipp._tcp.", @"_printer._tcp.", @"_hap._tcp.",
        @"_spotify-connect._tcp."
    ];
}

@interface LFBonjourDiscovery () <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property(nonatomic, strong) NSMutableArray<NSNetServiceBrowser *> *browsers;
@property(nonatomic, strong) NSMutableSet<NSNetService *> *services;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *evidence;
@property(nonatomic, assign) BOOL started;
@end

@implementation LFBonjourDiscovery

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _browsers = [NSMutableArray array];
        _services = [NSMutableSet set];
        _evidence = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)startDiscovery {
    if (self.started) return;
    self.started = YES;
    for (NSString *type in LFServiceTypes()) {
        NSNetServiceBrowser *browser = [NSNetServiceBrowser new];
        browser.delegate = self;
        [self.browsers addObject:browser];
        [browser searchForServicesOfType:type inDomain:@"local."];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        for (NSNetServiceBrowser *browser in self.browsers) [browser stop];
        [self.browsers removeAllObjects];
    });
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    (void)browser;
    (void)moreComing;
    service.delegate = self;
    [self.services addObject:service];
    [service resolveWithTimeout:5.0];
}

- (void)netServiceDidResolveAddress:(NSNetService *)service {
    NSMutableSet<NSString *> *addresses = [NSMutableSet set];
    for (NSData *addressData in service.addresses) {
        const struct sockaddr *address = addressData.bytes;
        if (address == NULL || address->sa_family != AF_INET) continue;
        const struct sockaddr_in *ipv4 = (const struct sockaddr_in *)address;
        char buffer[INET_ADDRSTRLEN] = {0};
        if (inet_ntop(AF_INET, &ipv4->sin_addr, buffer, sizeof(buffer)) != NULL) {
            [addresses addObject:[NSString stringWithUTF8String:buffer]];
        }
    }

    for (NSString *ipAddress in addresses) {
        NSMutableDictionary *entry = self.evidence[ipAddress];
        if (entry == nil) {
            entry = [@{
                @"names" : [NSMutableSet set],
                @"hostnames" : [NSMutableSet set],
                @"services" : [NSMutableSet set],
            } mutableCopy];
            self.evidence[ipAddress] = entry;
        }
        if (service.name.length > 0) [entry[@"names"] addObject:service.name];
        if (service.hostName.length > 0) [entry[@"hostnames"] addObject:service.hostName];
        if (service.type.length > 0) [entry[@"services"] addObject:service.type];
        if (self.updateHandler != nil) self.updateHandler(ipAddress);
    }
    [self.services removeObject:service];
}

- (void)netService:(NSNetService *)service
    didNotResolve:(NSDictionary<NSString *, NSNumber *> *)errorDict {
    (void)errorDict;
    [self.services removeObject:service];
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)evidenceForIPAddress:
    (NSString *)ipAddress {
    NSDictionary *entry = self.evidence[ipAddress];
    if (entry == nil) return @{};
    return @{
        @"names" : [[entry[@"names"] allObjects]
            sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)],
        @"hostnames" : [[entry[@"hostnames"] allObjects]
            sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)],
        @"services" : [[entry[@"services"] allObjects]
            sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)],
    };
}

@end
