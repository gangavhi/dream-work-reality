#import <Foundation/Foundation.h>

#import <llama/llama.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

constexpr int32_t kOk = 0;
constexpr int32_t kInvalidArgument = 1;
constexpr int32_t kModelLoadFailed = 2;
constexpr int32_t kContextCreateFailed = 3;
constexpr int32_t kTokenizeFailed = 4;
constexpr int32_t kDecodeFailed = 5;
constexpr int32_t kSamplerFailed = 6;
constexpr int32_t kNoJsonObject = 7;
constexpr int32_t kPromptTooLong = 8;

constexpr uint32_t kContextTokens = 512;
constexpr uint32_t kReservedGenerationTokens = 96;

std::mutex gLlamaMutex;
bool gBackendInitialized = false;
llama_model *gCachedModel = nullptr;
std::string gCachedModelPath;

void copyCString(const std::string &value, char *buffer, uintptr_t bufferLen) {
    if (buffer == nullptr || bufferLen == 0) {
        return;
    }
    const size_t n = std::min(value.size(), static_cast<size_t>(bufferLen - 1));
    std::memcpy(buffer, value.data(), n);
    buffer[n] = '\0';
}

std::string tokenToPiece(const llama_vocab *vocab, llama_token token) {
    char small[256];
    int32_t n = llama_token_to_piece(vocab, token, small, sizeof(small), 0, true);
    if (n >= 0 && n < static_cast<int32_t>(sizeof(small))) {
        return std::string(small, static_cast<size_t>(n));
    }
    if (n < 0) {
        n = -n;
    }
    if (n <= 0) {
        return "";
    }
    std::vector<char> large(static_cast<size_t>(n) + 1);
    n = llama_token_to_piece(vocab, token, large.data(), static_cast<int32_t>(large.size()), 0, true);
    if (n <= 0) {
        return "";
    }
    return std::string(large.data(), static_cast<size_t>(n));
}

std::string firstBalancedJsonObject(const std::string &text) {
    size_t start = std::string::npos;
    int depth = 0;
    bool inString = false;
    bool escaped = false;

    for (size_t i = 0; i < text.size(); ++i) {
        const char c = text[i];
        if (start == std::string::npos) {
            if (c == '{') {
                start = i;
                depth = 1;
            }
            continue;
        }

        if (escaped) {
            escaped = false;
            continue;
        }
        if (c == '\\' && inString) {
            escaped = true;
            continue;
        }
        if (c == '"') {
            inString = !inString;
            continue;
        }
        if (inString) {
            continue;
        }
        if (c == '{') {
            depth += 1;
        } else if (c == '}') {
            depth -= 1;
            if (depth == 0) {
                return text.substr(start, i - start + 1);
            }
        }
    }
    return "";
}

std::string buildPrompt(const char *userPrompt) {
    return std::string(
               "<|im_start|>system\n"
               "You are an offline local ML JSON inference engine. "
               "Return one compact JSON object only. No markdown. No prose. "
               "Follow the exact JSON shape requested by the user prompt. "
               "Only include facts directly supported by the provided local input.\n"
               "<|im_end|>\n"
               "<|im_start|>user\n") +
           userPrompt +
           "\n<|im_end|>\n"
           "<|im_start|>assistant\n";
}

int32_t ensureModel(const char *modelPath, char *err, uintptr_t errLen) {
    if (!gBackendInitialized) {
        llama_backend_init();
        gBackendInitialized = true;
    }

    const std::string path(modelPath);
    if (gCachedModel != nullptr && gCachedModelPath == path) {
        return kOk;
    }

    if (gCachedModel != nullptr) {
        llama_model_free(gCachedModel);
        gCachedModel = nullptr;
        gCachedModelPath.clear();
    }

    llama_model_params modelParams = llama_model_default_params();
    // CPU-only inference avoids Metal allocator spikes that jetsam TestFlight builds.
    modelParams.n_gpu_layers = 0;
    modelParams.use_mmap = true;
    modelParams.use_mlock = false;

    gCachedModel = llama_model_load_from_file(modelPath, modelParams);
    if (gCachedModel == nullptr) {
        copyCString("llama_model_load_from_file returned null", err, errLen);
        return kModelLoadFailed;
    }

    gCachedModelPath = path;
    return kOk;
}

void releaseCachedModelLocked() {
    if (gCachedModel != nullptr) {
        llama_model_free(gCachedModel);
        gCachedModel = nullptr;
        gCachedModelPath.clear();
    }
}

} // namespace

extern "C" void dreamwork_llama_release_cached_model(void) {
    std::lock_guard<std::mutex> lock(gLlamaMutex);
    releaseCachedModelLocked();
}

