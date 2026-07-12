// SupplyChainChannelHandler.kt
// Native supply-chain inspection channel: com.orbguard/supply_chain
//
// Consumed by lib/services/security/supply_chain_monitor_service.dart:
//   getInstalledPackages {user_only}  -> List<String> package names
//   getAppInfo {package_name}         -> { name, version, ... }
//   getAppLibraries {package_name}    -> List<String> library package prefixes
//
// Library detection method (documented in getAppInfo as detection_method):
//   1. Enumerates the APK's classes*.dex type_id tables and resolves their
//      class descriptors from the DEX string pool (header-driven offsets, no
//      external dexlib). Each descriptor is reduced to a 2-3 segment package
//      prefix (e.g. Lcom/google/firebase/analytics/X; -> com.google.firebase).
//   2. Enumerates bundled native libraries (lib/<abi>/*.so) and maps the
//      well-known ones to their owning SDK package.
// Precision limits (honest): packages minified by R8/ProGuard collapse to
// 1-letter names and are skipped (not identifiable); native libs without a
// known mapping are not guessed.

package com.orb.guard

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.zip.ZipFile

class SupplyChainChannelHandler(private val context: Context) {

    companion object {
        private const val TAG = "OrbGuard.SupplyChain"
        private const val CHANNEL_NAME = "com.orbguard/supply_chain"
        private const val MAX_DEX_BYTES = 96L * 1024 * 1024
        private const val MAX_PREFIXES = 1200

        private const val DETECTION_METHOD =
            "dex_type_table_scan+native_lib_enumeration; package-prefix matching only; " +
                "R8/ProGuard-minified packages are not identifiable and are skipped"

        // Known native library -> owning SDK package.
        private val KNOWN_NATIVE_LIBS = mapOf(
            "libflutter.so" to "io.flutter",
            "libapp.so" to "io.flutter.app",
            "libreactnativejni.so" to "com.facebook.react",
            "libhermes.so" to "com.facebook.hermes",
            "libjsc.so" to "org.webkit.javascriptcore",
            "libsqlcipher.so" to "net.zetetic.sqlcipher",
            "librealm-jni.so" to "io.realm",
            "libtensorflowlite_jni.so" to "org.tensorflow.lite",
            "libopencv_java4.so" to "org.opencv",
            "libcrashlytics.so" to "com.google.firebase.crashlytics",
            "libunity.so" to "com.unity3d.player",
            "libil2cpp.so" to "com.unity3d.player",
            "libcocos2djs.so" to "org.cocos2dx",
            "libmono.so" to "mono.android",
            "libxamarin-app.so" to "mono.android",
            "libconceal.so" to "com.facebook.conceal",
            "libpl_droidsonroids_gif.so" to "pl.droidsonroids.gif"
        )

        // Framework / language prefixes that are not third-party dependencies.
        private val EXCLUDED_FIRST_SEGMENTS = setOf(
            "java", "javax", "android", "dalvik", "sun", "libcore", "j$"
        )
    }

