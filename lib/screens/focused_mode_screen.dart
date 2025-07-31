import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class FocusedModeTheme {
  static const TextStyle titleStyle = TextStyle(
    fontFamily: 'Poppins',
    color: Colors.white,
    fontSize: 20,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle timerStyle = TextStyle(
    fontFamily: 'Poppins',
    fontSize: 48,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static TextStyle modeNameStyle({required bool isSelected}) => TextStyle(
        fontFamily: 'Poppins',
        color: isSelected ? Colors.white : Colors.grey[400],
        fontSize: 14,
        fontWeight: FontWeight.w600,
      );

  static TextStyle modeDescriptionStyle({required bool isSelected}) =>
      TextStyle(
        fontFamily: 'Poppins',
        color: isSelected ? Colors.white70 : Colors.grey[600],
        fontSize: 12,
        fontWeight: FontWeight.normal,
      );

  static TextStyle durationStyle({required bool isSelected}) => TextStyle(
        fontFamily: 'Poppins',
        color: isSelected ? Colors.white : Colors.grey[400],
        fontSize: 12,
        fontWeight: FontWeight.w500,
      );

  static TextStyle dialogTitleStyle = TextStyle(
    fontFamily: 'Poppins',
    color: Colors.white,
    fontSize: 22,
    fontWeight: FontWeight.bold,
  );

  static TextStyle dialogContentStyle = TextStyle(
    fontFamily: 'Poppins',
    color: Colors.grey[300],
    fontSize: 16,
  );

  static TextStyle dialogButtonStyle = TextStyle(
    fontFamily: 'Poppins',
    color: Colors.white,
    fontWeight: FontWeight.w600,
  );

  static TextStyle statValueStyle = TextStyle(
    fontFamily: 'Poppins',
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.bold,
  );

  static TextStyle statLabelStyle = TextStyle(
    fontFamily: 'Poppins',
    color: Colors.grey[400],
    fontSize: 12,
  );
}

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Poppins',
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontFamily: 'Poppins'),
          bodyMedium: TextStyle(fontFamily: 'Poppins'),
          titleLarge: TextStyle(fontFamily: 'Poppins'),
          titleMedium: TextStyle(fontFamily: 'Poppins'),
          titleSmall: TextStyle(fontFamily: 'Poppins'),
        ),
      ),
      home: FocusedModeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class FocusedModeScreen extends StatefulWidget {
  const FocusedModeScreen({super.key});

  @override
  State<FocusedModeScreen> createState() => _FocusedModeScreenState();
}

class _FocusedModeScreenState extends State<FocusedModeScreen> {
  String _selectedMode = 'Work';
  int _customMinutes = 25;
  int _customSeconds = 0;

  final List<Map<String, dynamic>> _focusModes = [
    {
      'name': 'Work',
      'duration': 25,
      'icon': Icons.work,
      'color': Colors.blue[400],
      'description': 'Focus on work tasks'
    },
    {
      'name': 'Relax',
      'duration': 15,
      'icon': Icons.spa,
      'color': Colors.green[400],
      'description': 'Take a break and unwind'
    },
    {
      'name': '+ Add Mode',
      'duration': 30,
      'icon': Icons.add_circle,
      'color': Colors.purple[400],
      'description': 'Create a custom focus mode'
    },
  ];

  void _onModeSelected(String modeName) {
    setState(() {
      _selectedMode = modeName;
      final mode = _focusModes.firstWhere((m) => m['name'] == modeName);
      _customMinutes = mode['duration'];
      _customSeconds = 0;
      if (modeName == '+ Add Mode') {
        _showAddModeDialog();
      }
    });
  }

