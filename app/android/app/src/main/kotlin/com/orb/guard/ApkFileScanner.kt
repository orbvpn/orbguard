package com.orb.guard

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.security.MessageDigest

/**
 * Scans APK files the USER explicitly picks (SAF / file picker) for risk signals.
 *
 * Deliberately scoped: it only ever reads the exact files handed to it, so it needs
 * NO all-files (MANAGE_EXTERNAL_STORAGE) access. Sideloaded APKs in Downloads are
 * the realistic Android malware vector, and PackageManager can fully inspect an APK
 * from disk without installing it.
 *
 * Everything here is local — no file contents leave the device.
 */
class ApkFileScanner(private val context: Context) {

    /** Permission combinations that, together, indicate spyware/stalkerware intent. */
    private val spywareCombos: List<Pair<String, List<String>>> = listOf(
        "Message exfiltration" to listOf(
            "android.permission.READ_SMS", "android.permission.INTERNET"
        ),
        "Call recording" to listOf(
            "android.permission.RECORD_AUDIO", "android.permission.READ_CALL_LOG"
        ),
        "Covert location tracking" to listOf(
            "android.permission.ACCESS_BACKGROUND_LOCATION", "android.permission.INTERNET"
        ),
        "Contact harvesting" to listOf(
            "android.permission.READ_CONTACTS", "android.permission.INTERNET"
        ),
        "Screen/keystroke capture" to listOf(
            "android.permission.BIND_ACCESSIBILITY_SERVICE"
        ),
        "Silent install / self-update" to listOf(
            "android.permission.REQUEST_INSTALL_PACKAGES"
        ),
    )

    /** Individually high-risk permissions worth surfacing. */
    private val highRiskPermissions = setOf(
        "android.permission.READ_SMS",
        "android.permission.RECEIVE_SMS",
        "android.permission.READ_CALL_LOG",
        "android.permission.RECORD_AUDIO",
        "android.permission.CAMERA",
        "android.permission.ACCESS_BACKGROUND_LOCATION",
        "android.permission.REQUEST_INSTALL_PACKAGES",
        "android.permission.SYSTEM_ALERT_WINDOW",
        "android.permission.PACKAGE_USAGE_STATS",
    )

    /**
     * Analyse one APK at [path]. Returns a result map (never throws) describing the
     * package and any findings. `error` is set when the file can't be parsed.
     */
    fun scanApk(path: String): Map<String, Any?> {
        val file = File(path)
        if (!file.exists() || !file.canRead()) {
            return mapOf("path" to path, "error" to "File not readable")
        }

        val flags = PackageManager.GET_PERMISSIONS or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                PackageManager.GET_SIGNING_CERTIFICATES else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES)

        val info: PackageInfo = try {
            context.packageManager.getPackageArchiveInfo(path, flags)
                ?: return mapOf("path" to path, "error" to "Not a valid APK")
        } catch (e: Exception) {
            return mapOf("path" to path, "error" to "Could not parse APK: ${e.message}")
        }

        val requested = info.requestedPermissions?.toList() ?: emptyList()
        val findings = mutableListOf<Map<String, Any>>()

        // 1. Spyware-style permission combinations.
        for ((label, combo) in spywareCombos) {
            if (combo.all { requested.contains(it) }) {
                findings.add(
                    mapOf(
                        "type" to "permission_combo",
                        "severity" to "HIGH",
                        "title" to label,
                        "detail" to "Requests: ${combo.joinToString(", ") { it.substringAfterLast('.') }}"
                    )
                )
            }
        }

        // 2. Individually high-risk permissions.
        val risky = requested.filter { highRiskPermissions.contains(it) }
        if (risky.isNotEmpty()) {
            findings.add(
                mapOf(
                    "type" to "high_risk_permissions",
                    "severity" to if (risky.size >= 4) "HIGH" else "MEDIUM",
                    "title" to "${risky.size} high-risk permission(s)",
                    "detail" to risky.joinToString(", ") { it.substringAfterLast('.') }
                )
            )
        }

        // 3. Debug-signed APK — never legitimate for a distributed app.
        val signerSha = signerSha256(info)
        if (isDebugSigned(info)) {
            findings.add(
                mapOf(
                    "type" to "debug_signed",
                    "severity" to "HIGH",
                    "title" to "Signed with a debug key",
                    "detail" to "Distributed apps are never debug-signed; this is untrusted."
                )
            )
        }

        // 4. Already installed under the same package but a DIFFERENT signer =
        //    classic app-impersonation / update-hijack attempt.
        val installedSigner = installedSignerSha256(info.packageName)
        if (installedSigner != null && signerSha != null && installedSigner != signerSha) {
            findings.add(
                mapOf(
                    "type" to "signer_mismatch",
                    "severity" to "CRITICAL",
                    "title" to "Impersonates an installed app",
                    "detail" to "Same package name as an installed app but a different signing certificate."
                )
            )
        }

        val severity = when {
            findings.any { it["severity"] == "CRITICAL" } -> "CRITICAL"
            findings.any { it["severity"] == "HIGH" } -> "HIGH"
            findings.any { it["severity"] == "MEDIUM" } -> "MEDIUM"
            else -> "CLEAN"
        }

        return mapOf(
            "path" to path,
            "fileName" to file.name,
            "sizeBytes" to file.length(),
            "packageName" to info.packageName,
            "versionName" to (info.versionName ?: ""),
            "appLabel" to appLabel(info),
            "signerSha256" to (signerSha ?: ""),
            "permissionCount" to requested.size,
            "severity" to severity,
            "findings" to findings
        )
    }

    /** Analyse several APKs; results in the same order. */
    fun scanApks(paths: List<String>): List<Map<String, Any?>> = paths.map { scanApk(it) }

    private fun appLabel(info: PackageInfo): String = try {
        info.applicationInfo?.let {
            // The archive's resources aren't loaded, so fall back to the package name.
            context.packageManager.getApplicationLabel(it).toString()
        } ?: info.packageName
    } catch (_: Exception) {
        info.packageName
    }

    @Suppress("DEPRECATION")
    private fun signatures(info: PackageInfo): Array<android.content.pm.Signature>? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.let {
                if (it.hasMultipleSigners()) it.apkContentsSigners else it.signingCertificateHistory
            }
        } else {
            info.signatures
        }

    private fun signerSha256(info: PackageInfo): String? = try {
        signatures(info)?.firstOrNull()?.let { sig ->
            MessageDigest.getInstance("SHA-256").digest(sig.toByteArray())
                .joinToString("") { "%02x".format(it) }
        }
    } catch (_: Exception) {
        null
    }

    private fun installedSignerSha256(pkg: String): String? = try {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
            PackageManager.GET_SIGNING_CERTIFICATES else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
        val installed = context.packageManager.getPackageInfo(pkg, flags)
        signerSha256(installed)
    } catch (_: Exception) {
        null // not installed
    }

    /** Android's debug keystore always uses CN=Android Debug. */
    private fun isDebugSigned(info: PackageInfo): Boolean = try {
        signatures(info)?.any { sig ->
            val cf = java.security.cert.CertificateFactory.getInstance("X.509")
            val cert = cf.generateCertificate(sig.toByteArray().inputStream())
                as java.security.cert.X509Certificate
            cert.subjectX500Principal.name.contains("CN=Android Debug", ignoreCase = true)
        } ?: false
    } catch (_: Exception) {
        false
    }
}
