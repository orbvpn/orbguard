package com.orb.guard.glance

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Build
import android.util.Log
import kotlin.math.cos
import kotlin.math.sin

/** The OrbVPN 2026 kit values the widgets draw with (one place, mirrored in res/values*). */
internal class GlancePalette private constructor(val dark: Boolean) {
    val text: Int = if (dark) Color.parseColor("#F5F6F8") else Color.parseColor("#0B0B0E")
    val track: Int = if (dark) argb(0.065f, "#FFFFFF") else argb(0.06f, "#12121C")
    val fill: IntArray = (
        if (dark) arrayOf("#F6FFDA", "#E6FBAE", "#CDF57A", "#A9E36C", "#86CB6B", "#63AD5C")
        else arrayOf("#F2FCD0", "#E0F4B0", "#C4E896", "#A0D87C", "#84C86C", "#68B060")
        ).map { Color.parseColor(it) }.toIntArray()
    val glow: Int = if (dark) argb(0.30f, "#BEFA50") else argb(0.34f, "#96D25A")
    val dots: Int = if (dark) argb(0.9f, "#6F717C") else argb(0.9f, "#8A8C96")
    val amber: Int = Color.parseColor("#FFB800")

    /** Contact shadow under the band, and the shade along its edges. */
    val shadow: Int = argb(if (dark) 0.45f else 0.42f, "#6A9858")
    val depth: Int = Color.parseColor("#12300A")

    companion object {
        val DARK = GlancePalette(true)
        val LIGHT = GlancePalette(false)
        fun of(dark: Boolean) = if (dark) DARK else LIGHT

        fun argb(alpha: Float, hex: String): Int {
            val c = Color.parseColor(hex)
            return Color.argb((alpha * 255).toInt().coerceIn(0, 255), Color.red(c), Color.green(c), Color.blue(c))
        }
    }
}

/** Draws the ring exactly as `orb_ring.dart` does at rest, onto a Bitmap for a RemoteViews ImageView. */
internal object GlanceRingPainter {
    private const val TAG = "OrbGuard.Glance"
    private const val ARCHIVO = "flutter_assets/assets/fonts/Archivo-Variable.ttf"
    private val RAMP_STOPS = floatArrayOf(0f, 0.2f, 0.4f, 0.6f, 0.8f, 1f)

    /** saturate(.12) then brightness(.82): a ring with nothing on watch. */
    private val STILL = ColorMatrixColorFilter(
        ColorMatrix(
            floatArrayOf(
                0.2521f, 0.5159f, 0.0520f, 0f, 0f,
                0.1537f, 0.6143f, 0.0520f, 0f, 0f,
                0.1537f, 0.5159f, 0.1504f, 0f, 0f,
                0f, 0f, 0f, 1f, 0f,
            ),
        ),
    )

    @Volatile private var numerals: Typeface? = null

