package com.example.signlanguage

import android.content.Context
import android.util.Log
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.nio.FloatBuffer
import java.nio.LongBuffer
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Korean sentence -> glosses (KoBART text2gloss) -> keypoints (Gloss2Pose).
 *
 * Mirrors onnx_sentence_to_gloss / onnx_gloss_to_pose from the export notebook.
 * Returns {glosses: List<String>, durations: IntArray, pose: FloatArray(frames*123*4), frames: Int}.
 */
class TextToSignChannel(private val context: Context, messenger: BinaryMessenger) {
    private val env = OrtEnvironment.getEnvironment()
    private val modelCache = File(context.cacheDir, "text2sign-onnx-v2")
    private var tokenizer: KobartTokenizer? = null
    private var glossToId: Map<String, Int>? = null
    private var g2pEncoder: OrtSession? = null
    private var g2pDecoder: OrtSession? = null

    init {
        MethodChannel(messenger, "com.example.signlanguage/text_to_sign",
            StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result ->
            if (call.method != "generate") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val sentence = requireNotNull(call.argument<String>("sentence")).trim()
                require(sentence.isNotEmpty()) { "Please enter a sentence." }
                val speed = call.argument<Double>("speed") ?: 1.0
                val started = System.nanoTime()

                val glosses = sentenceToGlosses(sentence)
                require(glosses.isNotEmpty()) { "No sign glosses were predicted for this sentence." }
                val (durations, pose) = glossesToPose(glosses, speed)

                Log.i(TAG, "sentence=$sentence glosses=${glosses.joinToString(" ")} " +
                    "frames=${durations.sum()} ms=${(System.nanoTime() - started) / 1_000_000}")
                result.success(mapOf(
                    "glosses" to glosses,
                    "durations" to durations,
                    "pose" to pose,
                    "frames" to durations.sum(),
                ))
            } catch (e: Throwable) { // includes OutOfMemoryError from the large KoBART files
                Log.e(TAG, "Text-to-sign failed", e)
                result.error("TEXT_TO_SIGN", e.message ?: e.toString(), null)
            }
        }
    }

    // ---------------------------------------------------------------- Stage A: sentence -> glosses
    private fun sentenceToGlosses(sentence: String): List<String> {
        val config = readJson("t2g_config.json")
        val tok = tokenizer ?: openAsset("t2g_tokenizer/tokenizer.json").bufferedReader()
            .use { KobartTokenizer(JSONObject(it.readText())) }.also { tokenizer = it }
        val startId = config.getLong("decoder_start_token_id")
        val eos = config.getLong("eos_token_id")
        val maxLength = config.optInt("max_length", 192)

        // Same as training: tokens without special tokens, then EOS appended.
        val inputIds = tok.encode(sentence).take(maxLength - 1) + eos

        // Prefers INT8 files if you add them later (smaller, faster); falls back to full precision.
        val encoderFile = cachedModel("t2g_encoder_int8.onnx", "t2g_encoder.onnx")
        val decoderFile = cachedModel("t2g_decoder_int8.onnx", "t2g_decoder.onnx")

        val generated = mutableListOf(startId)
        OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(4)
            // KoBART sessions are large, so they are opened per request and released afterwards.
            env.createSession(encoderFile.absolutePath, options).use { encoder ->
                env.createSession(decoderFile.absolutePath, options).use { decoder ->
                    longTensor(inputIds).use { input ->
                        longTensor(List(inputIds.size) { 1L }).use { mask ->
                            encoder.run(mapOf("input_ids" to input, "attention_mask" to mask)).use { encoded ->
                                val hidden = encoded.get("encoder_hidden_states").get() as OnnxTensor
                                for (step in 0 until MAX_GLOSS_TOKENS) {
                                    // A single-token decoder input is padded with a second start token;
                                    // position 0 is causal, so its logits are unaffected (same as Stage 2).
                                    val single = generated.size == 1
                                    val decoderIds = if (single) listOf(startId, startId) else generated.toList()
                                    val next = longTensor(decoderIds).use { decoderInput ->
                                        decoder.run(mapOf(
                                            "decoder_input_ids" to decoderInput,
                                            "encoder_hidden_states" to hidden,
                                            "encoder_attention_mask" to mask,
                                        )).use { decoded ->
                                            @Suppress("UNCHECKED_CAST")
                                            val values = decoded.get("logits").get().value as Array<Array<FloatArray>>
                                            argmax(values[0][if (single) 0 else decoderIds.lastIndex])
                                        }
                                    }
                                    if (next == eos) break
                                    generated.add(next)
                                }
                            }
                        }
                    }
                }
            }
        }

        val text = tok.decode(generated.drop(1))
        val vocab = vocabulary()
        return text.split(Regex("\\s+")).filter { it.isNotBlank() }.mapNotNull { snapToVocabulary(it, vocab) }
    }

    // ---------------------------------------------------------------- Stage B: glosses -> pose
    private fun glossesToPose(glosses: List<String>, speed: Double): Pair<IntArray, FloatArray> {
        val vocab = vocabulary()
        val minDuration = readJson("g2p_config.json").optInt("min_duration", 4)
        val encoder = g2pEncoder ?: env.createSession(cachedModel("g2p_encoder.onnx").absolutePath)
            .also { g2pEncoder = it }
        val decoder = g2pDecoder ?: env.createSession(cachedModel("g2p_decoder.onnx").absolutePath)
            .also { g2pDecoder = it }

        val ids = glosses.map { vocab.getValue(it).toLong() }
        longTensor(ids).use { glossIds ->
            encoder.run(mapOf("gloss_ids" to glossIds)).use { encoded ->
                val hidden = encoded.get("gloss_hidden").get() as OnnxTensor
                @Suppress("UNCHECKED_CAST")
                val logDuration = (encoded.get("log_duration").get().value as Array<FloatArray>)[0]

                // frames per gloss = round((exp(log_dur) - 1) * speed), at least min_duration
                val durations = IntArray(ids.size) { i ->
                    max(minDuration, ((exp(logDuration[i].toDouble()) - 1.0) * speed).roundToInt())
                }
                val requested = durations.sum()
                if (requested > MAX_FRAMES) { // keep very long sentences within memory limits
                    val scale = MAX_FRAMES.toDouble() / requested
                    for (i in durations.indices) durations[i] = max(minDuration, (durations[i] * scale).roundToInt())
                }
                val total = durations.sum()

                // Length regulation: which gloss each frame belongs to, and progress (0 -> 1) inside it.
                val frameGlossIndex = LongArray(total)
                val framePhase = FloatArray(total)
                var t = 0
                for (i in durations.indices) {
                    val d = durations[i]
                    for (k in 0 until d) {
                        frameGlossIndex[t] = i.toLong()
                        framePhase[t] = k.toFloat() / d
                        t++
                    }
                }

                OnnxTensor.createTensor(env, LongBuffer.wrap(frameGlossIndex), longArrayOf(1, total.toLong())).use { index ->
                    OnnxTensor.createTensor(env, FloatBuffer.wrap(framePhase), longArrayOf(1, total.toLong(), 1)).use { phase ->
                        decoder.run(mapOf(
                            "gloss_hidden" to hidden,
                            "frame_gloss_index" to index,
                            "frame_phase" to phase,
                        )).use { decoded ->
                            val buffer = (decoded.get("pose").get() as OnnxTensor).floatBuffer
                            val pose = FloatArray(buffer.remaining())
                            buffer.get(pose)
                            check(pose.size == total * POSE_DIM) { "Unexpected pose size ${pose.size}" }
                            return durations to pose
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- helpers
    private fun vocabulary(): Map<String, Int> = glossToId ?: readJson("gloss_to_id.json").let { json ->
        json.keys().asSequence().associateWith { json.getInt(it) }
    }.also { glossToId = it }

    /** Same idea as the notebook's snap_to_vocab: keep real glosses, map near-misses to the closest one. */
    private fun snapToVocabulary(word: String, vocab: Map<String, Int>): String? {
        if (word != BACKGROUND && vocab.containsKey(word)) return word
        var best: String? = null
        var bestScore = SNAP_CUTOFF
        for (gloss in vocab.keys) {
            if (gloss == BACKGROUND) continue
            val score = similarity(word, gloss)
            if (score > bestScore) { bestScore = score; best = gloss }
        }
        return best
    }

    private fun similarity(a: String, b: String): Double {
        if (a.isEmpty() && b.isEmpty()) return 1.0
        var previous = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            val current = IntArray(b.length + 1)
            current[0] = i
            for (j in 1..b.length) {
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                current[j] = min(min(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + cost)
            }
            previous = current
        }
        return 1.0 - previous[b.length].toDouble() / max(a.length, b.length)
    }

    private fun argmax(values: FloatArray): Long {
        var best = 0
        for (i in 1 until values.size) if (values[i] > values[best]) best = i
        return best.toLong()
    }

    private fun longTensor(ids: List<Long>) =
        OnnxTensor.createTensor(env, LongBuffer.wrap(ids.toLongArray()), longArrayOf(1, ids.size.toLong()))

    private fun openAsset(name: String) = context.assets.open(ASSET_DIR + name)

    private fun readJson(name: String) = openAsset(name).bufferedReader().use { JSONObject(it.readText()) }

    private fun assetExists(name: String) = try {
        openAsset(name).close(); true
    } catch (e: IOException) {
        false
    }

    /** ONNX Runtime needs a real file path, so each model is copied out of the APK once. */
    private fun cachedModel(vararg candidates: String): File {
        val name = candidates.firstOrNull { assetExists(it) }
            ?: error("Model asset not found: ${candidates.joinToString(" or ")}. Check pubspec.yaml.")
        modelCache.mkdirs()
        val target = File(modelCache, name)
        if (!target.exists()) {
            val temporary = File(modelCache, "$name.partial")
            openAsset(name).use { input -> temporary.outputStream().use { input.copyTo(it) } }
            check(temporary.renameTo(target)) { "Unable to cache $name" }
        }
        return target
    }

    companion object {
        private const val TAG = "KSL_TEXT2SIGN"
        private const val ASSET_DIR = "flutter_assets/saved_models/TextToSignLanguage/"
        private const val BACKGROUND = "<background>"
        private const val SNAP_CUTOFF = 0.6
        private const val MAX_GLOSS_TOKENS = 128
        private const val MAX_FRAMES = 1800 // 60 s at 30 fps
        private const val POSE_DIM = 123 * 4
    }
}
