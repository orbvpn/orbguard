// ElevatedAccessManager.kt
// Location: android/app/src/main/kotlin/com/orb/guard/ElevatedAccessManager.kt

package com.orb.guard

import android.content.Context
import java.io.BufferedReader
import java.io.DataOutputStream
import java.io.File
import java.io.InputStreamReader

/**
 * Manages elevated access to Android system using multiple methods:
 * 1. Root access (su binary)
 * 2. Shell access (ADB shell privileges - Shizuku method)
 * 3. AppProcess access (system services)
 * 
 * Automatically detects and uses the highest available privilege level.
 */
class ElevatedAccessManager(private val context: Context) {
    
    var hasRoot = false
        private set
    
    var hasShell = false
        private set
    
    var accessMethod = "None"
        private set
    
    /**
     * Check for elevated access using multiple methods
     * Returns true if any elevated access method is available
     */
    fun checkElevatedAccess(): Boolean {
        // Try multiple methods in order of preference
        
        // Method 1: Check for root access (highest privilege)
        if (checkRootAccess()) {
            hasRoot = true
            hasShell = true
            accessMethod = "Root"
            return true
        }
        
        // Method 2: Use shell user access (Shizuku method)
        if (checkShellAccess()) {
            hasShell = true
            accessMethod = "Shell"
            return true
        }
        
        // Method 3: Use app_process for system services
        if (checkAppProcessAccess()) {
            hasShell = true
            accessMethod = "AppProcess"
            return true
        }
        
        accessMethod = "Standard"
        return false
    }
    
    /**
     * Check if we have any form of elevated access
     */
    fun hasElevatedAccess(): Boolean {
        return hasRoot || hasShell
    }
    
    /**
     * Check for root access by looking for su binary and testing execution
     */
    private fun checkRootAccess(): Boolean {
        val paths = arrayOf(
            "/system/xbin/su",
            "/system/bin/su",
            "/sbin/su",
            "/vendor/bin/su",
            "/system/su",
            "/su/bin/su"
        )
        
        // First check if su binary exists
        for (path in paths) {
            if (File(path).exists()) {
                try {
                    // Try to execute su command
                    val process = Runtime.getRuntime().exec("su")
                    val writer = DataOutputStream(process.outputStream)
                    
                    // Test if we actually have root by checking UID
                    writer.writeBytes("id\n")
                    writer.writeBytes("exit\n")
                    writer.flush()
                    
                    val reader = BufferedReader(InputStreamReader(process.inputStream))
                    val output = reader.readLine()
                    
                    process.waitFor()
                    
                    // If output contains uid=0, we have root
                    if (output?.contains("uid=0") == true) {
                        return true
                    }
                } catch (e: Exception) {
                    // Root access denied or su binary doesn't work
                    continue
                }
            }
        }
        return false
    }
    
