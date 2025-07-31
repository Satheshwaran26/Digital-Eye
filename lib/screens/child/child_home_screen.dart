import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_apps/device_apps.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:my_app/screens/child/app_selection_screen.dart' as app_select;
import 'package:my_app/screens/child/settings_screen.dart';
import 'package:my_app/screens/dashboard_screen.dart';
import 'package:my_app/screens/focused_mode_screen.dart';
import 'package:my_app/screens/child/weekly_dashboard_screen.dart';
import '../message_screen.dart';
import '../../dashboard/weeklyusage.dart';

class ChildHomeScreen extends StatefulWidget {
  final String qrCodeId;
  const ChildHomeScreen({super.key, required this.qrCodeId});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen> {
  int _selectedIndex = 0;
  List<app_select.AppInfo> _selectedApps = [];
  bool _isLoading = false;
  final UsageMonitorWeek _weeklyUsageMonitor = UsageMonitorWeek();

  // Timer related state
  int _remainingSeconds = 0;
  bool _isMonitoringActive = false;
  String? _currentForegroundAppName;
  Timer? _refreshTimer;

  // Session completion state
  bool _sessionCompletedToday = false;

  // Platform channel for native communication
  static const platform = MethodChannel('app_blocker');

  @override
  void initState() {
    super.initState();
    _checkInitialAppList();
    _setupFCM();
    _loadSelectedApps();
    _loadTimerState();
    _loadSessionCompletionState();
    _setupNativeMethodHandlers();
    _startRefreshTimer();
    _weeklyUsageMonitor.startMonitoring();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _weeklyUsageMonitor.stopMonitoring();
    super.dispose();
  }

  Future<void> _setupFCM() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final token = await messaging.getToken();
    if (token != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'fcmToken': token});
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${message.notification?.title}: ${message.notification?.body}',
            style: const TextStyle(fontFamily: 'Poppins'),
          ),
          backgroundColor: const Color(0xFF2196F3),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    });
  }

  Future<void> _checkInitialAppList() async {
    final prefs = await SharedPreferences.getInstance();
    final bool shown = prefs.getBool('showed_app_list') ?? false;
    if (!shown) {
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => app_select.AppSelectionScreen(
            onBlocked: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ChildHomeScreen(qrCodeId: widget.qrCodeId),
                ),
              );
            },
          ),
        ),
      );
      await prefs.setBool('showed_app_list', true);
    }
  }

  Future<void> _loadSelectedApps() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('cachedApps');
      if (jsonString != null) {
        final jsonList = json.decode(jsonString) as List;
        setState(() {
          _selectedApps = jsonList
              .map((json) => app_select.AppInfo.fromJson(json))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading selected apps: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Load timer state from SharedPreferences
  Future<void> _loadTimerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remainingSecs = prefs.getInt('remainingSeconds') ?? 0;

      if (mounted) {
        setState(() {
          _remainingSeconds = remainingSecs;
        });
      }
    } catch (e) {
      debugPrint('Error loading timer state: $e');
    }
  }

  // Load session completion state from SharedPreferences
  Future<void> _loadSessionCompletionState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isCompleted = prefs.getBool('sessionCompletedToday') ?? false;

      debugPrint('🔍 Loading session completion state: $isCompleted');

      if (mounted) {
        setState(() {
          _sessionCompletedToday = isCompleted;
        });
        debugPrint(
            '🔍 Session completion state set to: $_sessionCompletedToday');
      }
    } catch (e) {
      debugPrint('Error loading session completion state: $e');
    }
  }

  // Save session completion state to SharedPreferences
  Future<void> _saveSessionCompletionState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sessionCompletedToday', _sessionCompletedToday);
      debugPrint('💾 Session completion state saved: $_sessionCompletedToday');
    } catch (e) {
      debugPrint('Error saving session completion state: $e');
    }
  }

  // Refresh session completion state
  Future<void> _refreshSessionCompletionState() async {
    await _loadSessionCompletionState();
    debugPrint(
        '🔄 Refreshed session completion state: $_sessionCompletedToday');
  }

  // Simulate onTimeUp event for testing
  void _simulateOnTimeUp() {
    debugPrint('🧪 Simulating onTimeUp event');

    setState(() {
      _remainingSeconds = 0;
      _isMonitoringActive = false;
      _currentForegroundAppName = null;
      _sessionCompletedToday = true;
    });

    _saveSessionCompletionState();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          '🧪 Simulated session completion!',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.purple,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
    );
  }

  // Setup native method handlers to receive timer updates
  void _setupNativeMethodHandlers() {
    platform.setMethodCallHandler((call) async {
      if (!mounted) return null;

      try {
        switch (call.method) {
          case "updateForegroundAppStatus":
            final remainingSeconds =
                call.arguments['remainingSeconds'] as int? ?? 0;
            final isMonitoringActive =
                call.arguments['isMonitoringActive'] as bool? ?? false;
            final appName = call.arguments['appName'] as String? ?? '';

            if (mounted) {
              setState(() {
                _remainingSeconds = remainingSeconds;
                _isMonitoringActive = isMonitoringActive;
                _currentForegroundAppName = appName.isNotEmpty ? appName : null;
              });
            }
            break;

          case "onTimeUp":
            final sessionCompleted =
                call.arguments['sessionCompleted'] as bool? ?? false;
            final sessionCompletedToday =
                call.arguments['sessionCompletedToday'] as bool? ?? false;

            debugPrint(
                '🎯 onTimeUp received - sessionCompleted: $sessionCompleted, sessionCompletedToday: $sessionCompletedToday');

            if (mounted) {
              setState(() {
                _remainingSeconds = 0;
                _isMonitoringActive = false;
                _currentForegroundAppName = null;
                _sessionCompletedToday = sessionCompletedToday;
              });

              debugPrint(
                  '🎯 Session completion state updated to: $_sessionCompletedToday');

              // Save session completion state
              if (sessionCompletedToday) {
                _saveSessionCompletionState();
              }

              // Show completion message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    '🎉 Session Complete! Great job managing your screen time!',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  duration: const Duration(seconds: 5),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              );
            }
            break;
        }
      } catch (e) {
        debugPrint('Error handling native method call: $e');
      }
      return null;
    });
  }

  // Start a timer to periodically refresh the timer state
  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _loadTimerState();
      }
    });
  }

  // Format time display
  String _formatTime(int seconds) {
    if (seconds <= 0) return '0h 0m 0s';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return '${hours}h ${minutes}m ${secs}s';
  }

  Widget _buildHomeContent() {
    debugPrint(
        '🏠 Building home content - _sessionCompletedToday: $_sessionCompletedToday');

    return Column(
      children: [
        // Session completion indicator
        if (_sessionCompletedToday)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Colors.white,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Session Completed Today!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Great job managing your screen time!',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: DashboardScreen(qrCodeId: widget.qrCodeId),
        ),
      ],
    );
  }

  Widget _buildMessagesContent() {
    if (widget.qrCodeId.isEmpty) {
      return const Center(
        child: Text(
          'Please connect with a parent device first',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontFamily: 'Poppins',
          ),
        ),
      );
    }
    return MessagingPage(qrCodeId: widget.qrCodeId);
  }

  Widget _buildSettingsContent() {
    return const SettingsScreen();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        title: Row(
          children: [
            Icon(
              _selectedIndex == 0
                  ? Icons.child_care
                  : _selectedIndex == 1
                      ? Icons.psychology
                      : _selectedIndex == 2
                          ? Icons.family_restroom
                          : Icons.settings,
              color: const Color(0xFF2196F3),
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              _selectedIndex == 0
                  ? 'Child Home'
                  : _selectedIndex == 1
                      ? 'Focus Mode'
                      : _selectedIndex == 2
                          ? 'Parent Messages'
                          : 'Settings',
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Color(0xFF2196F3),
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
     
        
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeContent(),
          const FocusedModeScreen(),
          _buildMessagesContent(),
          _buildSettingsContent(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A1A), Color(0xFF000000)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 2,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF2196F3),
          unselectedItemColor: Colors.grey[400],
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w400,
            fontSize: 12,
          ),
          items: [
            BottomNavigationBarItem(
              icon: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: _selectedIndex == 0
                    ? const EdgeInsets.all(8)
                    : const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _selectedIndex == 0
                      ? const Color(0xFF2196F3).withOpacity(0.2)
                      : Colors.transparent,
                ),
                child: Icon(
                  _selectedIndex == 0 ? Icons.home : Icons.home_outlined,
                  size: _selectedIndex == 0 ? 28 : 24,
                ),
              ),
              label: 'Child Home',
            ),
            BottomNavigationBarItem(
              icon: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: _selectedIndex == 1
                    ? const EdgeInsets.all(8)
                    : const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _selectedIndex == 1
                      ? const Color(0xFF2196F3).withOpacity(0.2)
                      : Colors.transparent,
                ),
                child: Icon(
                  _selectedIndex == 1 ? Icons.timer : Icons.timer_outlined,
                  size: _selectedIndex == 1 ? 28 : 24,
                ),
              ),
              label: 'Focus',
            ),
            BottomNavigationBarItem(
              icon: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: _selectedIndex == 2
                    ? const EdgeInsets.all(8)
                    : const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _selectedIndex == 2
                      ? const Color(0xFF2196F3).withOpacity(0.2)
                      : Colors.transparent,
                ),
                child: Icon(
                  _selectedIndex == 2 ? Icons.message : Icons.message_outlined,
                  size: _selectedIndex == 2 ? 28 : 24,
                ),
              ),
              label: 'Parent Messages',
            ),
            BottomNavigationBarItem(
              icon: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: _selectedIndex == 3
                    ? const EdgeInsets.all(8)
                    : const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _selectedIndex == 3
                      ? const Color(0xFF2196F3).withOpacity(0.2)
                      : Colors.transparent,
                ),
                child: Icon(
                  _selectedIndex == 3
                      ? Icons.settings
                      : Icons.settings_outlined,
                  size: _selectedIndex == 3 ? 28 : 24,
                ),
              ),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
