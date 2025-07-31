import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ParentSettingsScreen extends StatefulWidget {
  const ParentSettingsScreen({super.key});

  @override
  State<ParentSettingsScreen> createState() => _ParentSettingsScreenState();
}

class _ParentSettingsScreenState extends State<ParentSettingsScreen> {
  static const Color primaryBlue = Color(0xFF2196F3);
  static const Color darkGrey = Color(0xFF1A1A1A);
  static const Color greyText = Color(0xFF9E9E9E);
  static const Color accentColor = Color(0xFFE2E8F0);

  String? _parentName;
  String? _parentEmail;
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _emailNotifications = false;
  bool _isLoading = true;
  String? _qrCodeId;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _checkConnectionStatus();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final data = userDoc.data();
          setState(() {
            _parentName = data?['name'] ?? user.displayName ?? 'Parent';
            _parentEmail = data?['email'] ?? user.email ?? '';
            _notificationsEnabled = data?['notificationsEnabled'] ?? true;
            _soundEnabled = data?['soundEnabled'] ?? true;
            _vibrationEnabled = data?['vibrationEnabled'] ?? true;
            _emailNotifications = data?['emailNotifications'] ?? false;
            _isLoading = false;
          });
        } else {
          setState(() {
            _parentName = user.displayName ?? 'Parent';
            _parentEmail = user.email ?? '';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkConnectionStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final linkSnapshot = await FirebaseFirestore.instance
            .collection('links')
            .where('parentId', isEqualTo: user.uid)
            .get();

        if (linkSnapshot.docs.isNotEmpty) {
          setState(() {
            _qrCodeId = linkSnapshot.docs.first.id;
            _isConnected = true;
          });
        } else {
          setState(() {
            _qrCodeId = null;
            _isConnected = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking connection status: $e');
    }
  }

  Future<void> _disconnect() async {
    if (_qrCodeId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('links')
          .doc(_qrCodeId)
          .delete();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('qrCodeId');

      setState(() {
        _qrCodeId = null;
        _isConnected = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Disconnected successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }

      debugPrint('Disconnected QR code: $_qrCodeId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to disconnect: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Disconnect error: $e');
    }
  }

  Future<void> _updateNotificationSetting(String setting, bool value) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          setting: value,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(primaryBlue),
                ),
              )
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // Profile Section
                          _buildSettingsCard([
                            _buildProfileTile(),
                            _buildTile(
                              icon: Icons.apps_rounded,
                              title: 'Manage Child Apps',
                              subtitle: 'Configure monitored applications',
                              onTap: () {},
                            ),
                          ]),
                          const SizedBox(height: 16),

                          // Help & About Section
                          _buildSettingsCard([
                            _buildTile(
                              icon: Icons.help,
                              title: 'Help & Support',
                              subtitle: 'Get help and contact support',
                              onTap: _showHelpDialog,
                            ),
                            _buildTile(
                              icon: Icons.info,
                              title: 'About',
                              subtitle: 'App version and information',
                              onTap: _showAboutDialog,
                            ),
                          ]),
                          const SizedBox(height: 16),

                          // Connection Management Section
                          if (_isConnected) ...[
                            _buildSettingsCard([
                              _buildConnectionInfoTile(),
                              _buildTile(
                                icon: Icons.link_off,
                                title: 'Disconnect Device',
                                subtitle: 'Remove connection to child device',
                                isDestructive: true,
                                onTap: () => _showDisconnectDialog(context),
                              ),
                            ]),
                            const SizedBox(height: 16),
                          ],

                          // Logout Section
                          _buildSettingsCard([
                            _buildTile(
                              icon: Icons.logout,
                              title: 'Logout',
                              subtitle: 'Sign out of your parent account',
                              isDestructive: true,
                              onTap: () => _showLogoutDialog(context),
                            ),
                          ]),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildProfileTile() {
    return InkWell(
      onTap: _showEditProfileDialog,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.person,
                color: primaryBlue,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _parentName ?? 'Parent',
                    style: const TextStyle(
                      color: primaryBlue,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _parentEmail ?? '',
                    style: const TextStyle(
                      color: greyText,
                      fontSize: 13,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: primaryBlue,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: darkGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryBlue.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildConnectionInfoTile() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.link,
              color: primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connection ID',
                  style: TextStyle(
                    color: primaryBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _qrCodeId ?? 'Not connected',
                  style: const TextStyle(
                    color: greyText,
                    fontSize: 13,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    (isDestructive ? Colors.red : primaryBlue).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isDestructive ? Colors.red : primaryBlue,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDestructive ? Colors.red : primaryBlue,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: greyText,
                      fontSize: 13,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: isDestructive ? Colors.red : primaryBlue,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: primaryBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: greyText,
                    fontSize: 13,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: primaryBlue,
            inactiveThumbColor: greyText,
            inactiveTrackColor: greyText.withOpacity(0.3),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: _parentName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: darkGrey,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: primaryBlue.withOpacity(0.2)),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: primaryBlue, fontFamily: 'Poppins'),
        ),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: accentColor, fontFamily: 'Poppins'),
          decoration: InputDecoration(
            labelText: 'Name',
            labelStyle: const TextStyle(color: greyText),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: greyText),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: primaryBlue),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: greyText)),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .set({
                    'name': nameController.text.trim(),
                  }, SetOptions(merge: true));

                  setState(() {
                    _parentName = nameController.text.trim();
                  });
                }
                Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error updating profile: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: primaryBlue),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: darkGrey,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: primaryBlue.withOpacity(0.2)),
        ),
        title: const Text(
          'Help & Support',
          style: TextStyle(color: primaryBlue, fontFamily: 'Poppins'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Need help? Contact us:',
              style: TextStyle(color: accentColor, fontFamily: 'Poppins'),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                Clipboard.setData(
                    const ClipboardData(text: 'support@digitalwellbeing.com'));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Email copied to clipboard')),
                );
              },
              child: const Text(
                'support@digitalwellbeing.com',
                style: TextStyle(
                  color: primaryBlue,
                  fontFamily: 'Poppins',
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: primaryBlue)),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: darkGrey,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: primaryBlue.withOpacity(0.2)),
        ),
        title: const Text(
          'About Digital Wellbeing',
          style: TextStyle(color: primaryBlue, fontFamily: 'Poppins'),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version: 1.0.0',
              style: TextStyle(color: accentColor, fontFamily: 'Poppins'),
            ),
            SizedBox(height: 8),
            Text(
              'Digital Wellbeing helps parents manage their children\'s screen time and app usage in a healthy way.',
              style: TextStyle(color: greyText, fontFamily: 'Poppins'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: primaryBlue)),
          ),
        ],
      ),
    );
  }

  Future<void> _showDisconnectDialog(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: darkGrey,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Colors.red.withOpacity(0.2),
            ),
          ),
          title: const Text(
            'Disconnect Device',
            style: TextStyle(
              color: Colors.red,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Poppins',
            ),
          ),
          content: const Text(
            'Are you sure you want to disconnect from the child device? This will stop monitoring and remove the connection.',
            style: TextStyle(
              color: greyText,
              fontSize: 15,
              fontFamily: 'Poppins',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: greyText,
                  fontSize: 15,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _disconnect();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Disconnect',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: darkGrey,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: primaryBlue.withOpacity(0.2),
            ),
          ),
          title: const Text(
            'Logout',
            style: TextStyle(
              color: primaryBlue,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Poppins',
            ),
          ),
          content: const Text(
            'Are you sure you want to logout from your parent account?',
            style: TextStyle(
              color: greyText,
              fontSize: 15,
              fontFamily: 'Poppins',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: greyText,
                  fontSize: 15,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await FirebaseAuth.instance.signOut();
                Navigator.pushReplacementNamed(context, '/');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
