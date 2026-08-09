#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LFNetworkController : NSObject

- (nullable NSDictionary *)statusWithError:(NSError **)error;
- (nullable NSDictionary *)scanWithError:(NSError **)error;
- (BOOL)blockIP:(NSString *)ipAddress
             mac:(NSString *)macAddress
      intervalMs:(NSUInteger)intervalMs
           error:(NSError **)error;
- (BOOL)unblockIP:(NSString *)ipAddress error:(NSError **)error;
- (BOOL)stopAllWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

