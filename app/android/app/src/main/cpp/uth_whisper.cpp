// Writing the words on Android: the thin native side of WhisperEngine.kt (docs/android-plan.md 3.5,
// tasks 8 to 10). whisper.cpp (MIT, github.com/ggml-org/whisper.cpp) linked statically into one
// library per ABI by tool/android_whisper.sh; nothing here touches the network or any file but the
// two models it is given.
//
// The app, not whisper.cpp, decides what Whisper hears: the recording is decoded in Kotlin,
// brought to 16 kHz here (resample), cut at its silences by the Silero model (speech), and each
// stretch of speech is handed to Whisper on its own (transcribe) with nothing carried over from
// the stretch before. whisper.cpp's own --vad joins the stretches back together and reads them in
// 30-second windows; measured on a real voice that dropped whole passages (android-plan.md 3.5).
#include <jni.h>
#include <android/log.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <exception>
#include <string>
#include <vector>

#include "whisper.h"

#define TAG "whisper"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

static void quiet_log(enum ggml_log_level level, const char * text, void *) {
    if (level >= GGML_LOG_LEVEL_WARN && text) __android_log_print(ANDROID_LOG_WARN, TAG, "%s", text);
}

static std::atomic<bool> g_abort{false};
static bool aborted(void *) { return g_abort.load(); }

namespace {
struct UtfChars {
    JNIEnv * env;
    jstring jstr;
    const char * ptr;
    UtfChars(JNIEnv * e, jstring s) : env(e), jstr(s), ptr(s ? e->GetStringUTFChars(s, nullptr) : nullptr) {}
    ~UtfChars() { if (ptr) env->ReleaseStringUTFChars(jstr, ptr); }
    UtfChars(const UtfChars &) = delete;
    UtfChars & operator=(const UtfChars &) = delete;
};

struct VadCtxGuard {
    whisper_vad_context * ctx;
    ~VadCtxGuard() { if (ctx) whisper_vad_free(ctx); }
};

struct VadSegsGuard {
    whisper_vad_segments * segs;
    ~VadSegsGuard() { if (segs) whisper_vad_free_segments(segs); }
};
} // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_dev_summitstudio_uponthyhead_WhisperNative_load(JNIEnv * env, jclass, jstring jpath) {
    try {
        if (!jpath) return 0;
        whisper_log_set(quiet_log, nullptr);
        UtfChars path(env, jpath);
        if (!path.ptr) return 0;
        whisper_context_params cp = whisper_context_default_params();
        cp.use_gpu = false;
        cp.flash_attn = false;
        whisper_context * ctx = whisper_init_from_file_with_params(path.ptr, cp);
        if (!ctx) LOGE("the model could not be loaded");
        return (jlong) ctx;
    } catch (const std::exception & e) {
        LOGE("load exception: %s", e.what());
        return 0;
    } catch (...) {
        LOGE("load unknown exception");
        return 0;
    }
}

JNIEXPORT void JNICALL
Java_dev_summitstudio_uponthyhead_WhisperNative_free(JNIEnv *, jclass, jlong ctx) {
    try {
        if (ctx) whisper_free((whisper_context *) ctx);
    } catch (const std::exception & e) {
        LOGE("free exception: %s", e.what());
    } catch (...) {
        LOGE("free unknown exception");
    }
}

JNIEXPORT void JNICALL
Java_dev_summitstudio_uponthyhead_WhisperNative_abort(JNIEnv *, jclass, jboolean on) {
    g_abort.store(on != JNI_FALSE);
}

