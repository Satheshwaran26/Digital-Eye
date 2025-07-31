import 'dart:async';
import 'dart:typed_data';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:flutter/material.dart';
import 'package:usage_stats_new/usage_stats.dart';

const Map<int, String> eventTypeMap = {
  1: "Activity Resumed",
  23: "Activity Stopped",
  2: "Activity Paused",
};

const List<String> eventTypeForDurationList = [
  "Activity Resumed",
  "Activity Paused",
  "Activity Stopped",
];

const List<String> appNameExcludedList = [
  "Permission controller",
  "Pixel Launcher",
  "Quickstep",
  "System UI",
];

class AppEvent {
  AppEvent({
    required this.time,
    required this.appName,
    required this.appIconByte,
    required this.eventType,
  });

  DateTime time;
  String appName;
  Uint8List? appIconByte;
  String? eventType;
}

class AppUsage {
  AppUsage({
    required this.appName,
    required this.appIconByte,
    required this.time,
    required this.durationInSeconds,
  });

  String appName;
  Uint8List? appIconByte;
  DateTime time;
  int durationInSeconds;
}

class UsageMonitor {
  Timer? _timer;
  List<AppUsage> _usages = [];
  Function(List<AppUsage>)? _onUpdate;
  final String _currentAppPackage = 'com.nth.lockerapp'; // Replace with your actual package name


  Future<String> _getAppName(String packageName) async {
    if (packageName == _currentAppPackage) return ''; // Skip our own app

    try {
      final appInfo = await InstalledApps.getAppInfo(packageName, false as BuiltWith?);
      return appInfo?.name ?? packageName;
    } catch (e) {
      debugPrint('Error getting app name for $packageName: $e');
      return packageName;
    }
  }


  void startMonitoring(Function(List<AppUsage>) onUpdate) {
    _onUpdate = onUpdate;
    UsageStats.grantUsagePermission();
    _updateUsageData();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateUsageData();
    });
  }

  void stopMonitoring() {
    _timer?.cancel();
    _onUpdate = null;
  }

  Future<void> _updateUsageData() async {
    try {
      DateTime endDate = DateTime.now();
      DateTime startDate = endDate.subtract(const Duration(minutes: 60)); // Last hour

      List<EventUsageInfo> queryEvents = await UsageStats.queryEvents(startDate, endDate);
      List<AppUsage> appUsages = [];
      Map<String, List<AppEvent>> appNameToAppEventMap = {};

      Uint8List defaultIcon = Uint8List(0);

      for (var event in queryEvents) {
        var packageName = event.packageName;
        if (packageName == null || packageName == _currentAppPackage) continue;
        var eventType = eventTypeMap[int.parse(event.eventType ?? '0')];
        if (eventType == null || packageName == null) continue;
        String appName = await _getAppName(packageName);
        if (appName.isEmpty) continue; // Skip our own app

        var appEvent = AppEvent(
          time: DateTime.fromMillisecondsSinceEpoch(int.parse(event.timeStamp ?? '0')),
          appName: packageName,
          appIconByte: defaultIcon,
          eventType: eventType,
        );

        try {
          var appInfo = await InstalledApps.getAppInfo(packageName, true as BuiltWith?);
          if (appNameExcludedList.contains(appInfo?.name)) continue;
          appEvent.appName = appInfo?.name ?? packageName;
          appEvent.appIconByte = appInfo?.icon ?? defaultIcon;
        } catch (e) {
          debugPrint('Error getting app info for $packageName: $e');
        }

        if (eventTypeForDurationList.contains(eventType)) {
          appNameToAppEventMap.putIfAbsent(appEvent.appName, () => []).add(appEvent);
        }
      }

      appNameToAppEventMap.forEach((appName, events) {
        for (int x = 0; x < events.length; x++) {
          var eventX = events[x];
          if (eventX.eventType == "Activity Resumed") {
            int y = x + 1;
            while (y < events.length &&
                !(events[y].eventType == "Activity Paused" || events[y].eventType == "Activity Stopped")) {
              y++;
            }
            if (y < events.length) {
              var eventY = events[y];
              Duration duration = eventY.time.difference(eventX.time);
              int durationInSeconds = duration.inSeconds;
              if (durationInSeconds > 0) {
                appUsages.add(AppUsage(
                  appName: appName,
                  appIconByte: eventX.appIconByte,
                  time: eventX.time,
                  durationInSeconds: durationInSeconds,
                ));
              }
            }
          }
        }
      });

      Map<String, int> aggregatedDurations = {};
      Map<String, Uint8List?> appIcons = {};
      for (var usage in appUsages) {
        aggregatedDurations[usage.appName] = (aggregatedDurations[usage.appName] ?? 0) + usage.durationInSeconds;
        appIcons[usage.appName] = usage.appIconByte;
      }

      appUsages.clear();
      aggregatedDurations.forEach((appName, duration) {
        appUsages.add(AppUsage(
          appName: appName,
          appIconByte: appIcons[appName] ?? defaultIcon,
          time: DateTime.now(),
          durationInSeconds: duration,
        ));
      });

      _usages = appUsages;
      _onUpdate?.call(_usages);
      debugPrint('App usages updated: ${_usages.length}');
    } catch (e) {
      debugPrint('Error updating usage data: $e');
    }
  }
}