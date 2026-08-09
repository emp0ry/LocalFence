#import <Foundation/Foundation.h>

#import "LFIPCClient.h"

static void printUsage(void) {
    fprintf(stderr,
        "Usage:\n"
        "  localfencectl status\n"
        "  localfencectl scan\n"
        "  localfencectl block <private-ip> <mac> [interval-ms]\n"
        "  localfencectl unblock <private-ip>\n"
        "  localfencectl stop\n");
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            printUsage();
            return 64;
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        NSMutableDictionary *request = [@{ @"command" : command } mutableCopy];
        if ([command isEqualToString:@"block"]) {
            if (argc < 4 || argc > 5) {
                printUsage();
                return 64;
            }
            request[@"ip"] = [NSString stringWithUTF8String:argv[2]];
            request[@"mac"] = [NSString stringWithUTF8String:argv[3]];
            request[@"intervalMs"] = @(argc == 5 ? strtoul(argv[4], NULL, 10) : 500);
        } else if ([command isEqualToString:@"unblock"]) {
            if (argc != 3) {
                printUsage();
                return 64;
            }
            request[@"ip"] = [NSString stringWithUTF8String:argv[2]];
        } else if (!([command isEqualToString:@"status"] ||
                     [command isEqualToString:@"scan"] ||
                     [command isEqualToString:@"stop"]) || argc != 2) {
            printUsage();
            return 64;
        }

        NSError *error = nil;
        NSDictionary *response = [LFIPCClient sendRequest:request error:&error];
        if (response == nil) {
            fprintf(stderr, "localfencectl: %s\n", error.localizedDescription.UTF8String);
            return 69;
        }

        NSData *json = [NSJSONSerialization dataWithJSONObject:response
                                                       options:NSJSONWritingPrettyPrinted |
                                                               NSJSONWritingSortedKeys
                                                         error:&error];
        if (json == nil) {
            fprintf(stderr, "localfencectl: %s\n", error.localizedDescription.UTF8String);
            return 70;
        }
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        return [response[@"ok"] boolValue] ? 0 : 1;
    }
}

