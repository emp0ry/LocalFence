#import "LFServer.h"

#import "LFNetwork.h"

#include <errno.h>
#include <pwd.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

extern int proc_pidpath(int pid, void *buffer, unsigned int buffersize);

#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif

static NSString *const LFServerErrorDomain = @"com.emp0ry.localfence.server";
static const NSUInteger LFMaximumRequestSize = 64 * 1024;
static const char *const LFIPCDirectory = "/var/mobile/Library/LocalFence";
static const char *const LFIPCSocketPath =
    "/var/mobile/Library/LocalFence/localfence.sock";

static NSError *LFServerError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:LFServerErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}

static BOOL LFPathHasSuffix(const char *path, const char *suffix) {
    size_t pathLength = strlen(path);
    size_t suffixLength = strlen(suffix);
    return pathLength >= suffixLength &&
           memcmp(path + pathLength - suffixLength, suffix, suffixLength) == 0;
}

static BOOL LFAuthorizePeer(int descriptor) {
    uid_t userID = (uid_t)-1;
    gid_t groupID = (gid_t)-1;
    if (getpeereid(descriptor, &userID, &groupID) != 0) {
        return NO;
    }
    (void)groupID;

    pid_t peerPID = 0;
    socklen_t peerPIDLength = sizeof(peerPID);
    if (getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &peerPID,
                   &peerPIDLength) != 0 || peerPID <= 0) {
        return NO;
    }

    char peerPath[PROC_PIDPATHINFO_MAXSIZE] = {0};
    if (proc_pidpath(peerPID, peerPath, sizeof(peerPath)) <= 0) {
        return NO;
    }

    if (userID == 0 && LFPathHasSuffix(peerPath, "/usr/bin/localfencectl")) {
        return YES;
    }

    struct passwd *mobile = getpwnam("mobile");
    uid_t mobileID = mobile == NULL ? 501 : mobile->pw_uid;
    return userID == mobileID &&
           LFPathHasSuffix(peerPath,
                           "/Applications/LocalFence.app/LocalFence");
}

@interface LFServer ()
@property(nonatomic, strong) LFNetworkController *networkController;
@end

@implementation LFServer

- (instancetype)initWithNetworkController:(LFNetworkController *)networkController {
    self = [super init];
    if (self != nil) {
        _networkController = networkController;
    }
    return self;
}

- (NSDictionary *)responseForRequest:(NSDictionary *)request {
    NSString *command = request[@"command"];
    if (![command isKindOfClass:[NSString class]]) {
        return @{ @"ok" : @NO, @"error" : @"Missing command." };
    }

    NSError *error = nil;
    NSDictionary *payload = nil;
    if ([command isEqualToString:@"status"]) {
        payload = [self.networkController statusWithError:&error];
    } else if ([command isEqualToString:@"scan"]) {
        payload = [self.networkController scanWithError:&error];
    } else if ([command isEqualToString:@"block"]) {
        NSString *ipAddress = request[@"ip"];
        NSString *macAddress = request[@"mac"];
        NSNumber *interval = request[@"intervalMs"];
        if (![ipAddress isKindOfClass:[NSString class]] ||
            ![macAddress isKindOfClass:[NSString class]] ||
            ![interval isKindOfClass:[NSNumber class]]) {
            return @{ @"ok" : @NO, @"error" : @"Block requires ip, mac, and intervalMs." };
        }
        if ([self.networkController blockIP:ipAddress mac:macAddress
                                  intervalMs:interval.unsignedIntegerValue
                                       error:&error]) {
            payload = [self.networkController statusWithError:&error];
        }
    } else if ([command isEqualToString:@"unblock"]) {
        NSString *ipAddress = request[@"ip"];
        if (![ipAddress isKindOfClass:[NSString class]]) {
            return @{ @"ok" : @NO, @"error" : @"Unblock requires an IP address." };
        }
        if ([self.networkController unblockIP:ipAddress error:&error]) {
            payload = [self.networkController statusWithError:&error];
        }
    } else if ([command isEqualToString:@"stop"]) {
        if ([self.networkController stopAllWithError:&error]) {
            payload = [self.networkController statusWithError:&error];
        }
    } else {
        return @{ @"ok" : @NO, @"error" : @"Unknown command." };
    }

    if (payload == nil) {
        return @{ @"ok" : @NO,
                  @"error" : error.localizedDescription ?: @"Operation failed." };
    }
    NSMutableDictionary *response = [payload mutableCopy];
    response[@"ok"] = @YES;
    return response;
}

