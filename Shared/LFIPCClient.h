#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LFIPCClient : NSObject

+ (nullable NSDictionary *)sendRequest:(NSDictionary *)request
                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

