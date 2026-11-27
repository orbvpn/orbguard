package com.orb.guard.glance

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * The last glance Dart sent, kept as JSON in its own private preferences file
 * (not `FlutterSharedPreferences`, which holds tokens), so the widgets can draw
 * it while the app is closed.
 */
object GlanceStore {
    private const val TAG = "OrbGuard.Glance"
    private const val FILE = "orbguard_glance"
    private const val KEY = "glance"

    fun save(context: Context, map: Map<*, *>) {
        val json = JSONObject(map).toString()
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putString(KEY, json).commit()
    }

    /** The stored glance, or null when none has arrived or it cannot be read. */
    fun load(context: Context): GlanceState? {
        val json = context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getString(KEY, null)
            ?: return null
        return try {
            GlanceParse.from(toMap(JSONObject(json)))
        } catch (e: Exception) {
            Log.w(TAG, "stored glance unreadable", e)
            null
        }
    }

    private fun toMap(o: JSONObject): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        val keys = o.keys()
        while (keys.hasNext()) {
            val k = keys.next()
            out[k] = plain(o.opt(k))
        }
        return out
    }

    private fun plain(v: Any?): Any? = when (v) {
        null, JSONObject.NULL -> null
        is JSONObject -> toMap(v)
        is JSONArray -> (0 until v.length()).map { plain(v.opt(it)) }
        else -> v
    }
}
