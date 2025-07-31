import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_pie_chart/easy_pie_chart.dart' as easy_pie_chart;
import 'package:device_apps/device_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../dashboard/usage_monitor.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';

class AppManagementScreen extends StatefulWidget {
  final String qrCodeId;
  const AppManagementScreen({super.key, required this.qrCodeId});

  @override
  State<AppManagementScreen> createState() => _AppManagementScreenState();
}

class _AppManagementScreenState extends State<AppManagementScreen> {
  bool _showAppList = false;
  bool _showUsageStats = false;
  List<AppInfo>? _apps;
  List<AppInfo> _filteredApps = [];
  Set<String> _blockedPackages = {};
  bool _loading = false;
  List<easy_pie_chart.PieData> _pieChartData = [];
  Map<String, Map<String, dynamic>> _packageToDetails = {};
  static const platform = MethodChannel('app_blocker');
  static const widgetChannel = MethodChannel('app_blocker/widget');
  final UsageMonitor _usageMonitor = UsageMonitor();
  List<AppUsage> _usages = [];
  double _blockDurationHours = 0.0;
  static const String _currentAppPackage = 'com.example.my_app';
  static const String _youTubePackage = 'com.google.android.youtube';
  final TextEditingController _searchController = TextEditingController();
  final _debouncer = Debouncer(delay: const Duration(milliseconds: 300));
  static const Duration cacheValidity = Duration(minutes: 15);

  @override
  void initState() {
    super.initState();
    _loadBlockedApps();
    _checkPermissions();
    _preloadApps();
    _usageMonitor.startMonitoring((usages) {
      setState(() {
        _usages = usages;
        _buildPieChartData();
      });
      _syncUsageToFirestore();
    });
    _setupWidgetChannel();
    _setupUnlockHandler();
    _searchController.addListener(() {
      _filterApps(_searchController.text);
    });
  }

  Future<void> _checkPermissions() async {
    try {
      final bool hasUsagePermission =
          await platform.invokeMethod('checkUsageStatsPermission');
      if (!hasUsagePermission) {
        await platform.invokeMethod('requestUsageStatsPermission');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please grant Usage Access permission.'),
              backgroundColor: Colors.red,
            ),
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
              content: Text('Please grant Overlay permission.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      debugPrint(
          'Permissions: Usage=$hasUsagePermission, Overlay=$hasOverlayPermission');
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permission error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

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
            content: Text('Failed to preload apps: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

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
              content: Text('No user-installed apps found.'),
              backgroundColor: Colors.orange,
            ),
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
            content: Text('Failed to load apps: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

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
      await SharedPreferences.getInstance().then((prefs) {
        prefs.remove('cachedApps');
        prefs.remove('cacheTimestamp');
      });
      return null;
    }
  }

  Future<void> _cacheApps(List<AppInfo> apps) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = apps.map((app) => app.toJson()).toList();
      await prefs.setString('cachedApps', json.encode(jsonList));
      await prefs.setString('cacheTimestamp', DateTime.now().toIso8601String());
      debugPrint('Cached ${apps.length} apps');
    } catch (e) {
      debugPrint('Error caching apps: $e');
    }
  }

  void _filterApps(String query) {
    _debouncer.call(() {
      setState(() {
        _filteredApps = _apps!
            .where((app) =>
                app.appName.toLowerCase().contains(query.toLowerCase()))
            .toList();
        debugPrint('Filtered apps for query "$query": ${_filteredApps.length}');
      });
    });
  }

  void _setupUnlockHandler() {
    platform.setMethodCallHandler((call) async {
      if (call.method == "unlockApp") {
        final packageName = call.arguments['packageName'] as String?;
        if (packageName != null) {
          setState(() {
            _blockedPackages.remove(packageName);
          });
          await _saveBlockedApps();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$packageName has been unblocked.')),
            );
          }
          debugPrint('Unblocked app: $packageName');
        }
      }
      return null;
    });
  }

  void _syncUsageToFirestore() async {
    final user = FirebaseAuth.instance.currentUser!;
    final batch = FirebaseFirestore.instance.batch();
    final collection = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('usage');
    for (var usage in _usages) {
      final docRef = collection.doc(usage.appName);
      batch.set(docRef, {
        'appName': usage.appName,
        'durationInSeconds': usage.durationInSeconds,
        'updatedAt': Timestamp.now(),
      });
    }
    await batch.commit();
    debugPrint('Synced ${_usages.length} usage records to Firestore');
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

  void _buildPieChartData() {
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
    ];

    final validPackages = {for (var app in _apps ?? []) app.packageName};

    for (var usage in _usages) {
      if (usage.durationInSeconds >= 60 &&
          validPackages.contains(usage.appName) &&
          usage.appName != _currentAppPackage) {
        final app = _apps!.firstWhere(
          (a) => a.packageName == usage.appName,
          orElse: () => AppInfo(
            appName: usage.appName,
            packageName: usage.appName,
            icon: null,
          ),
        );
        final color = colors[random.nextInt(colors.length)];
        pieData.add(
          easy_pie_chart.PieData(
            value: usage.durationInSeconds.toDouble(),
            color: color,
          ),
        );
        packageToDetails[usage.appName] = {
          'icon': app.icon,
          'duration':
              '${(usage.durationInSeconds / 60).toStringAsFixed(1)} min',
          'color': color,
        };
      }
    }

    setState(() {
      _pieChartData = pieData;
      _packageToDetails = packageToDetails;
      debugPrint('Pie chart data: ${pieData.length} entries');
    });
  }