- (void)writeResponse:(NSDictionary *)response toDescriptor:(int)descriptor {
    NSData *data = [NSJSONSerialization dataWithJSONObject:response
                                                   options:0
                                                     error:nil];
    const uint8_t *bytes = data.bytes;
    NSUInteger remaining = data.length;
    while (remaining > 0) {
        ssize_t written = write(descriptor, bytes, remaining);
        if (written <= 0) return;
        bytes += written;
        remaining -= (NSUInteger)written;
    }
}

- (void)handleClient:(int)descriptor {
    if (!LFAuthorizePeer(descriptor)) {
        [self writeResponse:@{ @"ok" : @NO, @"error" : @"Unauthorized client." }
               toDescriptor:descriptor];
        return;
    }

    NSMutableData *requestData = [NSMutableData data];
    uint8_t buffer[4096] = {0};
    for (;;) {
        ssize_t count = read(descriptor, buffer, sizeof(buffer));
        if (count == 0) break;
        if (count < 0) {
            [self writeResponse:@{ @"ok" : @NO, @"error" : @"Unable to read request." }
                   toDescriptor:descriptor];
            return;
        }
        [requestData appendBytes:buffer length:(NSUInteger)count];
        if (requestData.length > LFMaximumRequestSize) {
            [self writeResponse:@{ @"ok" : @NO, @"error" : @"Request is too large." }
                   toDescriptor:descriptor];
            return;
        }
    }

    NSError *jsonError = nil;
    id request = [NSJSONSerialization JSONObjectWithData:requestData
                                                  options:0
                                                    error:&jsonError];
    if (![request isKindOfClass:[NSDictionary class]]) {
        [self writeResponse:@{ @"ok" : @NO,
                               @"error" : jsonError.localizedDescription ?: @"Invalid JSON." }
               toDescriptor:descriptor];
        return;
    }
    [self writeResponse:[self responseForRequest:request] toDescriptor:descriptor];
}

- (BOOL)runWithError:(NSError **)error {
    struct passwd *mobile = getpwnam("mobile");
    uid_t mobileID = mobile == NULL ? 501 : mobile->pw_uid;
    gid_t mobileGroupID = mobile == NULL ? 501 : mobile->pw_gid;
    if (mkdir(LFIPCDirectory, 0700) != 0 && errno != EEXIST) {
        if (error != NULL) {
            *error = LFServerError(1, [NSString stringWithFormat:
                @"Unable to create IPC directory: %s", strerror(errno)]);
        }
        return NO;
    }
    chown(LFIPCDirectory, mobileID, mobileGroupID);
    chmod(LFIPCDirectory, 0700);

    const char *socketPath = LFIPCSocketPath;
    unlink(socketPath);

    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) {
        if (error != NULL) {
            *error = LFServerError(1, [NSString stringWithFormat:
                @"Unable to create server socket: %s", strerror(errno)]);
        }
        return NO;
    }

    struct sockaddr_un address = {0};
    address.sun_len = sizeof(address);
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, socketPath, sizeof(address.sun_path));
    if (bind(server, (const struct sockaddr *)&address, sizeof(address)) != 0 ||
        listen(server, 8) != 0) {
        int savedError = errno;
        close(server);
        unlink(socketPath);
        if (error != NULL) {
            *error = LFServerError(2, [NSString stringWithFormat:
                @"Unable to start server socket: %s", strerror(savedError)]);
        }
        return NO;
    }

    chown(socketPath, mobileID, mobileGroupID);
    chmod(socketPath, 0600);

    for (;;) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            close(server);
            unlink(socketPath);
            if (error != NULL) {
                *error = LFServerError(3, [NSString stringWithFormat:
                    @"Server accept failed: %s", strerror(errno)]);
            }
            return NO;
        }
        @autoreleasepool {
            [self handleClient:client];
        }
        close(client);
    }
}

@end
