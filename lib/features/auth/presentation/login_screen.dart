import 'dart:io';
import 'package:flutter/material.dart';
import 'package:driver_app/features/auth/services/auth_service.dart';
import 'package:driver_app/features/home/presentation/home_screen.dart';
import 'package:url_launcher/url_launcher.dart';

/// Driver login / sign-up screen (Reverted to Email/Password).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService.instance;
  final _formKey = GlobalKey<FormState>();

  /// Admin Portal URL (opened in browser)
  String get _adminPortalUrl {
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8081';
    } catch (_) {}
    return 'http://localhost:8081';
  }

  // ── Controllers ─────────────────────────────────────────────────────────────
  final _emailCtrl = TextEditingController();   // PRIMARY identifier (Reverted)
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();    // Sign-up only
  final _phoneCtrl = TextEditingController();   // Sign-up (optional/profile)
  final _vehicleCtrl = TextEditingController(); // Sign-up, required for drivers
  final _otpCtrl = TextEditingController();    // Email OTP

  bool _isLogin = true;
  bool _isVerifyingEmail = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _successMessage;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _vehicleCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  // ── Toggle Login ↔ Sign Up ───────────────────────────────────────────────────
  void _toggleMode() {
    _animController.reverse().then((_) {
      setState(() {
        _isLogin = !_isLogin;
        _isVerifyingEmail = false;
        _errorMessage = null;
        _successMessage = null;
        _formKey.currentState?.reset();
      });
      _animController.forward();
    });
  }

  // ── Navigate to HomeScreen ───────────────────────────────────────────────────
  void _navigateToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  // ── Verify OTP ──────────────────────────────────────────────────────────────
  Future<void> _verifyEmail() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length < 6) {
      setState(() => _errorMessage = 'Please enter a 6-digit code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _authService.verifyOTP(
        email: _emailCtrl.text.trim(),
        token: otp,
      );

      if (!mounted) return;

      if (result.success) {
        _navigateToHome();
      } else {
        setState(() => _errorMessage = result.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Submit ───────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_isVerifyingEmail) {
      await _verifyEmail();
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    try {
      if (_isLogin) {
        // ── SIGN IN: Email + Password ──────────────────────────────────────────
        final result = await _authService.signIn(
          email: email,
          password: password,
        );

        if (!mounted) return;

        if (result.success) {
          _navigateToHome();
        } else {
          setState(() => _errorMessage = result.error);
        }
      } else {
        // ── SIGN UP: Email + Password ──────────────────────────────────────────
        final result = await _authService.signUp(
          email: email,
          password: password,
          fullName: _nameCtrl.text.trim(),
          phoneNumber: _phoneCtrl.text.trim(),
          vehicleNumber: _vehicleCtrl.text.trim(),
        );

        if (!mounted) return;

        if (result.success) {
          setState(() {
            _isVerifyingEmail = true;
            _successMessage = 'Success! A 6-digit code has been sent to your email. Please enter it below.';
          });
        } else {
          setState(() => _errorMessage = result.error);
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Logo / Header ───────────────────────────────────────────────
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.local_shipping,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    _isVerifyingEmail
                        ? 'Verify Email'
                        : (_isLogin ? 'Welcome Back' : 'Create Account'),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    _isVerifyingEmail
                        ? 'Enter the code sent to your email'
                        : (_isLogin
                            ? 'Sign in with your email address'
                            : 'Register as a fleet driver'),
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Form ─────────────────────────────────────────────────────────
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      if (_errorMessage != null) ...[
                        _Banner(message: _errorMessage!, isError: true),
                        const SizedBox(height: 14),
                      ],
                      if (_successMessage != null) ...[
                        _Banner(message: _successMessage!, isError: false),
                        const SizedBox(height: 14),
                      ],

                      if (_isVerifyingEmail) ...[
                        _buildField(
                          controller: _otpCtrl,
                          label: 'Verification Code',
                          icon: Icons.pin_outlined,
                          keyboardType: TextInputType.number,
                          hint: 'Enter 6-digit code',
                          validator: (v) => v!.length < 6 ? 'Required' : null,
                        ),
                      ] else ...[
                        if (!_isLogin) ...[
                          _buildField(
                            controller: _nameCtrl,
                            label: 'Full Name *',
                            icon: Icons.person_outline,
                            validator: (v) =>
                                v!.trim().isEmpty ? 'Name is required' : null,
                          ),
                          const SizedBox(height: 14),
                        ],

                        // ── Email (primary field) ──────────────────────────────────
                        _buildField(
                          controller: _emailCtrl,
                          label: 'Email Address *',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          hint: 'e.g. driver@example.com',
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Email is required';
                            }
                            if (!v.contains('@') || !v.contains('.')) {
                              return 'Enter a valid email address';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // ── Password ───────────────────────────────────────────────
                        _buildField(
                          controller: _passwordCtrl,
                          label: 'Password *',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePassword,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 20,
                              color: Colors.grey[400],
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                          validator: (v) {
                            if (v!.isEmpty) return 'Password is required';
                            if (v.length < 6) return 'Minimum 6 characters';
                            return null;
                          },
                        ),

                        if (!_isLogin) ...[
                          const SizedBox(height: 14),
                          _buildField(
                            controller: _phoneCtrl,
                            label: 'Phone Number (optional)',
                            icon: Icons.phone_android_outlined,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 14),
                          _buildField(
                            controller: _vehicleCtrl,
                            label: 'Vehicle Number *',
                            icon: Icons.local_shipping_outlined,
                            validator: (v) => v!.trim().isEmpty
                                ? 'Vehicle number is required'
                                : null,
                          ),
                        ],
                      ],

                      const SizedBox(height: 24),

                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE53935),
                            disabledBackgroundColor: Colors.grey[300],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isVerifyingEmail
                                      ? 'VERIFY CODE'
                                      : (_isLogin ? 'SIGN IN' : 'SIGN UP'),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isLogin
                          ? "Don't have an account? "
                          : 'Already have an account? ',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    GestureDetector(
                      onTap: () {
                        if (_isLoading) return;
                        if (_isVerifyingEmail) {
                          setState(() {
                            _isVerifyingEmail = false;
                            _successMessage = null;
                            _errorMessage = null;
                          });
                        } else {
                          _toggleMode();
                        }
                      },
                      child: Text(
                        _isVerifyingEmail
                            ? 'Back to Sign Up'
                            : (_isLogin ? 'Sign Up' : 'Sign In'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE53935),
                        ),
                      ),
                    ),
                  ],
                ),

                if (_isLogin) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final uri = Uri.parse(_adminPortalUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                    child: Center(
                      child: Text(
                        'Admin Portal →',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[500],
                          decoration: TextDecoration.underline,
                        ),
                      ),
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    String? hint,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: Colors.grey[500]),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFFE53935), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Colors.red, width: 1.5),
        ),
        labelStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String message;
  final bool isError;

  const _Banner({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError
            ? const Color(0xFFFFEBEE)
            : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isError
              ? const Color(0xFFEF9A9A)
              : const Color(0xFFA5D6A7),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError
                ? const Color(0xFFC62828)
                : const Color(0xFF2E7D32),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: isError
                    ? const Color(0xFFC62828)
                    : const Color(0xFF2E7D32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

