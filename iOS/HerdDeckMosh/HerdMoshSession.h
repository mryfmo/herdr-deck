#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^HerdMoshOutputHandler)(NSData *data);
typedef void (^HerdMoshExitHandler)(int32_t exitCode);

@interface HerdMoshSession : NSObject

- (instancetype)initWithHost:(NSString *)host
                         port:(int32_t)port
                          key:(NSString *)key
               predictionMode:(NSString *)predictionMode
                      columns:(int32_t)columns
                         rows:(int32_t)rows
                outputHandler:(HerdMoshOutputHandler)outputHandler
                  exitHandler:(HerdMoshExitHandler)exitHandler NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)start;
- (void)write:(NSData *)data;
- (void)resizeWithColumns:(int32_t)columns rows:(int32_t)rows;
- (void)stop;

@end

NS_ASSUME_NONNULL_END