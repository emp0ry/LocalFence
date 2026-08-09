#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LFBonjourDiscovery : NSObject
@property(nonatomic, copy, nullable) void (^updateHandler)(NSString *ipAddress);
- (void)startDiscovery;
- (NSDictionary<NSString *, NSArray<NSString *> *> *)evidenceForIPAddress:
    (NSString *)ipAddress;
@end

NS_ASSUME_NONNULL_END
