#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LFOUIResolver : NSObject
- (nullable NSString *)vendorForMACAddress:(NSString *)macAddress
                        locallyAdministered:(nullable BOOL *)locallyAdministered;
@end

NS_ASSUME_NONNULL_END
