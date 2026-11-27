package com.orb.guard.glance

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.text.format.DateFormat
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import com.orb.guard.MainActivity
import com.orb.guard.R
import java.text.SimpleDateFormat
import java.time.ZoneId
import java.util.Date
import java.util.Locale

/** The 2x2 glance: ring with the score, then the title. */
class GlanceSmallProvider : GlanceProvider()

/** The 4x2 glance: ring left; title, line or check time, and the amber chip when something waits. */
class GlanceMediumProvider : GlanceProvider()

abstract class GlanceProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        GlanceWidgets.updateAll(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == GlanceWidgets.ACTION_REDRAW) GlanceWidgets.updateAll(context)
    }

    override fun onDisabled(context: Context) {
        if (!GlanceWidgets.anyPlaced(context)) GlanceWidgets.cancelRedraws(context)
    }
}

object GlanceWidgets {
    private const val TAG = "OrbGuard.Glance"
    const val ACTION_REDRAW = "com.orb.guard.glance.REDRAW"

    /** The ring in both widgets, in dp, and the square its bitmap fills (room for the bloom). */
    private const val RING_DP = 92.0
    private const val SIDE_DP = 98.0

    private fun ids(context: Context, cls: Class<*>): IntArray =
        AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, cls))

    fun anyPlaced(context: Context): Boolean =
        ids(context, GlanceSmallProvider::class.java).isNotEmpty() ||
            ids(context, GlanceMediumProvider::class.java).isNotEmpty()

    /** Draws every placed widget from the stored glance and schedules the next redraws. */
    fun updateAll(context: Context) {
        val app = context.applicationContext
        val small = ids(app, GlanceSmallProvider::class.java)
        val medium = ids(app, GlanceMediumProvider::class.java)
        if (small.isEmpty() && medium.isEmpty()) {
            cancelRedraws(app)
            return
        }
        val state = GlanceStore.load(app)
        val now = System.currentTimeMillis()
        val zone = ZoneId.systemDefault()
        val face = GlanceLogic.face(state, now) { checkedAt ->
            GlanceLogic.checkedLabel(checkedAt, now, zone, { timeText(app, it) }, { dateText(it) })
        }
        try {
            val manager = AppWidgetManager.getInstance(app)
            if (small.isNotEmpty()) manager.updateAppWidget(small, views(app, R.layout.glance_small, face, false))
            if (medium.isNotEmpty()) manager.updateAppWidget(medium, views(app, R.layout.glance_medium, face, true))
        } catch (e: Exception) {
            Log.e(TAG, "widget update failed", e)
        }
        scheduleRedraws(app, GlanceLogic.redrawTimes(state, now, zone))
    }

    private fun views(context: Context, layout: Int, face: GlanceFace, medium: Boolean): RemoteViews {
        val v = RemoteViews(context.packageName, layout)
        val ring = face.ring
        // Each layout carries one ring slot, picked by the host's night mode
        // (layout/ and layout-night/glance_ring_slot.xml); both get their own
        // drawing so the widget follows the system without a round trip.
        if (ring == null) {
            v.setImageViewResource(R.id.glance_ring_light, R.drawable.glance_logo)
            v.setImageViewResource(R.id.glance_ring_dark, R.drawable.glance_logo)
        } else {
            val density = context.resources.displayMetrics.density
            val ringPx = (RING_DP * density).toInt()
            val sidePx = (SIDE_DP * density).toInt()
            v.setImageViewBitmap(
                R.id.glance_ring_light,
                GlanceRingPainter.draw(context, face, ring, false, ringPx, sidePx, RING_DP),
            )
            v.setImageViewBitmap(
                R.id.glance_ring_dark,
                GlanceRingPainter.draw(context, face, ring, true, ringPx, sidePx, RING_DP),
            )
        }
        v.setContentDescription(R.id.glance_ring_light, face.description)
        v.setContentDescription(R.id.glance_ring_dark, face.description)
        v.setTextViewText(R.id.glance_title, face.title)
        if (medium) {
            if (face.line != null) {
                v.setTextViewText(R.id.glance_line, face.line)
                v.setViewVisibility(R.id.glance_line, View.VISIBLE)
            } else {
                v.setViewVisibility(R.id.glance_line, View.GONE)
            }
            if (face.checkedUnder != null) {
                v.setTextViewText(R.id.glance_checked, face.checkedUnder)
                v.setViewVisibility(R.id.glance_checked, View.VISIBLE)
            } else {
                v.setViewVisibility(R.id.glance_checked, View.GONE)
            }
            v.setViewVisibility(R.id.glance_chip, if (face.chip) View.VISIBLE else View.GONE)
        }
        v.setOnClickPendingIntent(android.R.id.background, openApp(context))
        return v
    }

    private fun openApp(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        return PendingIntent.getActivity(
            context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /** The clock time in the system's own 12 or 24 hour format. */
    private fun timeText(context: Context, ms: Long): String = DateFormat.getTimeFormat(context).format(Date(ms))

    /** A short day and month in the system locale's order (22 Nov, Nov 22). */
    private fun dateText(ms: Long): String {
        val locale = Locale.getDefault()
        return SimpleDateFormat(DateFormat.getBestDateTimePattern(locale, "dMMM"), locale).format(Date(ms))
    }

    private fun redrawIntent(context: Context, slot: Int): PendingIntent {
        val intent = Intent(context, GlanceSmallProvider::class.java).setAction(ACTION_REDRAW)
        return PendingIntent.getBroadcast(
            context, 0x6A0 + slot, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /** Inexact alarms are enough: the 30 minute update period is the backstop. */
    private fun scheduleRedraws(context: Context, times: List<Long>) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        for (slot in 0..1) {
            val at = times.getOrNull(slot)
            val pi = redrawIntent(context, slot)
            if (at == null) alarms.cancel(pi) else alarms.set(AlarmManager.RTC, at, pi)
        }
    }

    fun cancelRedraws(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        for (slot in 0..1) alarms.cancel(redrawIntent(context, slot))
    }
}