    /** Archivo bold from the Flutter assets already in the APK; system bold when it cannot load. */
    private fun numerals(context: Context): Typeface {
        numerals?.let { return it }
        val face = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Typeface.Builder(context.assets, ARCHIVO)
                    .setFontVariationSettings("'wght' 700")
                    .build()
            } else {
                Typeface.create(Typeface.createFromAsset(context.assets, ARCHIVO), Typeface.BOLD)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Archivo not loaded, using the system face", e)
            null
        } ?: Typeface.DEFAULT_BOLD
        numerals = face
        return face
    }

    /**
     * A square bitmap of [sidePx] with the ring of [ringPx] centred in it. The
     * extra side leaves room for the bloom, which fades out just past the band.
     */
    fun draw(
        context: Context,
        face: GlanceFace,
        ring: RingStyle,
        dark: Boolean,
        ringPx: Int,
        sidePx: Int,
        ringDp: Double,
    ): Bitmap {
        val p = GlancePalette.of(dark)
        val bmp = Bitmap.createBitmap(sidePx, sidePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val c = sidePx / 2f
        val d = ringPx.toFloat()

        // The bloom behind the ring.
        val bloom = if (ring == RingStyle.OPEN) 0.86f else 0.25f
        val bloomRadius = d * 0.7f
        val glow = Color.argb(
            (Color.alpha(p.glow) * bloom).toInt(), Color.red(p.glow), Color.green(p.glow), Color.blue(p.glow),
        )
        canvas.drawCircle(
            c, c, bloomRadius,
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = RadialGradient(
                    c, c, bloomRadius,
                    intArrayOf(glow, glow and 0x00FFFFFF), floatArrayOf(0f, 0.74f), Shader.TileMode.CLAMP,
                )
            },
        )

        // From here on: the ring's own 200 unit box, centred on the origin.
        canvas.save()
        canvas.translate(c, c)
        canvas.scale(d / GlanceLogic.BOX.toFloat(), d / GlanceLogic.BOX.toFloat())
        val r = GlanceLogic.CENTRE.toFloat()
        canvas.drawCircle(0f, 0f, r, band().apply { color = p.track })

        if (ring == RingStyle.FRESH) {
            val n = GlanceLogic.dotCount(ringDp)
            val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = p.dots }
            for (i in 0 until n) {
                val (x, y) = at(i * 360.0 / n, r)
                canvas.drawCircle(x, y, 1.6f, dot)
            }
        } else {
            val path = Path()
            val box = RectF(-r, -r, r, r)
            for (a in GlanceLogic.arcs(face.gaps)) {
                if (a.isWhole) path.addOval(box, Path.Direction.CW)
                else path.addArc(box, (a.start - 90).toFloat(), a.sweep.toFloat())
            }
            val still = ring == RingStyle.STILL
            // Contact shadow, then the band in the logo's ramp, then a sheen from
            // the top left that falls to shade at the bottom right.
            canvas.save()
            canvas.translate(0f, 2.5f)
            canvas.drawPath(
                path,
                band().apply {
                    color = p.shadow
                    if (still) colorFilter = STILL
                    maskFilter = BlurMaskFilter(blur(3f), BlurMaskFilter.Blur.NORMAL)
                },
            )
            canvas.restore()
            canvas.drawPath(
                path,
                band().apply {
                    shader = RadialGradient(-20f, -22f, 124f, p.fill, RAMP_STOPS, Shader.TileMode.CLAMP)
                    if (still) colorFilter = STILL
                },
            )
            canvas.drawPath(
                path,
                band().apply {
                    shader = LinearGradient(
                        -80f, -80f, 80f, 80f,
                        intArrayOf(
                            GlancePalette.argb(0.18f, "#FFFFFF"),
                            GlancePalette.argb(0f, "#FFFFFF"),
                            GlancePalette.argb(0.14f, "#000000"),
                        ),
                        floatArrayOf(0f, 0.42f, 1f), Shader.TileMode.CLAMP,
                    )
                },
            )

            // Depth: both edges of the band shaded, and a highlight along the
            // upper outer edge, kept inside the band so a gap's round ends stay clean.
            val depth = if (still) 0.5f else 1f
            val outline = Path()
            band().getFillPath(path, outline)
            canvas.save()
            canvas.clipPath(outline)
            for ((radius, width, alpha) in listOf(
                Triple(GlanceLogic.INNER.toFloat() + 1f, 8f, 0.28f),
                Triple(GlanceLogic.OUTER.toFloat() - 1f, 6f, 0.2f),
            )) {
                canvas.drawCircle(
                    0f, 0f, radius,
                    Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        style = Paint.Style.STROKE
                        strokeWidth = width
                        color = withAlpha(p.depth, alpha * depth)
                        maskFilter = BlurMaskFilter(blur(3.2f), BlurMaskFilter.Blur.NORMAL)
                    },
                )
            }
            val lit = (GlanceLogic.OUTER - 9).toFloat()
            canvas.drawArc(
                RectF(-lit, -lit, lit, lit), -62f - 90f, 76f, false,
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = 3.4f
                    strokeCap = Paint.Cap.ROUND
                    color = withAlpha(Color.WHITE, 0.62f * depth)
                    maskFilter = BlurMaskFilter(blur(1.7f), BlurMaskFilter.Blur.NORMAL)
                },
            )
            canvas.restore()

            val spark = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = p.amber }
            for (g in face.gaps) {
                val (x, y) = at(g, r)
                canvas.drawCircle(x, y, 4.6f, spark)
            }
        }
        canvas.restore()

        // The score in the hole.
        face.score?.let { score ->
            val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                typeface = numerals(context)
                textSize = d * 0.158f
                color = p.text
                textAlign = Paint.Align.CENTER
                letterSpacing = -0.02f
                fontFeatureSettings = "'lnum'"
            }
            val fm = text.fontMetrics
            canvas.drawText(score.toString(), c, c - (fm.ascent + fm.descent) / 2f, text)
        }
        return bmp
    }

    /** A Gaussian of [sigma] (as Flutter's MaskFilter.blur takes it) as a BlurMaskFilter radius. */
    private fun blur(sigma: Float) = ((sigma - 0.5f) / 0.57735f).coerceAtLeast(0.1f)

    private fun withAlpha(c: Int, alpha: Float) =
        Color.argb((alpha * 255).toInt().coerceIn(0, 255), Color.red(c), Color.green(c), Color.blue(c))

    private fun band() = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = GlanceLogic.THICKNESS.toFloat()
        strokeCap = Paint.Cap.ROUND
    }

    private fun at(degreesFromTop: Double, radius: Float): Pair<Float, Float> {
        val a = Math.toRadians(degreesFromTop - 90)
        return Pair((radius * cos(a)).toFloat(), (radius * sin(a)).toFloat())
    }
}
