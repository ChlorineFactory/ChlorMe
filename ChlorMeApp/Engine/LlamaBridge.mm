#import "LlamaBridge.h"
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
#include <os/proc.h>
#endif

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <type_traits>
#include <vector>

#if __has_include(<llama/llama.h>)
#import <llama/llama.h>
#define CHLOR_HAS_LLAMA 1
#elif __has_include("llama.h")
#import "llama.h"
#define CHLOR_HAS_LLAMA 1
#else
#define CHLOR_HAS_LLAMA 0
#endif

@implementation ChlorLlamaSamplingParams
- (instancetype)init {
    if (self = [super init]) {
        _temperature = 0.8f;
        _minP = 0.06f;
        _topP = 0.92f;
        _topK = 50;
        _repeatPenalty = 1.12f;
        _repeatLastN = 128;
        _frequencyPenalty = 0.05f;
        _presencePenalty = 0.05f;
        _dryMultiplier = 0.8f;
        _dryBase = 1.75f;
        _dryAllowedLength = 2;
        _dryPenaltyLastN = 512;
        _maxTokens = 512;
        _stopSequences = @[@"<|im_end|>", @"<|eot_id|>", @"<end_of_turn>", @"</s>"];
    }
    return self;
}
@end

#if CHLOR_HAS_LLAMA

// MARK: - C++17 SFINAE Adapters for Cross-Version llama.cpp Compatibility

template <typename Fn>
static llama_sampler *chlor_make_penalties(Fn fn, int32_t n_vocab, int32_t last_n, float repeat, float freq, float present) {
    if constexpr (std::is_invocable_v<Fn, int32_t, int32_t, float, float, float>) {
        return fn(n_vocab, last_n, repeat, freq, present);
    } else if constexpr (std::is_invocable_v<Fn, int32_t, float, float, float>) {
        return fn(last_n, repeat, freq, present);
    } else {
        return nullptr;
    }
}

template <typename Fn>
static llama_sampler *chlor_make_dry(Fn fn,
                                     const llama_vocab *vocab,
                                     int32_t n_ctx_train,
                                     float multiplier,
                                     float base,
                                     int32_t allowed_length,
                                     int32_t penalty_last_n,
                                     const char **breakers,
                                     size_t num_breakers) {
    if constexpr (std::is_invocable_v<Fn, const llama_vocab *, int32_t, float, float, int32_t, int32_t, const char **, size_t>) {
        return fn(vocab, n_ctx_train, multiplier, base, allowed_length, penalty_last_n, breakers, num_breakers);
    } else if constexpr (std::is_invocable_v<Fn, const llama_vocab *, float, float, int32_t, int32_t, const char **, size_t>) {
        return fn(vocab, multiplier, base, allowed_length, penalty_last_n, breakers, num_breakers);
    } else {
        return nullptr;
    }
}

template <typename T, typename = void>
struct has_flash_attn_bool : std::false_type {};
template <typename T>
struct has_flash_attn_bool<T, std::void_t<decltype(std::declval<T &>().flash_attn = true)>> : std::true_type {};

template <typename T, typename = void>
struct has_flash_attn_type : std::false_type {};
template <typename T>
struct has_flash_attn_type<T, std::void_t<decltype(std::declval<T &>().flash_attn_type)>> : std::true_type {};

template <typename CtxParams>
static void chlor_enable_flash_attn(CtxParams &params) {
    if constexpr (has_flash_attn_type<CtxParams>::value) {
        params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;
    } else if constexpr (has_flash_attn_bool<CtxParams>::value) {
        params.flash_attn = true;
    }
}

static void chlor_clear_memory(llama_context *ctx) {
    if (!ctx) return;
    llama_memory_t mem = llama_get_memory(ctx);
    if (mem) {
        llama_memory_clear(mem, true);
    }
}