  void _showAddModeDialog() {
    String newModeName = '';
    String newModeDescription = '';
    int newModeDuration = 30;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Create New Mode',
            style: FocusedModeTheme.dialogTitleStyle,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: 'Mode Name',
                  labelStyle: FocusedModeTheme.dialogContentStyle,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[800]!),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue[400]!),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                style: FocusedModeTheme.dialogContentStyle,
                onChanged: (value) {
                  newModeName = value;
                },
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Description',
                  labelStyle: FocusedModeTheme.dialogContentStyle,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[800]!),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue[400]!),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                style: FocusedModeTheme.dialogContentStyle,
                onChanged: (value) {
                  newModeDescription = value;
                },
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Duration (minutes)',
                  labelStyle: FocusedModeTheme.dialogContentStyle,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[800]!),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue[400]!),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                style: FocusedModeTheme.dialogContentStyle,
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  newModeDuration = int.tryParse(value) ?? 30;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Cancel',
                style: FocusedModeTheme.dialogButtonStyle,
              ),
            ),
            TextButton(
              onPressed: () {
                if (newModeName.isNotEmpty && newModeDescription.isNotEmpty) {
                  setState(() {
                    _focusModes.removeWhere((m) => m['name'] == '+ Add Mode');
                    _focusModes.add({
                      'name': newModeName,
                      'duration': newModeDuration,
                      'icon': Icons.star,
                      'color': Colors.purple[400],
                      'description': newModeDescription,
                    });
                    _focusModes.add({
                      'name': '+ Add Mode',
                      'duration': 30,
                      'icon': Icons.add_circle,
                      'color': Colors.purple[400],
                      'description': 'Create a custom focus mode'
                    });
                    _selectedMode = newModeName;
                    _customMinutes = newModeDuration;
                    _customSeconds = 0;
                  });
                  Navigator.of(context).pop();
                }
              },
              child: Text(
                'Add',
                style: FocusedModeTheme.dialogButtonStyle,
              ),
            ),
          ],
        );
      },
    );
  }

  void _startFocusSession() {
    final totalSeconds = (_customMinutes * 60) + _customSeconds;
    final selectedModeData =
        _focusModes.firstWhere((m) => m['name'] == _selectedMode);

    // Show a snackbar notification when starting
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🎯 Starting ${_customMinutes}m ${_customSeconds}s $_selectedMode session',
          style: const TextStyle(fontFamily: 'Poppins'),
        ),
        backgroundColor: selectedModeData['color'],
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CountdownScreen(
          mode: _selectedMode,
          totalSeconds: totalSeconds,
          modeColor: selectedModeData['color'],
          modeIcon: selectedModeData['icon'],
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Column(
            children: _focusModes.map((mode) {
              final isSelected = _selectedMode == mode['name'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onTap: () => _onModeSelected(mode['name']),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.9,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              colors: [
                                mode['color'],
                                mode['color'].withOpacity(0.6)
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            )
                          : const LinearGradient(
                              colors: [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? mode['color'] : Colors.grey[800]!,
                        width: 2,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: mode['color'].withOpacity(0.3),
                                blurRadius: 15,
                                spreadRadius: 2,
                              )
                            ]
                          : [],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withOpacity(0.2)
                                : Colors.black.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            mode['icon'],
                            color: isSelected ? Colors.white : Colors.grey[400],
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mode['name'],
                                style: FocusedModeTheme.modeNameStyle(
                                    isSelected: isSelected),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                mode['description'],
                                style: FocusedModeTheme.modeDescriptionStyle(
                                    isSelected: isSelected),
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
                            color: isSelected
                                ? Colors.white.withOpacity(0.2)
                                : Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${mode['duration']} min',
                            style: FocusedModeTheme.durationStyle(
                                isSelected: isSelected),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[800]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Custom Time',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCompactTimeSelector(
                label: 'Min',
                value: _customMinutes,
                maxValue: 180,
                onChanged: (value) {
                  setState(() {
                    _customMinutes = value;
                  });
                },
              ),
              Container(
                height: 60,
                width: 1,
                color: Colors.grey[700],
              ),
              _buildCompactTimeSelector(
                label: 'Sec',
                value: _customSeconds,
                maxValue: 59,
                onChanged: (value) {
                  setState(() {
                    _customSeconds = value;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactTimeSelector({
    required String label,
    required int value,
    required int maxValue,
    required Function(int) onChanged,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 100,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[700]!, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  if (value > 0) {
                    onChanged(value - 1);
                  }
                },
                child: Container(
                  width: 30,
                  height: 40,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                  child: Icon(
                    Icons.remove,
                    color: value > 0 ? Colors.blue[400] : Colors.grey[600],
                    size: 16,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    value.toString(),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[400],
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  if (value < maxValue) {
                    onChanged(value + 1);
                  }
                },
                child: Container(
                  width: 30,
                  height: 40,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Icon(
                    Icons.add,
                    color:
                        value < maxValue ? Colors.blue[400] : Colors.grey[600],
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStartButton() {
    return Container(
      margin: const EdgeInsets.all(20),
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _startFocusSession,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
        ).copyWith(
          backgroundColor: MaterialStateProperty.all(Colors.transparent),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[400]!, Colors.blue[600]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.blue[400]!.withOpacity(0.3),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.play_arrow, size: 28),
              const SizedBox(width: 8),
              Text(
                'Start ${_customMinutes}m ${_customSeconds}s $_selectedMode Session',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildModeSelector(),
            _buildTimeSelector(),
            _buildStartButton(),
          ],
        ),
      ),
    );
  }
}

class CountdownScreen extends StatefulWidget {
  final String mode;
  final int totalSeconds;
  final Color modeColor;
  final IconData modeIcon;

  const CountdownScreen({
    super.key,
    required this.mode,
    required this.totalSeconds,
    required this.modeColor,
    required this.modeIcon,
  });

  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen>
    with TickerProviderStateMixin {
  Timer? _timer;
  int _timeRemaining = 0;
  bool _isRunning = false;
  bool _isPaused = false;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _timeRemaining = widget.totalSeconds;
    _initializeNotifications();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _fadeController.forward();

    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _notificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _showStartNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'focused_mode_channel',
      'Focused Mode',
      channelDescription: 'Notifications for focused mode sessions',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      0,
      '🎯 Focused Mode Started',
      '${widget.mode} session has begun. Stay focused for ${widget.totalSeconds ~/ 60} minutes!',
      platformChannelSpecifics,
    );
  }

  Future<void> _showEndNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'focused_mode_channel',
      'Focused Mode',
      channelDescription: 'Notifications for focused mode sessions',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      1,
      '🎉 Focused Mode Complete!',
      'Great job! You\'ve successfully completed your ${widget.mode} session.',
      platformChannelSpecifics,
    );
  }

  void _startTimer() {
    if (_isRunning) return;

    setState(() {
      _isRunning = true;
      _isPaused = false;
    });

    // Show start notification
    _showStartNotification();

    _pulseController.repeat(reverse: true);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_timeRemaining > 0) {
          _timeRemaining--;

          if (_timeRemaining % 60 == 0 && _timeRemaining > 0) {
            _showProgressNotification();
          }
        } else {
          _stopTimer();
          _showCompletionDialog();
        }
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _pulseController.stop();
    setState(() {
      _isRunning = false;
    });

    // Show end notification if session completed
    if (_timeRemaining == 0) {
      _showEndNotification();
    }
  }

  void _pauseTimer() {
    _timer?.cancel();
    _pulseController.stop();
    setState(() {
      _isRunning = false;
      _isPaused = true;
    });
  }

  void _showProgressNotification() {
    final minutesLeft = _timeRemaining ~/ 60;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '⏰ ${widget.mode} session: $minutesLeft minutes remaining',
          style: const TextStyle(fontFamily: 'Poppins'),
        ),
        backgroundColor: widget.modeColor,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showCompletionDialog() {
    // Show completion snackbar first
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🎉 ${widget.mode} session completed! Great job staying focused!',
          style: const TextStyle(fontFamily: 'Poppins'),
        ),
        backgroundColor: widget.modeColor,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            '🎉 Session Complete!',
            style: FocusedModeTheme.dialogTitleStyle,
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Congratulations! You\'ve successfully completed your ${widget.mode} session.',
                style: FocusedModeTheme.dialogContentStyle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: widget.modeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.modeColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Icon(Icons.timer, color: widget.modeColor, size: 24),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.totalSeconds ~/ 60}m',
                          style: TextStyle(
                            color: widget.modeColor,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        Text(
                          'Duration',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Icon(widget.modeIcon,
                            color: widget.modeColor, size: 24),
                        const SizedBox(height: 4),
                        Text(
                          widget.mode,
                          style: TextStyle(
                            color: widget.modeColor,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        Text(
                          'Mode',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                            fontFamily: 'Poppins',
                          ),
                        ),
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
                Navigator.of(context).pop();
              },
              child: Text(
                'Done',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _resetTimer();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.modeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Start New Session',
                style: FocusedModeTheme.dialogButtonStyle,
              ),
            ),
          ],
        );
      },
    );
  }

  void _resetTimer() {
    _stopTimer();
    setState(() {
      _timeRemaining = widget.totalSeconds;
      _isPaused = false;
    });
    _startTimer();
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildTimerDisplay() {
    double progress = 1.0 - (_timeRemaining / widget.totalSeconds);

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isRunning ? _pulseAnimation.value : 1.0,
          child: SizedBox(
            width: 250,
            height: 250,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [
                        Color(0xFF2A2A2A),
                        Color(0xFF1A1A1A),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 220,
                  height: 220,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 8,
                    backgroundColor: Colors.grey[800],
                    valueColor: AlwaysStoppedAnimation<Color>(widget.modeColor),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _formatTime(_timeRemaining),
                      style: FocusedModeTheme.timerStyle,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.mode,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        color: widget.modeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.grey[800]!, width: 1),
          ),
          child: IconButton(
            onPressed: () {
              _stopTimer();
              Navigator.of(context).pop();
            },
            icon: Icon(Icons.arrow_back, color: Colors.grey[400]),
            iconSize: 30,
            padding: const EdgeInsets.all(15),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [widget.modeColor, widget.modeColor.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(35),
            boxShadow: [
              BoxShadow(
                color: widget.modeColor.withOpacity(0.3),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: IconButton(
            onPressed: _isRunning ? _pauseTimer : _startTimer,
            icon: Icon(
              _isRunning ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            iconSize: 45,
            padding: const EdgeInsets.all(20),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.grey[800]!, width: 1),
          ),
          child: IconButton(
            onPressed: () {
              _stopTimer();
              setState(() {
                _timeRemaining = widget.totalSeconds;
                _isPaused = false;
              });
            },
            icon: Icon(Icons.refresh, color: Colors.grey[400]),
            iconSize: 30,
            padding: const EdgeInsets.all(15),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            _stopTimer();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          '${widget.mode} Session',
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.modeColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: widget.modeColor, width: 1),
            ),
            child: Text(
              _isRunning ? 'RUNNING' : (_isPaused ? 'PAUSED' : 'READY'),
              style: TextStyle(
                fontFamily: 'Poppins',
                color: widget.modeColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              _buildTimerDisplay(),
              const SizedBox(height: 60),
              _buildControlButtons(),
              const Spacer(),
              Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[800]!, width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(
                        'Elapsed',
                        _formatTime(widget.totalSeconds - _timeRemaining),
                        Icons.access_time,
                        widget.modeColor),
                    Container(
                      height: 30,
                      width: 1,
                      color: Colors.grey[800],
                    ),
                    _buildStatItem(
                        'Progress',
                        '${(((widget.totalSeconds - _timeRemaining) / widget.totalSeconds) * 100).toInt()}%',
                        Icons.percent,
                        widget.modeColor),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: FocusedModeTheme.statValueStyle,
        ),
        Text(
          label,
          style: FocusedModeTheme.statLabelStyle,
        ),
      ],
    );
  }
}
