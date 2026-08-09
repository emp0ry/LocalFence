#import "LFNetwork.h"

#import "LFCore.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <netinet/in.h>
#include <rootless.h>
#include <signal.h>
#include <spawn.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

#ifndef BIOCSETIF
#define BIOCSETIF _IOW('B', 108, struct ifreq)
#endif

#ifndef BIOCSHDRCMPLT
#define BIOCSHDRCMPLT _IOW('B', 117, unsigned int)
#endif

static NSString *const LFErrorDomain = @"com.emp0ry.localfence.network";
static const NSUInteger LFMaximumBlockedDevices = 255;
static const double LFMaximumSendEventsPerSecond = 1000.0;

typedef struct {
    BOOL valid;
    char interfaceName[LF_INTERFACE_NAME_LENGTH];
    uint32_t localIP;
    uint32_t netmask;
    uint32_t gatewayIP;
    uint8_t localMAC[LF_MAC_LENGTH];
    uint8_t gatewayMAC[LF_MAC_LENGTH];
} LFNetworkContext;

static NSError *LFMakeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:LFErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}

static NSString *LFIPv4String(uint32_t networkOrderAddress) {
    char buffer[LF_IPV4_STRING_LENGTH] = {0};
    struct in_addr address = {.s_addr = networkOrderAddress};
    if (inet_ntop(AF_INET, &address, buffer, sizeof(buffer)) == NULL) {
        return @"";
    }
    return [NSString stringWithUTF8String:buffer];
}

static NSString *LFMACString(const uint8_t mac[LF_MAC_LENGTH]) {
    char buffer[LF_MAC_STRING_LENGTH] = {0};
    lf_format_mac(mac, buffer);
    return [NSString stringWithUTF8String:buffer];
}

static NSString *LFRunUtility(const char *executable,
                              NSArray<NSString *> *arguments,
                              NSError **error) {
    int outputPipe[2] = {-1, -1};
    if (pipe(outputPipe) != 0) {
        if (error != NULL) {
            *error = LFMakeError(10, [NSString stringWithFormat:
                @"Unable to create utility pipe: %s", strerror(errno)]);
        }
        return nil;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addclose(&actions, outputPipe[0]);
    posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, outputPipe[1]);

    NSUInteger argumentCount = arguments.count;
    char **argv = calloc(argumentCount + 2, sizeof(char *));
    if (argv == NULL) {
        posix_spawn_file_actions_destroy(&actions);
        close(outputPipe[0]);
        close(outputPipe[1]);
        if (error != NULL) {
            *error = LFMakeError(11, @"Unable to allocate utility arguments.");
        }
        return nil;
    }
    argv[0] = (char *)executable;
    for (NSUInteger index = 0; index < argumentCount; index++) {
        argv[index + 1] = (char *)arguments[index].UTF8String;
    }

    pid_t process = 0;
    int spawnStatus = posix_spawn(&process, executable, &actions, NULL,
                                  argv, environ);
    free(argv);
    posix_spawn_file_actions_destroy(&actions);
    close(outputPipe[1]);
    if (spawnStatus != 0) {
        close(outputPipe[0]);
        if (error != NULL) {
            *error = LFMakeError(12, [NSString stringWithFormat:
                @"Unable to launch network utility: %s", strerror(spawnStatus)]);
        }
        return nil;
    }

    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[1024] = {0};
    for (;;) {
        ssize_t count = read(outputPipe[0], buffer, sizeof(buffer));
        if (count == 0) break;
        if (count < 0) {
            if (errno == EINTR) continue;
            int savedError = errno;
            close(outputPipe[0]);
            kill(process, SIGKILL);
            waitpid(process, NULL, 0);
            if (error != NULL) {
                *error = LFMakeError(13, [NSString stringWithFormat:
                    @"Unable to read utility output: %s", strerror(savedError)]);
            }
            return nil;
        }
        [data appendBytes:buffer length:(NSUInteger)count];
        if (data.length > 128 * 1024) {
            close(outputPipe[0]);
            kill(process, SIGKILL);
            waitpid(process, NULL, 0);
            if (error != NULL) {
                *error = LFMakeError(14, @"Network utility returned too much data.");
            }
            return nil;
        }
    }
    close(outputPipe[0]);

    int processStatus = 0;
    pid_t waitResult;
    do {
        waitResult = waitpid(process, &processStatus, 0);
    } while (waitResult < 0 && errno == EINTR);
    if (waitResult < 0 || !WIFEXITED(processStatus) ||
        WEXITSTATUS(processStatus) != 0) {
        if (error != NULL) {
            NSString *details = [[NSString alloc] initWithData:data
                                                       encoding:NSUTF8StringEncoding];
            details = [details stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet];
            *error = LFMakeError(15, details.length > 0
                ? [NSString stringWithFormat:@"Network utility failed: %@", details]
                : @"A required network utility failed.");
        }
        return nil;
    }

    NSString *result = [[NSString alloc] initWithData:data
                                              encoding:NSUTF8StringEncoding];
    if (result == nil && error != NULL) {
        *error = LFMakeError(16, @"Network utility output was not valid UTF-8.");
    }
    return result;
}