static void chlor_batch_add(llama_batch &batch, llama_token id, llama_pos pos, llama_seq_id seq_id, bool logits) {
    batch.token[batch.n_tokens] = id;
    batch.pos[batch.n_tokens] = pos;
    batch.n_seq_id[batch.n_tokens] = 1;
    batch.seq_id[batch.n_tokens][0] = seq_id;
    batch.logits[batch.n_tokens] = logits ? 1 : 0;
    batch.n_tokens += 1;
}

/// Checks how many trailing bytes form an incomplete UTF-8 sequence so we never emit broken characters.
static size_t incomplete_utf8_tail_length(const std::string &buf) {
    if (buf.empty()) return 0;
    const size_t n = buf.size();
    const size_t maxLookback = std::min<size_t>(4, n);
    for (size_t back = 1; back <= maxLookback; ++back) {
        unsigned char c = static_cast<unsigned char>(buf[n - back]);
        if ((c & 0x80) == 0) {
            return 0; // ASCII byte ends complete sequence
        }
        if ((c & 0xC0) != 0x80) {
            size_t expected = 0;
            if ((c & 0xE0) == 0xC0) expected = 2;
            else if ((c & 0xF0) == 0xE0) expected = 3;
            else if ((c & 0xF8) == 0xF0) expected = 4;
            else return 0;
            return (back < expected) ? back : 0;
        }
    }
    return maxLookback;
}

#endif // CHLOR_HAS_LLAMA

@implementation ChlorLlamaEngine {
    std::mutex _mutex;
#if CHLOR_HAS_LLAMA
    llama_model *_model;
    llama_context *_ctx;
    int32_t _contextLength;
#endif
    NSString *_loadedModelPath;
}

+ (void)initialize {
    if (self == [ChlorLlamaEngine class]) {
#if CHLOR_HAS_LLAMA
        llama_backend_init();
#endif
    }
}

+ (int64_t)availableMemoryBytes {
#if TARGET_OS_IPHONE
    return (int64_t)os_proc_available_memory();
#else
    return (int64_t)[NSProcessInfo processInfo].physicalMemory / 2;
#endif
}

- (BOOL)isLoaded {
    std::lock_guard<std::mutex> lock(_mutex);
#if CHLOR_HAS_LLAMA
    return _model != nullptr && _ctx != nullptr;
#else
    return NO;
#endif
}

- (nullable NSString *)loadedModelPath {
    std::lock_guard<std::mutex> lock(_mutex);
    return _loadedModelPath;
}

- (void)dealloc {
    [self unloadModel];
}

- (void)unloadModel {
    std::lock_guard<std::mutex> lock(_mutex);
#if CHLOR_HAS_LLAMA
    if (_ctx) {
        llama_free(_ctx);
        _ctx = nullptr;
    }
    if (_model) {
        llama_model_free(_model);
        _model = nullptr;
    }
#endif
    _loadedModelPath = nil;
}

