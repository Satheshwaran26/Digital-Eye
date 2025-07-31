package com.example.my_app

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayList
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val CHANNEL = "app_blocker"
    private val WIDGET_CHANNEL = "app_blocker/widget"
    private lateinit var methodChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put("my_flutter_engine", flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkUsageStatsPermission" -> {
                    result.success(checkUsageStatsPermission())
                }
                "requestUsageStatsPermission" -> {
                    requestUsageStatsPermission()
                    result.success(null)
                }
                "checkOverlayPermission" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }
                "checkQueryAllPackagesPermission" -> {
                    result.success(true)
                }
                "testMonitoring" -> {
                    val hasUsagePermission = checkUsageStatsPermission()
                    val hasOverlayPermission = Settings.canDrawOverlays(this)
                    val diagnostics = mapOf(
                        "usageStatsPermission" to hasUsagePermission,
                        "overlayPermission" to hasOverlayPermission,
                        "sdkVersion" to Build.VERSION.SDK_INT,
                        "packageName" to packageName
                    )
                    println("Native: Diagnostics - $diagnostics")
                    result.success(diagnostics)
                }
                "startMonitoring" -> {
                    val packageNames = call.argument<List<String>>("packageNames")
                    val durationSeconds = call.argument<Int>("durationSeconds")
                    if (packageNames != null && durationSeconds != null) {
                        requestBatteryOptimizationExemption()
                        val serviceIntent = Intent(this, AppMonitoringService::class.java).apply {
                            action = AppMonitoringService.ACTION_START_MONITORING
                            putStringArrayListExtra(AppMonitoringService.EXTRA_PACKAGE_NAMES, ArrayList(packageNames))
                            putExtra(AppMonitoringService.EXTRA_DURATION_SECONDS, durationSeconds)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        println("Native: Started AppMonitoringService for apps: $packageNames for $durationSeconds seconds")
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Package names and duration are required", null)
                    }
                }
                "lockAppsNow" -> {
                    val packageNames = call.argument<List<String>>("packageNames")
                    if (packageNames != null) {
                        val serviceIntent = Intent(this, AppMonitoringService::class.java).apply {
                            action = AppMonitoringService.ACTION_LOCK_APPS_NOW
                            putStringArrayListExtra(AppMonitoringService.EXTRA_PACKAGE_NAMES, ArrayList(packageNames))
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        println("Native: Sent lockAppsNow command to service for apps: $packageNames")
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Package names are required to lock", null)
                    }
                }
                "unlockApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        val serviceIntent = Intent(this, AppMonitoringService::class.java).apply {
                            action = AppMonitoringService.ACTION_UNLOCK_APP
                            putExtra(AppMonitoringService.EXTRA_PACKAGE_NAME, packageName)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        println("Native: Sent unlockApp command to service for app: $packageName")
                        result.success(true)
                    } else {
                        result.error("INVALID_PACKAGE", "Package not found for unlock", null)
                    }
                }
                "stopMonitoring" -> {
                    val serviceIntent = Intent(this, AppMonitoringService::class.java).apply {
                        action = AppMonitoringService.ACTION_STOP_MONITORING
                    }
                    startService(serviceIntent)
                    println("Native: Sent stop monitoring command to service")
                    result.success(true)
                }
                "getTimerStatus" -> {
                    try {
                        val sharedPreferences = getSharedPreferences("app_blocker_prefs", Context.MODE_PRIVATE)
                        val remainingSeconds = sharedPreferences.getInt("remaining_seconds", 0)
                        val isMonitoringActive = sharedPreferences.getBoolean("monitoring_active", false)
                        val currentAppName = sharedPreferences.getString("current_foreground_app", "")
                        
                        val status = mapOf(
                            "remainingSeconds" to remainingSeconds,
                            "isMonitoringActive" to isMonitoringActive,
                            "appName" to (currentAppName ?: "")
                        )
                        
                        println("Native: Returning timer status - remaining: $remainingSeconds, active: $isMonitoringActive, app: $currentAppName")
                        result.success(status)
                    } catch (e: Exception) {
                        println("Native: Error getting timer status: ${e.message}")
                        result.error("TIMER_STATUS_ERROR", "Failed to get timer status", e.message)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getUsageData") {
                result.success(emptyList<Map<String, Any>>())
            } else {
                result.notImplemented()
            }
        }
    }

    private fun checkUsageStatsPermission(): Boolean {
        val appOps = getSystemService(APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun requestUsageStatsPermission() {
        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
    }

    private fun requestOverlayPermission() {
        if (!Settings.canDrawOverlays(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                android.net.Uri.parse("package:$packageName")
            )
            startActivity(intent)
        }
    }

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                try {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    println("Native: Requested battery optimization exemption")
                } catch (e: Exception) {
                    println("Native: Failed to request battery optimization exemption: ${e.message}")
                    try {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        startActivity(intent)
                    } catch (e2: Exception) {
                        println("Native: Failed to open battery optimization settings: ${e2.message}")
                    }
                }
            } else {
                println("Native: Battery optimization already disabled")
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        // Remove FlutterEngine from cache to prevent memory leaks
        FlutterEngineCache.getInstance().remove("my_flutter_engine")
        println("Native: MainActivity onDestroy. Service continues running.")
        // Removed the stop command to allow AppMonitoringService to persist
    }
}