package com.example.my_app

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.animation.ObjectAnimator
import android.animation.AnimatorSet
import android.view.animation.AccelerateDecelerateInterpolator
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.ViewGroup
import androidx.core.content.res.ResourcesCompat
import android.graphics.Typeface
import android.widget.FrameLayout
import androidx.core.view.setPadding

class MilestoneAlertActivity : Activity() {

    companion object {
        const val EXTRA_PERCENTAGE = "percentage"
        const val EXTRA_REMAINING_TIME = "remaining_time"
        const val EXTRA_TOTAL_USED = "total_used"
        const val EXTRA_ORIGINAL_DURATION = "original_duration"
        
        private var isMilestoneActivityActive = false
        
        fun isActive(): Boolean = isMilestoneActivityActive
    }
    
    private lateinit var finishReceiver: BroadcastReceiver

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        if (AppBlockingActivity.isActive()) {
            println("MilestoneAlertActivity: AppBlockingActivity is already active, finishing")
            finish()
            return
        }
        
        isMilestoneActivityActive = true
        registerFinishReceiver()

        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )

        window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                        View.SYSTEM_UI_FLAG_FULLSCREEN or
                        View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                )

        createMilestoneLayout()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        isMilestoneActivityActive = false
        try {
            unregisterReceiver(finishReceiver)
        } catch (e: Exception) {
            // Receiver might not be registered
        }
    }
    
    override fun onPause() {
        super.onPause()
        isMilestoneActivityActive = false
    }
    
    private fun registerFinishReceiver() {
        finishReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "com.example.my_app.FINISH_ACTIVITIES") {
                    println("MilestoneAlertActivity: Received finish signal, finishing activity")
                    finish()
                }
            }
        }
        registerReceiver(finishReceiver, IntentFilter("com.example.my_app.FINISH_ACTIVITIES"))
    }

    private fun createMilestoneLayout() {
        val percentage = intent.getIntExtra(EXTRA_PERCENTAGE, 0)
        val remainingTime = intent.getStringExtra(EXTRA_REMAINING_TIME) ?: ""
        val totalUsed = intent.getStringExtra(EXTRA_TOTAL_USED) ?: ""
        val originalDuration = intent.getStringExtra(EXTRA_ORIGINAL_DURATION) ?: ""

        // Main container - using LinearLayout instead of ScrollView for better control
        val mainLayout = LinearLayout(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding((20 * resources.displayMetrics.density).toInt())
            setBackgroundColor(Color.parseColor("#1A1A1A")) // Dark background
        }

        // Create a container for the content with proper spacing
        val contentContainer = LinearLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER
            }
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding((16 * resources.displayMetrics.density).toInt())
        }

        // Gradient background for content container
        val gradientDrawable = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            getGradientColors(percentage)
        ).apply {
            cornerRadius = 20f
            setStroke(2, Color.parseColor("#33FFFFFF"))
        }
        contentContainer.background = gradientDrawable

        // Header section
        val headerSection = createHeaderSection(percentage)
        contentContainer.addView(headerSection)

        // Progress info section
        val progressSection = createProgressSection(totalUsed, remainingTime, originalDuration)
        contentContainer.addView(progressSection)

        // Content section based on percentage
        when (percentage) {
            30 -> contentContainer.addView(createEyeExerciseSection())
            50 -> contentContainer.addView(createPhysicalActivitySection())
            70 -> contentContainer.addView(createMotivationSection())
            100 -> contentContainer.addView(createCelebrationSection())
            else -> contentContainer.addView(createGeneralSection(percentage))
        }

        // Continue button section
        val buttonSection = createContinueButtonSection(percentage)
        contentContainer.addView(buttonSection)

        mainLayout.addView(contentContainer)
        setContentView(mainLayout)

        // Start animations
        startAnimations(headerSection)
    }

    private fun createHeaderSection(percentage: Int): LinearLayout {
        val headerLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, (16 * resources.displayMetrics.density).toInt(), 0, (16 * resources.displayMetrics.density).toInt())
            }
        }

        // Icon based on percentage - temporarily removed due to missing drawable resources
        // val iconView = ImageView(this).apply {
        //     layoutParams = LinearLayout.LayoutParams(
        //         (80 * resources.displayMetrics.density).toInt(),
        //         (80 * resources.displayMetrics.density).toInt()
        //     ).apply {
        //         gravity = Gravity.CENTER
        //         setMargins(0, 0, 0, (16 * resources.displayMetrics.density).toInt())
        //     }
        //     setImageResource(when (percentage) {
        //         30 -> R.drawable.ic_eye
        //         50 -> R.drawable.ic_activity
        //         70 -> R.drawable.ic_mind
        //         100 -> R.drawable.ic_trophy
        //         else -> R.drawable.ic_progress
        //     })
        //     setColorFilter(Color.WHITE)
        // }

        // Percentage text
        val percentageText = TextView(this).apply {
            text = "${percentage}%"
            textSize = 56f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            typeface = ResourcesCompat.getFont(this@MilestoneAlertActivity, R.font.poppins_bold) ?: Typeface.DEFAULT_BOLD
            setShadowLayer(8f, 0f, 4f, Color.parseColor("#66000000"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        // Title text
        val titleText = TextView(this).apply {
            text = getMilestoneTitle(percentage)
            textSize = 24f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            typeface = ResourcesCompat.getFont(this@MilestoneAlertActivity, R.font.poppins_semibold) ?: Typeface.DEFAULT_BOLD
            setShadowLayer(4f, 0f, 2f, Color.parseColor("#66000000"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, (6 * resources.displayMetrics.density).toInt(), 0, 0)
            }
        }

        // headerLayout.addView(iconView) // Commented out due to missing drawable resources
        headerLayout.addView(percentageText)
        headerLayout.addView(titleText)
        return headerLayout
    }

    private fun createProgressSection(totalUsed: String, remainingTime: String, originalDuration: String): LinearLayout {
        val progressLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins((12 * resources.displayMetrics.density).toInt(), 0, (12 * resources.displayMetrics.density).toInt(), (16 * resources.displayMetrics.density).toInt())
            }
            val containerDrawable = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 20f
                setColor(Color.parseColor("#26FFFFFF"))
                setStroke(2, Color.parseColor("#4DFFFFFF"))
            }
            background = containerDrawable
            setPadding((16 * resources.displayMetrics.density).toInt())
        }

        // Progress items
        val items = listOf(
            "Used: $totalUsed" to "Time spent",
            "Remaining: $remainingTime" to "Time left",
            "Total: $originalDuration" to "Goal"
        )

        items.forEachIndexed { index, (text, label) ->
            val itemLayout = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    0,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    1f
                )
            }

            val textView = TextView(this).apply {
                this.text = text
                textSize = 14f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                typeface = ResourcesCompat.getFont(this@MilestoneAlertActivity, R.font.poppins_semibold) ?: Typeface.DEFAULT
            }

            val labelView = TextView(this).apply {
                this.text = label
                textSize = 12f
                setTextColor(Color.parseColor("#B3FFFFFF"))
                gravity = Gravity.CENTER
                typeface = ResourcesCompat.getFont(this@MilestoneAlertActivity, R.font.poppins_regular) ?: Typeface.DEFAULT
            }

            itemLayout.addView(textView)
            itemLayout.addView(labelView)
            progressLayout.addView(itemLayout)

            if (index < items.size - 1) {
                val divider = View(this).apply {
                    layoutParams = LinearLayout.LayoutParams(
                        (2 * resources.displayMetrics.density).toInt(),
                        (40 * resources.displayMetrics.density).toInt()
                    ).apply {
                        setMargins((8 * resources.displayMetrics.density).toInt(), 0, (8 * resources.displayMetrics.density).toInt(), 0)
                    }
                    setBackgroundColor(Color.parseColor("#4DFFFFFF"))
                }
                progressLayout.addView(divider)
            }
        }

        return progressLayout
    }

    private fun createEyeExerciseSection(): LinearLayout {
        val sectionLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins((16 * resources.displayMetrics.density).toInt(), 0, (16 * resources.displayMetrics.density).toInt(), (24 * resources.displayMetrics.density).toInt())
            }
        }

        val sectionHeader = createSectionHeader("👁️ Eye Care Break", "Protect your eyes")
        sectionLayout.addView(sectionHeader)

        val exerciseCard = createExerciseCard(getDailyEyeExercise(), "Eye Exercise")
        sectionLayout.addView(exerciseCard)

        return sectionLayout
    }

    private fun createPhysicalActivitySection(): LinearLayout {
        val sectionLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins((16 * resources.displayMetrics.density).toInt(), 0, (16 * resources.displayMetrics.density).toInt(), (24 * resources.displayMetrics.density).toInt())
            }
        }

        val sectionHeader = createSectionHeader("🏃 Halfway Break", "Get moving")
        sectionLayout.addView(sectionHeader)

        val activityCard = createExerciseCard(getDailyPhysicalActivity(), "Physical Activity")
        sectionLayout.addView(activityCard)

        return sectionLayout
    }

    private fun createMotivationSection(): LinearLayout {
        val sectionLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins((16 * resources.displayMetrics.density).toInt(), 0, (16 * resources.displayMetrics.density).toInt(), (24 * resources.displayMetrics.density).toInt())
            }
        }

        val sectionHeader = createSectionHeader("🌟 Digital Detox", "Mindful moment")
        sectionLayout.addView(sectionHeader)

        val motivationCard = createExerciseCard(getDailyMotivation(), "Motivation")
        sectionLayout.addView(motivationCard)

        return sectionLayout
    }

    private fun createCelebrationSection(): LinearLayout {
        val sectionLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins((16 * resources.displayMetrics.density).toInt(), 0, (16 * resources.displayMetrics.density).toInt(), (24 * resources.displayMetrics.density).toInt())
            }
        }

        val celebrationCard = createExerciseCard(
            "🎉 Amazing Job!\n\nYou've successfully managed your screen time today! This milestone shows your dedication to digital wellness.\n\nCelebrate your progress!",
            "Mission Complete"
        )
        sectionLayout.addView(celebrationCard)

        return sectionLayout
    }

    private fun createGeneralSection(percentage: Int): LinearLayout {
        val sectionLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins((16 * resources.displayMetrics.density).toInt(), 0, (16 * resources.displayMetrics.density).toInt(), (24 * resources.displayMetrics.density).toInt())
            }
        }

        val generalCard = createExerciseCard(
            "💪 Great Progress!\n\nYou're making strides in managing your screen time.\n\nEach milestone brings you closer to better digital habits!",
            "Progress Update"
        )
        sectionLayout.addView(generalCard)

        return sectionLayout
    }

    private fun createSectionHeader(title: String, subtitle: String): LinearLayout {
        val headerLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, 0, 0, (16 * resources.displayMetrics.density).toInt())
            }
        }

        val titleText = TextView(this).apply {
            text = title
            textSize = 22f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            typeface = ResourcesCompat.getFont(this@MilestoneAlertActivity, R.font.poppins_bold) ?: Typeface.DEFAULT_BOLD
            setShadowLayer(4f, 0f, 2f, Color.parseColor("#66000000"))
        }

        val subtitleText = TextView(this).apply {
            text = subtitle
            textSize = 16f
            setTextColor(Color.parseColor("#CCFFFFFF"))
            gravity = Gravity.CENTER
            typeface = ResourcesCompat.getFont(this@MilestoneAlertActivity, R.font.poppins_regular) ?: Typeface.DEFAULT
        }

        headerLayout.addView(titleText)
        headerLayout.addView(subtitleText)
        return headerLayout
    }

    private fun createExerciseCard(content: String, cardTitle: String): LinearLayout {
        val cardLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            val cardDrawable = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 24f
                setColor(Color.parseColor("#1AFFFFFF"))
                setStroke(3, Color.parseColor("#66FFFFFF"))
            }
            background = cardDrawable
            setPadding((20 * resources.displayMetrics.density).toInt())
            elevation = 12f
        }

        val cardTitleText = TextView(this).apply {
            text = cardTitle
            textSize = 18f
            setTextColor(Color.parseColor("#FFD700"))
            gravity = Gravity.CENTER
            typeface = ResourcesCompat.getFont(this@MilestoneAlertActivity, R.font.poppins_bold) ?: Typeface.DEFAULT_BOLD
            setShadowLayer(3f, 0f, 2f, Color.parseColor("#66000000"))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, 0, 0, (12 * resources.displayMetrics.density).toInt())
            }
        }

        val contentText = TextView(this).apply {
            text = content
            textSize = 16f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            typeface = ResourcesCompat.getFont(this@MilestoneAlertActivity, R.font.poppins_regular) ?: Typeface.DEFAULT
            setLineSpacing(8f, 1.2f)
            setShadowLayer(2f, 0f, 1f, Color.parseColor("#66000000"))
        }

        cardLayout.addView(cardTitleText)
        cardLayout.addView(contentText)
        return cardLayout
    }

    private fun createContinueButtonSection(percentage: Int): LinearLayout {
        val buttonLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, (24 * resources.displayMetrics.density).toInt(), 0, (32 * resources.displayMetrics.density).toInt())
            }
        }

        val continueButton = Button(this).apply {
            text = when (percentage) {
                30 -> "Complete Eye Exercise"
                50 -> "Finish Activity"
                70 -> "Continue Break"
                100 -> "Celebrate!"
                else -> "Keep Going"
            }
            textSize = 16f
            setTextColor(Color.WHITE)
            typeface = ResourcesCompat.getFont(this@MilestoneAlertActivity, R.font.poppins_semibold) ?: Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            
            // Create button background
            val buttonDrawable = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 25f
                colors = getButtonGradientColors(percentage)
                setStroke(2, Color.parseColor("#66FFFFFF"))
            }
            background = buttonDrawable
            
            // Set proper layout parameters
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                (50 * resources.displayMetrics.density).toInt()
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                setMargins(0, (16 * resources.displayMetrics.density).toInt(), 0, 0)
            }
            
            // Set proper padding for text
            setPadding(
                (32 * resources.displayMetrics.density).toInt(),
                (12 * resources.displayMetrics.density).toInt(),
                (32 * resources.displayMetrics.density).toInt(),
                (12 * resources.displayMetrics.density).toInt()
            )
            
            elevation = 8f
            setShadowLayer(6f, 0f, 3f, Color.parseColor("#60000000"))
            setOnClickListener { finish() }
        }

        buttonLayout.addView(continueButton)
        return buttonLayout
    }

    private fun getMilestoneTitle(percentage: Int): String {
        return when (percentage) {
            30 -> "Eye Care Break"
            50 -> "Halfway Milestone"
            70 -> "Digital Detox"
            100 -> "Mission Accomplished!"
            else -> "Progress Milestone"
        }
    }

    private fun getGradientColors(percentage: Int): IntArray {
        return when (percentage) {
            30 -> intArrayOf(Color.parseColor("#0288D1"), Color.parseColor("#01579B")) // Blue
            50 -> intArrayOf(Color.parseColor("#4CAF50"), Color.parseColor("#2E7D32")) // Green
            70 -> intArrayOf(Color.parseColor("#7B1FA2"), Color.parseColor("#4A148C")) // Purple
            100 -> intArrayOf(Color.parseColor("#FF8F00"), Color.parseColor("#EF6C00")) // Amber
            else -> intArrayOf(Color.parseColor("#616161"), Color.parseColor("#424242")) // Gray
        }
    }

    private fun getButtonGradientColors(percentage: Int): IntArray {
        return when (percentage) {
            30 -> intArrayOf(Color.parseColor("#29B6F6"), Color.parseColor("#0288D1"))
            50 -> intArrayOf(Color.parseColor("#66BB6A"), Color.parseColor("#4CAF50"))
            70 -> intArrayOf(Color.parseColor("#AB47BC"), Color.parseColor("#8E24AA"))
            100 -> intArrayOf(Color.parseColor("#FFB300"), Color.parseColor("#FF8F00"))
            else -> intArrayOf(Color.parseColor("#F57C00"), Color.parseColor("#EF6C00"))
        }
    }

    private fun getDailyEyeExercise(): String {
        val eyeExercises = arrayOf(
            "🔄 Slow Blinks\nBlink slowly 20 times, holding each blink for 2 seconds to relax your eyes.",
            "👁️ 20-20-20 Rule\nLook at an object 20 feet away for 20 seconds to rest your eye muscles.",
            "🎯 Focus Shift\nFocus on your finger 6 inches away, then something far. Repeat 10 times.",
            "🔵 Figure 8\nTrace an imaginary figure 8 with your eyes 5 times, 10 feet away.",
            "⬆️ Eye Movements\nLook up, down, left, right for 3 seconds each without moving your head.",
            "🌀 Eye Rolls\nRoll your eyes in circles 5 times clockwise, then counterclockwise.",
            "👆 Near & Far\nFocus on your thumb at arm's length, then something far for 5 seconds each.",
            "✋ Palming\nCup your palms over closed eyes for 30 seconds, breathing deeply.",
            "💧 Rapid Blinks\nBlink rapidly 10 times to stimulate tear production.",
            "😴 Rest & Breathe\nClose your eyes, take 5 deep breaths, and relax for 30 seconds."
        )
        val dayOfYear = java.util.Calendar.getInstance().get(java.util.Calendar.DAY_OF_YEAR)
        return eyeExercises[dayOfYear % eyeExercises.size]
    }

    private fun getDailyPhysicalActivity(): String {
        val physicalActivities = arrayOf(
            "🚶 Quick Walk\nTake a 5-10 minute walk to refresh your mind and body.",
            "🧘 Stretch Break\nDo 5 minutes of neck, shoulder, and back stretches.",
            "🏃 Cardio Burst\nDo 2 minutes of jumping jacks or high knees.",
            "🎯 Active Game\nPlay catch or juggle for 5 minutes to stay active.",
            "💪 Bodyweight Workout\nDo 10 push-ups, 15 squats, or a 30-second plank.",
            "🌿 Nature Moment\nStep outside and observe nature for 5 minutes.",
            "🎵 Dance Party\nDance to a favorite song for 3-5 minutes.",
            "🧘‍♀️ Meditation\nPractice 5 minutes of deep breathing or meditation.",
            "🏠 Quick Chore\nOrganize your desk or water plants for 5 minutes.",
            "📞 Social Break\nCall a friend for a quick, uplifting chat."
        )
        val dayOfYear = java.util.Calendar.getInstance().get(java.util.Calendar.DAY_OF_YEAR)
        return physicalActivities[(dayOfYear + 5) % physicalActivities.size]
    }

    private fun getDailyMotivation(): String {
        val motivationalBreaks = arrayOf(
            "🌱 Reflect\n\"Take 5 minutes to think about your goals and dreams.\"",
            "🧠 Mindful Break\n\"Give your brain a rest with 5 minutes of quiet breathing.\"",
            "💭 Creative Spark\n\"Let your mind wander freely for new ideas.\"",
            "🌍 Real World\n\"Step outside and experience the world beyond screens.\"",
            "💪 Willpower Win\n\"You're mastering technology with every break you take!\"",
            "🎯 Focus Boost\n\"Screen breaks enhance your focus across all tasks.\"",
            "⚖️ Balance\n\"You're creating a healthier tech-life balance.\"",
            "🌟 Be Present\n\"Embrace the moment without digital distractions.\"",
            "🧘 Inner Peace\n\"Connect with yourself in a quiet moment.\"",
            "🚀 Productivity\n\"Breaks boost productivity by 23%. Keep it up!\""
        )
        val dayOfYear = java.util.Calendar.getInstance().get(java.util.Calendar.DAY_OF_YEAR)
        return motivationalBreaks[(dayOfYear + 10) % motivationalBreaks.size]
    }

    private fun startAnimations(headerSection: LinearLayout) {
        val scaleX = ObjectAnimator.ofFloat(headerSection, "scaleX", 0.8f, 1.05f, 1f)
        val scaleY = ObjectAnimator.ofFloat(headerSection, "scaleY", 0.8f, 1.05f, 1f)
        val fadeIn = ObjectAnimator.ofFloat(headerSection, "alpha", 0f, 1f)

        val animatorSet = AnimatorSet()
        animatorSet.playTogether(scaleX, scaleY, fadeIn)
        animatorSet.duration = 1000
        animatorSet.interpolator = AccelerateDecelerateInterpolator()
        animatorSet.start()

        val pulseAnimator = ObjectAnimator.ofFloat(headerSection, "alpha", 1f, 0.95f, 1f)
        pulseAnimator.duration = 2500
        pulseAnimator.repeatCount = ObjectAnimator.INFINITE
        pulseAnimator.startDelay = 1000
        pulseAnimator.start()
    }

    override fun onBackPressed() {
        // Prevent dismissing with back button
    }
}