- (BOOL)loadModelAtPath:(NSString *)path
          contextLength:(int32_t)contextLength
              gpuLayers:(int32_t)gpuLayers
            kvQuantMode:(int32_t)kvQuantMode
                  error:(NSError * _Nullable * _Nullable)error {
    [self unloadModel];
    std::lock_guard<std::mutex> lock(_mutex);

#if !CHLOR_HAS_LLAMA
    if (error) {
        *error = [NSError errorWithDomain:@"ChlorLlamaEngine"
                                     code:-100
                                 userInfo:@{NSLocalizedDescriptionKey: @"当前构建未链接 llama.xcframework"}];
    }
    return NO;
#else
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ChlorLlamaEngine"
                                         code:-101
                                     userInfo:@{NSLocalizedDescriptionKey: @"模型文件不存在，请重新导入或下载"}];
        }
        return NO;
    }

    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = gpuLayers;

    _model = llama_model_load_from_file(path.UTF8String, mparams);
    if (!_model) {
        if (error) {
            *error = [NSError errorWithDomain:@"ChlorLlamaEngine"
                                         code:-102
                                     userInfo:@{NSLocalizedDescriptionKey: @"加载 GGUF 模型失败（文件可能不完整或内存不足）"}];
        }
        return NO;
    }

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = (uint32_t)std::max<int32_t>(1024, contextLength);
    cparams.n_batch = 512;
    cparams.n_ubatch = 256;
    int32_t threads = std::max<int32_t>(2, std::min<int32_t>(6, (int32_t)[NSProcessInfo processInfo].activeProcessorCount - 2));
    cparams.n_threads = threads;
    cparams.n_threads_batch = threads;
    chlor_enable_flash_attn(cparams);

    if (kvQuantMode == 1) {
        cparams.type_k = GGML_TYPE_Q8_0;
        cparams.type_v = GGML_TYPE_Q8_0;
    } else if (kvQuantMode == 2) {
        cparams.type_k = GGML_TYPE_Q4_0;
        cparams.type_v = GGML_TYPE_Q4_0;
    } else {
        cparams.type_k = GGML_TYPE_F16;
        cparams.type_v = GGML_TYPE_F16;
    }

    _ctx = llama_init_from_model(_model, cparams);
    if (!_ctx) {
        llama_model_free(_model);
        _model = nullptr;
        if (error) {
            *error = [NSError errorWithDomain:@"ChlorLlamaEngine"
                                         code:-103
                                     userInfo:@{NSLocalizedDescriptionKey: @"创建推理上下文失败，请尝试调低上下文长度或开启 Q8/Q4 KV 量化"}];
        }
        return NO;
    }

    _contextLength = contextLength;
    _loadedModelPath = [path copy];
    return YES;
#endif
}

- (void)clearKVCache {
    std::lock_guard<std::mutex> lock(_mutex);
#if CHLOR_HAS_LLAMA
    chlor_clear_memory(_ctx);
#endif
}

- (BOOL)saveStateToPath:(NSString *)path {
    std::lock_guard<std::mutex> lock(_mutex);
#if CHLOR_HAS_LLAMA
    if (!_ctx) return NO;
    return llama_state_save_file(_ctx, path.UTF8String, nullptr, 0);
#else
    return NO;
#endif
}

- (BOOL)loadStateFromPath:(NSString *)path {
    std::lock_guard<std::mutex> lock(_mutex);
#if CHLOR_HAS_LLAMA
    if (!_ctx) return NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return NO;
    size_t tokenCountOut = 0;
    return llama_state_load_file(_ctx, path.UTF8String, nullptr, 0, &tokenCountOut);
#else
    return NO;
#endif
}

