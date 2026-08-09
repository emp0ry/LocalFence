#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LFPermissionManager : NSObject
- (void)requestPermissions;
- (void)requestPermissionsWithCompletion:(nullable dispatch_block_t)completion;
@end

NS_ASSUME_NONNULL_END
