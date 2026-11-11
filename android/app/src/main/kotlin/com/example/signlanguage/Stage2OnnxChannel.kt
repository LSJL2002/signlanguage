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
import java.nio.LongBuffer

/** CPU generation matching generate_korean_sentence in the Python reference. */
class Stage2OnnxChannel(context: Context, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "com.example.signlanguage/stage2_onnx",
            StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result ->
            if (call.method != "translate") {
                result.notImplemented()
            } else {
                try {
                    val gloss = requireNotNull(call.argument<String>("gloss")).trim()
                    require(gloss.isNotEmpty()) { "No glosses recognized; translation was not run." }
                    fun asset(name: String) = context.assets.open("flutter_assets/saved_models/" + name)
                    val config = asset("kobart_config.json").bufferedReader().use { JSONObject(it.readText()) }
                    val tokenizer = asset("kobart_tokenizer.json").bufferedReader().use { KobartTokenizer(JSONObject(it.readText())) }
                    val directory = File(context.cacheDir, "kobart-onnx").apply { mkdirs() }
                    for (name in listOf("encoder_model.onnx", "encoder_model.onnx.data", "decoder_model_quantized.onnx")) {
                        val target = File(directory, name)
                        // The package is fixed; copy once, publishing only a complete file.
                        if (!target.exists()) {
                            val temporary = File(directory, name + ".partial")
                            asset(name).use { input -> temporary.outputStream().use { input.copyTo(it) } }
                            check(temporary.renameTo(target)) { "Unable to cache " + name }
                        }
                    }
                    val env = OrtEnvironment.getEnvironment()
                    val inputIds = listOf(config.getLong("bos_token_id")) + tokenizer.encode(gloss) + config.getLong("eos_token_id")
                    require(inputIds.size <= config.getInt("max_position_embeddings")) { "Gloss sequence exceeds KoBART input limit." }
                    val startId = config.getLong("decoder_start_token_id")
                    val eos = config.getLong("eos_token_id")
                    fun tensor(ids: List<Long>) = OnnxTensor.createTensor(env, LongBuffer.wrap(ids.toLongArray()), longArrayOf(1, ids.size.toLong()))
                    val started = System.nanoTime()
                    OrtSession.SessionOptions().use { options ->
                        options.setIntraOpNumThreads(2)
                        env.createSession(File(directory, "encoder_model.onnx").absolutePath, options).use { encoder ->
                            env.createSession(File(directory, "decoder_model_quantized.onnx").absolutePath, options).use { decoder ->
                                tensor(inputIds).use { input ->
                                    tensor(List(inputIds.size) { 1L }).use { mask ->
                                        encoder.run(mapOf("input_ids" to input, "attention_mask" to mask)).use { encoded ->
                                            val hidden = encoded.get("last_hidden_state").get() as OnnxTensor
                                            val generated = mutableListOf(startId)
                                            for (step in 0 until 47) {
                                                val decoderIds = if (generated.size == 1) listOf(startId, startId) else generated.toList()
                                                tensor(decoderIds).use { decoderInput ->
                                                    decoder.run(mapOf("decoder_input_ids" to decoderInput,
                                                        "encoder_hidden_states" to hidden, "encoder_attention_mask" to mask)).use { decoded ->
                                                        @Suppress("UNCHECKED_CAST")
                                                        val values = decoded.get("logits").get().value as Array<Array<FloatArray>>
                                                        val logits = values[0][if (generated.size == 1) 0 else decoderIds.lastIndex].copyOf()
                                                        check(logits.all { it.isFinite() }) { "Non-finite KoBART logits" }
                                                        for (id in generated.drop(1).toSet()) {
                                                            val i = id.toInt()
                                                            logits[i] = if (logits[i] < 0) (logits[i] * 1.3).toFloat() else (logits[i] / 1.3).toFloat()
                                                        }
                                                        if (generated.size >= 2) {
                                                            for (i in 0 until generated.size - 2) {
                                                                if (generated[i] == generated[generated.size - 2] && generated[i + 1] == generated.last()) {
                                                                    logits[generated[i + 2].toInt()] = Float.NEGATIVE_INFINITY
                                                                }
                                                            }
                                                        }
                                                        var best = 0
                                                        for (i in 1 until logits.size) if (logits[i] > logits[best]) best = i
                                                        generated.add(best.toLong())
                                                    }
                                                }
                                                if (generated.last() == eos) break
                                            }
                                            val sentence = tokenizer.decode(generated.drop(1))
                                            check(sentence.isNotBlank()) { "KoBART returned no Korean sentence. Please try another video." }
                                            Log.i("KSL_STAGE2", "inputTokens=" + inputIds.size + " outputTokens=" + (generated.size - 1) + " ms=" + ((System.nanoTime() - started) / 1_000_000) + " sentence=" + sentence)
                                            result.success(sentence)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e("KSL_STAGE2", "Translation failed", e)
                    result.error("STAGE2_ONNX", e.message, null)
                }
            }
        }
    }
}