    /**
     * Check for shell user access (uid=2000)
     * This is how Shizuku works - using ADB shell privileges
     */
    private fun checkShellAccess(): Boolean {
        try {
            val process = Runtime.getRuntime().exec("sh")
            val writer = DataOutputStream(process.outputStream)
            writer.writeBytes("id\n")
            writer.writeBytes("exit\n")
            writer.flush()
            
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = reader.readLine()
            
            process.waitFor()
            
            // Check if we have shell user access (uid=2000) or higher
            // Note: This will return true even for app UID, so not a real elevated check
            // Real Shizuku would use binder IPC to a privileged service
            if (output?.contains("uid=") == true) {
                val uidMatch = Regex("uid=(\\d+)").find(output)
                val uid = uidMatch?.groupValues?.get(1)?.toIntOrNull()
                
                // Shell user is uid=2000, root is uid=0
                // App UIDs are typically 10000+
                return uid != null && uid < 10000
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }
    
    /**
     * Try using app_process to access system services
     * Alternative method similar to Shizuku
     */
    private fun checkAppProcessAccess(): Boolean {
        try {
            val process = Runtime.getRuntime().exec(arrayOf(
                "sh", "-c",
                "app_process / --version 2>&1"
            ))
            
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = reader.readLine()
            
            process.waitFor()
            
            // If app_process responds, we might be able to use it
            if (output != null && !output.contains("not found")) {
                return true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }
    
    /**
     * Execute command with elevated privileges
     * Returns command output or null if failed
     */
    fun executeCommand(command: String): String? {
        try {
            if (hasRoot) {
                return executeRootCommand(command)
            } else if (hasShell) {
                return executeShellCommand(command)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return null
    }
    
    /**
     * Execute command as root
     */
    private fun executeRootCommand(command: String): String? {
        try {
            val process = Runtime.getRuntime().exec("su")
            val writer = DataOutputStream(process.outputStream)
            
            writer.writeBytes("$command\n")
            writer.writeBytes("exit\n")
            writer.flush()
            
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = StringBuilder()
            var line: String?
            
            while (reader.readLine().also { line = it } != null) {
                output.append(line).append("\n")
            }
            
            process.waitFor()
            return output.toString()
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }
    
    /**
     * Execute command with shell access
     */
    private fun executeShellCommand(command: String): String? {
        try {
            val process = Runtime.getRuntime().exec(arrayOf("sh", "-c", command))
            
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val errorReader = BufferedReader(InputStreamReader(process.errorStream))
            val output = StringBuilder()
            var line: String?
            
            while (reader.readLine().also { line = it } != null) {
                output.append(line).append("\n")
            }
            
            // Also capture error stream
            while (errorReader.readLine().also { line = it } != null) {
                output.append(line).append("\n")
            }
            
            process.waitFor()
            return output.toString()
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }
    
    /**
     * Read system file using elevated access
     */
    fun readSystemFile(path: String): String? {
        return executeCommand("cat '$path'")
    }
    
    /**
     * Execute package manager (pm) commands
     */
    fun pmCommand(args: String): String? {
        return executeCommand("pm $args")
    }
    
    /**
     * Execute dumpsys commands
     */
    fun dumpsys(service: String): String? {
        return executeCommand("dumpsys $service")
    }
    
    /**
     * Get process list
     */
    fun getProcessList(): String? {
        return executeCommand("ps -A")
    }
    
    /**
     * Get network connections
     */
    fun getNetstat(): String? {
        // Try both locations
        val tcp = executeCommand("cat /proc/net/tcp")
        val tcp6 = executeCommand("cat /proc/net/tcp6")
        
        return if (tcp != null && tcp6 != null) {
            "$tcp\n$tcp6"
        } else {
            tcp ?: tcp6
        }
    }
    
    /**
     * List files in directory with details
     */
    fun listFiles(path: String): String? {
        return executeCommand("ls -la '$path'")
    }
    
    /**
     * Delete file or directory
     */
    fun deleteFile(path: String): Boolean {
        val result = executeCommand("rm -rf '$path'")
        return result != null && !result.contains("cannot remove")
    }
    
    /**
     * Kill process by name
     */
    fun killProcess(processName: String): Boolean {
        val result = executeCommand("killall '$processName'")
        return result != null
    }
    
    /**
     * Kill process by PID
     */
    fun killProcessByPid(pid: String): Boolean {
        val result = executeCommand("kill -9 $pid")
        return result != null
    }
    
    /**
     * Check if file exists
     */
    fun fileExists(path: String): Boolean {
        val result = executeCommand("test -e '$path' && echo 'exists'")
        return result?.contains("exists") == true
    }
    
    /**
     * Get file information
     */
    fun getFileInfo(path: String): String? {
        return executeCommand("stat '$path'")
    }
    
    /**
     * Find files matching pattern
     */
    fun findFiles(startPath: String, pattern: String): String? {
        return executeCommand("find '$startPath' -name '$pattern' 2>/dev/null")
    }
    
    /**
     * Execute SQL query on SQLite database
     */
    fun sqliteQuery(dbPath: String, query: String): String? {
        return executeCommand("sqlite3 '$dbPath' \"$query\" 2>/dev/null")
    }
    
    /**
     * Get system property
     */
    fun getSystemProperty(property: String): String? {
        return executeCommand("getprop $property")
    }
    
    /**
     * Set system property (requires root)
     */
    fun setSystemProperty(property: String, value: String): Boolean {
        if (!hasRoot) return false
        val result = executeCommand("setprop $property $value")
        return result != null
    }
    
    /**
     * Mount filesystem as read-write (requires root)
     */
    fun mountRW(path: String): Boolean {
        if (!hasRoot) return false
        val result = executeCommand("mount -o rw,remount $path")
        return result != null && !result.contains("failed")
    }
    
    /**
     * Mount filesystem as read-only (requires root)
     */
    fun mountRO(path: String): Boolean {
        if (!hasRoot) return false
        val result = executeCommand("mount -o ro,remount $path")
        return result != null && !result.contains("failed")
    }
}