import 'dart:async'; // Import 'dart:async' for StreamSubscription
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_app/screens/child/child_home_screen.dart';
import 'package:my_app/screens/message_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';

// Assuming MessagingPage is in this file, or import it correctly.

class ChildQRScreen extends StatefulWidget {
  const ChildQRScreen({super.key});

  @override
  State<ChildQRScreen> createState() => _ChildQRScreenState();
}

class _ChildQRScreenState extends State<ChildQRScreen>
    with SingleTickerProviderStateMixin {
  static const Color primaryBlue = Color(0xFF2196F3);
  static const Color darkGrey = Color(0xFF1A1A1A);
  static const Color greyText = Color(0xFF9E9E9E);
  static const Color accentColor = Color(0xFFE2E8F0);

  String? _qrCodeId;
  bool _isLoading = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // --- NEW: Add a StreamSubscription to listen for the connection ---
  StreamSubscription<DocumentSnapshot>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
    _loadQRCode();
  }

  @override
  void dispose() {
    _animationController.dispose();
    // --- NEW: Cancel the subscription to prevent memory leaks ---
    _linkSubscription?.cancel();
    super.dispose();
  }

  // --- NEW: Method to listen for the link document in Firestore ---
  void _listenForConnection() {
    if (_qrCodeId != null) {
      _linkSubscription = FirebaseFirestore.instance
          .collection('links')
          .doc(_qrCodeId!)
          .snapshots()
          .listen((snapshot) {
        // If the document exists, the connection is made.
        if (snapshot.exists && mounted) {
          _linkSubscription?.cancel(); // Stop listening
          // Navigate to the messaging page
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => ChildHomeScreen(qrCodeId: _qrCodeId!),
            ),
          );
        }
      });
    }
  }

  Future<void> _loadQRCode() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists && userDoc.data()?['qrCodeId'] != null) {
          setState(() {
            _qrCodeId = userDoc.data()!['qrCodeId'];
            _isLoading = false;
          });
          _animationController.forward();
          // --- NEW: Start listening for a connection ---
          _listenForConnection();
        } else {
          await _generateNewQRCode();
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading QR code: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _generateNewQRCode() async {
    // --- NEW: Cancel any existing listener before generating a new code ---
    await _linkSubscription?.cancel();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final uniqueId = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}';

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'qrCodeId': uniqueId,
          'isParent': false,
          'generatedAt': Timestamp.now(),
        }, SetOptions(merge: true));

        setState(() {
          _qrCodeId = uniqueId;
          _isLoading = false;
        });
        _animationController.forward();
        // --- NEW: Start listening with the new QR code ID ---
        _listenForConnection();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating QR code: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _copyQRCodeToClipboard() async {
    if (_qrCodeId != null) {
      await Clipboard.setData(ClipboardData(text: _qrCodeId!));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('QR Code ID copied to clipboard!'),
            backgroundColor: primaryBlue,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _regenerateQRCode() async {
    setState(() {
      _isLoading = true;
    });
    _animationController.reset();
    await _generateNewQRCode();
  }

  // The build method and _buildInstructionStep remain the same.
  // ... (Paste your existing build method here)
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isSmallScreen = size.width < 400;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: primaryBlue),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Child QR Code',
          style: TextStyle(
            color: primaryBlue,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
        ),
        centerTitle: true,
      
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(primaryBlue),
              ),
            )
          : FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Header Section

                      const SizedBox(height: 30),

                      // QR Code Section
                      if (_qrCodeId != null) ...[
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: primaryBlue.withOpacity(0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: QrImageView(
                            data: _qrCodeId!,
                            version: QrVersions.auto,
                            size: isSmallScreen ? 220.0 : 250.0,
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                        ),

                        const SizedBox(height: 20),

                        // QR Code ID Display
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: darkGrey,
                            borderRadius: BorderRadius.circular(15),
                            border:
                                Border.all(color: primaryBlue.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                             
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'CONNECTION ID: ${_qrCodeId!.substring(0, 11)}...',
                                      style: const TextStyle(
                                        color: accentColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'Poppins',
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 30),

                        // Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _regenerateQRCode,
                                icon: const Icon(Icons.refresh),
                                label: const Text('New Code'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryBlue,
                                  side: const BorderSide(color: primaryBlue),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Instructions Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            border:
                                Border.all(color: primaryBlue.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: primaryBlue,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'How to Connect',
                                    style: TextStyle(
                                      color: primaryBlue,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildInstructionStep(
                                  '1', 'Ask your parent to open the app'),
                              _buildInstructionStep('2',
                                  'Parent should tap the QR scanner button'),
                              _buildInstructionStep(
                                  '3', 'Show this QR code to your parent'),
                              _buildInstructionStep(
                                  '4', 'Wait for the connection to complete'),
                            ],
                          ),
                        ),
                      ] else ...[
                        const Text(
                          'Failed to generate QR code',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 18,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildInstructionStep(String number, String instruction) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: primaryBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              instruction,
              style: const TextStyle(
                color: accentColor,
                fontSize: 16,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