- (BOOL)generateWithPrompt:(NSString *)prompt
                    params:(ChlorLlamaSamplingParams *)params
                   onToken:(ChlorTokenHandler)onToken
                shouldStop:(ChlorStopCheck)shouldStop
                     error:(NSError * _Nullable * _Nullable)error {
    std::lock_guard<std::mutex> lock(_mutex);

#if !CHLOR_HAS_LLAMA
    if (error) {
        *error = [NSError errorWithDomain:@"ChlorLlamaEngine"
                                     code:-200
                                 userInfo:@{NSLocalizedDescriptionKey: @"未链接 llama.xcframework"}];
    }
    return NO;
#else
    if (!_model || !_ctx) {
        if (error) {
            *error = [NSError errorWithDomain:@"ChlorLlamaEngine"
                                         code:-201
                                     userInfo:@{NSLocalizedDescriptionKey: @"尚未加载本地模型"}];
        }
        return NO;
    }

    chlor_clear_memory(_ctx);

    const llama_vocab *vocab = llama_model_get_vocab(_model);
    const std::string promptStr = prompt.UTF8String ? std::string(prompt.UTF8String) : std::string();

    // Tokenize prompt
    int32_t maxTokensNeeded = (int32_t)promptStr.size() + 128;
    std::vector<llama_token> tokens(maxTokensNeeded);
    int32_t nTokens = llama_tokenize(
        vocab,
        promptStr.c_str(),
        (int32_t)promptStr.size(),
        tokens.data(),
        maxTokensNeeded,
        true,
        true
    );
    if (nTokens < 0) {
        tokens.resize(-nTokens);
        nTokens = llama_tokenize(
            vocab,
            promptStr.c_str(),
            (int32_t)promptStr.size(),
            tokens.data(),
            (int32_t)tokens.size(),
            true,
            true
        );
    }
    if (nTokens <= 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ChlorLlamaEngine"
                                         code:-202
                                     userInfo:@{NSLocalizedDescriptionKey: @"Prompt 分词失败"}];
        }
        return NO;
    }
    tokens.resize(nTokens);

    // Truncate oldest tokens if prompt slightly exceeds context
    const int32_t maxPromptTokens = std::max<int32_t>(256, _contextLength - std::max<int32_t>(64, params.maxTokens));
    if ((int32_t)tokens.size() > maxPromptTokens) {
        tokens.erase(tokens.begin(), tokens.end() - maxPromptTokens);
    }

    // Build modular sampler chain
    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    llama_sampler *sampler = llama_sampler_chain_init(sparams);

    const int32_t nVocab = llama_vocab_n_tokens(vocab);
    if (params.repeatPenalty != 1.0f || params.frequencyPenalty != 0.0f || params.presencePenalty != 0.0f) {
        llama_sampler *pen = chlor_make_penalties(
            llama_sampler_init_penalties,
            nVocab,
            params.repeatLastN,
            params.repeatPenalty,
            params.frequencyPenalty,
            params.presencePenalty
        );
        if (pen) llama_sampler_chain_add(sampler, pen);
    }

    if (params.dryMultiplier > 0.0f) {
        static const char *defaultBreakers[] = {"\n", ":", "\"", "*", "。", "！", "？"};
        int32_t nCtxTrain = llama_model_n_ctx_train(_model);
        llama_sampler *dry = chlor_make_dry(
            llama_sampler_init_dry,
            vocab,
            nCtxTrain,
            params.dryMultiplier,
            params.dryBase,
            params.dryAllowedLength,
            params.dryPenaltyLastN,
            defaultBreakers,
            sizeof(defaultBreakers) / sizeof(defaultBreakers[0])
        );
        if (dry) llama_sampler_chain_add(sampler, dry);
    }

    if (params.topK > 0) {
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(params.topK));
    }
    if (params.topP > 0.0f && params.topP < 1.0f) {
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(params.topP, 1));
    }
    if (params.minP > 0.0f) {
        llama_sampler_chain_add(sampler, llama_sampler_init_min_p(params.minP, 1));
    }
    if (params.temperature <= 0.0f) {
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    } else {
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(params.temperature));
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    }

    // Chunked prefill
    const int32_t batchCap = 512;
    llama_batch batch = llama_batch_init(batchCap, 0, 1);

    int32_t nCur = 0;
    while (nCur < (int32_t)tokens.size()) {
        if (shouldStop && shouldStop()) {
            llama_batch_free(batch);
            llama_sampler_free(sampler);
            return YES;
        }
        batch.n_tokens = 0;
        int32_t chunkEnd = std::min<int32_t>((int32_t)tokens.size(), nCur + batchCap);
        for (int32_t i = nCur; i < chunkEnd; ++i) {
            bool needLogits = (i == (int32_t)tokens.size() - 1);
            chlor_batch_add(batch, tokens[i], i, 0, needLogits);
        }
        if (llama_decode(_ctx, batch) != 0) {
            llama_batch_free(batch);
            llama_sampler_free(sampler);
            if (error) {
                *error = [NSError errorWithDomain:@"ChlorLlamaEngine"
                                             code:-203
                                         userInfo:@{NSLocalizedDescriptionKey: @"Prefill 推理失败，请尝试缩小上下文长度"}];
            }
            return NO;
        }
        nCur = chunkEnd;
    }

    // Prepare stop sequences
    std::vector<std::string> stopSeqs;
    size_t maxStopLen = 0;
    for (NSString *s in params.stopSequences) {
        if (s.length > 0 && s.UTF8String) {
            std::string str(s.UTF8String);
            maxStopLen = std::max(maxStopLen, str.size());
            stopSeqs.push_back(std::move(str));
        }
    }

    // Generation loop
    auto tStart = std::chrono::steady_clock::now();
    int32_t generatedCount = 0;
    std::string pendingUTF8;
    std::string stopHoldback;
    const int32_t maxGen = std::max<int32_t>(16, params.maxTokens);

    auto emitCleanText = [&](const std::string &chunk) {
        if (chunk.empty() || !onToken) return;
        auto now = std::chrono::steady_clock::now();
        double elapsed = std::chrono::duration<double>(now - tStart).count();
        double tps = elapsed > 0.02 ? (double)generatedCount / elapsed : 0.0;
        NSString *nsChunk = [[NSString alloc] initWithBytes:chunk.data()
                                                     length:chunk.size()
                                                   encoding:NSUTF8StringEncoding];
        if (nsChunk && nsChunk.length > 0) {
            onToken(nsChunk, tps);
        }
    };

    for (int32_t step = 0; step < maxGen; ++step) {
        if (shouldStop && shouldStop()) break;
        if (nCur >= _contextLength - 2) break;

        llama_token newToken = llama_sampler_sample(sampler, _ctx, -1);
        llama_sampler_accept(sampler, newToken);

        if (llama_vocab_is_eog(vocab, newToken)) {
            break;
        }

        char pieceBuf[256];
        int32_t pieceLen = llama_token_to_piece(vocab, newToken, pieceBuf, sizeof(pieceBuf), 0, true);
        if (pieceLen < 0) {
            std::vector<char> largeBuf(-pieceLen + 1);
            pieceLen = llama_token_to_piece(vocab, newToken, largeBuf.data(), (int32_t)largeBuf.size(), 0, true);
            if (pieceLen > 0) pendingUTF8.append(largeBuf.data(), pieceLen);
        } else if (pieceLen > 0) {
            pendingUTF8.append(pieceBuf, pieceLen);
        }

        generatedCount += 1;

        // Flush only complete UTF-8 sequences into stopHoldback
        size_t tailIncomplete = incomplete_utf8_tail_length(pendingUTF8);
        if (pendingUTF8.size() > tailIncomplete) {
            size_t completeLen = pendingUTF8.size() - tailIncomplete;
            stopHoldback.append(pendingUTF8.data(), completeLen);
            pendingUTF8.erase(0, completeLen);
        }

        // Check stop sequences
        bool hitStop = false;
        for (const auto &stop : stopSeqs) {
            size_t pos = stopHoldback.find(stop);
            if (pos != std::string::npos) {
                emitCleanText(stopHoldback.substr(0, pos));
                stopHoldback.clear();
                hitStop = true;
                break;
            }
        }
        if (hitStop) break;

        // Emit safe prefix outside maxStopLen window
        if (stopHoldback.size() > maxStopLen) {
            size_t safeEmitLen = stopHoldback.size() - maxStopLen;
            // Ensure we do not cut inside a UTF-8 sequence
            size_t cutIncomplete = incomplete_utf8_tail_length(stopHoldback.substr(0, safeEmitLen));
            if (safeEmitLen > cutIncomplete) {
                size_t emitBytes = safeEmitLen - cutIncomplete;
                emitCleanText(stopHoldback.substr(0, emitBytes));
                stopHoldback.erase(0, emitBytes);
            }
        }

        batch.n_tokens = 0;
        chlor_batch_add(batch, newToken, nCur, 0, true);
        nCur += 1;

        if (llama_decode(_ctx, batch) != 0) {
            break;
        }
    }

    if (!stopHoldback.empty()) {
        emitCleanText(stopHoldback);
    }

    llama_batch_free(batch);
    llama_sampler_free(sampler);
    return YES;
#endif
}

@end
