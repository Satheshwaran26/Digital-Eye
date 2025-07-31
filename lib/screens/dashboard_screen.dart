import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_pie_chart/easy_pie_chart.dart' as easy_pie_chart;
import 'package:my_app/screens/child/weekly_dashboard_screen.dart'
    hide AppUsage;
import 'package:shared_preferences/shared_preferences.dart';
import '../dashboard/usage_monitor.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';

class DashboardScreen extends StatefulWidget {
  final String qrCodeId;
  const DashboardScreen({super.key, required this.qrCodeId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  List<easy_pie_chart.PieData> _pieChartData = [];
  Map<String, Map<String, dynamic>> _packageToDetails = {};
  static const widgetChannel = MethodChannel('app_blocker/widget');
  final UsageMonitor _usageMonitor = UsageMonitor();
  List<AppUsage> _usages = [];
  static const String _currentAppPackage = 'com.example.my_app';
  // Map to store consistent colors for each app
  final Map<String, Color> _appColors = {};

  // Timer related state
  int _remainingSeconds = 0;
  bool _isMonitoringActive = false;
  String? _currentForegroundAppName;
  Timer? _refreshTimer;

  // Platform channel for native communication
  static const platform = MethodChannel('app_blocker');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _usageMonitor.startMonitoring((usages) {
      setState(() {
        _usages = usages;
        _buildPieChartData(usages);
      });
      _syncUsageToFirestore(usages);
    });
    _setupWidgetChannel();
    _loadTimerState();
    _setupNativeMethodHandlers();
    _startRefreshTimer();
    _requestTimerUpdate();
  }

  // Request timer update from native side
  Future<void> _requestTimerUpdate() async {
    try {
      final result = await platform.invokeMethod('getTimerStatus');
      if (result != null && mounted) {
        final remainingSeconds = result['remainingSeconds'] as int? ?? 0;
        final isMonitoringActive =
            result['isMonitoringActive'] as bool? ?? false;
        final appName = result['appName'] as String? ?? '';

        debugPrint(
            'Dashboard: Got timer status from native - $remainingSeconds seconds, active: $isMonitoringActive, app: $appName');

        setState(() {
          _remainingSeconds = remainingSeconds;
          _isMonitoringActive = isMonitoringActive;
          _currentForegroundAppName = appName.isNotEmpty ? appName : null;
        });
      } else {
        // Fallback to SharedPreferences if native method returns null
        debugPrint(
            'Dashboard: Native method returned null, falling back to SharedPreferences');
        _loadTimerState();
      }
    } catch (e) {
      debugPrint(
          'Error requesting timer status: $e, falling back to SharedPreferences');
      _loadTimerState();
    }
  }

  // Load timer state from SharedPreferences
  Future<void> _loadTimerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remainingSecs = prefs.getInt('remaining_seconds') ?? 0;
      final isMonitoringActive = prefs.getBool('monitoring_active') ?? false;
      final currentAppName = prefs.getString('current_foreground_app');

      debugPrint(
          'Dashboard: Loading timer state - remaining: $remainingSecs, active: $isMonitoringActive, app: $currentAppName');

      if (mounted) {
        setState(() {
          _remainingSeconds = remainingSecs;
          _isMonitoringActive = isMonitoringActive;
          _currentForegroundAppName = currentAppName;
        });
      }
    } catch (e) {
      debugPrint('Error loading timer state: $e');
    }
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

            debugPrint(
                'Dashboard: Received timer update - $remainingSeconds seconds, active: $isMonitoringActive');

            if (mounted) {
              setState(() {
                _remainingSeconds = remainingSeconds;
                _isMonitoringActive = isMonitoringActive;
                _currentForegroundAppName = appName.isNotEmpty ? appName : null;
              });
            }
            break;