extern "C" int32_t dreamwork_llama_generate_json(
    const char *modelPath,
    const char *userPrompt,
    uint32_t maxTokens,
    char *out,
    uintptr_t outLen,
    char *err,
    uintptr_t errLen
) {
    @autoreleasepool {
    if (modelPath == nullptr || userPrompt == nullptr || out == nullptr || outLen == 0) {
        copyCString("invalid llama generation arguments", err, errLen);
        return kInvalidArgument;
    }

    std::lock_guard<std::mutex> lock(gLlamaMutex);

    const int32_t modelStatus = ensureModel(modelPath, err, errLen);
    if (modelStatus != kOk) {
        return modelStatus;
    }

    struct ReleaseModelAfterCall {
        ~ReleaseModelAfterCall() { releaseCachedModelLocked(); }
    } releaseAfterCall;

    llama_context_params ctxParams = llama_context_default_params();
    ctxParams.n_ctx = kContextTokens;
    ctxParams.n_batch = 32;
    ctxParams.n_ubatch = 32;
    ctxParams.n_threads = 1;
    ctxParams.n_threads_batch = 1;
    ctxParams.offload_kqv = false;
    ctxParams.no_perf = true;

    llama_context *ctx = llama_init_from_model(gCachedModel, ctxParams);
    if (ctx == nullptr) {
        copyCString("llama_init_from_model returned null", err, errLen);
        return kContextCreateFailed;
    }

    const llama_vocab *vocab = llama_model_get_vocab(gCachedModel);
    const std::string prompt = buildPrompt(userPrompt);

    int32_t nPrompt = llama_tokenize(
        vocab,
        prompt.c_str(),
        static_cast<int32_t>(prompt.size()),
        nullptr,
        0,
        true,
        true
    );
    if (nPrompt < 0) {
        nPrompt = -nPrompt;
    }
    if (nPrompt <= 0) {
        llama_free(ctx);
        copyCString("llama_tokenize could not size prompt tokens", err, errLen);
        return kTokenizeFailed;
    }

    std::vector<llama_token> promptTokens(static_cast<size_t>(nPrompt));
    nPrompt = llama_tokenize(
        vocab,
        prompt.c_str(),
        static_cast<int32_t>(prompt.size()),
        promptTokens.data(),
        static_cast<int32_t>(promptTokens.size()),
        true,
        true
    );
    if (nPrompt <= 0) {
        llama_free(ctx);
        copyCString("llama_tokenize failed", err, errLen);
        return kTokenizeFailed;
    }
    promptTokens.resize(static_cast<size_t>(nPrompt));

    const uint32_t generationBudget =
        std::max<uint32_t>(1, std::min<uint32_t>(maxTokens, kContextTokens - kReservedGenerationTokens));
    if (static_cast<uint32_t>(nPrompt) + generationBudget > kContextTokens) {
        llama_free(ctx);
        copyCString("prompt exceeds llama context budget", err, errLen);
        return kPromptTooLong;
    }

    llama_batch batch = llama_batch_get_one(promptTokens.data(), nPrompt);
    if (llama_decode(ctx, batch) != 0) {
        llama_free(ctx);
        copyCString("llama_decode failed for prompt", err, errLen);
        return kDecodeFailed;
    }

    llama_sampler_chain_params samplerParams = llama_sampler_chain_default_params();
    samplerParams.no_perf = true;
    llama_sampler *sampler = llama_sampler_chain_init(samplerParams);
    if (sampler == nullptr) {
        llama_free(ctx);
        copyCString("llama_sampler_chain_init returned null", err, errLen);
        return kSamplerFailed;
    }

    // Grammar-constrained sampling allocates large auxiliary tables and can jetsam on device.
    llama_sampler_chain_add(sampler, llama_sampler_init_greedy());

    std::string generated;
    const uint32_t limit = generationBudget;
    for (uint32_t i = 0; i < limit; ++i) {
        const llama_token token = llama_sampler_sample(sampler, ctx, -1);
        if (llama_vocab_is_eog(vocab, token)) {
            break;
        }

        llama_sampler_accept(sampler, token);
        generated += tokenToPiece(vocab, token);

        const std::string json = firstBalancedJsonObject(generated);
        if (!json.empty()) {
            copyCString(json, out, outLen);
            llama_sampler_free(sampler);
            llama_free(ctx);
            return kOk;
        }

        llama_token next = token;
        llama_batch nextBatch = llama_batch_get_one(&next, 1);
        if (llama_decode(ctx, nextBatch) != 0) {
            llama_sampler_free(sampler);
            llama_free(ctx);
            copyCString("llama_decode failed during generation", err, errLen);
            return kDecodeFailed;
        }
    }

    llama_sampler_free(sampler);
    llama_free(ctx);

    const std::string json = firstBalancedJsonObject(generated);
    if (json.empty()) {
        copyCString("generation completed without a balanced JSON object", err, errLen);
        return kNoJsonObject;
    }

    copyCString(json, out, outLen);
    return kOk;
    }
}
