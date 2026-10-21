#include <jni.h>
#include "llama.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {
constexpr int kDimension = 768;
constexpr int kContext = 512;
struct Engine {
    llama_model * model = nullptr;
    llama_context * context = nullptr;
    ~Engine() {
        if (context) llama_free(context);
        if (model) llama_model_free(model);
    }
};
std::once_flag backend_once;
void fail(JNIEnv * env, const char * message) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), message);
}
std::string bytes(JNIEnv * env, jbyteArray input) {
    if (!input) throw std::runtime_error("Missing embedding input");
    const auto length = env->GetArrayLength(input);
    if (length <= 0 || length > 65536) throw std::runtime_error("Embedding input size is unsupported");
    std::string result(static_cast<size_t>(length), '\0');
    env->GetByteArrayRegion(input, 0, length, reinterpret_cast<jbyte *>(result.data()));
    if (result.find('\0') != std::string::npos) throw std::runtime_error("Embedding input contains NUL");
    return result;
}
struct Batch {
    llama_batch value;
    explicit Batch(int count) : value(llama_batch_init(count, 0, 1)) {}
    ~Batch() { llama_batch_free(value); }
};
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_mightyoung_muyon_product_ml_LocalEmbedding_nativeOpen(JNIEnv * env, jobject, jbyteArray path) {
    try {
        const auto filename = bytes(env, path);
        std::call_once(backend_once, [] {
            // Model/runtime diagnostics must not log document text to logcat.
            llama_log_set([](ggml_log_level, const char *, void *) {}, nullptr);
            llama_backend_init();
        });
        auto engine = std::make_unique<Engine>();
        auto model_params = llama_model_default_params();
        model_params.n_gpu_layers = 0;
        model_params.use_extra_bufts = false;
        engine->model = llama_model_load_from_file(filename.c_str(), model_params);
        if (!engine->model) throw std::runtime_error("Local embedding model could not be loaded");
        char architecture[64] = {};
        llama_model_meta_val_str(engine->model, "general.architecture", architecture, sizeof(architecture));
        if (std::string(architecture) != "gemma-embedding2" || llama_model_n_embd_out(engine->model) != kDimension)
            throw std::runtime_error("Expected gemma-embedding2 with 768 output dimensions");
        auto params = llama_context_default_params();
        params.n_ctx = kContext;
        params.n_batch = kContext;
        params.n_ubatch = kContext;
        params.n_seq_max = 1;
        params.n_threads = static_cast<int32_t>(std::max(1u, std::min(4u, std::thread::hardware_concurrency())));
        params.n_threads_batch = params.n_threads;
        params.embeddings = true;
        params.pooling_type = LLAMA_POOLING_TYPE_MEAN;
        params.attention_type = LLAMA_ATTENTION_TYPE_NON_CAUSAL;
        params.offload_kqv = false;
        params.op_offload = false;
        engine->context = llama_init_from_model(engine->model, params);
        if (!engine->context) throw std::runtime_error("Local embedding context could not be initialized");
        return reinterpret_cast<jlong>(engine.release());
    } catch (const std::exception & error) { fail(env, error.what()); return 0; }
}

extern "C" JNIEXPORT jfloatArray JNICALL
Java_com_mightyoung_muyon_product_ml_LocalEmbedding_nativeEmbed(JNIEnv * env, jobject, jlong handle, jbyteArray input) {
    try {
        auto * engine = reinterpret_cast<Engine *>(handle);
        if (!engine) throw std::runtime_error("Local embedding is closed");
        const auto text = bytes(env, input);
        const auto * vocab = llama_model_get_vocab(engine->model);
        std::vector<llama_token> tokens(kContext);
        const int count = llama_tokenize(vocab, text.data(), static_cast<int32_t>(text.size()), tokens.data(), kContext, true, false);
        if (count < 0 || count > kContext) throw std::runtime_error("Embedding input exceeds 512 tokens including task prefix");
        if (count == 0) throw std::runtime_error("Embedding input has no tokens");
        if (auto memory = llama_get_memory(engine->context)) llama_memory_clear(memory, true);
        Batch batch(count);
        batch.value.n_tokens = count;
        for (int i = 0; i < count; ++i) {
            batch.value.token[i] = tokens[i];
            batch.value.pos[i] = i;
            batch.value.n_seq_id[i] = 1;
            batch.value.seq_id[i][0] = 0;
            batch.value.logits[i] = true;
        }
        const int status = llama_model_has_encoder(engine->model)
            ? llama_encode(engine->context, batch.value) : llama_decode(engine->context, batch.value);
        if (status != 0) throw std::runtime_error("Local embedding inference failed");
        const float * pooled = llama_get_embeddings_seq(engine->context, 0);
        if (!pooled) throw std::runtime_error("Local embedding pooling returned no vector");
        std::vector<float> result(kDimension);
        double squared_norm = 0;
        for (int i = 0; i < kDimension; ++i) {
            if (!std::isfinite(pooled[i])) throw std::runtime_error("Local embedding contains a non-finite value");
            squared_norm += static_cast<double>(pooled[i]) * pooled[i];
        }
        if (!std::isfinite(squared_norm) || squared_norm <= 1e-20) throw std::runtime_error("Local embedding has zero norm");
        const double norm = std::sqrt(squared_norm);
        for (int i = 0; i < kDimension; ++i) result[i] = static_cast<float>(pooled[i] / norm);
        auto output = env->NewFloatArray(kDimension);
        if (output) env->SetFloatArrayRegion(output, 0, kDimension, result.data());
        return output;
    } catch (const std::exception & error) { fail(env, error.what()); return nullptr; }
}

extern "C" JNIEXPORT void JNICALL
Java_com_mightyoung_muyon_product_ml_LocalEmbedding_nativeClose(JNIEnv *, jobject, jlong handle) {
    delete reinterpret_cast<Engine *>(handle);
}