// 16-bit samples at [rate] to 16 kHz floats in [-1, 1]: a windowed-sinc low-pass at 7.2 kHz (a
// Blackman window), so the change of rate adds nothing Whisper could hear. The kernel is worked
// out once for 256 positions between input samples (the app records at 32 kHz, where only one is
// ever needed) and each output is one short dot product.
JNIEXPORT jfloatArray JNICALL
Java_dev_summitstudio_uponthyhead_WhisperNative_resample(JNIEnv * env, jclass, jshortArray jin, jint rate) {
    try {
        if (!jin || rate <= 0) return nullptr;
        const jsize n = env->GetArrayLength(jin);
        if (n < 0) return nullptr;
        if (n == 0) return env->NewFloatArray(0);
        std::vector<jshort> in((size_t) n);
        env->GetShortArrayRegion(jin, 0, n, in.data());
        const double ratio = (double) rate / 16000.0;
        const jsize m = (jsize) std::floor(n / ratio);
        if (m <= 0) return env->NewFloatArray(0);
        std::vector<float> out((size_t) m);
        if (rate == 16000) {
            for (jsize i = 0; i < m; i++) out[(size_t) i] = in[(size_t) i] / 32768.0f;
        } else {
            const double cutoff = std::min(7200.0, 0.45 * (double) rate) / (double) rate; // below Nyquist for every input rate
            const int reach = (int) std::ceil(16 * (ratio > 1 ? ratio : 1.0)); // input samples each side
            const int taps = 2 * reach, phases = 256;
            std::vector<float> table((size_t) phases * taps);
            for (int ph = 0; ph < phases; ph++) {
                const double frac = (double) ph / phases;
                double sum = 0;
                for (int t = 0; t < taps; t++) {
                    const double x = (t - reach + 1) - frac; // tap position relative to the output point
                    const double a = 2 * M_PI * cutoff * x;
                    const double sinc = x == 0 ? 1.0 : std::sin(a) / a;
                    const double u = (x + reach) / (2.0 * reach);
                    const double w = (u <= 0 || u >= 1) ? 0 : 0.42 - 0.5 * std::cos(2 * M_PI * u) + 0.08 * std::cos(4 * M_PI * u);
                    table[(size_t) ph * taps + t] = (float) (sinc * w);
                    sum += sinc * w;
                }
                if (sum != 0.0) {
                    for (int t = 0; t < taps; t++) table[(size_t) ph * taps + t] /= (float) sum;
                }
            }
            for (jsize i = 0; i < m; i++) {
                const double c = i * ratio;
                const long base = (long) std::floor(c);
                const int ph = (int) ((c - base) * phases) % phases;
                const float * h = &table[(size_t) ph * taps];
                const long k0 = base - reach + 1;
                float acc = 0;
                if (k0 >= 0 && k0 + taps <= n) {
                    for (int t = 0; t < taps; t++) acc += h[t] * in[(size_t) (k0 + t)];
                } else {
                    for (int t = 0; t < taps; t++) {
                        const long k = k0 + t;
                        if (k >= 0 && k < n) acc += h[t] * in[(size_t) k];
                    }
                }
                out[(size_t) i] = acc / 32768.0f;
            }
        }
        jfloatArray r = env->NewFloatArray(m);
        if (!r) return nullptr;
        env->SetFloatArrayRegion(r, 0, m, out.data());
        return r;
    } catch (const std::exception & e) {
        LOGE("resample exception: %s", e.what());
        return nullptr;
    } catch (...) {
        LOGE("resample unknown exception");
        return nullptr;
    }
}

// The stretches of speech in [pcm] (16 kHz), as [start0, end0, start1, end1, …] in seconds,
// unpadded: the Silero model with whisper.cpp's defaults (threshold 0.5, at least 250 ms of speech,
// a stretch ends after 100 ms of silence, padded 30 ms), as whisper-vad-speech-segments gives them.
// Null when the model cannot be loaded.
JNIEXPORT jfloatArray JNICALL
Java_dev_summitstudio_uponthyhead_WhisperNative_speech(JNIEnv * env, jclass, jstring jvad, jfloatArray jpcm, jint threads) {
    try {
        if (!jvad || !jpcm) return nullptr;
        const jsize n = env->GetArrayLength(jpcm);
        if (n < 0) return nullptr;
        whisper_log_set(quiet_log, nullptr);
        UtfChars vpath(env, jvad);
        if (!vpath.ptr) return nullptr;
        whisper_vad_context_params cp = whisper_vad_default_context_params();
        cp.n_threads = threads > 0 ? threads : 1;
        cp.use_gpu = false;
        VadCtxGuard vctx{whisper_vad_init_from_file_with_params(vpath.ptr, cp)};
        if (!vctx.ctx) { LOGE("the silence model could not be loaded"); return nullptr; }
        std::vector<float> out;
        if (n > 0) {
            std::vector<float> pcm((size_t) n);
            env->GetFloatArrayRegion(jpcm, 0, n, pcm.data());
            whisper_vad_params vp = whisper_vad_default_params();
            VadSegsGuard segs{whisper_vad_segments_from_samples(vctx.ctx, vp, pcm.data(), n)};
            if (segs.segs) {
                const int k = whisper_vad_segments_n_segments(segs.segs);
                out.reserve((size_t) std::max(0, k) * 2);
                for (int i = 0; i < k; i++) {
                    // whisper.cpp reports these in hundredths of a second
                    out.push_back(whisper_vad_segments_get_segment_t0(segs.segs, i) / 100.0f);
                    out.push_back(whisper_vad_segments_get_segment_t1(segs.segs, i) / 100.0f);
                }
            }
        }
        jfloatArray r = env->NewFloatArray((jsize) out.size());
        if (!r) return nullptr;
        if (!out.empty()) env->SetFloatArrayRegion(r, 0, (jsize) out.size(), out.data());
        return r;
    } catch (const std::exception & e) {
        LOGE("speech exception: %s", e.what());
        return nullptr;
    } catch (...) {
        LOGE("speech unknown exception");
        return nullptr;
    }
}

