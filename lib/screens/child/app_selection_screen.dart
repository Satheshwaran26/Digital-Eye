import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_apps/device_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:math';

class AppSelectionScreen extends StatefulWidget {
  final VoidCallback? onBlocked;
  const AppSelectionScreen({super.key, this.onBlocked});

  @override
  State<AppSelectionScreen> createState() => _AppSelectionScreenState();
}

class _AppSelectionScreenState extends State<AppSelectionScreen>
    with WidgetsBindingObserver {
  // Milestone percentages for notifications (30%, 50%, 70%, and 100%)
  static const List<int> _milestonePercentages = [30, 50, 70, 100];
  // Map to track if a milestone has been triggered to prevent repeated notifications
  final Map<int, bool> _milestoneTriggered = {
    30: false,
    50: false,
    70: false,
    100: false
  };

  List<AppInfo>? _apps; // All installed apps
  List<AppInfo> _filteredApps = []; // Apps filtered by search query
  Set<String> _blockedPackages = {}; // Apps selected by the user to be blocked
  bool _loading = false; // Loading indicator for app list
  static const platform =
      MethodChannel('app_blocker'); // Platform channel for native communication

  // Timer related state
  int _remainingSeconds = 0; // Current remaining seconds until apps are locked
  double _totalBlockDurationHours =
      0.0; // The initial duration set by the user in hours
  List<String> _currentBlockedApps =
      []; // List of package names that are currently subject to blocking

  // Native communication state
  bool _isSelectedAppInForeground =
      false; // True if a user-selected app is currently in foreground
  String?
      _currentForegroundPackageName; // Package name of the app currently in foreground
  String? _currentForegroundAppName; // Name of the app currently in foreground
  bool _isMonitoringActive = false; // True when timer is actively counting down
  bool _isScreenActive = true; // Track if screen is active
  Timer? _uiSyncTimer; // Timer to periodically sync UI state
  int _lastReceivedSeconds =
      -1; // Track last received seconds to prevent duplicates

  // Constants
  static const String _currentAppPackage =
      'com.example.my_app'; // Package name of this app
  static const String _youTubePackage =
      'com.google.android.youtube'; // Example allowed app

  static const Duration cacheValidity =
      Duration(minutes: 15); // Duration for app list cache validity
  static const int maxApps =
      10; // Maximum number of apps a user can select to block

  // Messages for milestone notifications
  final List<String> _greetingMessages = [
    "🌟 30% complete! You're off to a great start!",
    "💪 Keep it up! Making good progress!",
    "🎯 Nice work! Stay focused!",
    "✨ 30% done! You've got this!",
    "🚀 Great start! Keep going strong!",
  ];

  final List<String> _halfwayMessages = [
    "🌟 Halfway through! Keep up the great focus!",
    "💪 You've made it to 50%! Stay strong!",
    "🎯 Excellent progress! Halfway to your goal!",
    "✨ 50% complete! You're doing amazing!",
    "🌈 Halfway milestone reached! Keep going!",
  ];

  final List<String> _warningMessages = [
    "⏰ Time check: 30% of your time remaining!",
    "⚡ Almost there! Just 30% more to go!",
    "🔔 Heads up: 70% of time has passed!",
    "📊 Progress update: 70% complete!",
    "🎯 Final stretch! 30% remaining!",
  ];

  final List<String> _completionMessages = [
    "🎉 Congratulations! Timer completed successfully!",
    "✅ Well done! You've finished your session!",
    "🏆 Great job! Time's up - mission accomplished!",
    "🌟 Excellent! You've completed your focus time!",
    "💫 Amazing! You've reached your goal!",
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBlockedApps();
    _checkPermissions();
    _preloadApps();
    _setupNativeMethodHandlers();
    _loadBlockState();
    _startPeriodicSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiSyncTimer?.cancel();
    _localCountdownTimer?.cancel();
    platform.setMethodCallHandler(null);
    setState(() {
      _isScreenActive = false;
    });
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setupNativeMethodHandlers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshMonitoringState();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _setupNativeMethodHandlers();
      _refreshMonitoringState();
      setState(() {
        _isScreenActive = true;
      });
    } else if (state == AppLifecycleState.paused) {
      setState(() {
        _isScreenActive = false;
      });
    }
  }

  // Widget to show timer progress
  Widget _buildTimerProgress() {
    final totalSeconds = (_totalBlockDurationHours * 3600).toInt();
    double progress = 0.0;
    if (totalSeconds > 0 && _remainingSeconds >= 0) {
      progress = 1 - (_remainingSeconds / totalSeconds);
      progress = progress.clamp(0.0, 1.0);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _remainingSeconds <= 0 && _totalBlockDurationHours > 0
                    ? 'Ready to Monitor'
                    : 'Time Remaining',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_isMonitoringActive)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Text(
                        'Active',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_remainingSeconds <= 0 && _totalBlockDurationHours > 0)
            Text(
              _totalBlockDurationHours < 1.0
                  ? 'Ready to Start: ${(_totalBlockDurationHours * 60).toInt()} minutes'
                  : 'Ready to Start: ${_totalBlockDurationHours.toStringAsFixed(1)} hours',
              style: const TextStyle(
                color: Color(0xFF2196F3),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            )
          else if (_remainingSeconds <= 0)
            const Text(
              'Set up monitoring to begin',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            Column(
              children: [
                Text(
                  _formatTime(_remainingSeconds),
                  style: const TextStyle(
                    color: Color(0xFF2196F3),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_isMonitoringActive)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '⚡ COUNTING DOWN',
                      style: TextStyle(
                        color: Colors.green[400],
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
              ],
            ),
          if (_isMonitoringActive && _currentForegroundAppName != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green, width: 1),
                ),
                child: Text(
                  '⏱️ Using: $_currentForegroundAppName',
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          else if (_remainingSeconds > 0 && _totalBlockDurationHours > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '⏸️ Timer Paused - Open a selected app to resume',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Stack(
            children: [
              Container(
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: _getProgressColor(progress),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${(progress * 100).toInt()}% Complete',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // Format timer display to prevent flickering
  String _formatTime(int seconds) {
    if (seconds <= 0) return '0h 0m 0s';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return '${hours}h ${minutes}m ${secs}s';
  }

  // Get progress bar color based on completion percentage
  Color _getProgressColor(double progress) {
    if (progress < 0.5) return Colors.green;
    if (progress < 0.7) return Colors.orange;
    return Colors.red;
  }

  // Start periodic sync to ensure UI stays updated
  void _startPeriodicSync() {
    _uiSyncTimer?.cancel();
    _uiSyncTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // Only sync if we haven't received an update in the last 15 seconds
      if (_currentBlockedApps.isNotEmpty && _totalBlockDurationHours > 0) {
        debugPrint('🔄 Periodic sync check...');
        _refreshMonitoringState();
      }
    });
  }

  // Refresh monitoring state
  Future<void> _refreshMonitoringState() async {
    try {
      debugPrint('🔄 Refreshing monitoring state...');
      if (_currentBlockedApps.isNotEmpty && _totalBlockDurationHours > 0) {
        final bool hasUsagePermission =
            await platform.invokeMethod('checkUsageStatsPermission');
        if (hasUsagePermission) {
          final durationSeconds = (_totalBlockDurationHours * 3600).toInt();
          await platform.invokeMethod('startMonitoring', {
            'packageNames': _currentBlockedApps,
            'durationSeconds': durationSeconds,
          });
          debugPrint('✅ Monitoring refreshed successfully');
          await Future.delayed(const Duration(milliseconds: 500));
          debugPrint('🔄 Requested immediate status update');
        }
      }
    } catch (e) {
      debugPrint('❌ Error refreshing monitoring state: $e');
    }
  }

  // Loads any previously saved block state
  Future<void> _loadBlockState() async {
    final prefs = await SharedPreferences.getInstance();
    final remainingSecs = prefs.getInt('remainingSeconds') ?? 0;
    final totalDurationHrs = prefs.getDouble('totalBlockDurationHours') ?? 0.0;
    final blockedApps = prefs.getStringList('currentBlockedApps') ?? [];

    if (remainingSecs > 0 && blockedApps.isNotEmpty && totalDurationHrs > 0) {
      setState(() {
        _totalBlockDurationHours = totalDurationHrs;
        _currentBlockedApps = blockedApps;
      });
      debugPrint(
          'Loaded block state: remaining=$remainingSecs, total_duration=$totalDurationHrs, apps=${_currentBlockedApps.length}');
      final durationSeconds = (_totalBlockDurationHours * 3600).toInt();
      _startNativeMonitoring(durationSeconds);
    } else {
      await prefs.remove('remainingSeconds');
      await prefs.remove('totalBlockDurationHours');
      await prefs.remove('currentBlockedApps');
      debugPrint('Cleared stale block state');
    }
  }

  // Saves the current block state
  Future<void> _saveBlockState() async {
    final prefs = await SharedPreferences.getInstance();
    if (_remainingSeconds > 0 &&
        _currentBlockedApps.isNotEmpty &&
        _totalBlockDurationHours > 0) {
      await prefs.setInt('remainingSeconds', _remainingSeconds);
      await prefs.setDouble(
          'totalBlockDurationHours', _totalBlockDurationHours);
      await prefs.setStringList('currentBlockedApps', _currentBlockedApps);
      debugPrint(
          'Saved block state: remaining=$_remainingSeconds, total_duration=$_totalBlockDurationHours, apps=${_currentBlockedApps.length}');
    } else {
      await prefs.remove('remainingSeconds');
      await prefs.remove('totalBlockDurationHours');
      await prefs.remove('currentBlockedApps');
      debugPrint('Cleared block state');
    }
  }

  // Manages the countdown timer
  void _manageCountdown() {
    if (_currentBlockedApps.isEmpty || _totalBlockDurationHours <= 0) {
      debugPrint(
          'Invalid state for countdown. Apps: ${_currentBlockedApps.length}, Duration: $_totalBlockDurationHours');
      _finalizeBlockState();
      return;
    }
    final durationSeconds = (_totalBlockDurationHours * 3600).toInt();
    _startNativeMonitoring(durationSeconds);
  }

  // Starts the native monitoring service
  Future<void> _startNativeMonitoring(int durationSeconds) async {
    try {
      debugPrint(
          '🚀 Starting native monitoring for ${_currentBlockedApps.length} apps for ${durationSeconds}s');
      _milestoneTriggered
          .forEach((key, value) => _milestoneTriggered[key] = false);

      // Start the background service
      await platform.invokeMethod('startMonitoring', {
        'packageNames': _currentBlockedApps,
        'durationSeconds': durationSeconds,
      });

      debugPrint('✅ Native monitoring started successfully');

      // Start a local countdown timer as backup in case native communication fails
      _startLocalCountdownBackup(durationSeconds);
    } catch (e) {
      debugPrint('❌ Error starting native monitoring: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to start monitoring: $e'),
              backgroundColor: Colors.red),
        );
      }
      _finalizeBlockState();
    }
  }

  // Backup countdown timer in case native service communication fails
  Timer? _localCountdownTimer;

  void _startLocalCountdownBackup(int durationSeconds) {
    _localCountdownTimer?.cancel();
    int localRemainingSeconds = durationSeconds;

    _localCountdownTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || _currentBlockedApps.isEmpty) {
        timer.cancel();
        return;
      }

      // Only use local countdown if we haven't received updates from native service for a while
      final timeSinceLastUpdate =
          DateTime.now().millisecondsSinceEpoch - (_lastUpdateTime ?? 0);
      if (timeSinceLastUpdate > 10000) {
        // 10 seconds without native update
        localRemainingSeconds -= 5;
        debugPrint(
            '📱 Using local countdown backup: ${localRemainingSeconds}s remaining');

        setState(() {
          _remainingSeconds = localRemainingSeconds;
        });

        if (localRemainingSeconds <= 0) {
          timer.cancel();
          _handleLocalTimeUp();
        }
      }
    });
  }

  int? _lastUpdateTime;

  void _handleLocalTimeUp() {
    debugPrint('⏰ Local timer completed - native service may have failed');
    setState(() {
      _remainingSeconds = 0;
      _isMonitoringActive = false;
    });
    _finalizeBlockState();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Timer completed! Apps are now locked.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // Triggers milestone notifications
  void _triggerMilestoneNotifications(
      int elapsedSeconds, int totalDurationSeconds) {
    final percentageElapsed =
        (elapsedSeconds / totalDurationSeconds * 100).round();
    debugPrint('🎯 Milestone check: ${percentageElapsed}% elapsed');
    for (final milestone in _milestonePercentages) {
      if (percentageElapsed >= milestone && !_milestoneTriggered[milestone]!) {
        debugPrint('🎉 Triggering $milestone% milestone');
        _milestoneTriggered[milestone] = true;
        _showMilestoneDialog(milestone, elapsedSeconds, totalDurationSeconds);
        _sendBackgroundNotification(
            milestone, elapsedSeconds, totalDurationSeconds);
      }
    }
  }

  // Show AlertDialog for milestone notifications
  void _showMilestoneDialog(
      int milestone, int elapsedSeconds, int totalDurationSeconds) {
    if (!mounted) return;
    String title;
    String message;
    Color dialogColor;
    IconData dialogIcon;

    switch (milestone) {
      case 30:
        title = '🎯 30% Complete!';
        message = _greetingMessages[Random().nextInt(_greetingMessages.length)];
        dialogColor = Colors.green;
        dialogIcon = Icons.trending_up;
        break;
      case 50:
        title = '🌟 Halfway There!';
        message = _halfwayMessages[Random().nextInt(_halfwayMessages.length)];
        dialogColor = Colors.blue;
        dialogIcon = Icons.star;
        break;
      case 70:
        title = '⚡ Final Stretch!';
        message = _warningMessages[Random().nextInt(_warningMessages.length)];
        dialogColor = Colors.orange;
        dialogIcon = Icons.warning_amber;
        break;
      case 100:
        title = '🎉 Time\'s Up!';
        message =
            _completionMessages[Random().nextInt(_completionMessages.length)];
        dialogColor = Colors.purple;
        dialogIcon = Icons.celebration;
        break;
      default:
        return;
    }

    final remainingMinutes =
        ((totalDurationSeconds - elapsedSeconds) / 60).round();
    final elapsedMinutes = (elapsedSeconds / 60).round();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2D2D2D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: dialogColor, width: 2),
          ),
          title: Row(
            children: [
              Icon(dialogIcon, color: dialogColor, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: dialogColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Progress:',
                            style: TextStyle(
                                color: Colors.grey[300], fontSize: 14)),
                        Text('$milestone% Complete',
                            style: TextStyle(
                                color: dialogColor,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Time Used:',
                            style: TextStyle(
                                color: Colors.grey[300], fontSize: 14)),
                        Text('${elapsedMinutes}m',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14)),
                      ],
                    ),
                    if (milestone < 100) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Time Left:',
                              style: TextStyle(
                                  color: Colors.grey[300], fontSize: 14)),
                          Text('${remainingMinutes}m',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: dialogColor.withOpacity(0.1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  milestone == 100 ? 'Awesome!' : 'Keep Going!',
                  style: TextStyle(
                      color: dialogColor, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Show timer completion dialog
  void _showTimerCompletionDialog(
      String message, int totalUsedSeconds, int originalDurationSeconds) {
    if (!mounted || !_isScreenActive) return;

    final usedMinutes = (totalUsedSeconds / 60).round();
    final totalMinutes = (originalDurationSeconds / 60).round();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.green, width: 2),
        ),
        title: Row(
          children: [
            Icon(Icons.celebration, color: Colors.amber, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Timer Complete!',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.isNotEmpty
                  ? message
                  : '🎉 Congratulations! You successfully completed your focus session.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Session Time:',
                          style:
                              TextStyle(color: Colors.grey[300], fontSize: 14)),
                      Text('${totalMinutes}m',
                          style: TextStyle(
                              color: Colors.green,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Time Used:',
                          style:
                              TextStyle(color: Colors.grey[300], fontSize: 14)),
                      Text('${usedMinutes}m',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Navigate back to home or parent screen
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.green.withOpacity(0.1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Great Job!',
                style:
                    TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Send background notification for milestone
  void _sendBackgroundNotification(
      int milestone, int elapsedSeconds, int totalDurationSeconds) {
    String title;
    String body;

    switch (milestone) {
      case 30:
        title = '🎯 30% Complete!';
        body =
            'Great start! You\'ve used ${(elapsedSeconds / 60).round()} minutes of your session.';
        break;
      case 50:
        title = '🌟 Halfway There!';
        body =
            'Excellent progress! You\'re halfway through your ${(totalDurationSeconds / 60).round()}-minute session.';
        break;
      case 70:
        title = '⚡ Final Stretch!';
        body =
            '70% complete! Only ${((totalDurationSeconds - elapsedSeconds) / 60).round()} minutes remaining.';
        break;
      case 100:
        title = '🎉 Session Complete!';
        body =
            'Congratulations! You\'ve successfully completed your ${(totalDurationSeconds / 60).round()}-minute focus session.';
        break;
      default:
        return;
    }

    // Notification removed
  }

  // Shows blocking overlay when time is up
  void _showBlockingOverlay(String appName) async {
    try {
      final bool hasOverlayPermission =
          await platform.invokeMethod('checkOverlayPermission');
      if (hasOverlayPermission) {
        if (mounted) {
          // Use a more robust dialog that won't cause black screens
          showDialog(
            context: context,
            barrierDismissible: false,
            barrierColor: Colors.black.withOpacity(0.8),
            builder: (context) => WillPopScope(
              onWillPop: () async => false, // Prevent back button
              child: AlertDialog(
                backgroundColor: const Color(0xFF2D2D2D),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Colors.red, width: 2),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.lock, color: Colors.red, size: 28),
                    SizedBox(width: 10),
                    Text('App Blocked',
                        style: TextStyle(
                            color: Colors.red,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$appName is locked. Time limit reached.',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 16),
                    const Text(
                      'Please return to the home screen',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      // Force go to home screen
                      platform.invokeMethod('goToHome');
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('OK',
                          style: TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } else {
        await platform.invokeMethod('requestOverlayPermission');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please grant overlay permission to block apps'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error showing blocking overlay: $e');
    }
  }

  // Cleans up block state
  void _finalizeBlockState() {
    debugPrint('Finalizing block state');
    setState(() {
      _remainingSeconds = 0;
      _currentBlockedApps.clear();
      _totalBlockDurationHours = 0.0;
      _milestoneTriggered.forEach((key, _) => _milestoneTriggered[key] = false);
      _isSelectedAppInForeground = false;
      _currentForegroundPackageName = null;
      _currentForegroundAppName = null;
      _isMonitoringActive = false;
    });
    _saveBlockState();
  }

  // Checks and requests permissions
  Future<void> _checkPermissions() async {
    try {
      final bool hasQueryPermission =
          await platform.invokeMethod('checkQueryAllPackagesPermission');
      if (!hasQueryPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Please grant permission to list apps'),
                backgroundColor: Colors.red),
          );
        }
        return;
      }
      final bool hasUsagePermission =
          await platform.invokeMethod('checkUsageStatsPermission');
      if (!hasUsagePermission) {
        await platform.invokeMethod('requestUsageStatsPermission');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Please grant Usage Access permission'),
                backgroundColor: Colors.red),
          );
        }
      }
      final bool hasOverlayPermission =
          await platform.invokeMethod('checkOverlayPermission');
      if (!hasOverlayPermission) {
        await platform.invokeMethod('requestOverlayPermission');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Please grant Overlay permission'),
                backgroundColor: Colors.red),
          );
        }
      }
      debugPrint(
          'Permissions: Query=$hasQueryPermission, Usage=$hasUsagePermission, Overlay=$hasOverlayPermission');
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Permission error: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // Preloads and caches apps
  Future<void> _preloadApps() async {
    setState(() {
      _loading = true;
    });
    try {
      final cachedApps = await _loadAppsFromCache();
      if (cachedApps != null && cachedApps.isNotEmpty) {
        setState(() {
          _apps = cachedApps;
          _filteredApps = cachedApps;
          _loading = false;
        });
        debugPrint('Loaded ${cachedApps.length} apps from cache');
        return;
      }
      await _loadApps();
    } catch (e) {
      debugPrint('Error preloading apps: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to preload apps: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  // Loads apps from device
  Future<void> _loadApps() async {
    setState(() {
      _loading = true;
    });
    try {
      final installedApps = await DeviceApps.getInstalledApplications(
        includeAppIcons: true,
        includeSystemApps: false,
        onlyAppsWithLaunchIntent: true,
      );
      debugPrint('Total installed apps: ${installedApps.length}');
      final filteredInstalledApps = installedApps.where((app) {
        final allowedPackages = [_youTubePackage];
        if (allowedPackages.contains(app.packageName)) return true;
        final isExcluded = app.packageName.startsWith('com.android.') ||
            app.packageName.startsWith('com.google.android.') ||
            app.packageName.startsWith('com.sec.android.') ||
            app.packageName == 'android' ||
            app.packageName == _currentAppPackage;
        return !isExcluded;
      }).toList();
      debugPrint(
          'Filtered apps: ${filteredInstalledApps.map((a) => a.packageName).toList()}');
      final myApps = filteredInstalledApps
          .map((app) => AppInfo.fromApplication(app))
          .toList()
        ..sort((a, b) => a.appName.compareTo(b.appName));
      setState(() {
        _apps = myApps;
        _filteredApps = myApps;
      });
      if (myApps.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No user-installed apps found'),
                backgroundColor: Colors.orange),
          );
        }
      }
      await _cacheApps(myApps);
      debugPrint('Loaded and cached ${myApps.length} apps');
    } catch (e) {
      debugPrint('Error loading apps: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load apps: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  // Loads cached app list
  Future<List<AppInfo>?> _loadAppsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('cachedApps');
      final cacheTimeString = prefs.getString('cacheTimestamp');
      if (jsonString == null || cacheTimeString == null) {
        debugPrint('No cache found');
        return null;
      }
      final cacheTime = DateTime.parse(cacheTimeString);
      if (DateTime.now().difference(cacheTime) > cacheValidity) {
        debugPrint('Cache expired');
        await prefs.remove('cachedApps');
        await prefs.remove('cacheTimestamp');
        return null;
      }
      final jsonList = json.decode(jsonString) as List;
      final apps = jsonList.map((json) => AppInfo.fromJson(json)).toList();
      debugPrint('Cache loaded: ${apps.length} apps');
      return apps.isNotEmpty ? apps : null;
    } catch (e) {
      debugPrint('Error loading from cache: $e');
      await SharedPreferences.getInstance().then((prefs) async {
        await prefs.remove('cachedApps');
        await prefs.remove('cacheTimestamp');
      });
      return null;
    }
  }

  // Caches the app list
  Future<void> _cacheApps(List<AppInfo> apps) async {
    try {
      // --- Step 1: Cache locally on the child device ---
      final prefs = await SharedPreferences.getInstance();
      final jsonList = apps.map((app) => app.toJson()).toList();
      await prefs.setString('cachedApps', json.encode(jsonList));
      await prefs.setString('cacheTimestamp', DateTime.now().toIso8601String());
      debugPrint('Cached ${apps.length} apps locally.');

      // --- Step 2: Upload the app list to Firestore for the parent to access ---
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Use the child's own UID
        final childId = user.uid;
        // We store this in a subcollection for clarity
        final installedAppsCollection = FirebaseFirestore.instance
            .collection('users')
            .doc(childId)
            .collection('deviceInfo');

        // Firestore has document size limits, so we write each app as a separate doc
        for (final app in apps) {
          await installedAppsCollection.doc(app.packageName).set(app.toJson());
        }
        debugPrint(
            'Uploaded ${apps.length} app details to Firestore for parent access.');
      }
    } catch (e) {
      debugPrint('Error caching or uploading apps: $e');
    }
  }

  // Sets up method call handlers
  void _setupNativeMethodHandlers() {
    debugPrint('🔗 Setting up native method handlers...');
    platform.setMethodCallHandler((call) async {
      if (!mounted) return null;
      try {
        switch (call.method) {
          case "updateForegroundAppStatus":
            final isSelectedAppInForeground =
                call.arguments['isInForeground'] as bool? ?? false;
            final packageName = call.arguments['packageName'] as String? ?? '';
            final appName = call.arguments['appName'] as String? ?? '';
            final remainingSeconds =
                call.arguments['remainingSeconds'] as int? ?? _remainingSeconds;
            final totalUsedSeconds =
                call.arguments['totalUsedSeconds'] as int? ?? 0;
            final isMonitoringActive =
                call.arguments['isMonitoringActive'] as bool? ?? false;

            debugPrint(
                '🔄 Native update received: remaining=${remainingSeconds}s, active=$isMonitoringActive, app=$appName');

            // Track the last update time for backup countdown
            _lastUpdateTime = DateTime.now().millisecondsSinceEpoch;

            // Always update countdown when monitoring is active, but be selective for other updates
            final hasTimerUpdate = remainingSeconds >= 0 &&
                remainingSeconds != _lastReceivedSeconds;
            final hasStateChange =
                _isSelectedAppInForeground != isSelectedAppInForeground ||
                    _currentForegroundPackageName != packageName ||
                    _currentForegroundAppName != appName ||
                    _isMonitoringActive != isMonitoringActive;

            // Update if there's a timer change OR if there's a state change
            if (hasTimerUpdate || hasStateChange) {
              final oldRemainingSeconds = _remainingSeconds;
              debugPrint(
                  '🎯 Updating UI: timer=$hasTimerUpdate, state=$hasStateChange, old=${oldRemainingSeconds}s, new=${remainingSeconds}s');

              setState(() {
                _isSelectedAppInForeground = isSelectedAppInForeground;
                _currentForegroundPackageName = packageName;
                _currentForegroundAppName = appName;
                // Always update remaining seconds if it's a valid value
                if (remainingSeconds >= 0) {
                  _remainingSeconds = remainingSeconds;
                  _lastReceivedSeconds = remainingSeconds;
                  debugPrint(
                      '📊 Timer update: ${_remainingSeconds}s remaining, active: $isMonitoringActive');
                }
                _isMonitoringActive =
                    isMonitoringActive && remainingSeconds > 0;
              });

              // Always save state when timer changes
              if (hasTimerUpdate || oldRemainingSeconds != _remainingSeconds) {
                _saveBlockState();
              }

              if (isMonitoringActive && totalUsedSeconds > 0) {
                final totalSeconds = (_totalBlockDurationHours * 3600).toInt();
                _triggerMilestoneNotifications(totalUsedSeconds, totalSeconds);
              }
            } else {
              debugPrint('⏸️ Skipping update: no significant changes detected');
            }
            break;

          case "onTimeUp":
            final Map<String, dynamic>? data =
                call.arguments as Map<String, dynamic>?;
            final List<String> terminatedApps = data != null
                ? List<String>.from(data['terminatedApps'] ?? [])
                : [];
            final int totalUsed = data?['totalUsedSeconds'] ?? 0;
            final int originalDuration = data?['originalDuration'] ?? 0;
            final bool showCompletionDialog =
                data?['showCompletionDialog'] ?? false;
            final String message = data?['message'] ?? '';

            debugPrint(
                '⏰ TIME UP! Apps terminated: ${terminatedApps.join(", ")}');

            if (mounted) {
              setState(() {
                _remainingSeconds = 0;
                _isMonitoringActive = false;
                _isSelectedAppInForeground = false;
                // DON'T clear blocked apps - keep them blocked
                // _currentBlockedApps.clear();
                // DON'T reset duration - this maintains blocking state
                // _totalBlockDurationHours = 0.0;
              });
              // Save the blocking state (not cleared state)
              _saveBlockingCompleteState();

              // Show completion dialog or milestone dialog
              if (showCompletionDialog) {
                _showTimerCompletionDialog(
                    message, totalUsed, originalDuration);
              } else {
                // Ensure 100% milestone is shown
                _showMilestoneDialog(100, originalDuration, originalDuration);
                // Also show completion dialog after a short delay
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) {
                    _showTimerCompletionDialog(
                        message, totalUsed, originalDuration);
                  }
                });
              }
            }
            break;

          case "requestPermission":
            final permissionType = call.arguments['type'] as String?;
            switch (permissionType) {
              case "usageStats":
                await platform.invokeMethod('requestUsageStatsPermission');
                break;
              case "overlay":
                await platform.invokeMethod('requestOverlayPermission');
                break;
            }
            break;

          case "unlockApp":
            final String? packageName =
                call.arguments['packageName'] as String?;
            if (packageName != null) {
              setState(() {
                _blockedPackages.remove(packageName);
                _currentBlockedApps.remove(packageName);
              });
              await _saveBlockedApps();
              await _saveBlockState();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$packageName has been unblocked')),
                );
              }
            }
            break;

          default:
            debugPrint('Unknown method called from native: ${call.method}');
        }
      } catch (e) {
        debugPrint('Error handling native method call: $e');
      }
      return null;
    });
    debugPrint('✅ Native method handlers set up successfully');
  }

  // Test monitoring
  Future<void> _testMonitoring() async {
    try {
      debugPrint('🔍 Testing monitoring functionality...');
      final diagnostics = await platform.invokeMethod('testMonitoring');
      final hasUsagePermission =
          await platform.invokeMethod('checkUsageStatsPermission') as bool;
      final hasOverlayPermission =
          await platform.invokeMethod('checkOverlayPermission') as bool;
      debugPrint(
          '🔐 Permissions - Usage: $hasUsagePermission, Overlay: $hasOverlayPermission');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Monitoring Test Results'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Usage Stats New: ${hasUsagePermission ? "✅ Granted" : "❌ Missing"}'),
                Text(
                    'Overlay Permission: ${hasOverlayPermission ? "✅ Granted" : "❌ Missing"}'),
                const SizedBox(height: 10),
                Text('SDK Version: ${diagnostics['sdkVersion']}'),
                Text('Package: ${diagnostics['packageName']}'),
                const SizedBox(height: 10),
                Text(
                  hasUsagePermission && hasOverlayPermission
                      ? '✅ Monitoring should work!'
                      : '❌ Missing permissions - monitoring may not work',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: hasUsagePermission && hasOverlayPermission
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
              if (!hasUsagePermission)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    platform.invokeMethod('requestUsageStatsPermission');
                  },
                  child: const Text('Grant Usage Permission'),
                ),
              if (!hasOverlayPermission)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    platform.invokeMethod('requestOverlayPermission');
                  },
                  child: const Text('Grant Overlay Permission'),
                ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error testing monitoring: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Test failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Confirm block with timer
  Future<void> _confirmBlockWithTimer() async {
    if (_blockedPackages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select at least one app to monitor'),
            backgroundColor: Colors.red),
      );
      return;
    }
    if (_totalBlockDurationHours <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a duration greater than 0'),
            backgroundColor: Colors.red),
      );
      return;
    }

    // Check if session is already completed today
    final prefs = await SharedPreferences.getInstance();
    final sessionCompletedToday =
        prefs.getBool('sessionCompletedToday') ?? false;

    if (sessionCompletedToday) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Session already completed today. Try again tomorrow!'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      setState(() {
        _currentBlockedApps = _blockedPackages.toList();
        _isMonitoringActive = false;
      });
      await _saveBlockState();
      // MODIFIED: Save apps with the selected duration
      await _saveBlockedApps(durationHours: _totalBlockDurationHours);
      final bool hasOverlayPermission =
          await platform.invokeMethod('checkOverlayPermission');
      if (!hasOverlayPermission) {
        await platform.invokeMethod('requestOverlayPermission');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Please grant overlay permission to monitor apps'),
                backgroundColor: Colors.orange),
          );
        }
        return;
      }
      _manageCountdown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Apps ready for monitoring',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('Timer will start when you use any of these apps',
                    style: TextStyle(fontSize: 12)),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.green,
          ),
        );
        if (widget.onBlocked != null) {
          widget.onBlocked!();
        }
        Navigator.of(context).pop();
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      debugPrint('Error in confirmation process: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error setting up monitoring: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // Saves the blocking complete state (keep apps blocked)
  Future<void> _saveBlockingCompleteState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('remainingSeconds', 0); // Timer complete
    await prefs.setDouble('totalBlockDurationHours',
        _totalBlockDurationHours); // Keep original duration
    await prefs.setStringList(
        'currentBlockedApps', _currentBlockedApps); // Keep blocked apps
    await prefs.setBool('blocking_complete', true); // Mark as blocking complete
    await prefs.setInt(
        'blocking_complete_time', DateTime.now().millisecondsSinceEpoch);
    debugPrint(
        'Saved BLOCKING COMPLETE state: apps remain blocked=${_currentBlockedApps.length}');
  }

  // Loads blocked apps
  Future<void> _loadBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final blockedList = prefs.getStringList('blocked_apps') ?? [];
    setState(() {
      _blockedPackages = blockedList.toSet();
    });
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'blockedApps': blockedList,
      }, SetOptions(merge: true));
    } else {
      debugPrint('Firebase user not signed in.');
    }
    debugPrint('Loaded ${_blockedPackages.length} blocked apps');
  }

  // MODIFIED: Saves blocked apps to local storage and Firestore, now with optional duration.
  Future<void> _saveBlockedApps({double? durationHours}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('blocked_apps', _blockedPackages.toList());

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint(
          'Child user not signed in. Cannot save blocked apps to Firestore.');
      return;
    }

    final childId = user.uid;
    final blockedAppsCollection = FirebaseFirestore.instance
        .collection('users')
        .doc(childId)
        .collection('blockedApps');

    final existingBlockedAppsSnapshot = await blockedAppsCollection.get();
    final existingPackages =
        existingBlockedAppsSnapshot.docs.map((doc) => doc.id).toSet();

    final batch = FirebaseFirestore.instance.batch();

    // Add new apps or update existing ones
    for (final packageName in _blockedPackages) {
      final appInfo =
          _apps?.firstWhere((app) => app.packageName == packageName);
      final appNameToSave = appInfo?.appName ?? packageName;

      // Prepare data, including duration if available
      final Map<String, dynamic> dataToSet = {
        'appName': appNameToSave,
        'packageName': packageName,
        'blockedAt': Timestamp.now(),
        if (durationHours != null) 'durationHours': durationHours,
      };

      batch.set(blockedAppsCollection.doc(packageName), dataToSet,
          SetOptions(merge: true));
    }

    // Remove old apps that are no longer in the selection
    for (final doc in existingBlockedAppsSnapshot.docs) {
      if (!_blockedPackages.contains(doc.id)) {
        batch.delete(doc.reference);
      }
    }

    await batch.commit();
    debugPrint(
        'Saved/Updated ${_blockedPackages.length} blocked apps to Firestore for childId: $childId');
  }

  // Widget to build duration picker
  Widget _buildDurationPicker() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _blockApps,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text(
                'Set Timer',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for preset duration buttons
  Widget _buildPresetButton(double hours, String label) {
    final isSelected = _totalBlockDurationHours == hours;
    return InkWell(
      onTap: () {
        setState(() {
          _totalBlockDurationHours = hours;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3) : Colors.grey[800],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[400],
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 0, 0, 0),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF000000),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Color(0xFF2196F3),
            size: 28,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Select Apps to Block',
            style: TextStyle(
                color: Color(0xFF2196F3),
                fontSize: 24,
                fontWeight: FontWeight.w400)),
      ),
      body: Builder(
        builder: (BuildContext scaffoldContext) {
          return Column(
            children: [
              if (_remainingSeconds > 0 || _totalBlockDurationHours > 0)
                _buildTimerProgress(),
              if (_blockedPackages.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Selected Apps: ${_blockedPackages.length}/$maxApps',
                          style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500)),
                      if (_blockedPackages.length >= maxApps)
                        const Text('Maximum limit reached',
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.red,
                                fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFF2196F3)))
                    : _filteredApps.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.app_blocking,
                                    size: 64, color: Colors.grey[700]),
                                const SizedBox(height: 16),
                                const Text('No apps found',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Text('Check permissions or install apps',
                                    style: TextStyle(
                                        color: Colors.grey[500], fontSize: 14)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredApps.length,
                            itemBuilder: (context, index) {
                              final app = _filteredApps[index];
                              final isBlocked =
                                  _blockedPackages.contains(app.packageName);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A1A),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isBlocked
                                        ? const Color(0xFF2196F3)
                                            .withOpacity(0.3)
                                        : Colors.grey.withOpacity(0.2),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 12,
                                  ),
                                  leading: Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: app.icon != null
                                          ? Image.memory(
                                              app.icon!,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                return Container(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin: Alignment.topLeft,
                                                      end:
                                                          Alignment.bottomRight,
                                                      colors: [
                                                        const Color(0xFF2196F3)
                                                            .withOpacity(0.2),
                                                        const Color(0xFF1976D2)
                                                            .withOpacity(0.1),
                                                      ],
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            16),
                                                  ),
                                                  child: const Icon(
                                                    Icons.apps,
                                                    color: Color(0xFF2196F3),
                                                    size: 18,
                                                  ),
                                                );
                                              },
                                            )
                                          : Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    const Color(0xFF2196F3)
                                                        .withOpacity(0.2),
                                                    const Color(0xFF1976D2)
                                                        .withOpacity(0.1),
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              child: const Icon(
                                                Icons.apps,
                                                color: Color(0xFF2196F3),
                                                size: 18,
                                              ),
                                            ),
                                    ),
                                  ),
                                  title: Text(
                                    app.appName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Poppins',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Container(
                                    decoration: BoxDecoration(
                                      color: isBlocked
                                          ? const Color(0xFF2196F3)
                                              .withOpacity(0.2)
                                          : Colors.grey.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isBlocked
                                            ? const Color(0xFF2196F3)
                                            : Colors.grey.withOpacity(0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Transform.scale(
                                      scale: 1.3,
                                      child: Checkbox(
                                        value: isBlocked,
                                        activeColor: const Color(0xFF2196F3),
                                        checkColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        side: BorderSide(
                                          color: isBlocked
                                              ? const Color(0xFF2196F3)
                                              : Colors.grey.withOpacity(0.5),
                                          width: 2,
                                        ),
                                        onChanged: (value) {
                                          setState(() {
                                            if (value == true) {
                                              if (_blockedPackages.length <
                                                  maxApps) {
                                                _blockedPackages
                                                    .add(app.packageName);
                                              } else {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                        'Maximum 10 apps can be selected',
                                                        style: TextStyle(
                                                            color:
                                                                Colors.white)),
                                                    backgroundColor: Colors.red,
                                                    behavior: SnackBarBehavior
                                                        .floating,
                                                  ),
                                                );
                                              }
                                            } else {
                                              _blockedPackages
                                                  .remove(app.packageName);
                                            }
                                          });
                                          // MODIFIED: Save apps without duration on toggle
                                          _saveBlockedApps();
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              if (_blockedPackages.isNotEmpty) _buildDurationPicker(),
            ],
          );
        },
      ),
    );
  }

  Future<void> _blockApps() async {
    if (_blockedPackages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select at least one app to monitor'),
            backgroundColor: Colors.red),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TimeSelectionScreen(
          onConfirm: (durationHours) async {
            debugPrint('Setting duration: $durationHours hours');
            setState(() {
              _totalBlockDurationHours = durationHours;
            });
            await _confirmBlockWithTimer();
          },
          initialDuration: _totalBlockDurationHours,
        ),
      ),
    );
  }
}

