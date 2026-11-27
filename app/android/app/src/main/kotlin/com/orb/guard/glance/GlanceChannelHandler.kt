package com.orb.guard.glance

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * `com.orb.guard/glance`: Dart sends `update(map)` whenever something the
 * glance shows changed. The map is stored and every placed widget redrawn.
 * (`refresh` and `checkNow` run native to Dart and only matter on macOS.)
 */
class GlanceChannelHandler(private val context: Context) {
    companion object {
        private const val TAG = "OrbGuard.Glance"
        private const val CHANNEL_NAME = "com.orb.guard/glance"
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val map = call.arguments as? Map<*, *>
                    if (map == null) {
                        result.error("bad_args", "update expects a map", null)
                        return@setMethodCallHandler
                    }
                    try {
                        GlanceStore.save(context, map)
                        GlanceWidgets.updateAll(context)
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "glance update failed", e)
                        result.error("update_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
