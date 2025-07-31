package com.example.my_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("BootReceiver", "Received broadcast: ${intent.action}")
        
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_PACKAGE_REPLACED -> {
                Log.d("BootReceiver", "Device booted or app updated, checking for active monitoring")
                
                // Check if there was an active monitoring session or blocking session
                val sharedPrefs = context.getSharedPreferences("app_blocker_prefs", Context.MODE_PRIVATE)
                val isMonitoringActive = sharedPrefs.getBoolean("monitoring_active", false)
                val isBlockingActive = sharedPrefs.getBoolean("blocking_active", false)
                
                if (isMonitoringActive || isBlockingActive) {
                    Log.d("BootReceiver", "Restarting monitoring service after boot/update")
                    
                    // Get stored monitoring data
                    val packageNames = sharedPrefs.getStringSet("monitored_packages", emptySet())?.toList() ?: emptyList()
                    val remainingSeconds = sharedPrefs.getInt("remaining_seconds", 0)
                    val totalUsedSeconds = sharedPrefs.getInt("total_used_seconds", 0)
                    val originalDuration = sharedPrefs.getInt("original_duration", 0)
                    
                    if (packageNames.isNotEmpty() && (remainingSeconds > 0 || isBlockingActive)) {
                        // Restart the monitoring service (or blocking service)
                        val serviceIntent = Intent(context, AppMonitoringService::class.java).apply {
                            action = AppMonitoringService.ACTION_START_MONITORING
                            putStringArrayListExtra(AppMonitoringService.EXTRA_PACKAGE_NAMES, ArrayList(packageNames))
                            putExtra(AppMonitoringService.EXTRA_DURATION_SECONDS, if (isBlockingActive) 0 else remainingSeconds)
                            putExtra("total_used_seconds", totalUsedSeconds)
                            putExtra("original_duration", originalDuration)
                            putExtra("restore_blocking", isBlockingActive)
                        }
                        
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                context.startForegroundService(serviceIntent)
                            } else {
                                context.startService(serviceIntent)
                            }
                            Log.d("BootReceiver", "Successfully restarted monitoring service")
                        } catch (e: Exception) {
                            Log.e("BootReceiver", "Failed to restart monitoring service: ${e.message}")
                        }
                    }
                }
            }
        }
    }
} 