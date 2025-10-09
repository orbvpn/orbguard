// MainActivity.kt - Cleaned up version that uses separate files
// Location: android/app/src/main/kotlin/com/orb/guard/MainActivity.kt

package com.orb.guard

import android.content.Context
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.defense.antispyware/system"
    private var elevatedAccess: ElevatedAccessManager? = null
    private var spywareScanner: SpywareScanner? = null
    
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize elevated access manager
        elevatedAccess = ElevatedAccessManager(this)
        
        // Initialize spyware scanner
        spywareScanner = SpywareScanner(this, elevatedAccess!!)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "checkRootAccess" -> {
                    val hasElevated = elevatedAccess!!.checkElevatedAccess()
                    val accessLevel = when {
                        elevatedAccess!!.hasRoot -> "Root"
                        elevatedAccess!!.hasShell -> "Shell"
                        else -> "Standard"
                    }
                    result.success(mapOf(
                        "hasRoot" to hasElevated,
                        "accessLevel" to accessLevel,
                        "method" to elevatedAccess!!.accessMethod
                    ))
                }
                
                "initializeScan" -> {
                    val deepScan = call.argument<Boolean>("deepScan") ?: false
                    val hasRoot = call.argument<Boolean>("hasRoot") ?: false
                    spywareScanner!!.initialize(deepScan, elevatedAccess!!.hasElevatedAccess())
                    result.success(true)
                }
                
                "scanNetwork" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val threats = spywareScanner!!.scanNetwork()
                            withContext(Dispatchers.Main) {
                                result.success(mapOf("threats" to threats))
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("SCAN_ERROR", e.message, null)
                            }
                        }
                    }
                }
                
                "scanProcesses" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val threats = spywareScanner!!.scanProcesses()
                            withContext(Dispatchers.Main) {
                                result.success(mapOf("threats" to threats))
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("SCAN_ERROR", e.message, null)
                            }
                        }
                    }
                }
                
                "scanFileSystem" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val threats = spywareScanner!!.scanFileSystem()
                            withContext(Dispatchers.Main) {
                                result.success(mapOf("threats" to threats))
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("SCAN_ERROR", e.message, null)
                            }
                        }
                    }
                }
                
                "scanDatabases" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val threats = spywareScanner!!.scanDatabases()
                            withContext(Dispatchers.Main) {
                                result.success(mapOf("threats" to threats))
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("SCAN_ERROR", e.message, null)
                            }
                        }
                    }
                }
                
                "scanMemory" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val threats = spywareScanner!!.scanMemory()
                            withContext(Dispatchers.Main) {
                                result.success(mapOf("threats" to threats))
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("SCAN_ERROR", e.message, null)
                            }
                        }
                    }
                }
                
                "removeThreat" -> {
                    val id = call.argument<String>("id")
                    val type = call.argument<String>("type")
                    val path = call.argument<String>("path")
                    val requiresRoot = call.argument<Boolean>("requiresRoot") ?: false
                    
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val success = spywareScanner!!.removeThreat(
                                id!!, 
                                type!!, 
                                path!!, 
                                requiresRoot
                            )
                            withContext(Dispatchers.Main) {
                                result.success(mapOf("success" to success))
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("REMOVAL_ERROR", e.message, null)
                            }
                        }
                    }
                }
                
                else -> result.notImplemented()
            }
        }
    }
}