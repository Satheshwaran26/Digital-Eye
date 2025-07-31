package com.example.my_app

import android.Manifest
import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import androidx.annotation.RequiresApi
import androidx.annotation.RequiresPermission
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.concurrent.TimeUnit
import java.util.Date
import java.util.Locale

class AppMonitoringService : Service() {

    private val CHANNEL = "app_blocker"
    private lateinit var methodChannel: MethodChannel
    private lateinit var wakeLock: PowerManager.WakeLock
    private lateinit var sharedPreferences: SharedPreferences

    // Service state variables
    private var isMonitoring = false
    private var monitoredPackages: MutableSet<String> = mutableSetOf()
    private var isBlocking = false
    private var startTime: Long = 0
    private var totalDurationSeconds: Int = 0
    private var has50PercentNotified = false
    private var has70PercentNotified = false
    private var has30PercentNotified = false
    // Variables for tracking actual usage time (only when using selected apps)
    private var totalUsedSeconds: Int = 0
    private var currentSessionStartTime: Long = 0
    private var isCurrentlyUsingSelectedApp = false
    
    // Day-by-day reset variables
    private var lastResetDate: String = ""
    private var sessionCompletedToday: Boolean = false

    private val handler = Handler(Looper.getMainLooper())
    private val checkInterval: Long = 1000
    private var lastUpdateTime: Long = 0
    private var lastForceUpdateTime: Long = 0
    private val updateThrottleMs: Long = 2000 // Throttle non-critical updates to 2 seconds
    private val forceUpdateIntervalMs: Long = 3000 // Force update every 3 seconds for countdown
    
    // Separate handler for notification updates
    private val notificationHandler = Handler(Looper.getMainLooper())
    private val notificationUpdateInterval: Long = 1000 // Update notification every second
    
    // Notification IDs and Channels
    private val NOTIFICATION_CHANNEL_ID = "app_blocker_service_channel"
    private val ALERT_CHANNEL_ID = "app_blocker_alert_channel"
    private val SERVICE_NOTIFICATION_ID = 101
    private val ALERT_NOTIFICATION_ID = 102

    private lateinit var activityManager: ActivityManager

    companion object {
        const val ACTION_START_MONITORING = "START_MONITORING"
        const val ACTION_STOP_MONITORING = "STOP_MONITORING"
        const val ACTION_LOCK_APPS_NOW = "LOCK_APPS_NOW"
        const val ACTION_UNLOCK_APP = "UNLOCK_APP"
        const val EXTRA_PACKAGE_NAMES = "PACKAGE_NAMES"
        const val EXTRA_DURATION_SECONDS = "DURATION_SECONDS"
        const val EXTRA_PACKAGE_NAME = "PACKAGE_NAME"
        const val EXTRA_APP_NAME = "APP_NAME"
    }

    override fun onCreate() {
        super.onCreate()
        println("Service: onCreate")
        activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        sharedPreferences = getSharedPreferences("app_blocker_prefs", Context.MODE_PRIVATE)

        // Initialize WakeLock
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "AppBlocker::MonitoringWakeLock"
        )

        val flutterEngine: FlutterEngine? = FlutterEngineCache.getInstance().get("my_flutter_engine")
        if (flutterEngine != null) {
            methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        } else {
            println("Service: FlutterEngine not found in cache - creating minimal notification service")
            // Continue service without Flutter channel for persistence
        }

        createNotificationChannels()
        loadDailyResetState() // Load daily reset state on service start
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        println("Service: onStartCommand, action: ${intent?.action}")