          case "onTimeUp":
            debugPrint('Dashboard: Timer completed');
            if (mounted) {
              setState(() {
                _remainingSeconds = 0;
                _isMonitoringActive = false;
                _currentForegroundAppName = null;
              });

              // Show completion message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    '🎉 Timer Complete! Great job managing your screen time!',
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
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        // Only load from SharedPreferences as fallback, native method takes precedence
        _requestTimerUpdate();
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

  void _syncUsageToFirestore(List<AppUsage> usages) async {
    final user = FirebaseAuth.instance.currentUser!;
    final batch = FirebaseFirestore.instance.batch();
    final collection = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('usage');
    for (var usage in usages) {
      final docRef = collection.doc(usage.appName);
      batch.set(docRef, {
        'appName': usage.appName,
        'durationInSeconds': usage.durationInSeconds,
        'updatedAt': Timestamp.now(),
      });
    }
    await batch.commit();
    debugPrint('Synced ${usages.length} usage records to Firestore');
  }

  void _setupWidgetChannel() {
    widgetChannel.setMethodCallHandler((call) async {
      if (call.method == "getUsageData") {
        return _usages
            .map((usage) => {
                  'appName': usage.appName,
                  'durationInSeconds': usage.durationInSeconds,
                })
            .toList();
      }
      return null;
    });
  }

  void _buildPieChartData(List<AppUsage> usages) async {
    final List<easy_pie_chart.PieData> pieData = [];
    final Map<String, Map<String, dynamic>> packageToDetails = {};
    final random = math.Random();
    final colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.yellow,
      Colors.purple,
      Colors.orange,
      Colors.pink,
      Colors.teal,
      Colors.cyan,
      Colors.amber,
      Colors.indigo,
      Colors.lime,
      Colors.deepPurple,
      Colors.lightGreen,
      Colors.deepOrange,
      Colors.blueGrey,
      Colors.brown,
      Colors.grey,
      Colors.lightBlue,
      Colors.greenAccent,
      Colors.redAccent,
      Colors.purpleAccent,
      Colors.yellowAccent,
      Colors.tealAccent,
      Colors.orangeAccent,
    ];
    List<Color> availableColors =
        List.from(colors); // Copy of colors to track available ones

    final prefs = await SharedPreferences.getInstance();

    // Get selected/blocked apps (the ones actually being monitored)
    final selectedAppsList = prefs.getStringList('blocked_apps') ??
        prefs.getStringList('currentBlockedApps') ??
        [];
    final selectedAppsSet = selectedAppsList.toSet();

    // Get all cached apps for app info (names, icons)
    final jsonString = prefs.getString('cachedApps');
    List<AppInfo>? allApps;
    if (jsonString != null) {
      final jsonList = json.decode(jsonString) as List;
      allApps = jsonList.map((json) => AppInfo.fromJson(json)).toList();
    }

    // Create a map of usage data for quick lookup
    final Map<String, AppUsage> usageMap = {
      for (var usage in usages) usage.appName: usage
    };

    // Process only selected apps (including those with 0 usage)
    for (var packageName in selectedAppsSet) {
      if (packageName != _currentAppPackage) {
        // Find app info from cached apps
        final appInfo = allApps?.firstWhere(
          (app) => app.packageName == packageName,
          orElse: () => AppInfo(
            appName: packageName,
            packageName: packageName,
            icon: null,
          ),
        );

        final usage = usageMap[packageName];
        final durationInSeconds = usage?.durationInSeconds ?? 0;

        // Check if the app already has a color assigned; if not, assign one
        Color color;
        if (_appColors.containsKey(packageName)) {
          color = _appColors[packageName]!; // Use the existing color
        } else {
          // Assign a new color and store it
          if (availableColors.isNotEmpty) {
            final colorIndex = random.nextInt(availableColors.length);
            color = availableColors[colorIndex];
            availableColors.removeAt(colorIndex); // Remove the used color
          } else {
            // If no colors are left, reset the available colors and pick again
            availableColors = List.from(colors);
            final colorIndex = random.nextInt(availableColors.length);
            color = availableColors[colorIndex];
            availableColors.removeAt(colorIndex);
          }
          _appColors[packageName] = color; // Store the color for this app
        }

        // Add to pie chart only if there's actual usage (for visual clarity)
        if (durationInSeconds > 0) {
          pieData.add(
            easy_pie_chart.PieData(
              value: durationInSeconds.toDouble(),
              color: color,
            ),
          );
        }

        // Always add to package details (even with 0 usage) for selected apps
        packageToDetails[packageName] = {
          'appName': appInfo?.appName ?? packageName,
          'icon': appInfo?.icon,
          'duration': durationInSeconds > 0
              ? '${(durationInSeconds / 60).toStringAsFixed(1)} min'
              : '0.0 min',
          'color': color,
        };
      }
    }

    // Sort pie chart data by usage (highest first)
    pieData.sort((a, b) => b.value.compareTo(a.value));

    // Sort packageToDetails by duration (highest usage first)
    final sortedEntries = packageToDetails.entries.toList()
      ..sort((a, b) {
        // Extract duration in seconds for comparison
        final aDuration = usageMap[a.key]?.durationInSeconds ?? 0;
        final bDuration = usageMap[b.key]?.durationInSeconds ?? 0;
        return bDuration
            .compareTo(aDuration); // Descending order (highest first)
      });

    // Create a new sorted map
    final sortedPackageToDetails =
        Map<String, Map<String, dynamic>>.fromEntries(sortedEntries);

    setState(() {
      _pieChartData = pieData;
      _packageToDetails = sortedPackageToDetails;
      debugPrint('Pie chart data: ${pieData.length} entries');
      debugPrint(
          'App list sorted by usage: ${sortedPackageToDetails.length} apps');
    });
  }

