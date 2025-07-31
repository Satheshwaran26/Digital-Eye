import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_app/screens/parent/parent_home_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import 'child/child_home_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isParentLogin = true;
  final Color _primaryColor = const Color(0xFF2196F3);
  final Color _backgroundColor = const Color(0xFF000000);
  final Color _cardColor = const Color(0xFF111111);
  final Color _inputFieldColor = const Color(0xFF1A1A1A);
  final Color _textColor = const Color(0xFF2196F3);
  final Color _greyColor = const Color(0xFF808080);
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  String? _qrCodeId;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    if (!_isParentLogin) {
      _listenForConnection();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginWithEmail() async {
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
        'isParent': true,
        'email': _emailController.text.trim(),
      }, SetOptions(merge: true));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ParentHomeScreen()),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Sign-in failed: ${e.toString()}';
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // User canceled
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        'isParent': true,
        'email': userCredential.user!.email,
      }, SetOptions(merge: true));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ParentHomeScreen()),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Google sign-in failed: ${e.toString()}';
      });
    }
  }

  Future<void> _childAnonymousLogin() async {
    try {
      final credential = await FirebaseAuth.instance.signInAnonymously();
      final uniqueId = const Uuid().v4();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
        'isParent': false,
        'qrCodeId': uniqueId,
      });
      setState(() {
        _qrCodeId = uniqueId;
      });
      _listenForConnection();
    } catch (e) {
      setState(() {
        _errorMessage = 'Anonymous login failed: ${e.toString()}';
      });
    }
  }

  void _listenForConnection() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && _qrCodeId != null) {
      FirebaseFirestore.instance
          .collection('links')
          .doc(_qrCodeId)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) => ChildHomeScreen(qrCodeId: _qrCodeId!)),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isSmallScreen = size.width < 400;

    if (_isParentLogin && _isScanning) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          backgroundColor: _backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios, color: _textColor),
            onPressed: () => setState(() => _isScanning = false),
          ),
          title: Text(
            'Scan QR Code',
            style: TextStyle(
              color: _textColor,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
        body: MobileScanner(
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              if (barcode.rawValue != null) {
                _onQRCodeScanned(barcode.rawValue!);
                break;
              }
            }
          },
        ),
      );
    }

    if (!_isParentLogin && _qrCodeId != null) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 20.0 : 24.0,
              vertical: isSmallScreen ? 20.0 : 24.0,
            ),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _cardColor.withOpacity(0.8),
                          _cardColor.withOpacity(0.4),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _greyColor.withOpacity(0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back_ios,
                          color: _textColor, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                SizedBox(height: size.height * 0.02),
                Text(
                  'Child Mode',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 28 : 32,
                    fontWeight: FontWeight.w700,
                    color: _textColor,
                    fontFamily: 'Poppins',
                    letterSpacing: 0.5,
                    shadows: [
                      Shadow(
                        color: _textColor.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: size.height * 0.01),
                Text(
                  'Waiting for parent connection',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 16 : 18,
                    fontWeight: FontWeight.w400,
                    color: _greyColor,
                    fontFamily: 'Poppins',
                  ),
                ),
                SizedBox(height: size.height * 0.02),
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 20 : 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _cardColor.withOpacity(0.8),
                        _cardColor.withOpacity(0.4),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _greyColor.withOpacity(0.3),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      QrImageView(
                        data: _qrCodeId!,
                        version: QrVersions.auto,
                        size: isSmallScreen ? 240.0 : 280.0,
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                      SizedBox(
                          height: isSmallScreen ? 24 : 20,
                          width: isSmallScreen ? 240 : 280),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 12 : 16,
                          vertical: isSmallScreen ? 8 : 12,
                        ),
                        decoration: BoxDecoration(
                          color: _inputFieldColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _textColor.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'ID: ${_qrCodeId!.substring(0, 11)}...',
                          style: TextStyle(
                            color: _textColor,
                            fontSize: isSmallScreen ? 14 : 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: size.height * 0.02),
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _cardColor.withOpacity(0.6),
                        _cardColor.withOpacity(0.3),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _textColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: isSmallScreen ? 20 : 24,
                        height: isSmallScreen ? 20 : 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(_textColor),
                        ),
                      ),
                      SizedBox(width: isSmallScreen ? 12 : 16),
                      Text(
                        'Waiting for parent to scan...',
                        style: TextStyle(
                          color: _textColor,
                          fontSize: isSmallScreen ? 14 : 16,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: size.height * 0.02),
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _cardColor.withOpacity(0.6),
                        _cardColor.withOpacity(0.3),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _textColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How to connect:',
                        style: TextStyle(
                          color: _textColor,
                          fontSize: isSmallScreen ? 14 : 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      SizedBox(height: isSmallScreen ? 8 : 12),
                      Row(
                        children: [
                          Container(
                            width: isSmallScreen ? 20 : 24,
                            height: isSmallScreen ? 20 : 24,
                            decoration: BoxDecoration(
                              color: _textColor,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '1',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isSmallScreen ? 10 : 12,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: isSmallScreen ? 8 : 12),
                          Expanded(
                            child: Text(
                              'Open the app on parent device',
                              style: TextStyle(
                                color: _greyColor,
                                fontSize: isSmallScreen ? 12 : 14,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isSmallScreen ? 6 : 8),
                      Row(
                        children: [
                          Container(
                            width: isSmallScreen ? 20 : 24,
                            height: isSmallScreen ? 20 : 24,
                            decoration: BoxDecoration(
                              color: _textColor,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '2',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isSmallScreen ? 10 : 12,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: isSmallScreen ? 8 : 12),
                          Expanded(
                            child: Text(
                              'Click "Scan Child" and scan this QR code',
                              style: TextStyle(
                                color: _greyColor,
                                fontSize: isSmallScreen ? 12 : 14,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 20.0 : 24.0,
            vertical: isSmallScreen ? 20.0 : 24.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _cardColor.withOpacity(0.8),
                      _cardColor.withOpacity(0.4),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _greyColor.withOpacity(0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(Icons.arrow_back_ios, color: _textColor, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              SizedBox(height: size.height * 0.03),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: isSmallScreen ? 80 : 100,
                      height: isSmallScreen ? 80 : 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _textColor,
                            _textColor.withOpacity(0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: _textColor.withOpacity(0.4),
                            blurRadius: 25,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.shield_outlined,
                        size: isSmallScreen ? 40 : 50,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 16 : 20),
                    Text(
                      'Parent Control',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 24 : 28,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
                        fontFamily: 'Poppins',
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 8 : 12),
                    Text(
                      'Secure Digital Parenting',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 14 : 16,
                        fontWeight: FontWeight.w400,
                        color: _greyColor,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: size.height * 0.03),
              Center(
                child: Container(
                  width: size.width * 0.85,
                  height: isSmallScreen ? 60 : 65,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(35),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _cardColor.withOpacity(0.8),
                        _cardColor.withOpacity(0.4),
                      ],
                    ),
                    border: Border.all(
                      color: _greyColor.withOpacity(0.3),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _buildToggleButton(true, size),
                      _buildToggleButton(false, size),
                    ],
                  ),
                ),
              ),
              SizedBox(height: size.height * 0.02),
              Text(
                'Welcome Back',
                style: TextStyle(
                  fontSize: isSmallScreen ? 28 : 32,
                  fontWeight: FontWeight.w700,
                  color: _textColor,
                  fontFamily: 'Poppins',
                  letterSpacing: 0.5,
                  shadows: [
                    Shadow(
                      color: _textColor.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              SizedBox(height: size.height * 0.01),
              Text(
                'Sign in to continue',
                style: TextStyle(
                  fontSize: isSmallScreen ? 16 : 18,
                  fontWeight: FontWeight.w400,
                  color: _greyColor,
                  fontFamily: 'Poppins',
                ),
              ),
              if (_errorMessage != null) ...[
                SizedBox(height: size.height * 0.02),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              if (_isParentLogin) ...[
                SizedBox(height: size.height * 0.01),
                _buildInputLabel('Email'),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _emailController,
                  hintText: 'Enter your email',
                  icon: Icons.email_outlined,
                  size: size,
                ),
                SizedBox(height: size.height * 0.02),
                _buildInputLabel('Password'),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _passwordController,
                  hintText: 'Enter your password',
                  icon: Icons.lock_outline,
                  isPassword: true,
                  size: size,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.only(top: isSmallScreen ? 1 : 16),
                    child: TextButton(
                      onPressed: () {
                        // TODO: Implement forgot password
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: _textColor,
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                      ),
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: isSmallScreen ? 14 : 16,
                          fontFamily: 'Poppins',
                          decoration: TextDecoration.underline,
                          decorationColor: _textColor.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: size.height * 0.01),
                Container(
                  width: double.infinity,
                  height: isSmallScreen ? 55 : 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        _textColor,
                        _textColor.withOpacity(0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: _textColor.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _loginWithEmail,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      'Sign In',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: size.height * 0.03),
                Center(
                  child: Text(
                    'Or continue with',
                    style: TextStyle(
                      color: _greyColor,
                      fontWeight: FontWeight.w500,
                      fontSize: isSmallScreen ? 14 : 16,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
                SizedBox(height: size.height * 0.03),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _SocialLoginButton(
                      onPressed: _signInWithGoogle,
                      iconWidget: Image.asset('assets/download.png'),
                      size: isSmallScreen ? 60 : 65,
                    ),
                  ],
                ),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Don\'t have an account? ',
                        style: TextStyle(
                          color: _greyColor,
                          fontSize: isSmallScreen ? 14 : 16,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SignupScreen(),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: _textColor,
                          padding: const EdgeInsets.symmetric(horizontal: 0),
                        ),
                        child: Text(
                          'Sign Up',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: isSmallScreen ? 14 : 16,
                            fontFamily: 'Poppins',
                            decoration: TextDecoration.underline,
                            decorationColor: _textColor.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                SizedBox(height: size.height * 0.05),
                Center(
                  child: Container(
                    width: double.infinity,
                    height: isSmallScreen ? 55 : 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          _textColor,
                          _textColor.withOpacity(0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: _textColor.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _childAnonymousLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        'Generate QR Code for Parent',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 16 : 18,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _onQRCodeScanned(String qrCodeId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _errorMessage = 'Please log in as a parent first.';
          _isScanning = false;
        });
        return;
      }
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('qrCodeId', isEqualTo: qrCodeId)
          .get();
      if (querySnapshot.docs.isEmpty) {
        setState(() {
          _errorMessage = 'Invalid QR code.';
          _isScanning = false;
        });
        return;
      }
      final childId = querySnapshot.docs.first.id;
      await FirebaseFirestore.instance.collection('links').doc(qrCodeId).set({
        'parentId': user.uid,
        'childId': childId,
        'linkedAt': Timestamp.now(),
      });
      setState(() {
        _isScanning = false;
      });
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (context) => ParentHomeScreen(qrCodeId: qrCodeId)),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to link devices: ${e.toString()}';
        _isScanning = false;
      });
    }
  }

  Widget _buildToggleButton(bool isParent, Size size) {
    final bool isSelected = isParent ? _isParentLogin : !_isParentLogin;
    final bool isSmallScreen = size.width < 400;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _isParentLogin = isParent;
          if (!_isParentLogin) _listenForConnection();
        }),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 18 : 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      _textColor,
                      _textColor.withOpacity(0.8),
                    ],
                  )
                : null,
            color: isSelected ? null : Colors.transparent,
            border: Border.all(
              color: isSelected
                  ? _textColor.withOpacity(0.5)
                  : _greyColor.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _textColor.withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Text(
            isParent ? 'Parent Login' : 'Child Login',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : _greyColor,
              fontWeight: FontWeight.w600,
              fontSize: isSmallScreen ? 14 : 15,
              fontFamily: 'Poppins',
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: _textColor,
        fontFamily: 'Poppins',
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildTextField({
    required Size size,
    TextEditingController? controller,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
  }) {
    final bool isSmallScreen = size.width < 400;

    return Container(
      decoration: BoxDecoration(
        color: _inputFieldColor,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(
          color: Colors.white,
          fontSize: isSmallScreen ? 14 : 16,
        ),
        obscureText: isPassword,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.grey[600],
            fontSize: isSmallScreen ? 14 : 16,
          ),
          prefixIcon: Icon(
            icon,
            color: Colors.grey[600],
            size: isSmallScreen ? 20 : 22,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 16 : 20,
            vertical: isSmallScreen ? 14 : 16,
          ),
        ),
      ),
    );
  }
}

class _SocialLoginButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget iconWidget;
  final double size;

  const _SocialLoginButton({
    required this.onPressed,
    required this.iconWidget,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1A1A),
                const Color(0xFF111111),
              ],
            ),
            border: Border.all(
              color: const Color(0xFF2196F3).withOpacity(0.3),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: const Color(0xFF2196F3).withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(child: iconWidget),
        ),
      ),
    );
  }
}