        when (intent?.action) {
            ACTION_START_MONITORING -> {
                val packageNames = intent.getStringArrayListExtra(EXTRA_PACKAGE_NAMES)
                val durationSeconds = intent.getIntExtra(EXTRA_DURATION_SECONDS, 0)
                
                if (packageNames != null && durationSeconds > 0) {
                    monitoredPackages.clear()
                    monitoredPackages.addAll(packageNames)
                    totalDurationSeconds = durationSeconds
                    startTime = System.currentTimeMillis()
                    has50PercentNotified = false
                    has70PercentNotified = false
                    has30PercentNotified = false
                    isBlocking = false
                    
                    // Check if this is a restart from boot/update
                    val restoredUsedSeconds = intent.getIntExtra("total_used_seconds", 0)
                    val originalDuration = intent.getIntExtra("original_duration", 0)
                    val restoreBlocking = intent.getBooleanExtra("restore_blocking", false)
                    
                    // Reset usage tracking variables
                    totalUsedSeconds = restoredUsedSeconds
                    if (originalDuration > 0) {
                        totalDurationSeconds = originalDuration
                    }
                    currentSessionStartTime = 0
                    isCurrentlyUsingSelectedApp = false
                    lastUpdateTime = 0
                    lastForceUpdateTime = 0
                    
                    // If restoring blocking state, immediately activate blocking
                    if (restoreBlocking) {
                        println("Service: 🔒 RESTORING BLOCKING STATE after boot/restart")
                        isBlocking = true
                        isMonitoring = false
                        startAppBlockingLoop()
                        
                        // Immediately check and block any currently running monitored apps
                        val currentApp = getCurrentForegroundApp()
                        if (currentApp != null && monitoredPackages.contains(currentApp)) {
                            println("Service: 🚨 Found blocked app $currentApp running after boot - BLOCKING")
                            emergencyAppShutdown(currentApp)
                        }
                    }
                    
                    // Save monitoring state
                    saveMonitoringState()
                    
                    // Acquire WakeLock for longer duration to ensure service stays active
                    if (!wakeLock.isHeld) {
                        wakeLock.acquire(TimeUnit.SECONDS.toMillis((durationSeconds + 300).toLong()))
                    }
                    
                    // Start as foreground service with persistent notification
                    startForeground(SERVICE_NOTIFICATION_ID, createServiceNotification())
                    
                    if (!isMonitoring) {
                        startMonitoringLoop()
                        startNotificationUpdateLoop()
                    }
                    
                    println("Service: ✅ Monitoring started for ${packageNames.size} apps, duration: ${durationSeconds}s, used: ${totalUsedSeconds}s")
                }
            }
            ACTION_STOP_MONITORING -> {
                stopMonitoringLoop()
            }
        }
        // Return START_STICKY to ensure the service restarts if killed
        return START_STICKY
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "App Blocker Timer",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Shows real-time countdown for app usage limit"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            val alertChannel = NotificationChannel(
                ALERT_CHANNEL_ID,
                "App Blocker Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Time limit notifications"
                enableVibration(true)
                setShowBadge(true)
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
            manager.createNotificationChannel(alertChannel)
        }
    }

    private fun createServiceNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 0, notificationIntent, pendingIntentFlags)

        val currentTotalUsed = if (isCurrentlyUsingSelectedApp && currentSessionStartTime > 0) {
            val currentSessionTime = (System.currentTimeMillis() - currentSessionStartTime) / 1000
            totalUsedSeconds + currentSessionTime.toInt()
        } else {
            totalUsedSeconds
        }
        
        val remainingSeconds = maxOf(0, totalDurationSeconds - currentTotalUsed)
        val timeText = formatTime(remainingSeconds)
        val usedText = formatTime(currentTotalUsed)
        val totalText = formatTime(totalDurationSeconds)
        
        val title = if (isCurrentlyUsingSelectedApp) {
            "⏱️ ACTIVE: $timeText left"
        } else {
            "⏸️ PAUSED: $timeText left"
        }
        
        val contentText = if (isCurrentlyUsingSelectedApp) {
            "Used: $usedText / $totalText | ${monitoredPackages.size} apps monitored"
        } else {
            "Used: $usedText / $totalText | Open monitored app to continue"
        }

        // Add stop action
        val stopIntent = Intent(this, AppMonitoringService::class.java).apply {
            action = ACTION_STOP_MONITORING
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent, 
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(false)
            .setLocalOnly(false)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPendingIntent)
            .setStyle(NotificationCompat.BigTextStyle().bigText(contentText))
            .build()
    }
    
    private fun formatTime(seconds: Int): String {
        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        val secs = seconds % 60
        return when {
            hours > 0 -> "${hours}h ${minutes}m ${secs}s"
            minutes > 0 -> "${minutes}m ${secs}s"
            else -> "${secs}s"
        }
    }
    
    private fun updateServiceNotification() {
        val notification = createServiceNotification()
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(SERVICE_NOTIFICATION_ID, notification)
    }

    private fun startMonitoringLoop() {
        isMonitoring = true
        println("Service: 🚀 Starting monitoring loop with ${checkInterval}ms interval")
        
        handler.post(object : Runnable {
            @RequiresApi(Build.VERSION_CODES.M)
            override fun run() {
                if (isMonitoring || isBlocking) {
                    try {
                        // Check for daily reset first
                        checkAndResetDaily()
                        
                        if (isMonitoring) {
                            checkTimeAndNotify()
                        }
                        // Always check current app even in blocking mode
                        checkCurrentApp()
                        
                        // Save state every 10 seconds
                        if (System.currentTimeMillis() % 10000 < checkInterval) {
                            saveMonitoringState()
                        }
                        
                        handler.postDelayed(this, checkInterval)
                        
                        // Log the current state for debugging
                        if (isBlocking) {
                            println("Service: 🔒 BLOCKING MODE ACTIVE - Continuously monitoring for blocked apps")
                        }
                    } catch (e: Exception) {
                        println("Service: ❌ Error in monitoring loop: ${e.message}")
                        e.printStackTrace()
                        handler.postDelayed(this, checkInterval)
                    }
                } else {
                    println("Service: 🛑 Monitoring stopped, cleaning up")
                    cleanup()
                    stopSelf()
                }
            }
        })
    }

    private fun startNotificationUpdateLoop() {
        println("Service: 🔔 Starting notification update loop")
        notificationHandler.post(object : Runnable {
            override fun run() {
                if (isMonitoring) {
                    try {
                        // Update notification with current countdown every second
                        updateServiceNotification()
                        notificationHandler.postDelayed(this, notificationUpdateInterval)
                    } catch (e: Exception) {
                        println("Service: ❌ Error updating notification: ${e.message}")
                        notificationHandler.postDelayed(this, notificationUpdateInterval)
                    }
                }
            }
        })
    }

    private fun stopMonitoringLoop() {
        isMonitoring = false
        handler.removeCallbacksAndMessages(null)
        notificationHandler.removeCallbacksAndMessages(null)
        cleanup()
        stopSelf()
    }

    private fun terminateApp(packageName: String) {
        try {
            println("Service: 🔄 Attempting to terminate $packageName with enhanced methods")
            
            // Method 1: Kill background processes (limited effectiveness on newer Android)
            try {
                activityManager.killBackgroundProcesses(packageName)
                println("Service: 🔧 Killed background processes for $packageName")
            } catch (e: Exception) {
                println("Service: ⚠️ Kill background processes failed: ${e.message}")
            }
            
            // Method 2: Multiple shell command attempts
            val commands = arrayOf(
                "am force-stop $packageName",
                "pm disable $packageName",
                "killall $packageName"
            )
            
            for (command in commands) {
                try {
                    val process = Runtime.getRuntime().exec(command)
                    process.waitFor()
                    println("Service: 📱 Executed: $command")
                } catch (e: Exception) {
                    println("Service: ⚠️ Command failed '$command': ${e.message}")
                }
            }
            
            // Method 3: Send HOME intent to push app to background (most reliable)
            try {
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                startActivity(homeIntent)
                println("Service: 🏠 Sent HOME intent to background $packageName")
            } catch (e: Exception) {
                println("Service: ⚠️ HOME intent failed: ${e.message}")
            }
            
            // Method 4: Try to launch our own blocking overlay activity
            try {
                val blockingIntent = Intent(this, AppBlockingActivity::class.java).apply {
                    putExtra("blocked_app", packageName)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                           Intent.FLAG_ACTIVITY_CLEAR_TOP or
                           Intent.FLAG_ACTIVITY_SINGLE_TOP or
                           Intent.FLAG_ACTIVITY_NO_HISTORY
                }
                startActivity(blockingIntent)
                println("Service: 🚫 Launched blocking activity for $packageName")
            } catch (e: Exception) {
                println("Service: ⚠️ Blocking activity failed: ${e.message}")
            }
            
            // Method 5: Send broadcast to potentially running instances
            try {
                val blockingBroadcast = Intent("com.example.my_app.BLOCK_APP").apply {
                    putExtra("package_name", packageName)
                }
                sendBroadcast(blockingBroadcast)
                println("Service: 📡 Sent blocking broadcast for $packageName")
            } catch (e: Exception) {
                println("Service: ⚠️ Blocking broadcast failed: ${e.message}")
            }
            
            println("Service: ✅ Enhanced termination attempt completed for $packageName")
            
        } catch (e: Exception) {
            println("Service: ❌ Failed to terminate app: $packageName, error: ${e.message}")
        }
    }

    private fun handleTimeUp() {
        if (!isBlocking) {
            isBlocking = true
            isMonitoring = false
            sessionCompletedToday = true // Mark session as completed for today
            println("Service: 🔒 BLOCKING MODE ACTIVATED - isBlocking=$isBlocking, isMonitoring=$isMonitoring")
            
            println("Service: ⏰ TIME UP! Aggressively terminating ${monitoredPackages.size} apps")
            
            // ULTRA-AGGRESSIVE immediate termination
            repeat(5) { attempt ->
                monitoredPackages.forEach { packageName ->
                    println("Service: 🔥 ULTRA termination attempt ${attempt + 1} for $packageName")
                    
                    // Force home immediately
                    goToHomeImmediately()
                    
                    // Launch blocking screen
                    launchBlockingScreen(packageName)
                    
                    // Terminate aggressively
                    terminateAppAggressively(packageName)
                }
                // Very small delay between attempts
                Thread.sleep(100)
            }

            // Show immediate blocking notification
            showTimeUpNotification()

            try {
                // Notify Flutter about time up with completion message
                if (::methodChannel.isInitialized) {
                    methodChannel.invokeMethod("onTimeUp", mapOf(
                        "terminatedApps" to monitoredPackages.toList(),
                        "totalUsedSeconds" to totalUsedSeconds,
                        "originalDuration" to totalDurationSeconds,
                        "showCompletionDialog" to true,
                        "message" to "🎉 Timer Complete! Great job managing your screen time!",
                        "sessionCompleted" to true,
                        "sessionCompletedToday" to sessionCompletedToday
                    ))
                    println("Service: Notified Flutter about time up with completion dialog")
                } else {
                    println("Service: MethodChannel not available for time up notification")
                }
            } catch (e: Exception) {
                println("Service: Error notifying Flutter: ${e.message}")
            }

            // Immediately check if any monitored apps are currently running and block them
            val currentApp = getCurrentForegroundApp()
            if (currentApp != null && monitoredPackages.contains(currentApp)) {
                println("Service: 🚨 User is currently using blocked app $currentApp - IMMEDIATE BLOCKING")
                repeat(3) {
                    emergencyAppShutdown(currentApp)
                }
            }
            
            // Start blocking loop immediately (no delay)
            startAppBlockingLoop()
            
            // DON'T clear monitoring state - we need to maintain blocking
            // Save blocking state instead
            saveBlockingState()
            saveDailyResetState() // Save the session completion state
            
            // Stop service after extended time (24 hours)
            handler.postDelayed({
                cleanup()
                stopSelf()
            }, 86400000) // Keep blocking for 24 hours (until tomorrow)
        }
    }

    private fun startAppBlockingLoop() {
        println("Service: 🔒🔥 Starting ULTRA-AGGRESSIVE app blocking loop")
        
        // Create multiple parallel blocking threads for maximum effectiveness
        for (i in 1..3) {
            handler.post(object : Runnable {
                override fun run() {
                    if (isBlocking) {
                        // Continuously check and terminate monitored apps
                        checkAndBlockApps()
                        handler.postDelayed(this, 50) // Check every 0.05 seconds (20x per second)
                    }
                }
            })
        }
        
        // Additional watcher specifically for app launches
        handler.post(object : Runnable {
            override fun run() {
                if (isBlocking) {
                    watchForAppLaunches()
                    handler.postDelayed(this, 25) // Check every 0.025 seconds (40x per second)
                }
            }
        })
        
        // Emergency termination loop - even more aggressive
        handler.post(object : Runnable {
            override fun run() {
                if (isBlocking) {
                    monitoredPackages.forEach { packageName ->
                        val currentApp = getCurrentForegroundApp()
                        if (currentApp == packageName) {
                            emergencyAppShutdown(packageName)
                        }
                    }
                    handler.postDelayed(this, 100) // Check every 0.1 seconds
                }
            }
        })
    }
    
    private fun watchForAppLaunches() {
        try {
            val currentApp = getCurrentForegroundApp()
            if (currentApp != null && monitoredPackages.contains(currentApp)) {
                println("Service: 🚨 DETECTED BLOCKED APP LAUNCH: $currentApp - IMMEDIATE SHUTDOWN")
                
                // Emergency shutdown sequence
                emergencyAppShutdown(currentApp)
            }
        } catch (e: Exception) {
            println("Service: Error in app launch watcher: ${e.message}")
        }
    }

    private fun checkAndBlockApps() {
        try {
            val currentApp = getCurrentForegroundApp()
            if (currentApp != null && monitoredPackages.contains(currentApp)) {
                println("Service: 🚫🔥 IMMEDIATELY BLOCKING $currentApp - AGGRESSIVE MODE")
                
                // STEP 1: Immediately go to home (most effective)
                goToHomeImmediately()
                
                // STEP 2: Launch blocking screen overlay
                launchBlockingScreen(currentApp)
                
                // STEP 3: Aggressive termination
                terminateAppAggressively(currentApp)
                
                // STEP 4: Show blocking notification
                showBlockingNotification(currentApp)
                
                println("Service: ✅ Completed aggressive blocking sequence for $currentApp")
            }
        } catch (e: Exception) {
            println("Service: Error in app blocking: ${e.message}")
        }
    }
    
    private fun goToHomeImmediately() {
        try {
            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                       Intent.FLAG_ACTIVITY_CLEAR_TOP or
                       Intent.FLAG_ACTIVITY_CLEAR_TASK or
                       Intent.FLAG_ACTIVITY_SINGLE_TOP or
                       Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            }
            startActivity(homeIntent)
            println("Service: 🏠 FORCED HOME immediately")
        } catch (e: Exception) {
            println("Service: ⚠️ Failed to go home: ${e.message}")
        }
    }
    
    private fun launchBlockingScreen(packageName: String) {
        try {
            // Check if milestone activity is already active
            if (MilestoneAlertActivity.isActive()) {
                println("Service: 🚫 MilestoneAlertActivity is active, skipping blocking screen launch")
                return
            }
            
            val blockingIntent = Intent(this, AppBlockingActivity::class.java).apply {
                putExtra("blocked_app", packageName)
                putExtra("show_milestone", false)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                       Intent.FLAG_ACTIVITY_CLEAR_TOP or
                       Intent.FLAG_ACTIVITY_SINGLE_TOP or
                       Intent.FLAG_ACTIVITY_NO_HISTORY or
                       Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS or
                       Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            startActivity(blockingIntent)
            println("Service: 🚫 Launched blocking screen for $packageName")
        } catch (e: Exception) {
            println("Service: ⚠️ Failed to launch blocking screen: ${e.message}")
        }
    }
    
    private fun launchMilestoneScreen(packageName: String, percentage: Int) {
        try {
            // Check if blocking activity is already active
            if (AppBlockingActivity.isActive()) {
                println("Service: 🎯 AppBlockingActivity is active, skipping milestone screen launch")
                return
            }
            
            val milestoneIntent = Intent(this, AppBlockingActivity::class.java).apply {
                putExtra("blocked_app", packageName)
                putExtra("show_milestone", true)
                putExtra("milestone_percentage", percentage)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                       Intent.FLAG_ACTIVITY_CLEAR_TOP or
                       Intent.FLAG_ACTIVITY_SINGLE_TOP or
                       Intent.FLAG_ACTIVITY_NO_HISTORY or
                       Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS or
                       Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            startActivity(milestoneIntent)
            println("Service: 🎯 Launched milestone screen for $packageName (${percentage}%)")
        } catch (e: Exception) {
            println("Service: ⚠️ Failed to launch milestone screen: ${e.message}")
        }
    }
    
    private fun terminateAppAggressively(packageName: String) {
        // Multiple rapid termination attempts
        repeat(3) { attempt ->
            try {
                // Kill background processes
                activityManager.killBackgroundProcesses(packageName)
                
                // Multiple shell commands
                val commands = arrayOf(
                    "am force-stop $packageName",
                    "am kill $packageName",
                    "pm disable-user --user 0 $packageName || pm disable $packageName"
                )
                
                for (command in commands) {
                    try {
                        Runtime.getRuntime().exec(command)
                        println("Service: 📱 Executed: $command (attempt ${attempt + 1})")
                    } catch (e: Exception) {
                        // Continue with next command
                    }
                }
                
                Thread.sleep(50) // Very short delay between attempts
                
            } catch (e: Exception) {
                println("Service: ⚠️ Termination attempt ${attempt + 1} failed: ${e.message}")
            }
        }
    }
    
    private fun showBlockingNotification(packageName: String) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val blockNotification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                .setContentTitle("🚫 App Blocked for 24 Hours")
                .setContentText("$packageName is locked for 24 hours. Time limit reached!")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setStyle(NotificationCompat.BigTextStyle()
                    .bigText("$packageName is blocked for 24 hours because your usage time limit has been reached. The app will be available tomorrow."))
                .build()
            notificationManager.notify(200 + System.currentTimeMillis().toInt() % 100, blockNotification)
        } catch (e: Exception) {
            println("Service: ⚠️ Failed to show notification: ${e.message}")
        }
    }
    
    private fun emergencyAppShutdown(packageName: String) {
        println("Service: 🚨⚡ EMERGENCY SHUTDOWN for $packageName")
        
        // IMMEDIATE actions (no delays)
        repeat(10) { attempt ->
            try {
                // 1. Force home immediately
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                           Intent.FLAG_ACTIVITY_CLEAR_TOP or
                           Intent.FLAG_ACTIVITY_CLEAR_TASK or
                           Intent.FLAG_ACTIVITY_SINGLE_TOP or
                           Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED or
                           Intent.FLAG_ACTIVITY_NO_ANIMATION
                }
                startActivity(homeIntent)
                
                // 2. Launch milestone screen with high priority and make it more visible
                val milestoneIntent = Intent(this, AppBlockingActivity::class.java).apply {
                    putExtra("blocked_app", packageName)
                    putExtra("show_milestone", true)
                    putExtra("milestone_percentage", 100)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                           Intent.FLAG_ACTIVITY_CLEAR_TOP or
                           Intent.FLAG_ACTIVITY_SINGLE_TOP or
                           Intent.FLAG_ACTIVITY_NO_HISTORY or
                           Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS or
                           Intent.FLAG_ACTIVITY_CLEAR_TASK or
                           Intent.FLAG_ACTIVITY_NO_ANIMATION or
                           Intent.FLAG_ACTIVITY_TASK_ON_HOME
                }
                startActivity(milestoneIntent)
                
                // 3. Multiple termination commands
                activityManager.killBackgroundProcesses(packageName)
                
                val commands = arrayOf(
                    "am force-stop $packageName",
                    "am kill $packageName",
                    "am kill-all",
                    "pm disable-user --user 0 $packageName",
                    "pm disable $packageName",
                    "killall $packageName"
                )
                
                for (command in commands) {
                    try {
                        val process = Runtime.getRuntime().exec(command)
                        process.waitFor()
                    } catch (e: Exception) {
                        // Continue with next command
                    }
                }
                
                println("Service: 🚨 Emergency shutdown attempt ${attempt + 1} completed for $packageName")
                
            } catch (e: Exception) {
                println("Service: ⚠️ Emergency shutdown attempt ${attempt + 1} failed: ${e.message}")
            }
        }
    }

    private fun getCurrentForegroundApp(): String? {
        return try {
            val usageStatsManager = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
            val endTime = System.currentTimeMillis()
            val beginTime = endTime - 500 // Even shorter time window for faster detection

            var detectedApp: String? = null

            // Method 1: Check very recent usage events (most reliable)
            try {
                val usageEvents = usageStatsManager.queryEvents(beginTime, endTime)
                val event = UsageEvents.Event()
                var lastPackage: String? = null
                var lastTime = 0L

                while (usageEvents.hasNextEvent()) {
                    usageEvents.getNextEvent(event)
                    if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND && 
                        event.timeStamp > lastTime) {
                        lastTime = event.timeStamp
                        lastPackage = event.packageName
                    }
                }
                detectedApp = lastPackage
            } catch (e: Exception) {
                println("Service: Usage events failed: ${e.message}")
            }
            
            // Method 2: Check usage stats for any missed apps
            if (detectedApp == null) {
                try {
                    val usageStats = usageStatsManager.queryUsageStats(
                        UsageStatsManager.INTERVAL_BEST, beginTime, endTime
                    )
                    
                    var mostRecentApp: String? = null
                    var mostRecentTime = 0L
                    
                    for (stat in usageStats) {
                        if (stat.lastTimeUsed > mostRecentTime && 
                            stat.packageName != packageName &&
                            !stat.packageName.startsWith("com.android.systemui") &&
                            !stat.packageName.startsWith("android") &&
                            stat.lastTimeUsed > beginTime) {
                            mostRecentTime = stat.lastTimeUsed
                            mostRecentApp = stat.packageName
                        }
                    }
                    detectedApp = mostRecentApp
                } catch (e: Exception) {
                    println("Service: Usage stats failed: ${e.message}")
                }
            }
            
            // Method 3: Check running tasks (limited effectiveness on newer Android)
            if (detectedApp == null) {
                try {
                    val runningTasks = activityManager.getRunningTasks(5)
                    for (task in runningTasks) {
                        val topActivity = task.topActivity
                        if (topActivity != null && 
                            topActivity.packageName != packageName &&
                            !topActivity.packageName.startsWith("com.android.systemui")) {
                            detectedApp = topActivity.packageName
                            break
                        }
                    }
                } catch (e: Exception) {
                    println("Service: Running tasks method failed: ${e.message}")
                }
            }
            
            // Method 4: Check all running processes (additional backup)
            if (detectedApp == null) {
                try {
                    val runningProcesses = activityManager.runningAppProcesses
                    for (process in runningProcesses) {
                        if (process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND &&
                            process.processName != packageName &&
                            !process.processName.startsWith("com.android.systemui")) {
                            detectedApp = process.processName
                            break
                        }
                    }
                } catch (e: Exception) {
                    println("Service: Running processes failed: ${e.message}")
                }
            }
            
            detectedApp
        } catch (e: Exception) {
            println("Service: Error getting foreground app: ${e.message}")
            null
        }
    }

    private fun showTimeUpNotification() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setContentTitle("🔒 Apps Blocked for 24 Hours")
            .setContentText("Your app usage time has ended. Apps are locked for 24 hours.")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(false)
            .setOngoing(true)
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText("Your time limit has been reached. Selected apps are now blocked for 24 hours. The blocking will automatically end tomorrow."))
            .build()
            
        notificationManager.notify(ALERT_NOTIFICATION_ID, notification)
    }

    private fun showPercentageNotification(percentage: Int) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setContentTitle("⚠️ Time Alert")
            .setContentText("You've used $percentage% of your allocated time")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .build()
            
        notificationManager.notify(300 + percentage, notification)
    }

    private fun showMilestoneAlert(percentage: Int, remainingSeconds: Int, totalUsedSeconds: Int, originalDuration: Int = totalDurationSeconds) {
        try {
            println("Service: 🎯 Launching milestone alert for $percentage%")
            
            // Check if blocking activity is already active
            if (AppBlockingActivity.isActive()) {
                println("Service: 🎯 AppBlockingActivity is active, skipping milestone alert launch")
                return
            }
            
            // Finish any existing blocking activities first
            finishExistingBlockingActivities()
            
            // Format time strings
            val remainingTime = formatTime(remainingSeconds)
            val totalUsedTime = formatTime(totalUsedSeconds)
            val originalDurationTime = formatTime(originalDuration)
            
            // Create intent to launch the milestone alert activity
            val intent = Intent(this, MilestoneAlertActivity::class.java).apply {
                putExtra(MilestoneAlertActivity.EXTRA_PERCENTAGE, percentage)
                putExtra(MilestoneAlertActivity.EXTRA_REMAINING_TIME, remainingTime)
                putExtra(MilestoneAlertActivity.EXTRA_TOTAL_USED, totalUsedTime)
                putExtra(MilestoneAlertActivity.EXTRA_ORIGINAL_DURATION, originalDurationTime)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                       Intent.FLAG_ACTIVITY_CLEAR_TOP or
                       Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            
            startActivity(intent)
            println("Service: ✅ Milestone alert activity launched successfully")
            
        } catch (e: Exception) {
            println("Service: ❌ Failed to launch milestone alert: ${e.message}")
            // Fallback to notification if activity launch fails
            showPercentageNotification(percentage)
        }
    }
    
    private fun finishExistingBlockingActivities() {
        try {
            // Send broadcast to finish any existing blocking activities
            val finishIntent = Intent("com.example.my_app.FINISH_ACTIVITIES")
            sendBroadcast(finishIntent)
            println("Service: 🧹 Sent broadcast to finish existing blocking activities")
        } catch (e: Exception) {
            println("Service: ⚠️ Failed to send finish broadcast: ${e.message}")
        }
    }

  private fun checkTimeAndNotify() {
    if (totalDurationSeconds <= 0 || !isMonitoring) return

    val currentTime = System.currentTimeMillis()
    val timeSinceLastUpdate = currentTime - lastUpdateTime
    val timeSinceLastForceUpdate = currentTime - lastForceUpdateTime
    val shouldForceUpdate = timeSinceLastForceUpdate >= forceUpdateIntervalMs
    
    val currentTotalUsed = if (isCurrentlyUsingSelectedApp && currentSessionStartTime > 0) {
        val currentSessionTime = (System.currentTimeMillis() - currentSessionStartTime) / 1000
        totalUsedSeconds + currentSessionTime.toInt()
    } else {
        totalUsedSeconds
    }
    
    val remainingSeconds = maxOf(0, totalDurationSeconds - currentTotalUsed)
    
    // Always log timer state every second for debugging
    println("Service: ⏱️ Timer check - Total: ${totalDurationSeconds}s, Used: ${currentTotalUsed}s, Remaining: ${remainingSeconds}s, Active: $isCurrentlyUsingSelectedApp")
    
    // CRITICAL: Check for time-up condition REGARDLESS of current app usage
    if (currentTotalUsed >= totalDurationSeconds && !isBlocking) {
        totalUsedSeconds = currentTotalUsed
        println("Service: ⏰⏰⏰ TIME UP DETECTED! Total used: ${currentTotalUsed}s >= Duration: ${totalDurationSeconds}s - STARTING BLOCKING ⏰⏰⏰")
        // Show 100% completion milestone alert
        showMilestoneAlert(100, 0, currentTotalUsed, totalDurationSeconds)
        handleTimeUp()
        return // Exit early since we're now in blocking mode
    }
    
    // Log status for debugging
    if (totalDurationSeconds > 0) {
        val percentage = (currentTotalUsed.toFloat() / totalDurationSeconds.toFloat()) * 100
        println("Service: 📊 Status - ${percentage.toInt()}% complete (${currentTotalUsed}s/${totalDurationSeconds}s), Blocking: $isBlocking")
    }
    
    if (isCurrentlyUsingSelectedApp && currentSessionStartTime > 0) {
        val percentageComplete = if (totalDurationSeconds > 0) {
            (currentTotalUsed.toFloat() / totalDurationSeconds.toFloat()) * 100
        } else 0f

        // Always send update when actively using selected apps (countdown is critical)
        val currentApp = getCurrentForegroundApp()
        val currentAppName = if (currentApp != null) {
            try {
                val appInfo = applicationContext.packageManager.getApplicationInfo(currentApp, 0)
                applicationContext.packageManager.getApplicationLabel(appInfo).toString()
            } catch (e: Exception) {
                currentApp
            }
        } else ""

        try {
            if (::methodChannel.isInitialized) {
                methodChannel.invokeMethod(
                    "updateForegroundAppStatus",
                    mapOf(
                        "isSelectedAppInForeground" to isCurrentlyUsingSelectedApp,
                        "packageName" to (currentApp ?: ""),
                        "appName" to currentAppName,
                        "isInForeground" to isCurrentlyUsingSelectedApp,
                        "remainingSeconds" to remainingSeconds,
                        "totalUsedSeconds" to currentTotalUsed,
                        "isMonitoringActive" to isCurrentlyUsingSelectedApp
                    )
                )
                println("Service: 📡 Sent active update to Flutter - Remaining: ${remainingSeconds}s")
            } else {
                println("Service: ⚠️ MethodChannel not available, continuing countdown in notification only")
            }
            lastUpdateTime = currentTime
            lastForceUpdateTime = currentTime
        } catch (e: Exception) {
            println("Service: ❌ Error sending active update to Flutter: ${e.message}")
        }
        
        // Save state more frequently when actively using apps
        saveMonitoringState()

        when {
            percentageComplete >= 70 && !has70PercentNotified -> {
                has70PercentNotified = true
                println("Service: 🔔 70% milestone reached - Showing milestone alert")
                showMilestoneAlert(70, remainingSeconds, currentTotalUsed, totalDurationSeconds)
                showPercentageNotification(70)
            }
            percentageComplete >= 50 && !has50PercentNotified -> {
                has50PercentNotified = true
                println("Service: 🔔 50% milestone reached - Showing milestone alert")
                showMilestoneAlert(50, remainingSeconds, currentTotalUsed, totalDurationSeconds)
                showPercentageNotification(50)
            }
            percentageComplete >= 30 && !has30PercentNotified -> {
                has30PercentNotified = true
                println("Service: 🔔 30% milestone reached - Showing milestone alert")
                showMilestoneAlert(30, remainingSeconds, currentTotalUsed, totalDurationSeconds)
                showPercentageNotification(30)
            }
        }
    } else {
        // Send updates when paused - either throttled normal updates or forced updates
        val shouldSendPausedUpdate = timeSinceLastUpdate >= updateThrottleMs || shouldForceUpdate
        if (shouldSendPausedUpdate) {
            try {
                if (::methodChannel.isInitialized) {
                    methodChannel.invokeMethod(
                        "updateForegroundAppStatus",
                        mapOf(
                            "isSelectedAppInForeground" to false,
                            "packageName" to "",
                            "appName" to "",
                            "isInForeground" to false,
                            "remainingSeconds" to remainingSeconds,
                            "totalUsedSeconds" to currentTotalUsed,
                            "isMonitoringActive" to false
                        )
                    )
                    println("Service: 📡 Sent paused update to Flutter - Remaining: ${remainingSeconds}s (forced: $shouldForceUpdate)")
                } else {
                    println("Service: ⚠️ MethodChannel not available for paused update")
                }
                lastUpdateTime = currentTime
                if (shouldForceUpdate) {
                    lastForceUpdateTime = currentTime
                }
            } catch (e: Exception) {
                println("Service: ❌ Error sending paused update to Flutter: ${e.message}")
            }
        }
    }
}

    private fun saveMonitoringState() {
        try {
            // Get current app name if using selected app
            val currentApp = if (isCurrentlyUsingSelectedApp) getCurrentForegroundApp() else null
            val currentAppName = if (currentApp != null) {
                try {
                    val appInfo = applicationContext.packageManager.getApplicationInfo(currentApp, 0)
                    applicationContext.packageManager.getApplicationLabel(appInfo).toString()
                } catch (e: Exception) {
                    currentApp
                }
            } else ""
            
            sharedPreferences.edit().apply {
                putBoolean("monitoring_active", isMonitoring)
                putBoolean("blocking_active", isBlocking)
                putStringSet("monitored_packages", monitoredPackages.toSet())
                putInt("remaining_seconds", maxOf(0, totalDurationSeconds - totalUsedSeconds))
                putInt("total_used_seconds", totalUsedSeconds)
                putInt("original_duration", totalDurationSeconds)
                putLong("last_save_time", System.currentTimeMillis())
                putString("last_reset_date", lastResetDate)
                putBoolean("session_completed_today", sessionCompletedToday)
                putString("current_foreground_app", currentAppName)
                apply()
            }
            println("Service: 💾 Saved monitoring state - monitoring=$isMonitoring, blocking=$isBlocking, completed=$sessionCompletedToday, currentApp=$currentAppName")
        } catch (e: Exception) {
            println("Service: ❌ Failed to save monitoring state: ${e.message}")
        }
    }
    
    private fun saveBlockingState() {
        try {
            sharedPreferences.edit().apply {
                putBoolean("monitoring_active", false)
                putBoolean("blocking_active", true)
                putStringSet("monitored_packages", monitoredPackages.toSet())
                putInt("remaining_seconds", 0)
                putInt("total_used_seconds", totalUsedSeconds)
                putInt("original_duration", totalDurationSeconds)
                putLong("blocking_start_time", System.currentTimeMillis())
                putLong("last_save_time", System.currentTimeMillis())
                apply()
            }
            println("Service: 🔒 Saved BLOCKING state - Apps will remain blocked")
        } catch (e: Exception) {
            println("Service: ❌ Failed to save blocking state: ${e.message}")
        }
    }
    
    private fun clearMonitoringState() {
        try {
            sharedPreferences.edit().apply {
                putBoolean("monitoring_active", false)
                remove("monitored_packages")
                remove("remaining_seconds")
                remove("total_used_seconds")
                remove("original_duration")
                remove("last_save_time")
                apply()
            }
            println("Service: 🗑️ Cleared monitoring state")
        } catch (e: Exception) {
            println("Service: ❌ Failed to clear monitoring state: ${e.message}")
        }
    }

    private fun cleanup() {
        println("Service: 🧹 Starting cleanup process")
        
        // Finalize any ongoing session
        if (isCurrentlyUsingSelectedApp && currentSessionStartTime > 0) {
            val sessionTime = (System.currentTimeMillis() - currentSessionStartTime) / 1000
            totalUsedSeconds += sessionTime.toInt()
            println("Service: 💾 Saved final session: ${sessionTime}s")
        }
        
        // Clear persistent state
        clearMonitoringState()
        
        // Reset all state variables
        monitoredPackages.clear()
        totalUsedSeconds = 0
        currentSessionStartTime = 0
        isCurrentlyUsingSelectedApp = false
        isMonitoring = false
        isBlocking = false
        lastUpdateTime = 0
        lastForceUpdateTime = 0
        
        // Reset milestone flags
        has30PercentNotified = false
        has50PercentNotified = false
        has70PercentNotified = false
        
        // Note: Don't reset daily state variables here as they need to persist across service restarts
        
        // Remove all pending callbacks
        handler.removeCallbacksAndMessages(null)
        notificationHandler.removeCallbacksAndMessages(null)
        
        // Release wake lock safely
        if (::wakeLock.isInitialized && wakeLock.isHeld) {
            wakeLock.release()
            println("Service: 🔋 Released wake lock")
        }
        
        println("Service: ✅ Cleanup completed")
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun checkCurrentApp() {
        if (!checkUsageStatsPermission()) {
            if (::methodChannel.isInitialized) {
                methodChannel.invokeMethod("requestUsageStatsPermission", null)
            }
            return
        }

        val usageStatsManager = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
        val endTime = System.currentTimeMillis()
        val beginTime = endTime - 5000

        var currentPackage: String? = null
        var currentAppName: String? = null
        var isInForeground = false

        try {
            val usageEvents = usageStatsManager.queryEvents(beginTime, endTime)
            val event = UsageEvents.Event()
            var lastEventType: Int? = null

            while (usageEvents.hasNextEvent()) {
                usageEvents.getNextEvent(event)
                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND || 
                    event.eventType == UsageEvents.Event.MOVE_TO_BACKGROUND) {
                    currentPackage = event.packageName
                    lastEventType = event.eventType
                    try {
                        val appInfo = applicationContext.packageManager.getApplicationInfo(currentPackage!!, 0)
                        currentAppName = applicationContext.packageManager.getApplicationLabel(appInfo).toString()
                    } catch (e: Exception) {
                        currentAppName = currentPackage
                    }
                }
            }

            isInForeground = lastEventType == UsageEvents.Event.MOVE_TO_FOREGROUND

            if (currentPackage == null) {
                val usageStats = usageStatsManager.queryUsageStats(
                    UsageStatsManager.INTERVAL_BEST, beginTime, endTime
                )
                
                var mostRecentApp: String? = null
                var mostRecentTime = 0L
                
                for (stat in usageStats) {
                    if (stat.lastTimeUsed > mostRecentTime && stat.packageName != packageName) {
                        mostRecentTime = stat.lastTimeUsed
                        mostRecentApp = stat.packageName
                    }
                }
                
                if (mostRecentApp != null) {
                    currentPackage = mostRecentApp
                    isInForeground = true
                    try {
                        val appInfo = applicationContext.packageManager.getApplicationInfo(currentPackage!!, 0)
                        currentAppName = applicationContext.packageManager.getApplicationLabel(appInfo).toString()
                    } catch (e: Exception) {
                        currentAppName = currentPackage
                    }
                }
            }

        } catch (e: Exception) {
            println("Service: Error querying usage events: ${e.message}")
        }

        val isSelectedAppInForeground = isInForeground && currentPackage != null &&
                monitoredPackages.contains(currentPackage)

        // CRITICAL: If we're in blocking mode and user tries to access a monitored app, block immediately
        if (isBlocking && isSelectedAppInForeground && currentPackage != null) {
            println("Service: 🚫 BLOCKING MODE ACTIVE - Immediately blocking $currentPackage")
            
            // IMMEDIATE VISUAL FEEDBACK - Show milestone/blocking screen first
            launchMilestoneScreen(currentPackage, 100) // Show 100% completion milestone
            
            // Multiple blocking attempts for maximum effectiveness
            repeat(5) {
                emergencyAppShutdown(currentPackage)
                goToHomeImmediately()
                launchMilestoneScreen(currentPackage, 100)
            }
            
            // Also show blocking notification
            showBlockingNotification(currentPackage)
            
            // Force home after a short delay to ensure blocking screen is seen
            Handler(Looper.getMainLooper()).postDelayed({
                goToHomeImmediately()
            }, 1000)
            
            return
        }

        // Handle session tracking
        if (isSelectedAppInForeground && !isCurrentlyUsingSelectedApp) {
            currentSessionStartTime = System.currentTimeMillis()
            isCurrentlyUsingSelectedApp = true
            println("Service: 🟢 Started new session for selected app")
        } else if (!isSelectedAppInForeground && isCurrentlyUsingSelectedApp) {
            if (currentSessionStartTime > 0) {
                val sessionTime = (System.currentTimeMillis() - currentSessionStartTime) / 1000
                totalUsedSeconds += sessionTime.toInt()
                println("Service: 🔴 Ended session: ${sessionTime}s, Total used: ${totalUsedSeconds}s")
            }
            currentSessionStartTime = 0
            isCurrentlyUsingSelectedApp = false
        }

        // Calculate remaining time for Flutter UI
        val currentTotalUsed = if (isCurrentlyUsingSelectedApp && currentSessionStartTime > 0) {
            val currentSessionTime = (System.currentTimeMillis() - currentSessionStartTime) / 1000
            totalUsedSeconds + currentSessionTime.toInt()
        } else {
            totalUsedSeconds
        }
        val remainingSeconds = maxOf(0, totalDurationSeconds - currentTotalUsed)

        // Send update to Flutter
        if (::methodChannel.isInitialized) {
            methodChannel.invokeMethod(
                "updateForegroundAppStatus",
                mapOf(
                    "isSelectedAppInForeground" to isSelectedAppInForeground,
                    "packageName" to (currentPackage ?: ""),
                    "appName" to (currentAppName ?: ""),
                    "isInForeground" to isInForeground,
                    "remainingSeconds" to remainingSeconds,
                    "totalUsedSeconds" to currentTotalUsed,
                    "isMonitoringActive" to isCurrentlyUsingSelectedApp
                )
            )
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
    
    private fun checkAndResetDaily() {
        val currentDate = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        
        if (lastResetDate != currentDate) {
            println("Service: 📅 New day detected - Resetting daily counters")
            lastResetDate = currentDate
            sessionCompletedToday = false
            totalUsedSeconds = 0
            has30PercentNotified = false
            has50PercentNotified = false
            has70PercentNotified = false
            
            // Save the reset state
            saveDailyResetState()
        }
    }
    
    private fun saveDailyResetState() {
        try {
            sharedPreferences.edit().apply {
                putString("last_reset_date", lastResetDate)
                putBoolean("session_completed_today", sessionCompletedToday)
                putInt("total_used_seconds", totalUsedSeconds)
                apply()
            }
            println("Service: 💾 Saved daily reset state - Date: $lastResetDate, Completed: $sessionCompletedToday")
        } catch (e: Exception) {
            println("Service: ❌ Failed to save daily reset state: ${e.message}")
        }
    }
    
    private fun loadDailyResetState() {
        try {
            lastResetDate = sharedPreferences.getString("last_reset_date", "") ?: ""
            sessionCompletedToday = sharedPreferences.getBoolean("session_completed_today", false)
            totalUsedSeconds = sharedPreferences.getInt("total_used_seconds", 0)
            println("Service: 📅 Loaded daily reset state - Date: $lastResetDate, Completed: $sessionCompletedToday")
        } catch (e: Exception) {
            println("Service: ❌ Failed to load daily reset state: ${e.message}")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        cleanup()
    }
}