  Widget _buildGlassyBottomSection() {
    return Container(
      margin: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Timer Widget (Left Column)
          SizedBox(
            width: 150,
            child: _buildGlassyTimerWidget(),
          ),
          const SizedBox(width: 34),
          // Weekly Dashboard Button (Right Column)
          SizedBox(
            width: 150,
            child: _buildGlassyWeeklyDashboardButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassyTimerWidget() {
    debugPrint(
        'Dashboard: Building timer widget - remaining: $_remainingSeconds, active: $_isMonitoringActive, app: $_currentForegroundAppName');

    if (_remainingSeconds <= 0) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.08),
              Colors.white.withOpacity(0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.15),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.1),
                Colors.white.withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.timer_off,
                color: Colors.grey[400],
                size: 24,
              ),
              const SizedBox(height: 6),
              Text(
                'No Timer',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Start monitoring apps',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 10,
                  fontFamily: 'Poppins',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 115,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.1),
            Colors.white.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (_isMonitoringActive ? Colors.green : Colors.orange)
              .withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.08),
              Colors.white.withOpacity(0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isMonitoringActive ? Icons.timer : Icons.pause_circle_outline,
              color:
                  _isMonitoringActive ? Colors.green[300] : Colors.orange[300],
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              _formatTime(_remainingSeconds),
              style: TextStyle(
                color: _isMonitoringActive ? Colors.green[200] : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              _isMonitoringActive ? 'Active' : 'Paused',
              style: TextStyle(
                color: _isMonitoringActive
                    ? Colors.green[300]
                    : Colors.orange[300],
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
              ),
            ),
            if (_isMonitoringActive && _currentForegroundAppName != null) ...[
              const SizedBox(height: 4),
              Text(
                '📱 $_currentForegroundAppName',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 10,
                  fontFamily: 'Poppins',
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ] else if (!_isMonitoringActive && _remainingSeconds > 0) ...[
              const SizedBox(height: 4),
              Text(
                '⏸️ Open monitored app to resume',
                style: TextStyle(
                  color: Colors.orange[300],
                  fontSize: 10,
                  fontFamily: 'Poppins',
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGlassyWeeklyDashboardButton() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const WeeklyDashboardScreen(),
          ),
        );
      },
      child: Container(
        height: 115,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.1),
              Colors.white.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.08),
                Colors.white.withOpacity(0.03),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.analytics,
                color: Colors.white70,
                size: 24,
              ),
              const SizedBox(height: 8),
              Text(
                'Weekly\nDashboard',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color.fromARGB(255, 0, 0, 0),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Header

            // 1. Pie Chart Section (Center)
            if (_pieChartData.isNotEmpty)
              Container(
                height: 240,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    easy_pie_chart.EasyPieChart(
                      pieType: easy_pie_chart.PieType.crust,
                      size: 200,
                      gap: 4,
                      borderWidth: 14,
                      borderEdge: StrokeCap.round,
                      showValue: false,
                      children: _pieChartData,
                    ),
                    // Custom center text
                    Container(
                      width: 100,
                      height: 40,
                      child: const Center(
                        child: Text(
                          'App Usage',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2196F3),
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 2. Two Glassy Widgets (Timer and Weekly Dashboard)
            _buildGlassyBottomSection(),

            // 3. App List
            if (_packageToDetails.isNotEmpty) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'App Usage Details :',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: _packageToDetails.entries.map((entry) {
                    final packageName = entry.key;
                    final details = entry.value;
                    final appName = details['appName'] as String;
                    final icon = details['icon'] as Uint8List?;
                    final duration = details['duration'] as String;
                    final color = details['color'] as Color;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 0, 0, 0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: color.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: icon != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.memory(
                                      icon,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Icon(
                                    Icons.apps,
                                    size: 20,
                                    color: color,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              appName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              duration,
                              style: TextStyle(
                                color: color,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ] else ...[
              const SizedBox(height: 40),
              const Center(
                child: Text(
                  'No usage data available.\nStart using apps to see your dashboard.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFamily: 'Poppins',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _usageMonitor.stopMonitoring();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Refresh timer state when app becomes visible
      debugPrint('Dashboard: App resumed, refreshing timer state');
      _loadTimerState();
      _requestTimerUpdate();
    }
  }
}

class AppInfo {
  final String appName;
  final String packageName;
  final Uint8List? icon;

  AppInfo({
    required this.appName,
    required this.packageName,
    this.icon,
  });

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    return AppInfo(
      appName: json['appName'] as String,
      packageName: json['packageName'] as String,
      icon: json['icon'] != null ? base64Decode(json['icon']) : null,
    );
  }
}