    private val packageManager: PackageManager get() = context.packageManager

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledPackages" -> getInstalledPackages(
                    call.argument<Boolean>("user_only") ?: true, result
                )
                "getAppInfo" -> getAppInfo(call.argument<String>("package_name"), result)
                "getAppLibraries" -> getAppLibraries(call.argument<String>("package_name"), result)
                else -> result.notImplemented()
            }
        }
    }

    // ------------------------------------------------------------------
    // getInstalledPackages
    // ------------------------------------------------------------------

    private fun getInstalledPackages(userOnly: Boolean, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val apps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.getInstalledApplications(
                        PackageManager.ApplicationInfoFlags.of(0L)
                    )
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.getInstalledApplications(0)
                }

                val packages = apps.asSequence()
                    .filter { app ->
                        if (!userOnly) {
                            true
                        } else {
                            val isSystem = (app.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                            val isUpdatedSystem =
                                (app.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
                            !isSystem || isUpdatedSystem
                        }
                    }
                    .map { it.packageName }
                    .sorted()
                    .toList()

                withContext(Dispatchers.Main) { result.success(packages) }
            } catch (e: Exception) {
                Log.e(TAG, "getInstalledPackages failed", e)
                withContext(Dispatchers.Main) {
                    result.error("NATIVE_ERROR", "Package enumeration failed: ${e.message}", null)
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // getAppInfo
    // ------------------------------------------------------------------

    private fun getAppInfo(packageName: String?, result: MethodChannel.Result) {
        if (packageName.isNullOrEmpty()) {
            result.error("BAD_ARGS", "package_name argument is required", null)
            return
        }
        try {
            val pkgInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0L))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            val appInfo = pkgInfo.applicationInfo
            val installer = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    packageManager.getInstallSourceInfo(packageName).installingPackageName
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.getInstallerPackageName(packageName)
                }
            } catch (e: Exception) {
                null
            }

            result.success(
                mapOf(
                    "name" to (appInfo?.loadLabel(packageManager)?.toString() ?: packageName),
                    "package" to packageName,
                    "version" to (pkgInfo.versionName ?: "unknown"),
                    "version_code" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        pkgInfo.longVersionCode
                    } else {
                        @Suppress("DEPRECATION")
                        pkgInfo.versionCode.toLong()
                    },
                    "is_system" to (appInfo != null &&
                        (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                    "installer" to (installer ?: "unknown"),
                    "first_install_time" to pkgInfo.firstInstallTime,
                    "last_update_time" to pkgInfo.lastUpdateTime,
                    "target_sdk" to (appInfo?.targetSdkVersion ?: 0),
                    "detection_method" to DETECTION_METHOD
                )
            )
        } catch (e: PackageManager.NameNotFoundException) {
            result.error("NOT_FOUND", "Package not installed: $packageName", null)
        } catch (e: Exception) {
            Log.e(TAG, "getAppInfo failed for $packageName", e)
            result.error("NATIVE_ERROR", "App info read failed: ${e.message}", null)
        }
    }

    // ------------------------------------------------------------------
    // getAppLibraries
    // ------------------------------------------------------------------

    private fun getAppLibraries(packageName: String?, result: MethodChannel.Result) {
        if (packageName.isNullOrEmpty()) {
            result.error("BAD_ARGS", "package_name argument is required", null)
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val appInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.getApplicationInfo(
                        packageName, PackageManager.ApplicationInfoFlags.of(0L)
                    )
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.getApplicationInfo(packageName, 0)
                }

                val apkPaths = mutableListOf<String>()
                appInfo.sourceDir?.let { apkPaths.add(it) }
                appInfo.splitSourceDirs?.let { apkPaths.addAll(it) }

                if (apkPaths.isEmpty()) {
                    withContext(Dispatchers.Main) {
                        result.error(
                            "UNAVAILABLE",
                            "No readable APK paths for $packageName",
                            mapOf("package" to packageName)
                        )
                    }
                    return@launch
                }

                val ownPrefix = ownPackagePrefix(packageName)
                val prefixes = sortedSetOf<String>()

                for (apkPath in apkPaths) {
                    val apkFile = File(apkPath)
                    if (!apkFile.canRead()) {
                        Log.d(TAG, "APK not readable: $apkPath")
                        continue
                    }
                    try {
                        ZipFile(apkFile).use { zip ->
                            val entries = zip.entries()
                            while (entries.hasMoreElements()) {
                                if (prefixes.size >= MAX_PREFIXES) break
                                val entry = entries.nextElement()
                                val name = entry.name
                                when {
                                    name.startsWith("classes") && name.endsWith(".dex") -> {
                                        if (entry.size in 1..MAX_DEX_BYTES) {
                                            val bytes = zip.getInputStream(entry).readBytes()
                                            extractDexPackagePrefixes(bytes, ownPrefix, prefixes)
                                        } else {
                                            Log.w(TAG, "Skipping oversized dex ${entry.name} (${entry.size} bytes)")
                                        }
                                    }
                                    name.startsWith("lib/") && name.endsWith(".so") -> {
                                        val libName = name.substringAfterLast('/')
                                        KNOWN_NATIVE_LIBS[libName]?.let { prefixes.add(it) }
                                    }
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed reading APK $apkPath: ${e.message}")
                    }
                }

                withContext(Dispatchers.Main) {
                    result.success(prefixes.toList())
                }
            } catch (e: PackageManager.NameNotFoundException) {
                withContext(Dispatchers.Main) {
                    result.error("NOT_FOUND", "Package not installed: $packageName", null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "getAppLibraries failed for $packageName", e)
                withContext(Dispatchers.Main) {
                    result.error("NATIVE_ERROR", "Library extraction failed: ${e.message}", null)
                }
            }
        }
    }

    /** First two segments of the scanned app's own package (excluded from results). */
    private fun ownPackagePrefix(packageName: String): String {
        val segments = packageName.split('.')
        return if (segments.size >= 2) "${segments[0]}.${segments[1]}" else packageName
    }

    // ------------------------------------------------------------------
    // Minimal DEX type-table reader
    // ------------------------------------------------------------------

    /**
     * Walks the DEX type_ids table and resolves each class descriptor from the
     * string pool, collecting 2-3 segment package prefixes. Reads only the
     * strings referenced by type_ids (class descriptors), not the full pool.
     */
    private fun extractDexPackagePrefixes(
        dex: ByteArray,
        ownPrefix: String,
        out: MutableSet<String>
    ) {
        if (dex.size < 0x70) return
        // Magic: "dex\n0xx\0"
        if (!(dex[0] == 'd'.code.toByte() && dex[1] == 'e'.code.toByte() &&
                dex[2] == 'x'.code.toByte() && dex[3] == 0x0A.toByte())
        ) {
            return
        }

        fun u4(off: Int): Int {
            if (off < 0 || off + 4 > dex.size) return -1
            return (dex[off].toInt() and 0xFF) or
                ((dex[off + 1].toInt() and 0xFF) shl 8) or
                ((dex[off + 2].toInt() and 0xFF) shl 16) or
                ((dex[off + 3].toInt() and 0xFF) shl 24)
        }

        val stringIdsSize = u4(0x38)
        val stringIdsOff = u4(0x3C)
        val typeIdsSize = u4(0x40)
        val typeIdsOff = u4(0x44)
        if (stringIdsSize <= 0 || stringIdsOff <= 0 || typeIdsSize <= 0 || typeIdsOff <= 0) return

        for (i in 0 until typeIdsSize) {
            if (out.size >= MAX_PREFIXES) return
            val descriptorIdx = u4(typeIdsOff + i * 4)
            if (descriptorIdx < 0 || descriptorIdx >= stringIdsSize) continue
            val dataOff = u4(stringIdsOff + descriptorIdx * 4)
            if (dataOff <= 0 || dataOff >= dex.size) continue

            val descriptor = readDexString(dex, dataOff) ?: continue
            packagePrefixFromDescriptor(descriptor, ownPrefix)?.let { out.add(it) }
        }
    }

    /** Reads a string_data_item: uleb128 utf16 length followed by MUTF-8 bytes. */
    private fun readDexString(dex: ByteArray, offset: Int): String? {
        var off = offset
        // Skip uleb128 length.
        var guard = 0
        while (off < dex.size) {
            val b = dex[off].toInt() and 0xFF
            off++
            if (b and 0x80 == 0) break
            if (++guard > 5) return null
        }
        if (off >= dex.size) return null
        // Class descriptors are ASCII; read until NUL with a sanity cap.
        val sb = StringBuilder()
        var i = off
        while (i < dex.size && sb.length < 512) {
            val b = dex[i].toInt() and 0xFF
            if (b == 0) break
            if (b in 0x20..0x7E) {
                sb.append(b.toChar())
            } else {
                // Non-ASCII descriptor — not a package-bearing class name.
                return null
            }
            i++
        }
        return sb.toString()
    }

    /**
     * Lcom/google/firebase/analytics/Foo; -> com.google.firebase
     * Returns null for primitives, arrays, framework classes, the app's own
     * classes, and minified (single-letter) packages.
     */
    private fun packagePrefixFromDescriptor(descriptor: String, ownPrefix: String): String? {
        if (descriptor.length < 4 || descriptor[0] != 'L' || !descriptor.endsWith(";")) return null
        val inner = descriptor.substring(1, descriptor.length - 1)
        if (!inner.contains('/')) return null

        val segments = inner.split('/')
        // Last segment is the class name; need at least 2 package segments.
        if (segments.size < 3) return null

        val first = segments[0]
        if (first in EXCLUDED_FIRST_SEGMENTS) return null
        // Minified/obfuscated packages (single-letter roots) are not
        // identifiable — skip rather than report noise.
        if (first.length < 2 || segments[1].length < 2) return null

        val depth = minOf(3, segments.size - 1)
        val prefix = segments.subList(0, depth).joinToString(".")
        if (prefix == ownPrefix || prefix.startsWith("$ownPrefix.")) return null
        return prefix
    }
}
