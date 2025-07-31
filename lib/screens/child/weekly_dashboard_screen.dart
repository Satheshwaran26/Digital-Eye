import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_apps/device_apps.dart';

import '../../dashboard/database_helper.dart'; // Adjust path if needed
import '../../dashboard/usage_models.dart';

class WeeklyDashboardScreen extends StatefulWidget {
  const WeeklyDashboardScreen({super.key});

  @override
  State<WeeklyDashboardScreen> createState() => _WeeklyDashboardScreenState();
}

class _WeeklyDashboardScreenState extends State<WeeklyDashboardScreen> {
  late Future<List<WeeklyUsage>> _weeklyReportFuture;
  late Future<List<AppUsage>> _topAppsFuture;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<String> _monitoredAppNames = [];

  @override
  void initState() {
    super.initState();
    _loadMonitoredApps();
  }

  Future<void> _loadMonitoredApps() async {
    final prefs = await SharedPreferences.getInstance();
    final blockedApps = prefs.getStringList('blocked_apps') ?? [];

    // For now, use package names as app names
    // In a real implementation, you would convert package names to app names
    setState(() {
      _monitoredAppNames = blockedApps;
    });

    debugPrint('Loaded monitored apps: $_monitoredAppNames');
    _loadData();
  }

  void _loadData() {
    setState(() {
      _weeklyReportFuture = _dbHelper
          .getMonitoredAppsWeeklyReport(_monitoredAppNames)
          .then((data) {
        debugPrint(
            'Monitored apps weekly report loaded: ${data.length} entries');
        for (var entry in data) {
          debugPrint('Day ${entry.dayOfWeek}: ${entry.totalHours} hours');
        }
        return data;
      }).catchError((error) {
        debugPrint('Error loading monitored apps weekly report: $error');
        return <WeeklyUsage>[];
      });

      _topAppsFuture =
          _dbHelper.getTopMonitoredAppsForWeek(_monitoredAppNames).then((data) {
        debugPrint('Top monitored apps loaded: ${data.length} apps');
        for (var app in data) {
          debugPrint('${app.appName}: ${app.totalSeconds} seconds');
        }
        return data;
      }).catchError((error) {
        debugPrint('Error loading top monitored apps: $error');
        return <AppUsage>[];
      });
    });
  }

  // Refresh data and reload monitored apps
  Future<void> _refreshData() async {
    await _loadMonitoredApps();
    _loadData();
  }

