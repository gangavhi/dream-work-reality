// GGUF / llama.cpp disabled on Apple-native pipeline (NaturalLanguage + Create ML).
// Symbols remain for Rust linkage; calls return a clear error instead of loading weights.

#include <stdint.h>
#include <string.h>

static void copyCString(const char *src, char *dst, uintptr_t dstLen) {
    if (dst == nullptr || dstLen == 0) {
        return;
    }
    if (src == nullptr) {
        dst[0] = '\0';
        return;
    }
    strncpy(dst, src, dstLen - 1);
    dst[dstLen - 1] = '\0';
}

extern "C" void dreamwork_llama_release_cached_model(void) {}

extern "C" int32_t dreamwork_llama_generate_json(
    const char *modelPath,
    const char *userPrompt,
    uint32_t maxTokens,
    char *out,
    uintptr_t outLen,
    char *err,
    uintptr_t errLen
) {
    (void)modelPath;
    (void)userPrompt;
    (void)maxTokens;
    if (out != nullptr && outLen > 0) {
        out[0] = '\0';
    }
    copyCString("llama_disabled:apple_native_pipeline", err, errLen);
    return -1;
}
