# Local embedding JNI runtime

The Android runtime statically links the CPU backend of official
[llama.cpp b11763](https://github.com/ggml-org/llama.cpp/releases/tag/b11763),
commit `a01ce9ffc64cf370439d6f861a534a65100133ae`.
Source archive SHA256: `a3d34dba84adbe488c62fb53e0d7398f469d791e6640e88c463f9a23184d2222`.

llama.cpp and GGML are MIT licensed. The script copies the upstream MIT license
to the output directory; include it in application notices. The model has its
own license and is not covered by the runtime license. No model is committed
here. The fixed model candidate is `embeddinggemma-2-Q8_0.gguf` published by
`ggml-org/embeddinggemma-2-GGUF` at revision
`58faf90940886df2d62be555c8765d00dac362c5`, 309855456 bytes, SHA256
`2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135`.
Its pinned model card declares Apache-2.0 and Google embeddinggemma-2 as base;
the exact converter/base revisions used in conversion remain unspecified.
The previous user-supplied GGUF with SHA256 `6f1bd4ac6c5df7444f9cca7ca36cafe6cfa34cd6f49fefb1e0b4be8143aed8bc`
is a distinct artifact whose source was not established; it is not overwritten
or represented as the new pinned artifact. New inference acceptance must use the
new candidate's actual bytes. CI provisioning uses fixed official download URLs
in `prepare-model-assets.py`, with weight/config/card/license hash verification.

```sh
ANDROID_HOME=/Users/muyi/Library/Android/sdk \
MUYON_ML_OUTPUT=/private/tmp/muyon-ml-native-inputs \
MUYON_LLAMA_ARCHIVE=/private/tmp/muyon-llama-b11763.tar.gz \
sh apps/muyon_android/build-ml-native.sh
```

If the pinned archive is absent, `MUYON_ML_FETCH=1` explicitly enables its
download from official GitHub codeload. NDK 28.2.13676358 and SDK CMake 3.22.1
are required. Output is `jni/{arm64-v8a,x86_64}/libmuyon_local_embedding.so`,
with API 26, static C++ runtime, and 16 KiB ELF segment alignment. No GPU,
OpenMP, KleidiAI, llamafile, OpenSSL, server, or remote download path is built
into the application runtime.

`LocalEmbedding` serializes inference and close. UTF-8 text is tokenized by the
model's own Gemma4 tokenizer, with BOS/EOS enabled and special-token parsing
disabled for user text. The 512-token limit includes the retrieval prefix.
Long input raises an error instead of silently truncating. Document chunks
must therefore fit this limit. Query prefix is `task: search result | query: `;
document prefix is `title: none | text: `.

The graph applies the model's real output projection before mean pooling.
The bridge validates `llama_model_n_embd_out == 768`, reads the pooled sequence
vector, rejects invalid/zero norms, and L2 normalizes it. Internal hidden width
512 is not the output dimension. Each call clears previous sequence state.
Model file integrity must be verified by the model installer before opening.

Cross compilation establishes ABI compatibility only. Actual model loading,
finite 768-dimensional output, retrieval behavior, and resource use require
device instrumentation with the real model. Cancellation is cooperative
between calls; an already running native inference completes before close.