static BOOL LFLoadInterfaceAddresses(LFNetworkContext *context, NSError **error) {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) {
        if (error != NULL) {
            *error = LFMakeError(20, [NSString stringWithFormat:
                @"Unable to inspect interfaces: %s", strerror(errno)]);
        }
        return NO;
    }

    BOOL foundIPv4 = NO;
    BOOL foundMAC = NO;
    for (struct ifaddrs *entry = interfaces; entry != NULL;
         entry = entry->ifa_next) {
        if (entry->ifa_addr == NULL ||
            strcmp(entry->ifa_name, context->interfaceName) != 0) {
            continue;
        }

        if (entry->ifa_addr->sa_family == AF_INET && entry->ifa_netmask != NULL) {
            const struct sockaddr_in *address =
                (const struct sockaddr_in *)entry->ifa_addr;
            const struct sockaddr_in *mask =
                (const struct sockaddr_in *)entry->ifa_netmask;
            context->localIP = address->sin_addr.s_addr;
            context->netmask = mask->sin_addr.s_addr;
            foundIPv4 = YES;
        } else if (entry->ifa_addr->sa_family == AF_LINK) {
            const struct sockaddr_dl *link =
                (const struct sockaddr_dl *)entry->ifa_addr;
            if (link->sdl_alen == LF_MAC_LENGTH) {
                memcpy(context->localMAC, LLADDR(link), LF_MAC_LENGTH);
                foundMAC = YES;
            }
        }
    }

    freeifaddrs(interfaces);
    if ((!foundIPv4 || !foundMAC) && error != NULL) {
        *error = LFMakeError(21, @"The active interface has no usable IPv4 or MAC address.");
    }
    return foundIPv4 && foundMAC;
}

static BOOL LFReadNeighborTable(NSString *interfaceName,
                                NSMutableDictionary<NSString *, NSString *> *neighbors,
                                NSError **error) {
    NSString *output = LFRunUtility(ROOT_PATH("/usr/sbin/arp"), @[@"-an"], error);
    if (output == nil) {
        return NO;
    }

    [output enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        (void)stop;
        char parsedIP[LF_IPV4_STRING_LENGTH] = {0};
        char parsedInterface[LF_INTERFACE_NAME_LENGTH] = {0};
        uint8_t parsedMAC[LF_MAC_LENGTH] = {0};
        if (!lf_parse_arp_line(line.UTF8String, parsedIP, parsedMAC,
                               parsedInterface) ||
            strcmp(parsedInterface, interfaceName.UTF8String) != 0 ||
            (parsedMAC[0] & 1U) != 0) {
            return;
        }

        neighbors[[NSString stringWithUTF8String:parsedIP]] = LFMACString(parsedMAC);
    }];
    return YES;
}