// Time selection screen
class TimeSelectionScreen extends StatefulWidget {
  final Function(double) onConfirm;
  final double initialDuration;

  const TimeSelectionScreen(
      {super.key, required this.onConfirm, required this.initialDuration});

  @override
  State<TimeSelectionScreen> createState() => _TimeSelectionScreenState();
}

class _TimeSelectionScreenState extends State<TimeSelectionScreen> {
  late double _blockDurationHours;

  @override
  void initState() {
    super.initState();
    // Ensure initial duration is within the new range (1.0 to 7.0 hours)
    double initialDuration =
        widget.initialDuration > 0 ? widget.initialDuration : 1.0;
    if (initialDuration < 1.0) {
      initialDuration = 1.0;
    } else if (initialDuration > 7.0) {
      initialDuration = 7.0;
    }
    _blockDurationHours = initialDuration;
    debugPrint(
        'TimeSelectionScreen initialized with initial duration: $_blockDurationHours');
  }

  // Helper widget for preset duration buttons
  Widget _buildPresetButton(double hours, String label) {
    // Special handling for 5-minute button
    bool isFiveMinSelected =
        label == '5 min' && (_blockDurationHours - (5.0 / 60.0)).abs() < 0.01;
    final isSelected = label == '5 min'
        ? isFiveMinSelected
        : (_blockDurationHours - hours).abs() < 0.01;

    return InkWell(
      onTap: () {
        setState(() {
          if (label == '5 min') {
            // For 5-minute option, set the actual 5-minute value
            _blockDurationHours = 5.0 / 60.0; // 5 minutes = 0.083 hours
          } else {
            // For other options, ensure the value is within slider range (1.0 to 7.0 hours)
            if (hours < 1.0) {
              _blockDurationHours = 1.0;
            } else if (hours > 7.0) {
              _blockDurationHours = 7.0;
            } else {
              _blockDurationHours = hours;
            }
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3) : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isSelected ? const Color(0xFF2196F3) : Colors.grey[700]!,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFF2196F3).withOpacity(0.3)
                  : Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[300],
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 0, 0, 0),
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 0, 0, 0),
        title: const Text('Set Block Duration',
            style: TextStyle(
                color: Color(0xFF2196F3),
                fontSize: 24,
                fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back, color: Color(0xFF2196F3), size: 28),
          onPressed: () {
            debugPrint('Back button pressed on TimeSelectionScreen');
            Navigator.pop(context);
          },
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Header section
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF2196F3).withOpacity(0.1),
                      const Color(0xFF2196F3).withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF2196F3).withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.timer,
                      color: Color(0xFF2196F3),
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _blockDurationHours < 1.0
                          ? 'Duration: ${(_blockDurationHours * 60).toInt()} minutes'
                          : 'Duration: ${_blockDurationHours.toInt()} hours',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _blockDurationHours < 1.0
                          ? 'Quick 5-minute block selected'
                          : 'Drag slider to set duration (1-7 hours)',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // Slider section
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.grey[800]!,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '1 hour',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '8 hours',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF2196F3),
                        inactiveTrackColor: Colors.grey[700],
                        thumbColor: const Color(0xFF2196F3),
                        overlayColor: const Color(0xFF2196F3).withOpacity(0.2),
                        valueIndicatorColor: const Color(0xFF2196F3),
                        valueIndicatorTextStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: Slider(
                        value: _blockDurationHours < 1.0
                            ? 1.0
                            : _blockDurationHours,
                        min: 1.0,
                        max: 8.0,
                        divisions: 6,
                        label: _blockDurationHours < 1.0
                            ? '${(_blockDurationHours * 60).toInt()} min'
                            : '${_blockDurationHours.toInt()} hours',
                        onChanged: (value) {
                          setState(() {
                            // Ensure the value is properly set for hours (1-7)
                            _blockDurationHours = value;
                            debugPrint(
                                'Slider updated to: $_blockDurationHours hours (${(_blockDurationHours * 60).toInt()} minutes)');
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              // Quick select section
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.grey[800]!,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.flash_on,
                          color: Colors.grey[400],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Quick Select',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildPresetButton(5.0 / 60.0, '5 min'),
                  ],
                ),
              ),
              const Spacer(),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        debugPrint(
                            'Cancel button pressed on TimeSelectionScreen');
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2A2A2A),
                        foregroundColor: const Color(0xFF2196F3),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                        elevation: 0,
                        side: BorderSide(
                          color: const Color(0xFF2196F3).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _blockDurationHours > 0
                          ? () {
                              debugPrint(
                                  'Confirm button pressed with duration: $_blockDurationHours hours (${(_blockDurationHours * 60).toInt()} minutes)');
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Setting up timer...'),
                                  duration: Duration(seconds: 1),
                                  backgroundColor: Colors.blue,
                                ),
                              );
                              widget.onConfirm(_blockDurationHours);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blockDurationHours > 0
                            ? const Color(0xFF2196F3)
                            : Colors.grey[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                        elevation: _blockDurationHours > 0 ? 8 : 0,
                        shadowColor: _blockDurationHours > 0
                            ? const Color(0xFF2196F3).withOpacity(0.3)
                            : Colors.transparent,
                      ),
                      child: Text(
                        _blockDurationHours > 0 ? 'Confirm' : 'Select Duration',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _blockDurationHours > 0
                              ? Colors.white
                              : Colors.grey[400],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Data model for application information
class AppInfo {
  final String appName;
  final String packageName;
  final Uint8List? icon;

  AppInfo({required this.appName, required this.packageName, this.icon});

  factory AppInfo.fromApplication(Application app) {
    return AppInfo(
      appName: app.appName,
      packageName: app.packageName,
      icon: app is ApplicationWithIcon ? app.icon : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'appName': appName,
      'packageName': packageName,
      'icon': icon != null ? base64Encode(icon!) : null,
    };
  }

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    return AppInfo(
      appName: json['appName'] as String,
      packageName: json['packageName'] as String,
      icon: json['icon'] != null ? base64Decode(json['icon']) : null,
    );
  }
}
