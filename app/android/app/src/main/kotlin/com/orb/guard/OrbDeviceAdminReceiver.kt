// OrbDeviceAdminReceiver.kt
// The DeviceAdminReceiver backing OrbGuard's remote anti-theft LOCK / WIPE.
//
// Declaring this receiver (with the force-lock + wipe-data policies in
// res/xml/device_admin.xml) is what lets DevicePolicyManager.lockNow() and
// wipeData() run for this app once the user enables OrbGuard as a device
// administrator via the intrusive ACTION_ADD_DEVICE_ADMIN system screen.
// The DeviceAdminReceiver base class already handles the admin lifecycle; we
// only override onEnabled/onDisabled to log the transitions for diagnostics.

package com.orb.guard

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class OrbDeviceAdminReceiver : DeviceAdminReceiver() {

    companion object {
        private const val TAG = "OrbDeviceAdmin"
    }

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i(TAG, "device administrator enabled — remote lock/wipe available")
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.i(TAG, "device administrator disabled — remote lock/wipe unavailable")
    }
}
