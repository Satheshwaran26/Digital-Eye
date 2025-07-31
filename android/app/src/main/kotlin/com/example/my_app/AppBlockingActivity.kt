package com.example.my_app

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import android.widget.LinearLayout
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.graphics.Typeface

class AppBlockingActivity : Activity() {

    companion object {
        const val EXTRA_BLOCKED_APP = "blocked_app"
        const val EXTRA_SHOW_MILESTONE = "show_milestone"
        const val EXTRA_MILESTONE_PERCENTAGE = "milestone_percentage"
        
        // Activity management
        private var isBlockingActivityActive = false
        
        fun isActive(): Boolean = isBlockingActivityActive
    }
    
    private lateinit var finishReceiver: BroadcastReceiver

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Check if other blocking activities are already running
        if (MilestoneAlertActivity.isActive()) {
            println("AppBlockingActivity: MilestoneAlertActivity is already active, finishing")
            finish()
            return
        }
        
        // Set this activity as active
        isBlockingActivityActive = true
        
        // Register broadcast receiver for finish signal
        registerFinishReceiver()

        // Make this a fullscreen activity that appears over other apps
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )

        // Set fullscreen
        window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                        View.SYSTEM_UI_FLAG_FULLSCREEN or
                        View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                )

        createBlockingLayout()

        // Show blocking screen for longer duration to make it more visible
        // Auto-dismiss after 5 seconds and go to home (give user more time to see the message)
        Handler(Looper.getMainLooper()).postDelayed({
            goToHome()
            finish()
        }, 5000)
        
        // Aggressive safety: Force home every 0.2 seconds while this activity exists
        Handler(Looper.getMainLooper()).post(object : Runnable {
            override fun run() {
                if (!isFinishing && !isDestroyed) {
                    goToHome()
                    Handler(Looper.getMainLooper()).postDelayed(this, 200)
                }
            }
        })
        
        // Secondary safety: Force home every 0.5 seconds
        Handler(Looper.getMainLooper()).post(object : Runnable {
            override fun run() {
                if (!isFinishing && !isDestroyed) {
                    forceHomeAggressively()
                    Handler(Looper.getMainLooper()).postDelayed(this, 500)
                }
            }
        })
        
        // Emergency safety: Launch multiple home intents immediately
        Handler(Looper.getMainLooper()).postDelayed({
            repeat(3) {
                forceHomeAggressively()
            }
        }, 100)
    }
    
    override fun onDestroy() {
        super.onDestroy()
        // Mark this activity as inactive
        isBlockingActivityActive = false
        // Unregister broadcast receiver
        try {
            unregisterReceiver(finishReceiver)
        } catch (e: Exception) {
            // Receiver might not be registered
        }
    }
    
    override fun onPause() {
        super.onPause()
        // If activity is paused, mark as inactive to allow other activities
        isBlockingActivityActive = false
    }
    
    private fun registerFinishReceiver() {
        finishReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "com.example.my_app.FINISH_ACTIVITIES") {
                    println("AppBlockingActivity: Received finish signal, finishing activity")
                    finish()
                }
            }
        }
        registerReceiver(finishReceiver, IntentFilter("com.example.my_app.FINISH_ACTIVITIES"))
    }

    private fun createBlockingLayout() {
        val blockedApp = intent.getStringExtra(EXTRA_BLOCKED_APP) ?: "App"
        val showMilestone = intent.getBooleanExtra(EXTRA_SHOW_MILESTONE, false)
        val milestonePercentage = intent.getIntExtra(EXTRA_MILESTONE_PERCENTAGE, 100)
        
        if (showMilestone) {
            createMilestoneLayout(blockedApp, milestonePercentage)
        } else {
            createStandardBlockingLayout(blockedApp)
        }
    }
    
    private fun createStandardBlockingLayout(blockedApp: String) {

        // Create main container
        val mainLayout = LinearLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 64, 48, 64)
        }

        // Set red gradient background for blocking
        val gradientDrawable = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(Color.parseColor("#D32F2F"), Color.parseColor("#B71C1C"))
        )
        mainLayout.background = gradientDrawable

        // Create blocked icon (large X or stop symbol)
        val blockedIcon = TextView(this).apply {
            text = "🚫"
            textSize = 120f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, 0, 0, 40)
            }
        }

        // Create blocked message
        val messageText = TextView(this).apply {
            text = "🚫 APP BLOCKED!"
            textSize = 36f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            setShadowLayer(6f, 0f, 3f, Color.parseColor("#60000000"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, 0, 0, 24)
            }
        }

        // Create app name text
        val appNameText = TextView(this).apply {
            text = "\"$blockedApp\" is currently blocked"
            textSize = 20f
            setTextColor(Color.parseColor("#FFCDD2"))
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            setShadowLayer(3f, 0f, 2f, Color.parseColor("#40000000"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, 0, 0, 32)
            }
        }

        // Create explanation text
        val explanationText = TextView(this).apply {
            text = "⏰ Your time limit has been reached!\n\n📱 This app will be available tomorrow.\n\n🎯 Great job managing your screen time!"
            textSize = 18f
            setTextColor(Color.parseColor("#FFCDD2"))
            gravity = Gravity.CENTER
            setLineSpacing(6f, 1.3f)
            setShadowLayer(3f, 0f, 2f, Color.parseColor("#40000000"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, 0, 0, 48)
            }
        }

        // Create go home button
        val homeButton = Button(this).apply {
            text = "🏠 Go to Home"
            textSize = 20f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            
            val buttonDrawable = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 30f
                setColor(Color.parseColor("#F44336"))
                setStroke(3, Color.parseColor("#FFCDD2"))
            }
            background = buttonDrawable
            
            layoutParams = LinearLayout.LayoutParams(
                (250 * resources.displayMetrics.density).toInt(),
                (70 * resources.displayMetrics.density).toInt()
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
            
            setPadding(40, 20, 40, 20)
            elevation = 8f
            
            setOnClickListener {
                goToHome()
            }
        }

        // Add all views to layout
        mainLayout.addView(blockedIcon)
        mainLayout.addView(messageText)
        mainLayout.addView(appNameText)
        mainLayout.addView(explanationText)
        mainLayout.addView(homeButton)

        setContentView(mainLayout)
    }
    
    private fun createMilestoneLayout(blockedApp: String, percentage: Int) {
        // Create main container
        val mainLayout = LinearLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 64, 48, 64)
        }

        // Set gradient background based on percentage
        val gradientDrawable = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            when (percentage) {
                100 -> intArrayOf(Color.parseColor("#4CAF50"), Color.parseColor("#2E7D32")) // Green for completion
                else -> intArrayOf(Color.parseColor("#D32F2F"), Color.parseColor("#B71C1C")) // Red for blocking
            }
        )
        mainLayout.background = gradientDrawable

        // Create percentage text
        val percentageText = TextView(this).apply {
            text = "${percentage}%"
            textSize = 84f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            setShadowLayer(8f, 0f, 4f, Color.parseColor("#40000000"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, 80, 0, 30)
            }
        }

        // Create milestone message
        val messageText = TextView(this).apply {
            text = when (percentage) {
                100 -> "🎉 Session Complete!\n\nCongratulations!\nYou've successfully completed your daily session!\n\nApps will be blocked for 24 hours."
                else -> "⏰ Time Alert!\n\nYou've used $percentage% of your allocated time.\n\nKeep going!"
            }
            textSize = 20f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT
            setLineSpacing(6f, 1.3f)
            setShadowLayer(4f, 0f, 2f, Color.parseColor("#40000000"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(24, 0, 24, 35)
            }
        }

        // Create continue button
        val continueButton = Button(this).apply {
            text = when (percentage) {
                100 -> "🏠 Go to Home"
                else -> "Continue"
            }
            textSize = 20f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            
            val buttonDrawable = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 30f
                setColor(Color.parseColor("#4CAF50"))
                setStroke(3, Color.parseColor("#FFFFFF"))
            }
            background = buttonDrawable
            
            layoutParams = LinearLayout.LayoutParams(
                (250 * resources.displayMetrics.density).toInt(),
                (70 * resources.displayMetrics.density).toInt()
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
            
            setPadding(40, 20, 40, 20)
            elevation = 8f
            
            setOnClickListener {
                goToHome()
            }
        }

        // Add all views to layout
        mainLayout.addView(percentageText)
        mainLayout.addView(messageText)
        mainLayout.addView(continueButton)

        setContentView(mainLayout)
    }

    private fun goToHome() {
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
        } catch (e: Exception) {
            println("AppBlockingActivity: Failed to go home: ${e.message}")
        }
        finish()
    }
    
    private fun forceHomeAggressively() {
        try {
            // Multiple home intents with different flags
            val homeIntents = arrayOf(
                Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                },
                Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                }
            )
            
            for (intent in homeIntents) {
                try {
                    startActivity(intent)
                } catch (e: Exception) {
                    // Continue with next intent
                }
            }
            
        } catch (e: Exception) {
            println("AppBlockingActivity: Failed aggressive home forcing: ${e.message}")
        }
    }

    // Override back button to prevent dismissing
    override fun onBackPressed() {
        goToHome()
    }

    // Override home button interception
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Allow user to leave this activity
    }
} 