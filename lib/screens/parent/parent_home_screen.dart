import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:easy_pie_chart/easy_pie_chart.dart' as easy_pie_chart;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:async';
import 'package:my_app/screens/message_screen.dart';
import 'parent_settings_screen.dart';
import 'package:intl/intl.dart';

// Data model for app information fetched from the child's device
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
      icon: json['icon'] != null ? base64Decode(json['icon'] as String) : null,
    );
  }
}

class ParentHomeScreen extends StatefulWidget {
  final String? qrCodeId;
  const ParentHomeScreen({super.key, this.qrCodeId});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  bool _isScanning = false;
  String? _errorMessage;
  final Map<String, Color> _appColors = {};
  List<easy_pie_chart.PieData> _pieChartData = [];
  Map<String, Map<String, dynamic>> _packageToDetails = {};
  DateTime? _lastUpdateTime;
  Timer? _updateTimer;
  int _selectedIndex = 0;
  String? _qrCodeId;
  bool _isLoading = true;

  // Cache for holding the child's app info (name, icon, package)
  final Map<String, AppInfo> _childAppInfoCache = {};

  @override
  void initState() {
    super.initState();
    _loadQrCodeId();
    _setupFCM();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadQrCodeId() async {
    final prefs = await SharedPreferences.getInstance();
    String? storedQrCodeId = prefs.getString('qrCodeId');
    if (storedQrCodeId == null && widget.qrCodeId == null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final linkSnapshot = await FirebaseFirestore.instance
            .collection('links')
            .where('parentId', isEqualTo: user.uid)
            .limit(1)
            .get();
        if (linkSnapshot.docs.isNotEmpty) {
          storedQrCodeId = linkSnapshot.docs.first.id;
          await prefs.setString('qrCodeId', storedQrCodeId);
        }
      }
    }
    setState(() {
      _qrCodeId = widget.qrCodeId ?? storedQrCodeId;
      _isLoading = _qrCodeId == null;
      debugPrint('Loaded qrCodeId: $_qrCodeId');
    });
    if (_qrCodeId != null) {
      _startPeriodicUpdate();
    }
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
          .set({'fcmToken': token}, SetOptions(merge: true));
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['screen'] == 'messages') {
        if (mounted) setState(() => _selectedIndex = 1);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${message.notification?.title ?? 'Notification'}: ${message.notification?.body ?? ''}')),
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (message.data['screen'] == 'messages' && mounted) {
        setState(() => _selectedIndex = 1);
      }
    });
  }

  void _startPeriodicUpdate() {
    _updatePieChartData();
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _updatePieChartData();
    });
  }

  void _scanQRCode() {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });
  }

  void _onQRCodeScanned(String qrCodeId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Please log in as a parent first.';
            _isScanning = false;
          });
        }
        return;
      }
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('qrCodeId', isEqualTo: qrCodeId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Invalid QR code.';
            _isScanning = false;
          });
        }
        return;
      }

      final childId = querySnapshot.docs.first.id;
      await FirebaseFirestore.instance.collection('links').doc(qrCodeId).set({
        'parentId': user.uid,
        'childId': childId,
        'linkedAt': Timestamp.now(),
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('qrCodeId', qrCodeId);

      if (mounted) {
        setState(() {
          _isScanning = false;
          _qrCodeId = qrCodeId;
          _errorMessage = null;
          _childAppInfoCache.clear();
        });
      }
      debugPrint('QR code scanned, linked childId: $childId');
      _startPeriodicUpdate();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to link devices: ${e.toString()}';
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _fetchAndCacheChildApps(String childId) async {
    if (_childAppInfoCache.isNotEmpty) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(childId)
          .collection('deviceInfo')
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint("No installed app info found for child $childId");
        return;
      }

      final Map<String, AppInfo> tempCache = {};
      for (var doc in snapshot.docs) {
        final app = AppInfo.fromJson(doc.data());
        tempCache[app.packageName] = app;
      }

      if (mounted) {
        setState(() {
          _childAppInfoCache.clear();
          _childAppInfoCache.addAll(tempCache);
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch child app info: $e");
    }
  }

  Future<void> _updatePieChartData() async {
    if (!mounted || _qrCodeId == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final linkSnapshot = await FirebaseFirestore.instance
          .collection('links')
          .doc(_qrCodeId)
          .get();

      if (!linkSnapshot.exists) {
        throw Exception('No child device linked for this QR ID');
      }

      final childId = linkSnapshot['childId'] as String;

      await _fetchAndCacheChildApps(childId);

      final usageSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(childId)
          .collection('usage')
          .get();

      if (usageSnapshot.docs.isEmpty) {
        throw Exception('No usage data available from child device');
      }

      final usageData = usageSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'packageName': data['appName'] as String? ?? 'Unknown',
          'durationInSeconds':
              (data['durationInSeconds'] as num?)?.toDouble() ?? 0.0,
        };
      }).toList();

      await _buildPieChartData(usageData);
      if (mounted) {
        setState(() {
          _lastUpdateTime = DateTime.now();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to update dashboard: ${e.toString()}';
          _pieChartData = [];
          _packageToDetails = {};
        });
      }
    }
  }

  Future<void> _buildPieChartData(List<Map<String, dynamic>> usages) async {
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
    ];
    List<Color> availableColors = List.from(colors);

    const List<String> systemPrefixes = [
      'com.android.',
      'com.google.android.',
      'com.sec.android.',
      'android'
    ];
    const List<String> appNameExcludedList = [
      'Permission controller',
      'Pixel Launcher',
      'Quickstep',
      'System UI',
      'Android System Intelligence',
      'Android System'
    ];
    const String childAppPackage = 'com.example.my_app';

    final Map<String, double> usageMap = {
      for (var usage in usages)
        usage['packageName'] as String: usage['durationInSeconds'] as double
    };

    for (var usage in usages) {
      final packageName = usage['packageName'] as String;
      final durationInSeconds = usage['durationInSeconds'] as double;
      final appInfo = _childAppInfoCache[packageName];
      final String appName = appInfo?.appName ?? packageName;
      final Uint8List? icon = appInfo?.icon;

      if (durationInSeconds >= 60 &&
          packageName != childAppPackage &&
          !appNameExcludedList
              .any((excludedName) => appName.contains(excludedName)) &&
          !systemPrefixes.any((prefix) => packageName.startsWith(prefix))) {
        Color color;
        if (_appColors.containsKey(packageName)) {
          color = _appColors[packageName]!;
        } else {
          if (availableColors.isNotEmpty) {
            color = availableColors
                .removeAt(random.nextInt(availableColors.length));
          } else {
            availableColors = List.from(colors);
            color = availableColors
                .removeAt(random.nextInt(availableColors.length));
          }
          _appColors[packageName] = color;
        }

        pieData.add(
            easy_pie_chart.PieData(value: durationInSeconds, color: color));

        packageToDetails[packageName] = {
          'appName': appName,
          'icon': icon,
          'duration': '${(durationInSeconds / 60).toStringAsFixed(1)} min',
          'color': color,
        };
      }
    }

    final sortedEntries = packageToDetails.entries.toList()
      ..sort((a, b) {
        final aDuration = usageMap[a.key] ?? 0.0;
        final bDuration = usageMap[b.key] ?? 0.0;
        return bDuration.compareTo(aDuration);
      });

    final sortedPackageToDetails =
        Map<String, Map<String, dynamic>>.fromEntries(sortedEntries);

    if (mounted) {
      setState(() {
        _pieChartData = pieData;
        _packageToDetails = sortedPackageToDetails;
      });
    }
  }

  Widget _buildGlassyBottomSection() {
    return Container(
      margin: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 150, child: _buildGlassyStatusWidget()),
          const SizedBox(width: 34),
          SizedBox(width: 150, child: _buildGlassyManageWidget()),
        ],
      ),
    );
  }

  Widget _buildGlassyStatusWidget() {
    return Container(
      height: 115,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.1),
            Colors.white.withOpacity(0.05)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sync, color: Colors.blue[300], size: 24),
          const SizedBox(height: 6),
          const Text(
            'Last Updated',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _lastUpdateTime != null
                ? DateFormat('h:mm a').format(_lastUpdateTime!)
                : 'Never',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassyManageWidget() {
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = 2),
      child: Container(
        height: 115,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.1),
              Colors.white.withOpacity(0.05)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.apps_outage, color: Colors.white70, size: 24),
            SizedBox(height: 8),
            Text(
              'Manage\nApps & Rules',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedAppsList(String childId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(childId)
          .collection('blockedApps')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final blockedDocs = snapshot.data!.docs;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Blocked App${blockedDocs.length > 1 ? 's' : ''}',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10.0,
                runSpacing: 10.0,
                children: blockedDocs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final packageName = doc.id;
                  final appInfo = _childAppInfoCache[packageName];
                  final appName =
                      appInfo?.appName ?? data['appName'] ?? packageName;
                  final icon = appInfo?.icon;
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.red.withOpacity(0.5), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null)
                          Image.memory(icon, width: 22, height: 22)
                        else
                          const Icon(Icons.block,
                              size: 20, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            appName,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHomeContent() {
    // --- FIX: Restored the scan QR prompt for when no child is linked ---
    if (_qrCodeId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner, color: Colors.white, size: 60),
            const SizedBox(height: 20),
            const Text(
              'No child linked. Please scan a QR code.',
              style: TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _scanQRCode,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan Child QR Code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF2196F3)));
    }

    if (_errorMessage != null) {
      return Center(
          child: Text(_errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 16)));
    }

    return RefreshIndicator(
      onRefresh: _updatePieChartData,
      color: const Color(0xFF2196F3),
      backgroundColor: const Color.fromARGB(255, 0, 0, 0),
      child: FutureBuilder<DocumentSnapshot>(
        future:
            FirebaseFirestore.instance.collection('links').doc(_qrCodeId).get(),
        builder: (context, linkSnapshot) {
          if (linkSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFF2196F3)));
          }
          if (!linkSnapshot.hasData || !linkSnapshot.data!.exists) {
            return Center(
                child: Text("Error: Link data not found.",
                    style: TextStyle(color: Colors.red)));
          }
          final childId = linkSnapshot.data!['childId'] as String;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                _buildBlockedAppsList(childId),
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
                        const SizedBox(
                          width: 100,
                          height: 40,
                          child: Center(
                            child: Text(
                              'Child Usage',
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
                  )
                else
                  const SizedBox(
                      height: 240,
                      child: Center(
                          child: Text("No significant app usage to display.",
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 16)))),
                _buildGlassyBottomSection(),
                if (_packageToDetails.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'App Usage Details:',
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
                        final details = entry.value;
                        final appName = details['appName'] as String;
                        final icon = details['icon'] as Uint8List?;
                        final duration = details['duration'] as String;
                        final color = details['color'] as Color;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(255, 18, 18, 18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: color.withOpacity(0.3), width: 1),
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
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: icon != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.memory(
                                          icon,
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Icon(Icons.apps, size: 24, color: color),
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
                ],
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessagesContent() {
    // --- FIX: Restored the scan QR prompt for when no child is linked ---
    if (_qrCodeId == null || _qrCodeId!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.link_off, color: Colors.white70, size: 60),
            const SizedBox(height: 20),
            const Text(
              'Link a child device to start messaging.',
              style: TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _scanQRCode,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR Code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ],
        ),
      );
    }
    return MessagingPage(qrCodeId: _qrCodeId!);
  }

  Widget _buildSettingsContent() {
    return const ParentSettingsScreen();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
          backgroundColor: const Color(0xFF000000),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Please log in',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: 'Poppins')),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text('Go to Login',
                      style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ));
    }

    if (_isScanning) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF212121),
          title: const Text('Scan QR Code',
              style: TextStyle(
                  color: Color(0xFF2196F3),
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 20)),
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => setState(() => _isScanning = false),
          ),
        ),
        body: MobileScanner(
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
              _onQRCodeScanned(barcodes.first.rawValue!);
            }
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        title: _selectedIndex == 0
            ? const Row(
                children: [
                  Icon(Icons.dashboard_customize,
                      color: Color(0xFF2196F3), size: 28),
                  SizedBox(width: 12),
                  Text('Dashboard',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Color(0xFF2196F3),
                          fontSize: 24,
                          fontWeight: FontWeight.w500)),
                ],
              )
            : Row(
                children: [
                  Icon(_selectedIndex == 1 ? Icons.child_care : Icons.settings,
                      color: const Color(0xFF2196F3), size: 28),
                  const SizedBox(width: 12),
                  Text(_selectedIndex == 1 ? 'Child Messages' : 'Settings',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Color(0xFF2196F3),
                          fontSize: 24,
                          fontWeight: FontWeight.w500)),
                ],
              ),
        actions: _selectedIndex == 0
            ? [
                IconButton(
                  icon: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF2196F3)))
                      : const Icon(Icons.refresh,
                          color: Color(0xFF2196F3), size: 28),
                  tooltip: 'Refresh Usage Data',
                  onPressed: _qrCodeId != null && !_isLoading
                      ? _updatePieChartData
                      : null,
                ),
              ]
            : null,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeContent(),
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
          onTap: (index) => setState(() => _selectedIndex = index),
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 10,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w400,
            fontSize: 10,
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
              label: 'Home',
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
                  _selectedIndex == 1 ? Icons.message : Icons.message_outlined,
                  size: _selectedIndex == 1 ? 28 : 24,
                ),
              ),
              label: 'Messages',
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
                  _selectedIndex == 2
                      ? Icons.settings
                      : Icons.settings_outlined,
                  size: _selectedIndex == 2 ? 28 : 24,
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