  // Add test data for debugging
  Future<void> _addTestData() async {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    final threeDaysAgo = today.subtract(const Duration(days: 3));
    final fourDaysAgo = today.subtract(const Duration(days: 4));
    final fiveDaysAgo = today.subtract(const Duration(days: 5));
    final sixDaysAgo = today.subtract(const Duration(days: 6));

    // Today's data
    await _dbHelper.upsertAppUsage('WhatsApp', 3600); // 1 hour today
    await _dbHelper.upsertAppUsage('Instagram', 1800); // 30 min today
    await _dbHelper.upsertAppUsage('YouTube', 7200); // 2 hours today

    // Yesterday's data
    await _dbHelper.upsertAppUsage('WhatsApp', 2400); // 40 min yesterday
    await _dbHelper.upsertAppUsage('TikTok', 3600); // 1 hour yesterday
    await _dbHelper.upsertAppUsage('Instagram', 1200); // 20 min yesterday

    // 2 days ago
    await _dbHelper.upsertAppUsage('Chrome', 1800); // 30 min 2 days ago
    await _dbHelper.upsertAppUsage('WhatsApp', 1200); // 20 min 2 days ago

    // 3 days ago
    await _dbHelper.upsertAppUsage('YouTube', 5400); // 1.5 hours 3 days ago
    await _dbHelper.upsertAppUsage('TikTok', 2400); // 40 min 3 days ago

    // 4 days ago
    await _dbHelper.upsertAppUsage('WhatsApp', 3600); // 1 hour 4 days ago
    await _dbHelper.upsertAppUsage('Instagram', 1800); // 30 min 4 days ago

    // 5 days ago
    await _dbHelper.upsertAppUsage('Chrome', 1200); // 20 min 5 days ago
    await _dbHelper.upsertAppUsage('YouTube', 3600); // 1 hour 5 days ago

    // 6 days ago
    await _dbHelper.upsertAppUsage('WhatsApp', 1800); // 30 min 6 days ago
    await _dbHelper.upsertAppUsage('TikTok', 2400); // 40 min 6 days ago

    debugPrint('Test data added successfully');

    // Refresh the data
    _loadData();
  }

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  List<BarChartGroupData> _createBarGroups(List<WeeklyUsage> report) {
    final Map<int, double> usageMap = {
      for (var item in report) item.dayOfWeek: item.totalHours
    };
    final List<BarChartGroupData> barGroups = [];
    final maxY = _calculateMaxY(report);

    for (int i = 0; i < 7; i++) {
      int dayOfWeek = i + 1; // Monday = 1, Sunday = 7
      final hours = usageMap[dayOfWeek] ?? 0.0;

      // Create different colors for each day
      final colors = [
        const Color(0xFF2196F3), // Blue
        const Color(0xFF4CAF50), // Green
        const Color(0xFFFF9800), // Orange
        const Color(0xFF9C27B0), // Purple
        const Color(0xFFF44336), // Red
        const Color(0xFF00BCD4), // Cyan
        const Color(0xFFFFEB3B), // Yellow
      ];

      barGroups.add(
        BarChartGroupData(
          x: i,
          groupVertically: false,
          barRods: [
            BarChartRodData(
              toY: hours,
              gradient: hours > 0
                  ? LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        colors[i % colors.length].withOpacity(0.8),
                        colors[i % colors.length],
                        colors[i % colors.length].withOpacity(0.9),
                      ],
                      stops: const [0.0, 0.6, 1.0],
                    )
                  : null,
              color: hours > 0 ? colors[i % colors.length] : Colors.grey[800]!,
              width: 36,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(4),
              ),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxY,
                color: Colors.grey[900]!,
              ),
            ),
          ],
        ),
      );
    }
    return barGroups;
  }

  // Build usage summary section similar to main dashboard
  Widget _buildUsageSummarySection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A1A),
            const Color(0xFF2A2A2A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2196F3).withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics,
                color: Color(0xFF2196F3),
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Weekly Usage Summary',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FutureBuilder<List<WeeklyUsage>>(
            future: _weeklyReportFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF2196F3),
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                  child: Text(
                    'No usage data available',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                      fontFamily: 'Poppins',
                    ),
                  ),
                );
              }

              final weeklyData = snapshot.data!;
              final totalHours = weeklyData.fold<double>(
                  0, (sum, day) => sum + day.totalHours);
              final averageHours = totalHours / 7;
              final maxDay = weeklyData
                  .reduce((a, b) => a.totalHours > b.totalHours ? a : b);
              final minDay = weeklyData
                  .reduce((a, b) => a.totalHours < b.totalHours ? a : b);

              return Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      'Total',
                      '${totalHours.toStringAsFixed(1)}h',
                      Icons.timer,
                      const Color(0xFF2196F3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      'Average',
                      '${averageHours.toStringAsFixed(1)}h',
                      Icons.analytics,
                      const Color(0xFF4CAF50),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      'Peak',
                      '${maxDay.totalHours.toStringAsFixed(1)}h',
                      Icons.trending_up,
                      const Color(0xFFFF9800),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.1),
            color.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }

  double _calculateMaxY(List<WeeklyUsage> report) {
    if (report.isEmpty) return 2; // Default to 2 hours if no data
    final maxHours = report.map((e) => e.totalHours).reduce(max);

    debugPrint('Max hours in data: $maxHours');

    // If max usage is less than 1 hour, scale appropriately
    if (maxHours < 1.0) {
      // For minutes, scale to show up to 2 hours max
      debugPrint('Scaling for minutes: maxY = 2.0');
      return 2.0;
    } else if (maxHours < 5.0) {
      // For 1-5 hours, scale to show up to 6 hours max
      debugPrint('Scaling for 1-5 hours: maxY = 6.0');
      return 6.0;
    } else if (maxHours < 12.0) {
      // For 5-12 hours, scale to show up to 15 hours max
      debugPrint('Scaling for 5-12 hours: maxY = 15.0');
      return 15.0;
    } else {
      // For 12+ hours, scale to show up to 24 hours max
      debugPrint('Scaling for 12+ hours: maxY = 24.0');
      return 24.0;
    }
  }

  // Get app color based on app name
  Color _getAppColor(String appName) {
    final name = appName.toLowerCase();
    if (name.contains('whatsapp')) {
      return const Color(0xFF25D366);
    } else if (name.contains('instagram')) {
      return const Color(0xFFE4405F);
    } else if (name.contains('youtube')) {
      return const Color(0xFFFF0000);
    } else if (name.contains('tiktok')) {
      return const Color(0xFF000000);
    } else if (name.contains('chrome')) {
      return const Color(0xFF4285F4);
    } else if (name.contains('facebook')) {
      return const Color(0xFF1877F2);
    } else if (name.contains('twitter')) {
      return const Color(0xFF1DA1F2);
    } else if (name.contains('snapchat')) {
      return const Color(0xFFFFFC00);
    } else if (name.contains('discord')) {
      return const Color(0xFF7289DA);
    } else if (name.contains('telegram')) {
      return const Color(0xFF0088CC);
    } else {
      return const Color(0xFF2196F3);
    }
  }

  // Get app icon based on app name
  Icon _getAppIcon(String appName) {
    final name = appName.toLowerCase();
    if (name.contains('whatsapp')) {
      return const Icon(Icons.message, color: Color(0xFF25D366));
    } else if (name.contains('instagram')) {
      return const Icon(Icons.camera_alt, color: Color(0xFFE4405F));
    } else if (name.contains('youtube')) {
      return const Icon(Icons.play_circle, color: Color(0xFFFF0000));
    } else if (name.contains('tiktok')) {
      return const Icon(Icons.music_note, color: Color(0xFF000000));
    } else if (name.contains('chrome')) {
      return const Icon(Icons.language, color: Color(0xFF4285F4));
    } else if (name.contains('facebook')) {
      return const Icon(Icons.facebook, color: Color(0xFF1877F2));
    } else if (name.contains('twitter')) {
      return const Icon(Icons.flutter_dash, color: Color(0xFF1DA1F2));
    } else {
      return const Icon(Icons.phone_android, color: Color(0xFF2196F3));
    }
  }

  // Get app logo widget with enhanced styling and better error handling
  Widget _getAppLogo(String appName) {
    return FutureBuilder<Application?>(
      future: _getAppInfo(appName),
      builder: (context, snapshot) {
        // Show loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF2196F3).withOpacity(0.2),
                  const Color(0xFF1976D2).withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF2196F3).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2196F3)),
                ),
              ),
            ),
          );
        }

        // Show app icon if found
        if (snapshot.hasData && snapshot.data != null) {
          final app = snapshot.data!;
          if (app is ApplicationWithIcon && app.icon != null) {
            return Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  app.icon!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('Error loading app icon for $appName: $error');
                    return _buildFallbackIcon(appName);
                  },
                ),
              ),
            );
          }
        }

        // Fallback to custom icon
        return _buildFallbackIcon(appName);
      },
    );
  }

  // Build fallback icon with better styling
  Widget _buildFallbackIcon(String appName) {
    final color = _getAppColor(appName);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.2),
            color.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: _getAppIcon(appName),
      ),
    );
  }

  // Get app info from package name or app name
  Future<Application?> _getAppInfo(String appName) async {
    try {
      // Try to find the app by name first
      final apps = await DeviceApps.getInstalledApplications(
        includeAppIcons: true,
        includeSystemApps: false,
        onlyAppsWithLaunchIntent: true,
      );

      debugPrint('Looking for app: $appName');
      debugPrint('Available apps: ${apps.length}');

      // First try to find by exact app name match
      try {
        final app = apps.firstWhere(
          (app) => app.appName.toLowerCase() == appName.toLowerCase(),
        );
        debugPrint('Found app by exact name: ${app.appName}');
        return app;
      } catch (e) {
        // If not found by exact name, try to find by partial match
        try {
          final app = apps.firstWhere(
            (app) =>
                app.appName.toLowerCase().contains(appName.toLowerCase()) ||
                appName.toLowerCase().contains(app.appName.toLowerCase()),
          );
          debugPrint('Found app by partial match: ${app.appName}');
          return app;
        } catch (e) {
          // If still not found, try to find by package name
          try {
            final app = apps.firstWhere(
              (app) => app.packageName.toLowerCase() == appName.toLowerCase(),
            );
            debugPrint('Found app by package name: ${app.appName}');
            return app;
          } catch (e) {
            // Try to find by common app name variations
            final commonNames = _getCommonAppNames(appName);
            for (final commonName in commonNames) {
              try {
                final app = apps.firstWhere(
                  (app) => app.appName
                      .toLowerCase()
                      .contains(commonName.toLowerCase()),
                );
                debugPrint('Found app by common name: ${app.appName}');
                return app;
              } catch (e) {
                // Continue to next common name
              }
            }

            // If all else fails, return null
            debugPrint('No app found for: $appName');
            return null;
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting app info for $appName: $e');
      return null;
    }
  }

  // Get common app name variations
  List<String> _getCommonAppNames(String appName) {
    final name = appName.toLowerCase();
    final variations = <String>[];

    // Add common variations
    if (name.contains('whatsapp')) {
      variations.addAll(['whatsapp', 'whats app', 'whats-app']);
    } else if (name.contains('instagram')) {
      variations.addAll(['instagram', 'insta', 'ig']);
    } else if (name.contains('youtube')) {
      variations.addAll(['youtube', 'yt', 'you tube']);
    } else if (name.contains('tiktok')) {
      variations.addAll(['tiktok', 'tik tok', 'tiktok']);
    } else if (name.contains('facebook')) {
      variations.addAll(['facebook', 'fb', 'face book']);
    } else if (name.contains('twitter')) {
      variations.addAll(['twitter', 'tw', 'x']);
    } else if (name.contains('snapchat')) {
      variations.addAll(['snapchat', 'snap', 'snap chat']);
    } else if (name.contains('discord')) {
      variations.addAll(['discord', 'disc']);
    } else if (name.contains('telegram')) {
      variations.addAll(['telegram', 'tg']);
    }

    return variations;
  }

  // Convert package name to readable app name
  String _getReadableAppName(String packageName) {
    // Handle common app package names
    final name = packageName.toLowerCase();

    if (name.contains('com.openai.chatgpt') || name.contains('chatgpt')) {
      return 'ChatGPT';
    } else if (name.contains('com.whatsapp') || name.contains('whatsapp')) {
      return 'WhatsApp';
    } else if (name.contains('com.instagram') || name.contains('instagram')) {
      return 'Instagram';
    } else if (name.contains('com.google.android.youtube') ||
        name.contains('youtube')) {
      return 'YouTube';
    } else if (name.contains('com.zhiliaoapp.musically') ||
        name.contains('tiktok')) {
      return 'TikTok';
    } else if (name.contains('com.facebook') || name.contains('facebook')) {
      return 'Facebook';
    } else if (name.contains('com.twitter') || name.contains('twitter')) {
      return 'Twitter';
    } else if (name.contains('com.snapchat') || name.contains('snapchat')) {
      return 'Snapchat';
    } else if (name.contains('com.discord') || name.contains('discord')) {
      return 'Discord';
    } else if (name.contains('org.telegram') || name.contains('telegram')) {
      return 'Telegram';
    } else if (name.contains('com.android.chrome') || name.contains('chrome')) {
      return 'Chrome';
    } else if (name.contains('com.android.vending') ||
        name.contains('play store')) {
      return 'Play Store';
    } else if (name.contains('com.google.android.gm') ||
        name.contains('gmail')) {
      return 'Gmail';
    } else if (name.contains('com.spotify') || name.contains('spotify')) {
      return 'Spotify';
    } else if (name.contains('com.netflix') || name.contains('netflix')) {
      return 'Netflix';
    } else if (name.contains('com.microsoft.teams') || name.contains('teams')) {
      return 'Teams';
    } else if (name.contains('com.skype') || name.contains('skype')) {
      return 'Skype';
    } else if (name.contains('com.zoom') || name.contains('zoom')) {
      return 'Zoom';
    }

    // Remove common package prefixes
    String readableName = packageName;
    if (readableName.startsWith('com.')) {
      readableName = readableName.substring(4);
    }
    if (readableName.startsWith('org.')) {
      readableName = readableName.substring(4);
    }
    if (readableName.startsWith('io.')) {
      readableName = readableName.substring(3);
    }
    if (readableName.startsWith('net.')) {
      readableName = readableName.substring(4);
    }

    // Convert to title case
    readableName = readableName.split('.').last;
    if (readableName.isNotEmpty) {
      readableName = readableName[0].toUpperCase() +
          readableName.substring(1).toLowerCase();
    }

    return readableName;
  }

  // Create a complete week data with all 7 days, including days with no usage
  List<WeeklyUsage> _createCompleteWeekData(List<WeeklyUsage> report) {
    final List<WeeklyUsage> completeWeekData = [];
    final Map<int, double> usageMap = {
      for (var item in report) item.dayOfWeek: item.totalHours
    };

    // Create entries for all 7 days (Monday = 1, Sunday = 7)
    for (int i = 1; i <= 7; i++) {
      final hours = usageMap[i] ?? 0.0;
      completeWeekData.add(WeeklyUsage(dayOfWeek: i, totalHours: hours));
    }

    debugPrint('Created complete week data: ${completeWeekData.length} days');
    for (var day in completeWeekData) {
      debugPrint('Day ${day.dayOfWeek}: ${day.totalHours} hours');
    }

    return completeWeekData;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Color(0xFF2196F3),
            size: 28,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Weekly Analytics',
          style: TextStyle(
            color: Color(0xFF2196F3),
            fontSize: 24,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh,
              color: Color(0xFF2196F3),
            ),
            onPressed: _refreshData,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              Color(0xFF1A1A1A),
              Colors.black,
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bar Chart Section - Child Home Style
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF2196F3).withOpacity(0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2196F3).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.bar_chart,
                            color: Color(0xFF2196F3),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Daily Usage',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 280,
                      child: FutureBuilder<List<WeeklyUsage>>(
                        future: _weeklyReportFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF2196F3),
                              ),
                            );
                          }
                          if (snapshot.hasError) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 48,
                                    color: Colors.red.withOpacity(0.7),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Error loading data',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 16,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.bar_chart_outlined,
                                    size: 48,
                                    color: const Color(0xFF2196F3)
                                        .withOpacity(0.7),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _monitoredAppNames.isEmpty
                                        ? 'No apps selected for monitoring'
                                        : 'No usage data available',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'Poppins',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            );
                          }

                          final weeklyData = snapshot.data!;
                          final maxY = _calculateMaxY(weeklyData);

                          // Create a complete week data with all 7 days
                          final completeWeekData =
                              _createCompleteWeekData(weeklyData);

                          return BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: maxY,
                              minY: 0,
                              barTouchData: BarTouchData(
                                enabled: true,
                                touchTooltipData: BarTouchTooltipData(
                                  tooltipBgColor:
                                      Colors.black.withOpacity(0.95),
                                  tooltipRoundedRadius: 12,
                                  tooltipPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  tooltipMargin: 8,
                                  getTooltipItem:
                                      (group, groupIndex, rod, rodIndex) {
                                    const days = [
                                      'Monday',
                                      'Tuesday',
                                      'Wednesday',
                                      'Thursday',
                                      'Friday',
                                      'Saturday',
                                      'Sunday'
                                    ];
                                    final hours = rod.toY;
                                    final totalSeconds = (hours * 3600).round();
                                    final dayIndex = group.x.toInt();
                                    final dayName = (dayIndex >= 0 &&
                                            dayIndex < days.length)
                                        ? days[dayIndex]
                                        : 'Unknown';

                                    return BarTooltipItem(
                                      '$dayName\n${_formatDuration(totalSeconds)}',
                                      const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        fontFamily: 'Poppins',
                                      ),
                                    );
                                  },
                                ),
                              ),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 50,
                                    getTitlesWidget: (value, meta) {
                                      const days = [
                                        'MON',
                                        'TUE',
                                        'WED',
                                        'THU',
                                        'FRI',
                                        'SAT',
                                        'SUN'
                                      ];
                                      final index = value.toInt();
                                      if (index >= 0 && index < days.length) {
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(top: 12.0),
                                          child: Text(
                                            days[index],
                                            style: const TextStyle(
                                              color: Color(0xFF2196F3),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                              fontFamily: 'Poppins',
                                            ),
                                          ),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    interval: (maxY / 4)
                                        .ceilToDouble()
                                        .clamp(0.5, 100)
                                        .toDouble(),
                                    reservedSize: 25,
                                    getTitlesWidget: (value, meta) {
                                      if (value == 0)
                                        return const SizedBox.shrink();

                                      final hours = value.toInt();
                                      final minutes =
                                          ((value - hours) * 60).round();

                                      String label;
                                      if (hours > 0) {
                                        label = '${hours}h';
                                        if (minutes > 0) {
                                          label += ' ${minutes}m';
                                        }
                                      } else {
                                        label = '${minutes}m';
                                      }

                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8.0),
                                        child: Text(
                                          label,
                                          style: TextStyle(
                                            color: Colors.grey.withOpacity(0.8),
                                            fontWeight: FontWeight.w500,
                                            fontSize: 11,
                                            fontFamily: 'Poppins',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                              ),
                              gridData: FlGridData(
                                show: true,
                                horizontalInterval: (maxY / 4)
                                    .ceilToDouble()
                                    .clamp(0.5, 100)
                                    .toDouble(),
                                drawVerticalLine: false,
                                getDrawingHorizontalLine: (value) {
                                  return FlLine(
                                    color: Colors.grey.withOpacity(0.1),
                                    strokeWidth: 1,
                                  );
                                },
                                checkToShowHorizontalLine: (value) {
                                  return value > 0 && value < maxY;
                                },
                              ),
                              borderData: FlBorderData(show: false),
                              barGroups:
                                  completeWeekData.asMap().entries.map((entry) {
                                final index = entry.key;
                                final data = entry.value;
                                final hours = data.totalHours;

                                // Different colors for each day
                                final dayColors = [
                                  const Color(0xFF2196F3), // Monday - Blue
                                  const Color(0xFF4CAF50), // Tuesday - Green
                                  const Color(0xFFFF9800), // Wednesday - Orange
                                  const Color(0xFF9C27B0), // Thursday - Purple
                                  const Color(0xFFF44336), // Friday - Red
                                  const Color(0xFF00BCD4), // Saturday - Cyan
                                  const Color(0xFFE91E63), // Sunday - Pink
                                ];

                                final dayColor =
                                    dayColors[index % dayColors.length];

                                return BarChartGroupData(
                                  x: index,
                                  groupVertically: false,
                                  barRods: [
                                    BarChartRodData(
                                      toY: hours,
                                      width: 28,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(8),
                                        topRight: Radius.circular(8),
                                      ),
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          dayColor.withOpacity(0.8),
                                          dayColor,
                                          dayColor.withOpacity(0.9),
                                        ],
                                        stops: const [0.0, 0.6, 1.0],
                                      ),
                                      backDrawRodData:
                                          BackgroundBarChartRodData(
                                        show: true,
                                        toY: maxY,
                                        color: Colors.grey.withOpacity(0.05),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Apps List Section - Child Home Style
              if (_topAppsFuture != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF2196F3).withOpacity(0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2196F3).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.apps,
                              color: Color(0xFF2196F3),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'App Usage Details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      FutureBuilder<List<AppUsage>>(
                        future: _topAppsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF2196F3),
                              ),
                            );
                          }
                          if (snapshot.hasError) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 48,
                                    color: Colors.red.withOpacity(0.7),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Error loading apps',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 16,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.apps_outlined,
                                    size: 48,
                                    color: const Color(0xFF2196F3)
                                        .withOpacity(0.7),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _monitoredAppNames.isEmpty
                                        ? 'No apps selected for monitoring'
                                        : 'No usage data for monitored apps',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'Poppins',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            );
                          }

                          final apps = snapshot.data!;
                          return Column(
                            children: apps.map((app) {
                              final readableAppName =
                                  _getReadableAppName(app.appName);
                              final color = _getAppColor(readableAppName);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A0A0A),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: color.withOpacity(0.4),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: color.withOpacity(0.1),
                                      blurRadius: 15,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 45,
                                      height: 45,
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: _getAppLogo(readableAppName),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            readableAppName,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              fontFamily: 'Poppins',
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${_formatDuration(app.totalSeconds)} this week',
                                            style: TextStyle(
                                              color:
                                                  Colors.grey.withOpacity(0.8),
                                              fontSize: 13,
                                              fontFamily: 'Poppins',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.25),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: color.withOpacity(0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        _formatDuration(app.totalSeconds),
                                        style: TextStyle(
                                          color: color,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Poppins',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
