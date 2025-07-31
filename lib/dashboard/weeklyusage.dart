// lib/services/usage_monitor.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart' hide AppInfo;
import 'package:installed_apps/installed_apps.dart';
import 'package:usage_stats_new/usage_stats.dart';
import '../dashboard/database_helper.dart';
import '../screens/app_manager.dart'; // Make sure this path is correct

class UsageMonitorWeek {
  Timer? _timer;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // List of packages to exclude from tracking
  static const List<String> _excludedApps = [
    "com.android.systemui",
    "com.google.android.apps.nexuslauncher", // Pixel Launcher
    "com.example.my_app", // Add your own app's package name here
  ];

  void startMonitoring() {
    UsageStats.grantUsagePermission();

    _timer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _updateUsageData();
    });

    _updateUsageData(); // Run an initial update

    Timer.periodic(const Duration(days: 1), (timer) {
      _dbHelper.clearOldData();
    });
  }

  void stopMonitoring() {
    _timer?.cancel();
  }

  Future<void> _updateUsageData() async {
    try {
      DateTime endDate = DateTime.now();
      DateTime startDate = DateTime(endDate.year, endDate.month, endDate.day);

      List<UsageInfo> usageStats =
          await UsageStats.queryUsageStats(startDate, endDate);

      for (UsageInfo info in usageStats) {
        if (_isTrackableApp(info.packageName!, info)) {
          String appName = await _getAppName(info.packageName!);
          int durationInSeconds =
              (int.tryParse(info.totalTimeInForeground ?? '0') ?? 0) ~/ 1000;
          if (appName.isNotEmpty && durationInSeconds > 0) {
            // NOTE: The usage_stats plugin returns the CUMULATIVE usage for the day.
            // Our upsert function will correctly overwrite the old value with the new cumulative value.
            await _dbHelper.upsertAppUsage(appName, durationInSeconds);
          }
        }
      }
      debugPrint('Usage data updated in the database.');
    } catch (e) {
      debugPrint('Error updating usage data: $e');
    }
  }

  bool _isTrackableApp(String packageName, UsageInfo info) {
    int usageInMillis = int.tryParse(info.totalTimeInForeground ?? '0') ?? 0;
    return usageInMillis > 0 && !_excludedApps.contains(packageName);
  }

  Future<String> _getAppName(String packageName) async {
    try {
      // ✅ This is the corrected call.
      AppInfo appInfo =
          (await InstalledApps.getAppInfo(packageName, false as BuiltWith?))
              as AppInfo;
      ;
      return appInfo.appName;
    } catch (e) {
      debugPrint('Could not get app name for $packageName: $e');
      return packageName; // Fallback to package name
    }
  }
}
