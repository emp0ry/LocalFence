#import "LFIPCClient.h"

#include <errno.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static NSString *const LFIPCErrorDomain = @"com.emp0ry.localfence.ipc";
static const char *const LFIPCSocketPath =
    "/var/mobile/Library/LocalFence/localfence.sock";

static NSError *LFIPCError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:LFIPCErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}

@implementation LFIPCClient

+ (NSDictionary *)sendRequest:(NSDictionary *)request error:(NSError **)error {
    if (![NSJSONSerialization isValidJSONObject:request]) {
        if (error != NULL) {
            *error = LFIPCError(1, @"The daemon request is not valid JSON.");
        }
        return nil;
    }

    NSError *serializationError = nil;
    NSData *requestData = [NSJSONSerialization dataWithJSONObject:request
                                                           options:0
                                                             error:&serializationError];
    if (requestData == nil) {
        if (error != NULL) *error = serializationError;
        return nil;
    }

    int descriptor = socket(AF_UNIX, SOCK_STREAM, 0);
    if (descriptor < 0) {
        if (error != NULL) {
            *error = LFIPCError(2, [NSString stringWithFormat:
                @"Unable to create IPC socket: %s", strerror(errno)]);
        }
        return nil;
    }

    struct timeval timeout = {.tv_sec = 20, .tv_usec = 0};
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_un address = {0};
    address.sun_len = sizeof(address);
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, LFIPCSocketPath, sizeof(address.sun_path));

    if (connect(descriptor, (const struct sockaddr *)&address,
                sizeof(address)) != 0) {
        int savedError = errno;
        close(descriptor);
        if (error != NULL) {
            *error = LFIPCError(3, [NSString stringWithFormat:
                @"LocalFence daemon is unavailable: %s", strerror(savedError)]);
        }
        return nil;
    }

    const uint8_t *bytes = requestData.bytes;
    NSUInteger remaining = requestData.length;
    while (remaining > 0) {
        ssize_t written = write(descriptor, bytes, remaining);
        if (written <= 0) {
            int savedError = errno;
            close(descriptor);
            if (error != NULL) {
                *error = LFIPCError(4, [NSString stringWithFormat:
                    @"Unable to write daemon request: %s", strerror(savedError)]);
            }
            return nil;
        }
        bytes += written;
        remaining -= (NSUInteger)written;
    }
    shutdown(descriptor, SHUT_WR);

    NSMutableData *responseData = [NSMutableData data];
    uint8_t buffer[4096] = {0};
    for (;;) {
        ssize_t count = read(descriptor, buffer, sizeof(buffer));
        if (count == 0) break;
        if (count < 0) {
            int savedError = errno;
            close(descriptor);
            if (error != NULL) {
                *error = LFIPCError(5, [NSString stringWithFormat:
                    @"Unable to read daemon response: %s", strerror(savedError)]);
            }
            return nil;
        }
        [responseData appendBytes:buffer length:(NSUInteger)count];
        if (responseData.length > 512 * 1024) {
            close(descriptor);
            if (error != NULL) {
                *error = LFIPCError(6, @"Daemon response exceeded the safety limit.");
            }
            return nil;
        }
    }
    close(descriptor);

    id response = [NSJSONSerialization JSONObjectWithData:responseData
                                                   options:0
                                                     error:&serializationError];
    if (![response isKindOfClass:[NSDictionary class]]) {
        if (error != NULL) {
            *error = serializationError ?: LFIPCError(7, @"Daemon returned an invalid response.");
        }
        return nil;
    }
    return response;
}

@end
