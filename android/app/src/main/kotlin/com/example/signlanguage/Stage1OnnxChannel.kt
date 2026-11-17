package com.example.signlanguage

import android.content.Context
import android.util.Log
import ai.onnxruntime.OnnxJavaType
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Isolated CPU Stage 1 inference; no camera state or Stage 2 dependencies. */
class Stage1OnnxChannel(context: Context, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "com.example.signlanguage/stage1_onnx",
            StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue())
            .setMethodCallHandler { call, result ->
                if (call.method != "infer") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                var directory: File? = null
                try {
                    val frames = requireNotNull(call.argument<Int>("frames"))
                    val classes = requireNotNull(call.argument<Int>("classes"))
                    val bytes = requireNotNull(call.argument<ByteArray>("features"))
                    require(frames in 1..3000 && classes > 0)
                    require(bytes.size == frames * 492 * 4)
                    val floats = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
                    for (i in 0 until floats.limit()) require(floats.get(i).isFinite())
                    // Keep any external data beside the ONNX file. Source assets are read-only.
                    directory = File.createTempFile("stage1-", "", context.cacheDir).apply {
                        check(delete()); check(mkdir())
                    }
                    for (name in listOf("stage1_model.onnx", "stage1_model.onnx.data")) {
                        context.assets.open("flutter_assets/saved_models/$name").use { input ->
                            File(directory, name).outputStream().use { input.copyTo(it) }
                        }
                    }
                    val env = OrtEnvironment.getEnvironment()
                    OrtSession.SessionOptions().use { options ->
                        options.setIntraOpNumThreads(2)
                        env.createSession(File(directory, "stage1_model.onnx").absolutePath, options).use { session ->
                            require(session.inputInfo.size == 1 && session.outputInfo.size == 1)
                            val inputName = session.inputNames.single()
                            val info = session.inputInfo.getValue(inputName).info as TensorInfo
                            require(info.type == OnnxJavaType.FLOAT && info.shape.size == 3 && info.shape[2] == 492L)
                            OnnxTensor.createTensor(env, floats, longArrayOf(1, frames.toLong(), 492)).use { tensor ->
                                session.run(mapOf(inputName to tensor)).use { outputs ->
                                    val output = outputs[0] as OnnxTensor
                                    val shape = output.info.shape
                                    require(output.info.type == OnnxJavaType.FLOAT &&
                                        shape.contentEquals(longArrayOf(1, frames.toLong(), classes.toLong()))) {
                                        "Unexpected Stage 1 output: ${shape.contentToString()}"
                                    }
                                    @Suppress("UNCHECKED_CAST")
                                    val values = output.value as Array<Array<FloatArray>>
                                    val packed = ByteBuffer.allocate(frames * classes * 4).order(ByteOrder.LITTLE_ENDIAN)
                                    for (row in values.single()) for (value in row) {
                                        check(value.isFinite()) { "Non-finite Stage 1 logits" }
                                        packed.putFloat(value)
                                    }
                                    Log.i("KSL_STAGE1_ONNX", "input=[1,$frames,492] output=${shape.contentToString()} finite=true")
                                    result.success(mapOf("shape" to shape.toList(), "logits" to packed.array()))
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e("KSL_STAGE1_ONNX", "Stage 1 inference failed", e)
                    result.error("STAGE1_ONNX", e.message, null)
                } finally {
                    directory?.deleteRecursively()
                }
            }
    }
}
