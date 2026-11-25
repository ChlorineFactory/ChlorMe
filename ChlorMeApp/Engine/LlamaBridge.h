#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ChlorLlamaSamplingParams : NSObject
@property (nonatomic, assign) float temperature;
@property (nonatomic, assign) float minP;
@property (nonatomic, assign) float topP;
@property (nonatomic, assign) int32_t topK;
@property (nonatomic, assign) float repeatPenalty;
@property (nonatomic, assign) int32_t repeatLastN;
@property (nonatomic, assign) float frequencyPenalty;
@property (nonatomic, assign) float presencePenalty;
@property (nonatomic, assign) float dryMultiplier;
@property (nonatomic, assign) float dryBase;
@property (nonatomic, assign) int32_t dryAllowedLength;
@property (nonatomic, assign) int32_t dryPenaltyLastN;
@property (nonatomic, assign) int32_t maxTokens;
@property (nonatomic, copy) NSArray<NSString *> *stopSequences;
@end

typedef void (^ChlorTokenHandler)(NSString *tokenText, double tokensPerSecond);
typedef BOOL (^ChlorStopCheck)(void);

@interface ChlorLlamaEngine : NSObject

@property (nonatomic, readonly) BOOL isLoaded;
@property (nonatomic, readonly, nullable) NSString *loadedModelPath;

/// Returns iOS per-process available memory via os_proc_available_memory() (or physical memory fallback).
+ (int64_t)availableMemoryBytes;

/// kvQuantMode: 0 = F16, 1 = Q8_0, 2 = Q4_0
- (BOOL)loadModelAtPath:(NSString *)path
          contextLength:(int32_t)contextLength
              gpuLayers:(int32_t)gpuLayers
            kvQuantMode:(int32_t)kvQuantMode
                  error:(NSError * _Nullable * _Nullable)error;

- (BOOL)generateWithPrompt:(NSString *)prompt
                    params:(ChlorLlamaSamplingParams *)params
                   onToken:(ChlorTokenHandler)onToken
                shouldStop:(ChlorStopCheck)shouldStop
                     error:(NSError * _Nullable * _Nullable)error;

- (void)clearKVCache;
- (BOOL)saveStateToPath:(NSString *)path;
- (BOOL)loadStateFromPath:(NSString *)path;
- (void)unloadModel;

@end

NS_ASSUME_NONNULL_END
