package com.example.signlanguage

import android.graphics.Rect
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max

/** A padded head ROI in the already-upright bitmap; never changes Pose/Hand input. */
internal object PoseFaceCrop {
    fun bounds(width: Int, height: Int, body: List<Map<String, Double>>, mirror: Boolean): Rect? {
        if (width <= 0 || height <= 0 || body.size != 33) return null
        fun reliable(p: Map<String, Double>): Boolean =
            listOf("x", "y", "visibility", "presence").all { p[it]?.isFinite() == true } &&
                p.getValue("x") in 0.0..1.0 && p.getValue("y") in 0.0..1.0 &&
                p.getValue("visibility") >= 0.5 && p.getValue("presence") >= 0.5
        if (!reliable(body[0])) return null
        val head = body.take(11).filter(::reliable)
        if (head.size < 5) return null
        val xs = head.map { (if (mirror) 1.0 - it.getValue("x") else it.getValue("x")) * width }
        val ys = head.map { it.getValue("y") * height }
        val spanX = xs.max() - xs.min()
        val spanY = ys.max() - ys.min()
        if (spanX < 4 || spanY < 4) return null
        // Pose covers eyes/ears/mouth, not forehead/chin. Pad around these anchors.
        val side = max(32.0, max(spanX * 2.5, spanY * 3.0))
        val cx = (xs.min() + xs.max()) / 2
        val cy = (ys.min() + ys.max()) / 2
        val rect = Rect(
            floor(cx - side / 2).toInt().coerceIn(0, width),
            floor(cy - side / 2).toInt().coerceIn(0, height),
            ceil(cx + side / 2).toInt().coerceIn(0, width),
            ceil(cy + side / 2).toInt().coerceIn(0, height),
        )
        if (rect.width() < 16 || rect.height() < 16 ||
            (rect.width() == width && rect.height() == height)) return null
        return rect
    }

    fun project(x: Double, y: Double, z: Double, rect: Rect,
                width: Int, height: Int, mirror: Boolean): Map<String, Double> {
        val fullX = (rect.left + x * rect.width()) / width
        return mapOf(
            "x" to if (mirror) 1.0 - fullX else fullX,
            "y" to (rect.top + y * rect.height()) / height,
            // MediaPipe z uses the same scale as x; preserve full-frame units.
            "z" to z * rect.width() / width,
        )
    }
}