static BOOL LFLoadNetworkContext(LFNetworkContext *context,
                                 BOOL requireGatewayMAC,
                                 NSError **error) {
    memset(context, 0, sizeof(*context));
    NSString *routeOutput = LFRunUtility(ROOT_PATH("/usr/sbin/route"),
                                         @[@"-n", @"get", @"default"],
                                         error);
    if (routeOutput == nil) {
        return NO;
    }

    char gateway[LF_IPV4_STRING_LENGTH] = {0};
    if (!lf_parse_route_output(routeOutput.UTF8String, gateway,
                               context->interfaceName) ||
        !lf_parse_ipv4(gateway, &context->gatewayIP)) {
        if (error != NULL) {
            *error = LFMakeError(30, @"Unable to identify the default IPv4 route.");
        }
        return NO;
    }

    if (strcmp(context->interfaceName, "en0") != 0) {
        if (error != NULL) {
            *error = LFMakeError(31,
                @"LocalFence currently supports Wi-Fi interface en0 only.");
        }
        return NO;
    }

    if (!LFLoadInterfaceAddresses(context, error) ||
        !lf_is_private_ipv4(context->localIP) ||
        !lf_is_private_ipv4(context->gatewayIP) ||
        !lf_same_subnet(context->localIP, context->gatewayIP,
                        context->netmask)) {
        if (error != NULL && *error == nil) {
            *error = LFMakeError(32,
                @"The active Wi-Fi route is not a supported private IPv4 LAN.");
        }
        return NO;
    }

    NSMutableDictionary<NSString *, NSString *> *neighbors =
        [NSMutableDictionary dictionary];
    if (!LFReadNeighborTable([NSString stringWithUTF8String:context->interfaceName],
                             neighbors, error)) {
        return NO;
    }

    NSString *gatewayMAC = neighbors[LFIPv4String(context->gatewayIP)];
    if (gatewayMAC != nil) {
        lf_parse_mac(gatewayMAC.UTF8String, context->gatewayMAC);
    } else if (requireGatewayMAC) {
        if (error != NULL) {
            *error = LFMakeError(33,
                @"The router MAC address is not available yet. Refresh and retry.");
        }
        return NO;
    }

    context->valid = YES;
    return YES;
}

static void LFProbeAddress(uint32_t address) {
    int socketFD = socket(AF_INET, SOCK_DGRAM, 0);
    if (socketFD < 0) {
        return;
    }

    struct sockaddr_in destination = {0};
    destination.sin_len = sizeof(destination);
    destination.sin_family = AF_INET;
    destination.sin_port = htons(9);
    destination.sin_addr.s_addr = address;
    const uint8_t marker = 0;
    sendto(socketFD, &marker, sizeof(marker), MSG_DONTWAIT,
           (const struct sockaddr *)&destination, sizeof(destination));
    close(socketFD);
}

static BOOL LFProbeSubnet(const LFNetworkContext *context, NSError **error) {
    uint32_t hostMask = ntohl(context->netmask);
    uint32_t wildcard = ~hostMask;
    if (wildcard < 3 || wildcard > 1023) {
        if (error != NULL) {
            *error = LFMakeError(40,
                @"For safety, active discovery is limited to /22 through /30 private subnets.");
        }
        return NO;
    }

    uint32_t network = ntohl(context->localIP) & hostMask;
    for (uint32_t offset = 1; offset < wildcard; offset++) {
        LFProbeAddress(htonl(network + offset));
    }
    usleep(650000);
    return YES;
}

static BOOL LFNetworkContextsMatch(const LFNetworkContext *first,
                                   const LFNetworkContext *second) {
    return first->valid && second->valid &&
           strcmp(first->interfaceName, second->interfaceName) == 0 &&
           first->localIP == second->localIP &&
           first->netmask == second->netmask &&
           first->gatewayIP == second->gatewayIP &&
           memcmp(first->localMAC, second->localMAC, LF_MAC_LENGTH) == 0 &&
           memcmp(first->gatewayMAC, second->gatewayMAC, LF_MAC_LENGTH) == 0;
}

@interface LFNetworkController ()
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *blocks;
@property(nonatomic, assign) LFNetworkContext context;
@property(nonatomic, assign) int bpfFileDescriptor;
@property(nonatomic, assign) BOOL workerShouldExit;
@end

@implementation LFNetworkController

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _lock = [NSLock new];
        _blocks = [NSMutableDictionary dictionary];
        _bpfFileDescriptor = -1;
        [NSThread detachNewThreadSelector:@selector(poisonWorker)
                                 toTarget:self
                               withObject:nil];
    }
    return self;
}

- (void)dealloc {
    _workerShouldExit = YES;
    if (_bpfFileDescriptor >= 0) {
        close(_bpfFileDescriptor);
    }
}

- (NSDictionary *)networkDictionary:(const LFNetworkContext *)context {
    return @{
        @"interface" : [NSString stringWithUTF8String:context->interfaceName],
        @"localIP" : LFIPv4String(context->localIP),
        @"localMAC" : LFMACString(context->localMAC),
        @"gatewayIP" : LFIPv4String(context->gatewayIP),
        @"gatewayMAC" : LFMACString(context->gatewayMAC),
        @"netmask" : LFIPv4String(context->netmask),
    };
}

