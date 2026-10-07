package com.example.signlanguage

import android.graphics.Bitmap
import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.signlanguage/mediapipe"
    private var handLandmarker: HandLandmarker? = null
    private var videoPickerResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.signlanguage/video_picker")
            .setMethodCallHandler { call, result ->
                if (call.method != "pickVideo") result.notImplemented()
                else if (videoPickerResult != null) result.error("PICKER_BUSY", "Video picker already open", null)
                else {
                    videoPickerResult = result
                    try {
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            type = "video/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }, 701)
                    } catch (e: Exception) {
                        videoPickerResult = null
                        result.error("PICKER_ERROR", e.message, null)
                    }
                }
            }
        PoseChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL,
            StandardMethodCodec.INSTANCE, flutterEngine.dartExecutor.binaryMessenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result ->
            when (call.method) {
                "initHandLandmarker" -> {
                    try {
                        val baseOptions = BaseOptions.builder()
                            .setModelAssetPath("hand_landmarker.task")
                            .build()

                        val options = HandLandmarker.HandLandmarkerOptions.builder()
                            .setBaseOptions(baseOptions)
                            .setMinHandDetectionConfidence(0.3f)
                            .setMinHandPresenceConfidence(0.3f)
                            .setMinTrackingConfidence(0.3f)
                            .setNumHands(2)
                            .setRunningMode(RunningMode.IMAGE)
                            .build()

                        handLandmarker?.close()
                        handLandmarker = HandLandmarker.createFromOptions(context, options)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INIT_ERROR", "Failed to initialize HandLandmarker: ${e.message}", null)
                    }
                }
                "detectHandLandmarksFromFile" -> {
                    val landmarker = handLandmarker
                    if (landmarker == null) {
                        result.error("NOT_INITIALIZED", "HandLandmarker is not initialized", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val filePath = call.argument<String>("filePath")
                        if (filePath == null || !File(filePath).exists()) {
                            result.error("FILE_NOT_FOUND", "File not found at $filePath", null)
                            return@setMethodCallHandler
                        }

                        var bitmap = BitmapFactory.decodeFile(filePath)
                        if (bitmap == null) {
                            result.error("DECODE_ERROR", "Failed to decode bitmap from $filePath", null)
                            return@setMethodCallHandler
                        }

                        val mpImage: MPImage = BitmapImageBuilder(bitmap).build()
                        try {
                            val detectionResult = landmarker.detect(mpImage)
                            result.success(detectionResult.landmarks().mapIndexed { index, points ->
                                val category = detectionResult.handedness()[index].maxByOrNull { it.score() }
                                val rawSide = category?.categoryName() ?: "Unknown"
                                val side = if (false || rawSide == "Unknown") rawSide
                                    else if (rawSide == "Left") "Right" else "Left"
                                mapOf("handedness" to side, "confidence" to (category?.score()?.toDouble() ?: 0.0),
                                    "landmarks" to points.map { point -> mapOf(
                                        "x" to point.x().toDouble(), "y" to point.y().toDouble(), "z" to point.z().toDouble()) })
                            })
                        } finally {
                            mpImage.close()
                            bitmap.recycle()
                        }
                    } catch (e: Exception) {
                        result.error("DETECTION_ERROR", "Error detecting hand landmarks: ${e.message}", null)
                    }
                }
                "detectHandLandmarks" -> {
                    val landmarker = handLandmarker
                    if (landmarker == null) {
                        result.error("NOT_INITIALIZED", "HandLandmarker is not initialized", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val yBytes = call.argument<ByteArray>("yBuffer")
                        val uBytes = call.argument<ByteArray>("uBuffer")
                        val vBytes = call.argument<ByteArray>("vBuffer")
                        val width = call.argument<Int>("width") ?: 0
                        val height = call.argument<Int>("height") ?: 0
                        val yRowStride = call.argument<Int>("yRowStride") ?: width
                        val uvRowStride = call.argument<Int>("uvRowStride") ?: width
                        val uvPixelStride = call.argument<Int>("uvPixelStride") ?: 1
                        val rotationDegrees = call.argument<Int>("rotationDegrees") ?: 0
                        val isFrontCamera = call.argument<Boolean>("isFrontCamera") ?: false

                        if (yBytes == null || uBytes == null || vBytes == null || width == 0 || height == 0) {
                            result.error("INVALID_ARGS", "Missing image plane buffers or dimensions", null)
                            return@setMethodCallHandler
                        }

                        val nv21 = yuv420ToNv21(
                            width, height,
                            ByteBuffer.wrap(yBytes),
                            ByteBuffer.wrap(uBytes),
                            ByteBuffer.wrap(vBytes),
                            yRowStride, uvRowStride, uvPixelStride
                        )

                        val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
                        val out = ByteArrayOutputStream()
                        yuvImage.compressToJpeg(Rect(0, 0, width, height), 100, out)
                        val imageBytes = out.toByteArray()
                        var bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)

                        if (rotationDegrees != 0 || isFrontCamera) {
                            val matrix = Matrix()
                            matrix.postRotate(rotationDegrees.toFloat())
                            if (isFrontCamera) {
                                matrix.postScale(-1f, 1f)
                            }
                            val original = bitmap
                            bitmap = Bitmap.createBitmap(original, 0, 0, original.width, original.height, matrix, true)
                            if (bitmap !== original) original.recycle()
                        }

                        val mpImage: MPImage = BitmapImageBuilder(bitmap).build()
                        try {
                            val detectionResult = landmarker.detect(mpImage)
                            result.success(detectionResult.landmarks().mapIndexed { index, points ->
                                val category = detectionResult.handedness()[index].maxByOrNull { it.score() }
                                val rawSide = category?.categoryName() ?: "Unknown"
                                val side = if (isFrontCamera || rawSide == "Unknown") rawSide
                                    else if (rawSide == "Left") "Right" else "Left"
                                mapOf("handedness" to side, "confidence" to (category?.score()?.toDouble() ?: 0.0),
                                    "landmarks" to points.map { point -> mapOf(
                                        "x" to point.x().toDouble(), "y" to point.y().toDouble(), "z" to point.z().toDouble()) })
                            })
                        } finally {
                            mpImage.close()
                            bitmap.recycle()
                        }
                    } catch (e: Exception) {
                        result.error("DETECTION_ERROR", "Error detecting hand landmarks: ${e.message}", null)
                    }
                }
                "closeHandLandmarker" -> {
                    try {
                        handLandmarker?.close()
                        handLandmarker = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CLOSE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Uses FlutterActivity activity result forwarding")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 701) {
            val pending = videoPickerResult
            videoPickerResult = null
            pending?.success(if (resultCode == Activity.RESULT_OK) data?.data?.toString() else null)
        }
    }

    override fun onDestroy() {
        videoPickerResult?.success(null)
        videoPickerResult = null
        super.onDestroy()
    }

    private fun yuv420ToNv21(
        width: Int,
        height: Int,
        yBuffer: ByteBuffer,
        uBuffer: ByteBuffer,
        vBuffer: ByteBuffer,
        yRowStride: Int,
        uvRowStride: Int,
        uvPixelStride: Int
    ): ByteArray {
        val nv21 = ByteArray(width * height * 3 / 2)
        var pos = 0

        if (yRowStride == width) {
            yBuffer.get(nv21, 0, width * height)
            pos = width * height
        } else {
            for (row in 0 until height) {
                yBuffer.position(row * yRowStride)
                yBuffer.get(nv21, pos, width)
                pos += width
            }
        }

        val uvHeight = height / 2
        val uvWidth = width / 2
        for (row in 0 until uvHeight) {
            val uRowStart = row * uvRowStride
            val vRowStart = row * uvRowStride
            for (col in 0 until uvWidth) {
                val uPos = uRowStart + col * uvPixelStride
                val vPos = vRowStart + col * uvPixelStride
                if (uPos < uBuffer.capacity() && vPos < vBuffer.capacity() && pos < nv21.size - 1) {
                    nv21[pos++] = vBuffer.get(vPos)
                    nv21[pos++] = uBuffer.get(uPos)
                }
            }
        }
        return nv21
    }
}
