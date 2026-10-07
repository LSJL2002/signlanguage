package com.example.signlanguage

import android.content.Context
import android.graphics.*
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import android.os.Build
import android.util.Log
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream

/** Dedicated serial background queue: pose inference never blocks the UI thread. */
class PoseChannel(context: Context, messenger: BinaryMessenger) {
    private var detector: PoseLandmarker? = null
    private var hands: HandLandmarker? = null
    private var face: FaceLandmarker? = null
    private var faceError: String? = null
    private var video: MediaMetadataRetriever? = null
    private var videoDurationUs = 0L

    init {
        MethodChannel(messenger, "com.example.signlanguage/pose",
            StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue())
            .setMethodCallHandler { call, result ->
                var videoStage = "open video"
                try {
                    when (call.method) {
                        "initialize" -> {
                            detector?.close()
                            hands?.close()
                            detector = null
                            hands = null
                            detector = PoseLandmarker.createFromOptions(context,
                                PoseLandmarker.PoseLandmarkerOptions.builder()
                                    .setBaseOptions(BaseOptions.builder()
                                        .setModelAssetPath("pose_landmarker_lite.task").build())
                                    .setRunningMode(RunningMode.IMAGE)
                                    .setNumPoses(1)
                                    .setMinPoseDetectionConfidence(0.5f)
                                    .setMinPosePresenceConfidence(0.5f)
                                    .build())
                            hands = HandLandmarker.createFromOptions(context,
                                HandLandmarker.HandLandmarkerOptions.builder()
                                    .setBaseOptions(BaseOptions.builder()
                                        .setModelAssetPath("hand_landmarker.task").build())
                                    .setRunningMode(RunningMode.IMAGE)
                                    .setNumHands(2)
                                    .setMinHandDetectionConfidence(0.5f)
                                    .setMinHandPresenceConfidence(0.5f)
                                    .build())
                            face?.close()
                            face = null
                            faceError = null
                            try {
                                face = FaceLandmarker.createFromOptions(context,
                                    FaceLandmarker.FaceLandmarkerOptions.builder()
                                        .setBaseOptions(BaseOptions.builder().setModelAssetPath("face_landmarker.task").setDelegate(Delegate.CPU).build())
                                        .setRunningMode(RunningMode.IMAGE)
                                        .setNumFaces(1)
                                        .setMinFaceDetectionConfidence(0.5f)
                                        .setMinFacePresenceConfidence(0.5f)
                                        .setOutputFaceBlendshapes(false)
                                        .setOutputFacialTransformationMatrixes(false)
                                        .build())
                                Log.i("KSL_FACE", "KSL_FACE init OK model=face_landmarker.task mode=IMAGE delegate=CPU numFaces=1 detectionThreshold=0.5 presenceThreshold=0.5")
                            } catch (e: Exception) {
                                faceError = e.message ?: "Face initialization failed"
                                Log.e("KSL_FACE", "KSL_FACE init FAILED model=face_landmarker.task mode=IMAGE delegate=CPU", e)
                            }
                            result.success(true)
                        }
                        "detect" -> {
                            val bitmap = frameBitmap(call)
                            try {
                                result.success(analyzeBitmap(bitmap,
                                    call.argument<Number>("frameId")!!.toLong(),
                                    call.argument<Number>("timestampUs")!!.toLong(),
                                    call.argument<Int>("rotation") ?: 0,
                                    call.argument<Boolean>("mirror") == true))
                            } finally { bitmap.recycle() }
                        }
                        "openVideo" -> {
                            video?.release(); video = null
                            val retriever = MediaMetadataRetriever()
                            try {
                                val uri = Uri.parse(requireNotNull(call.argument<String>("uri")))
                                require(uri.scheme == "content") { "Select a video using the document picker" }
                                var name: String? = null
                                var size: Long? = null
                                context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                                    if (cursor.moveToFirst()) {
                                        val ni = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                                        val si = cursor.getColumnIndex(OpenableColumns.SIZE)
                                        if (ni >= 0 && !cursor.isNull(ni)) name = cursor.getString(ni)
                                        if (si >= 0 && !cursor.isNull(si)) size = cursor.getLong(si)
                                    }
                                }
                                Log.i("KSL_VIDEO_PICK", "KSL_VIDEO_PICK uri=$uri name=$name extension=${name?.substringAfterLast('.', "")} size=$size content=${uri.scheme == "content"}")
                                // ContentResolver grants are used directly; never derive a gallery file path.
                                retriever.setDataSource(context, uri)
                                Log.i("KSL_VIDEO_PICK", "KSL_VIDEO_PICK accessibleViaAndroid=true uri=$uri")
                                videoStage = "read metadata"
                                fun meta(key: Int) = retriever.extractMetadata(key)
                                videoDurationUs = (meta(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0) * 1000L
                                require(videoDurationUs > 0) { "Video has no readable duration" }
                                val metadata = mapOf(
                                    "durationUs" to videoDurationUs,
                                    "durationMs" to videoDurationUs / 1000,
                                    "width" to meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH),
                                    "height" to meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT),
                                    "rotation" to meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION),
                                    "mimeType" to (context.contentResolver.getType(uri) ?: meta(MediaMetadataRetriever.METADATA_KEY_MIMETYPE)),
                                    "frameRate" to meta(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE),
                                    "fileName" to name, "fileSize" to size,
                                    "accessibleViaAndroid" to true)
                                Log.i("KSL_VIDEO_META", "KSL_VIDEO_META $metadata")
                                videoStage = "decode first frame at 0ms"
                                val probe = decodeVideoFrame(retriever, 0)
                                probe.recycle()
                                video = retriever
                                result.success(metadata)
                            } catch (e: Exception) { retriever.release(); throw e }
                        }
                        "detectVideoFrame" -> {
                            videoStage = "decode frame"
                            val retriever = checkNotNull(video) { "No video open" }
                            val timestamp = requireNotNull(call.argument<Number>("timestampUs")).toLong()
                            require(timestamp >= 0 && timestamp < videoDurationUs)
                            // Retriever applies container rotation to the returned bitmap.
                            // OPTION_CLOSEST samples near the requested time, not just key frames.
                            videoStage = "decode frame at ${timestamp / 1000}ms"
                            val bitmap = decodeVideoFrame(retriever, timestamp)
                            if (bitmap == null) {
                                result.error("VIDEO_DECODE", "Cannot decode sample at $timestamp us", null)
                            } else {
                                val scaled = limitSize(bitmap)
                                try {
                                    // MPImage.close() owns/recycles this bitmap during analysis.
                                    // Encode the preview while it is still alive.
                                    videoStage = "encode preview at ${timestamp / 1000}ms"
                                    val preview = ByteArrayOutputStream()
                                    check(scaled.compress(Bitmap.CompressFormat.JPEG, 80, preview))
                                    videoStage = "landmark analysis at ${timestamp / 1000}ms"
                                    val packet = analyzeBitmap(scaled,
                                        call.argument<Number>("frameId")!!.toLong(), timestamp, 0, false).toMutableMap()
                                    Log.i("KSL_VIDEO_FRAME", "KSL_VIDEO_FRAME ts=${timestamp / 1000}ms pipelineSuccess=true previewBytes=${preview.size()}")
                                    packet["preview"] = preview.toByteArray()
                                    packet["timestampKind"] = "requestedSampleTimeUs"
                                    result.success(packet)
                                } finally { scaled.recycle() }
                            }
                        }
                        "closeVideo" -> {
                            video?.release(); video = null
                            result.success(null)
                        }
                        "close" -> {
                            video?.release(); video = null
                            detector?.close()
                            detector = null
                            hands?.close()
                            hands = null
                            face?.close(); face = null
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    if (call.method == "initialize") {
                        detector?.close(); detector = null
                        hands?.close(); hands = null
                        face?.close(); face = null
                    }
                    if (call.method == "openVideo" || call.method == "detectVideoFrame") {
                        Log.e("KSL_VIDEO_ERROR", "KSL_VIDEO_ERROR stage=$videoStage", e)
                        result.error("VIDEO_ERROR", "Failed to $videoStage: ${e.message}", Log.getStackTraceString(e))
                    } else result.error("POSE_ERROR", e.message, null)
                }
            }
    }

    private fun decodeVideoFrame(retriever: MediaMetadataRetriever, timestampUs: Long): Bitmap {
        try {
            val bitmap = if (Build.VERSION.SDK_INT >= 27)
                retriever.getScaledFrameAtTime(timestampUs, MediaMetadataRetriever.OPTION_CLOSEST, 640, 640)
            else retriever.getFrameAtTime(timestampUs, MediaMetadataRetriever.OPTION_CLOSEST)
            checkNotNull(bitmap) { "Android decoder returned no frame" }
            Log.i("KSL_VIDEO_FRAME", "KSL_VIDEO_FRAME ts=${timestampUs / 1000}ms success=true width=${bitmap.width} height=${bitmap.height} rotationAppliedByRetriever=true")
            return bitmap
        } catch (e: Exception) {
            Log.e("KSL_VIDEO_FRAME", "KSL_VIDEO_FRAME ts=${timestampUs / 1000}ms success=false", e)
            throw e
        }
    }

    private fun analyzeBitmap(bitmap: Bitmap, frameId: Long, timestampUs: Long,
        rotation: Int, mirror: Boolean): Map<String, Any?> {
        val model = checkNotNull(detector) { "Pose detector not initialized" }
        val image = BitmapImageBuilder(bitmap).build()
        try {
            // Infer on upright, unmirrored input. Mirror coordinates only for display.
            val poseStart = System.nanoTime()
            val body = model.detect(image).landmarks().firstOrNull()?.map { point -> mapOf(
                "x" to (if (mirror) 1.0 - point.x() else point.x().toDouble()),
                "y" to point.y().toDouble(), "z" to point.z().toDouble(),
                "visibility" to point.visibility().orElse(0f).toDouble(),
                "presence" to point.presence().orElse(0f).toDouble()
            ) } ?: emptyList()
            val poseMs = (System.nanoTime() - poseStart) / 1_000_000.0
            val handStart = System.nanoTime()
            val detected = checkNotNull(hands).detect(image)
            val handMs = (System.nanoTime() - handStart) / 1_000_000.0
            val grouped = mutableMapOf<String, Map<String, Any>>()
            detected.landmarks().forEachIndexed { i, landmarks ->
                val category = detected.handedness()[i].maxByOrNull { it.score() }
                if (category != null && category.score() >= 0.6f) {
                    // MediaPipe Hands handedness assumes selfie-mirrored input.
                    // Our inference input is unmirrored, so correct to anatomical side.
                    val side = if (category.categoryName() == "Left") "rightHand" else "leftHand"
                    val prior = grouped[side]?.get("confidence") as? Double ?: 0.0
                    if (category.score() > prior) grouped[side] = mapOf(
                        "handedness" to if (side == "leftHand") "Left" else "Right",
                        "confidence" to category.score().toDouble(),
                        "landmarks" to landmarks.map { point -> mapOf(
                            "x" to (if (mirror) 1.0 - point.x() else point.x().toDouble()),
                            "y" to point.y().toDouble(), "z" to point.z().toDouble()
                        ) })
                }
            }
            // Same MPImage, rotation, mirror and normalized preview space as Pose/Hands.
            val faceStart = System.nanoTime()
            var facesCount = 0
            val facePoints = try {
                val faces = face?.detect(image)?.faceLandmarks()
                facesCount = faces?.size ?: 0
                faces?.firstOrNull()?.map { point -> mapOf(
                    "x" to (if (mirror) 1.0 - point.x() else point.x().toDouble()),
                    "y" to point.y().toDouble(), "z" to point.z().toDouble()
                ) } ?: emptyList()
            } catch (e: Exception) {
                Log.e("KSL_FACE", "KSL_FACE detect FAILED f=$frameId timestampUs=$timestampUs", e)
                emptyList()
            }
            val faceMs = (System.nanoTime() - faceStart) / 1_000_000.0
            Log.i("KSL_FACE", "KSL_FACE f=$frameId timestampUs=$timestampUs faces=$facesCount landmarks=${facePoints.size} lm0=${facePoints.firstOrNull()} ms=$faceMs poseMs=$poseMs handMs=$handMs rotation=$rotation mirror=$mirror input=${bitmap.width}x${bitmap.height} error=$faceError")
            Log.i("KSL_SEND", "KSL_SEND frameId=$frameId face landmark count=${facePoints.size}")
            return mapOf(
                "face" to facePoints,
                "frameId" to frameId,
                "timestampUs" to timestampUs,
                "rotation" to rotation, "mirror" to mirror,
                "width" to bitmap.width, "height" to bitmap.height,
                "body" to body,
                "leftHand" to grouped["leftHand"], "rightHand" to grouped["rightHand"]
            )
        } finally { image.close() }
    }

    private fun limitSize(bitmap: Bitmap): Bitmap {
        val scale = 640f / maxOf(bitmap.width, bitmap.height)
        if (scale >= 1f) return bitmap
        val scaled = Bitmap.createScaledBitmap(bitmap,
            (bitmap.width * scale).toInt().coerceAtLeast(1),
            (bitmap.height * scale).toInt().coerceAtLeast(1), true)
        bitmap.recycle()
        return scaled
    }

    private fun frameBitmap(call: MethodCall): Bitmap {
        val width = requireNotNull(call.argument<Int>("width"))
        val height = requireNotNull(call.argument<Int>("height"))
        require(width > 0 && height > 0 && width % 2 == 0 && height % 2 == 0)
        val y = requireNotNull(call.argument<ByteArray>("y"))
        val u = requireNotNull(call.argument<ByteArray>("u"))
        val v = requireNotNull(call.argument<ByteArray>("v"))
        val ys = requireNotNull(call.argument<Int>("yStride"))
        val us = requireNotNull(call.argument<Int>("uStride"))
        val vs = requireNotNull(call.argument<Int>("vStride"))
        val up = requireNotNull(call.argument<Int>("uPixelStride"))
        val vp = requireNotNull(call.argument<Int>("vPixelStride"))
        val bytes = ByteArray(width * height * 3 / 2)
        var index = 0
        for (row in 0 until height) for (col in 0 until width) {
            bytes[index++] = y[row * ys + col]
        }
        for (row in 0 until height / 2) for (col in 0 until width / 2) {
            bytes[index++] = v[row * vs + col * vp]
            bytes[index++] = u[row * us + col * up]
        }
        val output = ByteArrayOutputStream()
        check(YuvImage(bytes, ImageFormat.NV21, width, height, null)
            .compressToJpeg(Rect(0, 0, width, height), 85, output))
        val jpeg = output.toByteArray()
        val original = requireNotNull(BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size))
        val matrix = Matrix().apply {
            postRotate((call.argument<Int>("rotation") ?: 0).toFloat())
        }
        val rotated = Bitmap.createBitmap(original, 0, 0, width, height, matrix, true)
        if (rotated !== original) original.recycle()
        // Cap inference input size to reduce CPU work; normalized coordinates stay valid.
        val scale = 640f / maxOf(rotated.width, rotated.height)
        if (scale >= 1f) return rotated
        val scaled = Bitmap.createScaledBitmap(rotated,
            (rotated.width * scale).toInt(), (rotated.height * scale).toInt(), true)
        rotated.recycle()
        return scaled
    }
}
