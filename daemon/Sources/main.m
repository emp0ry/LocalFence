#import <Foundation/Foundation.h>

#import "LFNetwork.h"
#import "LFServer.h"

#include <signal.h>

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;
    signal(SIGPIPE, SIG_IGN);

    @autoreleasepool {
        LFNetworkController *networkController = [LFNetworkController new];
        LFServer *server = [[LFServer alloc]
            initWithNetworkController:networkController];
        NSError *error = nil;
        if (![server runWithError:&error]) {
            fprintf(stderr, "localfenced: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
    }
    return 0;
}

