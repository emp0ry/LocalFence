#import <Foundation/Foundation.h>

@class LFNetworkController;

NS_ASSUME_NONNULL_BEGIN

@interface LFServer : NSObject

- (instancetype)initWithNetworkController:(LFNetworkController *)networkController;
- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

