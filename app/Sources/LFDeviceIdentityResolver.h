#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LFDeviceIdentityResolver : NSObject
- (NSDictionary<NSString *, id> *)identityForDevice:(NSDictionary *)device
                                            evidence:(NSDictionary *)evidence;
@end

NS_ASSUME_NONNULL_END