// Updated _blockApps method with proper navigation
  Future<void> _blockApps() async {
    if (_blockedPackages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select at least one app to block.')),
      );
      return;
    }

    try {
      // Check permissions first
      final bool hasOverlayPermission =
          await platform.invokeMethod('checkOverlayPermission');
      if (!hasOverlayPermission) {
        await platform.invokeMethod('requestOverlayPermission');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please grant Overlay permission to block apps.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      debugPrint('Permissions granted, navigating to TimeSelectionScreen');

      // Navigate to TimeSelectionScreen - ensure proper navigation
      final result = await Navigator.of(context).push<double>(
        MaterialPageRoute<double>(
          builder: (context) => TimeSelectionScreen(
            onConfirm: (durationHours) {
              debugPrint('Time selection confirmed: $durationHours hours');
              // Don't call the blocking method here, return the value instead
              Navigator.of(context).pop(durationHours);
            },
            initialDuration: _blockDurationHours,
          ),
        ),
      );

      // Handle the result when user comes back
      if (result != null && result > 0) {
        debugPrint('Received duration from TimeSelectionScreen: $result hours');
        await _confirmBlockWithTimer(result);
      } else {
        debugPrint('No duration selected or user cancelled');
      }
    } catch (e) {
      debugPrint('Error in _blockApps: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmBlockWithTimer(double durationHours) async {
    if (durationHours <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a duration greater than 0.')),
      );
      return;
    }
    try {
      final durationSeconds = (durationHours * 3600).toInt();
      debugPrint(
          'Blocking ${_blockedPackages.length} apps for $durationSeconds seconds');
      final bool success = await platform.invokeMethod('startMonitoring', {
        'packageNames': _blockedPackages.toList(),
        'durationSeconds': durationSeconds,
      });
      if (success) {
        await _saveBlockedApps();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Successfully blocked ${_blockedPackages.length} app(s) for ${durationHours.toStringAsFixed(1)} hours'),
              backgroundColor: Colors.green,
            ),
          );
        }
        setState(() {
          _showAppList = false;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to block apps. Please check permissions.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error blocking apps: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final blockedList = prefs.getStringList('blocked_apps') ?? [];
    setState(() {
      _blockedPackages = blockedList.toSet();
    });
    final user = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'blockedApps': blockedList,
    }, SetOptions(merge: true));
    debugPrint('Loaded ${blockedList.length} blocked apps');
  }

  Future<void> _saveBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('blocked_apps', _blockedPackages.toList());
    final user = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'blockedApps': _blockedPackages.toList(),
    }, SetOptions(merge: true));
    debugPrint('Saved ${_blockedPackages.length} blocked apps');
  }

  Future<void> _listApps() async {
    if (_apps != null && _apps!.isNotEmpty) {
      setState(() {
        _showAppList = true;
        _showUsageStats = false;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
    });

    await _loadApps();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF212121),
      appBar: AppBar(
        backgroundColor: const Color(0xFF424242),
        title: const Text(
          'App Management',
          style: TextStyle(color: Colors.white),
        ),
        elevation: 4,
      ),
      body: Builder(
        builder: (BuildContext scaffoldContext) {
          return SingleChildScrollView(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SearchBar(
                    controller: _searchController,
                    onChanged: _filterApps,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: _listApps,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 5,
                          shadowColor: Colors.black.withOpacity(0.3),
                        ),
                        child: const Text(
                          'List Apps',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _showUsageStats = true;
                            _showAppList = false;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 5,
                          shadowColor: Colors.black.withOpacity(0.3),
                        ),
                        child: const Text(
                          'Show Usage Stats New',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_blockedPackages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Blocked Apps: ${_blockedPackages.length}',
                      style: const TextStyle(fontSize: 14, color: Colors.red),
                    ),
                  ),
                SizedBox(
                  height: MediaQuery.of(scaffoldContext).size.height - 150,
                  child: Center(
                    child: _showUsageStats
                        ? _pieChartData.isEmpty
                            ? const Text(
                                'No usage data available (minimum 1 minute).',
                                style: TextStyle(color: Colors.white),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    height: 300,
                                    child: easy_pie_chart.EasyPieChart(
                                      pieType: easy_pie_chart.PieType.crust,
                                      size: 200,
                                      gap: 6,
                                      borderWidth: 14,
                                      borderEdge: StrokeCap.round,
                                      showValue: false,
                                      centerText: 'App Usage',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      children: _pieChartData,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children:
                                        _packageToDetails.entries.map((entry) {
                                      final packageName = entry.key;
                                      final details = entry.value;
                                      final icon =
                                          details['icon'] as Uint8List?;
                                      final duration =
                                          details['duration'] as String;
                                      final color = details['color'] as Color;
                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 16,
                                            height: 16,
                                            color: color,
                                          ),
                                          const SizedBox(width: 4),
                                          icon != null
                                              ? Image.memory(icon,
                                                  width: 24, height: 24)
                                              : const Icon(Icons.apps,
                                                  size: 24,
                                                  color: Color(0xFF2196F3)),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$packageName: $duration',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ],
                              )
                        : _showAppList
                            ? _loading
                                ? const CircularProgressIndicator(
                                    color: Color(0xFF2196F3))
                                : _filteredApps.isEmpty
                                    ? const Text(
                                        'No apps found. Check permissions or install apps.',
                                        style: TextStyle(color: Colors.white),
                                      )
                                    : Column(
                                        children: [
                                          Expanded(
                                            child: ListView.builder(
                                              itemCount: _filteredApps.length,
                                              itemBuilder: (context, index) {
                                                final app =
                                                    _filteredApps[index];
                                                final isBlocked =
                                                    _blockedPackages.contains(
                                                        app.packageName);

                                                return ListTile(
                                                  leading: app.icon != null
                                                      ? Image.memory(app.icon!,
                                                          width: 40, height: 40)
                                                      : const Icon(Icons.apps,
                                                          color: Color(
                                                              0xFF2196F3)),
                                                  title: Text(
                                                    app.appName,
                                                    style: const TextStyle(
                                                        color: Colors.white),
                                                  ),
                                                  subtitle: Text(
                                                    app.packageName,
                                                    style: const TextStyle(
                                                        color: Colors.grey),
                                                  ),
                                                  trailing: Checkbox(
                                                    value: isBlocked,
                                                    activeColor:
                                                        const Color(0xFF2196F3),
                                                    onChanged: (value) {
                                                      setState(() {
                                                        if (value == true) {
                                                          _blockedPackages.add(
                                                              app.packageName);
                                                        } else {
                                                          _blockedPackages
                                                              .remove(app
                                                                  .packageName);
                                                        }
                                                      });
                                                    },
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          if (_blockedPackages.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: ElevatedButton(
                                                onPressed: () =>
                                                    _blockApps(), // Use scaffoldContext
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.red,
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 20,
                                                      vertical: 12),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            15),
                                                  ),
                                                  elevation: 5,
                                                  shadowColor: Colors.black
                                                      .withOpacity(0.3),
                                                ),
                                                child: const Text(
                                                  'Block Selected Apps',
                                                  style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                        ],
                                      )
                            : const Center(
                                child: Text(
                                  'Press "List Apps" to select apps to block.',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _usageMonitor.stopMonitoring();
    _searchController.dispose();
    super.dispose();
  }
}

class TimeSelectionScreen extends StatefulWidget {
  final Function(double) onConfirm;
  final double initialDuration;

  const TimeSelectionScreen({
    super.key,
    required this.onConfirm,
    required this.initialDuration,
  });

  @override
  State<TimeSelectionScreen> createState() => _TimeSelectionScreenState();
}

class _TimeSelectionScreenState extends State<TimeSelectionScreen> {
  late double _blockDurationHours;

  @override
  void initState() {
    super.initState();
    _blockDurationHours =
        widget.initialDuration > 0 ? widget.initialDuration : 5.0 / 60.0;
    debugPrint(
        'TimeSelectionScreen initialized with duration: $_blockDurationHours');
  }

  // Helper widget for preset duration buttons
  Widget _buildPresetButton(double hours, String label) {
    final isSelected = (_blockDurationHours - hours).abs() < 0.01;
    return InkWell(
      onTap: () {
        setState(() {
          _blockDurationHours = hours;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3) : const Color(0xFF424242),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF2196F3) : Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[300],
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _handleConfirm() {
    debugPrint('Confirm pressed with duration: $_blockDurationHours hours');
    if (_blockDurationHours <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a duration greater than 0.')),
      );
      return;
    }
    widget.onConfirm(_blockDurationHours);
  }

  void _handleCancel() {
    debugPrint('Cancel pressed on TimeSelectionScreen');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
        'Building TimeSelectionScreen with duration: $_blockDurationHours');

    return Scaffold(
      backgroundColor: const Color(0xFF212121),
      appBar: AppBar(
        backgroundColor: const Color(0xFF424242),
        title: const Text(
          'Set Block Duration',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2196F3)),
          onPressed: _handleCancel,
        ),
        elevation: 4,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Select how long you want to block the selected apps',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF424242),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFF2196F3), width: 2),
                ),
                child: Column(
                  children: [
                    Text(
                      'Duration: ${_blockDurationHours.toStringAsFixed(1)} hours',
                      style: const TextStyle(
                        color: Color(0xFF2196F3),
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 8,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 12),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 20),
                      ),
                      child: Slider(
                        value: _blockDurationHours,
                        min: 5.0 / 60.0, // 5 minutes minimum
                        max: 12.0, // 12 hours maximum
                        divisions: 143, // Adjusted for 5-minute increments
                        activeColor: const Color(0xFF2196F3),
                        inactiveColor: Colors.grey,
                        label: _formatDuration(_blockDurationHours),
                        onChanged: (value) {
                          setState(() {
                            _blockDurationHours = value;
                            debugPrint(
                                'Slider updated to: $_blockDurationHours hours');
                          });
                        },
                      ),
                    ),
                    Text(
                      'Range: 5 minutes to 12 hours',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              // Preset duration buttons
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const Text(
                      'Quick Select',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildPresetButton(5.0 / 60.0, '5 min'),
                        _buildPresetButton(0.25, '15 min'),
                        _buildPresetButton(0.5, '30 min'),
                        _buildPresetButton(1.0, '1 hour'),
                        _buildPresetButton(2.0, '2 hours'),
                        _buildPresetButton(4.0, '4 hours'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _handleCancel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF424242),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: const BorderSide(color: Color(0xFF2196F3)),
                        ),
                        elevation: 5,
                        shadowColor: Colors.black.withOpacity(0.3),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF2196F3),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _handleConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2196F3),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 5,
                        shadowColor: Colors.black.withOpacity(0.3),
                      ),
                      child: const Text(
                        'Block Apps',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
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

  String _formatDuration(double hours) {
    if (hours < 1.0) {
      final minutes = (hours * 60).round();
      return '$minutes min';
    } else {
      return '${hours.toStringAsFixed(1)} hrs';
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

class SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const SearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
     
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: const InputDecoration(
          hintText: 'Search apps...',
          hintStyle: TextStyle(color: Colors.grey),
          prefixIcon: Icon(Icons.search, color: Color(0xFF2196F3)),
          border: InputBorder.none,
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}

class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({required this.delay});

  void call(void Function() callback) {
    _timer?.cancel();
    _timer = Timer(delay, callback);
  }
}
