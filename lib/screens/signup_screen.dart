import 'package:flutter/material.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final Color _primaryColor = const Color(0xFF2196F3);
  final Color _backgroundColor = const Color(0xFF000000);
  final Color _cardColor = const Color(0xFF111111);
  final Color _inputFieldColor = const Color(0xFF1A1A1A);
  final Color _textColor = const Color(0xFF2196F3);
  final Color _greyColor = const Color(0xFF808080);

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleSignup() {
    // TODO: Implement signup logic
    print('Signup pressed');
  }

  void _handleGoogleSignup() {
    // TODO: Implement Google signup logic
    print('Google signup pressed');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isSmallScreen = size.width < 400;

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
                child: Container(
                  width: isSmallScreen ? 120 : 140,
                  height: isSmallScreen ? 120 : 140,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _textColor.withOpacity(0.3),
                        _cardColor.withOpacity(0.9),
                        _backgroundColor,
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _textColor.withOpacity(0.5),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _textColor.withOpacity(0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.8),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: isSmallScreen ? 80 : 90,
                        height: isSmallScreen ? 80 : 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              _textColor.withOpacity(0.3),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      Icon(
                        Icons.person_add_outlined,
                        size: isSmallScreen ? 50 : 60,
                        color: _textColor,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: size.height * 0.04),
              Text(
                'Create Account',
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
                'Sign up to get started',
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
              SizedBox(height: size.height * 0.03),
              _buildInputLabel('Full Name'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _nameController,
                hintText: 'Enter your full name',
                icon: Icons.person_outline,
                size: size,
              ),
              SizedBox(height: size.height * 0.02),
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
              SizedBox(height: size.height * 0.02),
              _buildInputLabel('Confirm Password'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _confirmPasswordController,
                hintText: 'Confirm your password',
                icon: Icons.lock_outline,
                isPassword: true,
                size: size,
              ),
              SizedBox(height: size.height * 0.03),
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
                  onPressed: _handleSignup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    'Sign Up',
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
                    onPressed: _handleGoogleSignup,
                    iconWidget: Image.asset('assets/download.png'),
                    size: isSmallScreen ? 60 : 65,
                  ),
                ],
              ),
              SizedBox(height: size.height * 0.04),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(
                        color: _greyColor,
                        fontSize: isSmallScreen ? 14 : 16,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: _textColor,
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                      ),
                      child: Text(
                        'Sign In',
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
            ],
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