- (NSArray *)blockedDeviceArray {
    [self.lock lock];
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:self.blocks.count];
    for (NSDictionary *block in self.blocks.allValues) {
        [values addObject:[block copy]];
    }
    [self.lock unlock];
    return values;
}

- (NSDictionary *)statusWithError:(NSError **)error {
    LFNetworkContext context = {0};
    if (!LFLoadNetworkContext(&context, NO, error)) {
        return nil;
    }
    return @{
        @"network" : [self networkDictionary:&context],
        @"blocked" : [self blockedDeviceArray],
        @"daemonVersion" : @"0.2.0",
    };
}

- (NSDictionary *)scanWithError:(NSError **)error {
    LFNetworkContext context = {0};
    if (!LFLoadNetworkContext(&context, NO, error) ||
        !LFProbeSubnet(&context, error)) {
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *neighbors =
        [NSMutableDictionary dictionary];
    NSString *interfaceName = [NSString stringWithUTF8String:context.interfaceName];
    if (!LFReadNeighborTable(interfaceName, neighbors, error)) {
        return nil;
    }

    NSString *gatewayIP = LFIPv4String(context.gatewayIP);
    NSString *gatewayMAC = neighbors[gatewayIP];
    if (gatewayMAC != nil) {
        lf_parse_mac(gatewayMAC.UTF8String, context.gatewayMAC);
    }

    [self.lock lock];
    NSSet *blockedIPs = [NSSet setWithArray:self.blocks.allKeys];
    [self.lock unlock];
    NSMutableArray<NSDictionary *> *devices = [NSMutableArray array];
    [neighbors enumerateKeysAndObjectsUsingBlock:^(NSString *ipAddress,
                                                    NSString *macAddress,
                                                    BOOL *stop) {
        (void)stop;
        uint32_t parsedIP = 0;
        if (!lf_parse_ipv4(ipAddress.UTF8String, &parsedIP) ||
            !lf_same_subnet(parsedIP, context.localIP, context.netmask) ||
            parsedIP == context.localIP) {
            return;
        }
        [devices addObject:@{
            @"ip" : ipAddress,
            @"mac" : macAddress,
            @"gateway" : @(parsedIP == context.gatewayIP),
            @"blocked" : @([blockedIPs containsObject:ipAddress]),
        }];
    }];

    [devices sortUsingComparator:^NSComparisonResult(NSDictionary *first,
                                                      NSDictionary *second) {
        uint32_t firstIP = 0;
        uint32_t secondIP = 0;
        lf_parse_ipv4([first[@"ip"] UTF8String], &firstIP);
        lf_parse_ipv4([second[@"ip"] UTF8String], &secondIP);
        uint32_t firstHost = ntohl(firstIP);
        uint32_t secondHost = ntohl(secondIP);
        if (firstHost < secondHost) return NSOrderedAscending;
        if (firstHost > secondHost) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    self.context = context;
    return @{
        @"network" : [self networkDictionary:&context],
        @"devices" : devices,
        @"blocked" : [self blockedDeviceArray],
    };
}

- (BOOL)openBPFForInterface:(const char *)interfaceName error:(NSError **)error {
    if (self.bpfFileDescriptor >= 0) {
        return YES;
    }

    int descriptor = -1;
    for (unsigned int index = 0; index < 256; index++) {
        char path[32] = {0};
        snprintf(path, sizeof(path), "/dev/bpf%u", index);
        descriptor = open(path, O_RDWR);
        if (descriptor >= 0 || errno != EBUSY) {
            break;
        }
    }
    if (descriptor < 0) {
        if (error != NULL) {
            *error = LFMakeError(50, [NSString stringWithFormat:
                @"Unable to open BPF: %s", strerror(errno)]);
        }
        return NO;
    }

    struct ifreq request = {0};
    strlcpy(request.ifr_name, interfaceName, sizeof(request.ifr_name));
    unsigned int headerComplete = 1;
    if (ioctl(descriptor, BIOCSETIF, &request) != 0 ||
        ioctl(descriptor, BIOCSHDRCMPLT, &headerComplete) != 0) {
        int savedError = errno;
        close(descriptor);
        if (error != NULL) {
            *error = LFMakeError(51, [NSString stringWithFormat:
                @"Unable to configure BPF: %s", strerror(savedError)]);
        }
        return NO;
    }

    self.bpfFileDescriptor = descriptor;
    return YES;
}

- (BOOL)writeOperation:(LFArpOperation)operation
          sourceMAC:(const uint8_t[LF_MAC_LENGTH])sourceMAC
           sourceIP:(uint32_t)sourceIP
          targetMAC:(const uint8_t[LF_MAC_LENGTH])targetMAC
           targetIP:(uint32_t)targetIP {
    uint8_t frame[LF_ARP_FRAME_LENGTH] = {0};
    if (lf_build_arp_frame(frame, sourceMAC, targetMAC, sourceMAC, sourceIP,
                           targetMAC, targetIP, operation) !=
        LF_ARP_FRAME_LENGTH) {
        return NO;
    }
    return write(self.bpfFileDescriptor, frame, sizeof(frame)) == sizeof(frame);
}

- (void)sendPoisonForBlock:(NSDictionary *)block context:(LFNetworkContext)context {
    uint8_t targetMAC[LF_MAC_LENGTH] = {0};
    uint32_t targetIP = 0;
    if (!lf_parse_mac([block[@"mac"] UTF8String], targetMAC) ||
        !lf_parse_ipv4([block[@"ip"] UTF8String], &targetIP)) {
        return;
    }
    [self writeOperation:LFArpOperationRequest sourceMAC:context.localMAC
                sourceIP:context.gatewayIP targetMAC:targetMAC targetIP:targetIP];
    [self writeOperation:LFArpOperationReply sourceMAC:context.localMAC
                sourceIP:context.gatewayIP targetMAC:targetMAC targetIP:targetIP];
}

- (void)restoreBlock:(NSDictionary *)block context:(LFNetworkContext)context {
    if (!context.valid || self.bpfFileDescriptor < 0) {
        return;
    }
    uint8_t targetMAC[LF_MAC_LENGTH] = {0};
    uint32_t targetIP = 0;
    if (!lf_parse_mac([block[@"mac"] UTF8String], targetMAC) ||
        !lf_parse_ipv4([block[@"ip"] UTF8String], &targetIP)) {
        return;
    }
    for (NSUInteger count = 0; count < 6; count++) {
        [self writeOperation:LFArpOperationReply sourceMAC:context.gatewayMAC
                    sourceIP:context.gatewayIP targetMAC:targetMAC targetIP:targetIP];
        usleep(40000);
    }
}

- (BOOL)blockIP:(NSString *)ipAddress
             mac:(NSString *)macAddress
      intervalMs:(NSUInteger)intervalMs
           error:(NSError **)error {
    uint32_t targetIP = 0;
    uint8_t targetMAC[LF_MAC_LENGTH] = {0};
    if (!lf_parse_ipv4(ipAddress.UTF8String, &targetIP) ||
        !lf_parse_mac(macAddress.UTF8String, targetMAC) ||
        !lf_valid_interval_ms((unsigned int)intervalMs) ||
        (targetMAC[0] & 1U) != 0) {
        if (error != NULL) {
            *error = LFMakeError(60, @"Invalid client address or packet interval.");
        }
        return NO;
    }

    LFNetworkContext context = {0};
    if (!LFLoadNetworkContext(&context, NO, error)) {
        return NO;
    }
    LFProbeAddress(targetIP);
    LFProbeAddress(context.gatewayIP);
    usleep(150000);
    if (!LFLoadNetworkContext(&context, YES, error) ||
        !lf_is_usable_client(targetIP, context.localIP, context.gatewayIP,
                             context.netmask)) {
        if (error != NULL && *error == nil) {
            *error = LFMakeError(61, @"The client is outside the active private subnet.");
        }
        return NO;
    }

    NSMutableDictionary<NSString *, NSString *> *neighbors =
        [NSMutableDictionary dictionary];
    if (!LFReadNeighborTable([NSString stringWithUTF8String:context.interfaceName],
                             neighbors, error)) {
        return NO;
    }
    NSString *currentMAC = neighbors[ipAddress];
    if (currentMAC == nil ||
        [currentMAC caseInsensitiveCompare:macAddress] != NSOrderedSame) {
        if (error != NULL && *error == nil) {
            *error = LFMakeError(62,
                @"The supplied MAC does not match the current neighbor table.");
        }
        return NO;
    }

    if (![self openBPFForInterface:context.interfaceName error:error]) {
        return NO;
    }

    [self.lock lock];
    if (self.blocks.count >= LFMaximumBlockedDevices && self.blocks[ipAddress] == nil) {
        [self.lock unlock];
        if (error != NULL) {
            *error = LFMakeError(63, @"The 255-device limit has been reached.");
        }
        return NO;
    }
    __block double sendEventsPerSecond = 1000.0 / (double)intervalMs;
    [self.blocks enumerateKeysAndObjectsUsingBlock:^(NSString *existingIP,
                                                      NSDictionary *block,
                                                      BOOL *stop) {
        (void)stop;
        if (![existingIP isEqualToString:ipAddress]) {
            sendEventsPerSecond += 1000.0 / [block[@"intervalMs"] doubleValue];
        }
    }];
    if (sendEventsPerSecond > LFMaximumSendEventsPerSecond) {
        [self.lock unlock];
        if (error != NULL) {
            *error = LFMakeError(64,
                @"This interval would exceed the global LAN traffic ceiling. Use a longer interval or restore other devices first.");
        }
        return NO;
    }
    self.context = context;
    self.blocks[ipAddress] = [@{
        @"ip" : ipAddress,
        @"mac" : LFMACString(targetMAC),
        @"intervalMs" : @(intervalMs),
        @"nextSend" : @0.0,
    } mutableCopy];
    [self.lock unlock];
    return YES;
}

- (BOOL)unblockIP:(NSString *)ipAddress error:(NSError **)error {
    (void)error;
    [self.lock lock];
    NSDictionary *block = [self.blocks[ipAddress] copy];
    LFNetworkContext context = self.context;
    [self.blocks removeObjectForKey:ipAddress];
    [self.lock unlock];
    if (block != nil) {
        [self restoreBlock:block context:context];
    }
    return YES;
}

- (BOOL)stopAllWithError:(NSError **)error {
    (void)error;
    [self.lock lock];
    NSArray *blocks = [self.blocks.allValues valueForKey:@"copy"];
    LFNetworkContext context = self.context;
    [self.blocks removeAllObjects];
    [self.lock unlock];
    for (NSDictionary *block in blocks) {
        [self restoreBlock:block context:context];
    }
    return YES;
}

- (void)poisonWorker {
    NSTimeInterval nextNetworkValidation = 0;
    while (!self.workerShouldExit) {
        useconds_t workerSleep = 20000;
        @autoreleasepool {
            NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
            [self.lock lock];
            BOOL hasBlocks = self.blocks.count > 0;
            LFNetworkContext savedContext = self.context;
            [self.lock unlock];
            if (hasBlocks) workerSleep = 1000;

            if (hasBlocks && now >= nextNetworkValidation) {
                LFNetworkContext currentContext = {0};
                NSError *contextError = nil;
                BOOL contextIsCurrent =
                    LFLoadNetworkContext(&currentContext, YES, &contextError) &&
                    LFNetworkContextsMatch(&savedContext, &currentContext);
                if (!contextIsCurrent) {
                    [self.lock lock];
                    [self.blocks removeAllObjects];
                    memset(&_context, 0, sizeof(_context));
                    [self.lock unlock];
                    if (self.bpfFileDescriptor >= 0) {
                        close(self.bpfFileDescriptor);
                        self.bpfFileDescriptor = -1;
                    }
                    NSLog(@"LocalFence stopped all blocks after the active network changed: %@",
                          contextError.localizedDescription ?: @"network identity changed");
                }
                nextNetworkValidation = now + 2.0;
            }

            NSMutableArray<NSDictionary *> *due = [NSMutableArray array];
            [self.lock lock];
            LFNetworkContext context = self.context;
            [self.blocks enumerateKeysAndObjectsUsingBlock:^(NSString *key,
                                                              NSMutableDictionary *block,
                                                              BOOL *stop) {
                (void)key;
                (void)stop;
                if ([block[@"nextSend"] doubleValue] <= now) {
                    [due addObject:[block copy]];
                    block[@"nextSend"] =
                        @(now + [block[@"intervalMs"] doubleValue] / 1000.0);
                }
            }];
            [self.lock unlock];

            if (context.valid && self.bpfFileDescriptor >= 0) {
                for (NSDictionary *block in due) {
                    [self sendPoisonForBlock:block context:context];
                }
            }
        }
        usleep(workerSleep);
    }
}

@end
