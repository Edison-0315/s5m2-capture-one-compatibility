#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *S5ErrorDomain;
typedef void (^S5Progress)(NSString *message);

// All inspection is offline. No Capture One code is executed by this library.
@interface S5PatchCore : NSObject
+ (nullable NSDictionary *)analyzeBinary:(NSData *)data error:(NSError **)error;
+ (nullable NSDictionary *)inspectApp:(NSURL *)app error:(NSError **)error;
+ (nullable NSURL *)createCopy:(NSURL *)source inFolder:(NSURL *)folder
                    progress:(S5Progress)progress error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