// One stretch of speech to words, alone: no prompt, nothing from any stretch before
// (whisper-cli -mc 0). [temperature] 0 is Whisper's usual greedy reading with its own fallback;
// above 0, one sampled reading at that temperature, for a stretch whose first reading repeated
// itself. Returns the text as UTF-8 bytes (Whisper's bytes are not always the "modified UTF-8" a
// Java string from C must be), with the highest no-speech probability of its segments in
// [jnsp][0]; null on a failure.
JNIEXPORT jbyteArray JNICALL
Java_dev_summitstudio_uponthyhead_WhisperNative_transcribe(JNIEnv * env, jclass, jlong jctx, jfloatArray jpcm, jstring jlang,
                                                         jint threads, jfloat temperature, jfloatArray jnsp) {
    try {
        auto * ctx = (whisper_context *) jctx;
        if (!ctx || !jpcm || !jlang) return nullptr;
        const jsize n = env->GetArrayLength(jpcm);
        if (n < 0) return nullptr;
        if (n == 0) return env->NewByteArray(0);
        std::vector<float> pcm((size_t) n);
        env->GetFloatArrayRegion(jpcm, 0, n, pcm.data());
        std::string language;
        {
            UtfChars lang(env, jlang);
            if (!lang.ptr) return nullptr;
            language.assign(lang.ptr);
        }

        // As measured (docs/android-plan.md 3.5, whisper-cli's defaults): beam search of 5, falling
        // back to higher temperatures if a reading fails Whisper's own checks. Greedy reading was
        // measured too and is clearly worse in Spanish (es_varied, the app's own AAC: 10.3 wrong per
        // hundred greedy, 5.6 with the beam). A second reading after a repeat ([temperature] > 0) is
        // sampled: five tries at that temperature, the best kept.
        whisper_full_params p = whisper_full_default_params(temperature > 0 ? WHISPER_SAMPLING_GREEDY : WHISPER_SAMPLING_BEAM_SEARCH);
        if (temperature <= 0) p.beam_search.beam_size = 5;
        p.n_threads = threads > 0 ? threads : 1;
        p.language = language.c_str();
        p.translate = false;
        p.no_context = true;
        p.n_max_text_ctx = 0; // -mc 0: nothing carried from one 30 s window to the next either
        p.print_progress = false;
        p.print_realtime = false;
        p.print_special = false;
        p.print_timestamps = false;
        p.no_timestamps = true; // -nt, as measured
        if (temperature > 0) {
            p.temperature = temperature;
            p.temperature_inc = 0; // one reading only
            p.greedy.best_of = 5;
        }
        p.abort_callback = [](void * ud) { return aborted(ud); };
        p.abort_callback_user_data = nullptr;

        if (whisper_full(ctx, p, pcm.data(), n) != 0) { LOGE("whisper_full failed"); return nullptr; }
        std::string text;
        float nsp = 0;
        const int k = whisper_full_n_segments(ctx);
        for (int i = 0; i < k; i++) {
            const char * seg = whisper_full_get_segment_text(ctx, i);
            if (seg) text += seg;
            const float s = whisper_full_get_segment_no_speech_prob(ctx, i);
            if (s > nsp) nsp = s;
        }
        if (jnsp && env->GetArrayLength(jnsp) > 0) env->SetFloatArrayRegion(jnsp, 0, 1, &nsp);
        jbyteArray r = env->NewByteArray((jsize) text.size());
        if (!r) return nullptr;
        if (!text.empty()) env->SetByteArrayRegion(r, 0, (jsize) text.size(), (const jbyte *) text.data());
        return r;
    } catch (const std::exception & e) {
        LOGE("transcribe exception: %s", e.what());
        return nullptr;
    } catch (...) {
        LOGE("transcribe unknown exception");
        return nullptr;
    }
}

JNIEXPORT jstring JNICALL
Java_dev_summitstudio_uponthyhead_WhisperNative_info(JNIEnv * env, jclass) {
    try {
        const char * s = whisper_print_system_info();
        return env->NewStringUTF(s ? s : "");
    } catch (const std::exception & e) {
        LOGE("info exception: %s", e.what());
        return env->NewStringUTF("");
    } catch (...) {
        LOGE("info unknown exception");
        return env->NewStringUTF("");
    }
}

} // extern "C"
