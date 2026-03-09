import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:driver_fleet_admin/features/auth/services/auth_service.dart';
import 'package:driver_fleet_admin/features/admin/presentation/admin_dashboard_screen.dart';

/// Separate entry point for the Admin Web Portal.
/// Run with: flutter run -d chrome --target lib/main_admin.dart --web-port 8081
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://driver-fleet.jiobase.com',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZvcGF0dWV1dmt6eGV1bmp3aHZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA0NjcwNTcsImV4cCI6MjA4NjA0MzA1N30.vdS5HpNudKU4SRJMtusIt1xlIjic8q0MzgpYZX6MOLc',
  );

  runApp(const AdminPortalApp());
}

class AdminPortalApp extends StatelessWidget {
  const AdminPortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fleet Admin Portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: GoogleFonts.poppins().fontFamily,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A1A2E),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
      ),
      home: const _AdminAuthGate(),
    );
  }
}

/// Auth gate — shows AdminLoginPage if not signed in,
/// checks role and shows AdminDashboard or AccessDenied.
class _AdminAuthGate extends StatefulWidget {
  const _AdminAuthGate();

  @override
  State<_AdminAuthGate> createState() => _AdminAuthGateState();
}

class _AdminAuthGateState extends State<_AdminAuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const _LoadingScaffold();

        final session = snapshot.data!.session;
        if (session == null) return const AdminLoginPage();

        // Session exists — check role with retry
        return _RoleChecker(key: ValueKey(session.user.id));
      },
    );
  }
}

/// Fetches the user role with retries to handle auth token propagation delay.
class _RoleChecker extends StatefulWidget {
  const _RoleChecker({super.key});

  @override
  State<_RoleChecker> createState() => _RoleCheckerState();
}

class _RoleCheckerState extends State<_RoleChecker> {
  String? _role;
  String? _error;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    // Retry up to 4 times with increasing delay
    // (handles JWT propagation delay after sign-in/sign-up)
    for (int attempt = 0; attempt < 4; attempt++) {
      await Future.delayed(Duration(milliseconds: attempt == 0 ? 300 : 800));
      try {
        final uid = Supabase.instance.client.auth.currentUser?.id;
        if (uid == null) break;

        final response = await Supabase.instance.client
            .from('profiles')
            .select('role')
            .eq('id', uid)
            .maybeSingle();

        final role = response?['role']?.toString();
        if (role != null) {
          if (mounted) setState(() { _role = role; _checking = false; });
          return;
        }
      } catch (e) {
        debugPrint('Role check attempt $attempt failed: $e');
      }
    }
    // All retries failed
    if (mounted) setState(() { _role = 'driver'; _checking = false; _error = 'Could not verify role'; });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const _LoadingScaffold();
    if (_role == 'admin') return const AdminDashboardScreen();
    return _NotAdminScreen(errorHint: _error);
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Admin Login / Sign-Up Page (Web-optimised)
// ─────────────────────────────────────────────────────────────────────────────

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  bool _loading = false;
  bool _obscure = true;
  bool _isLogin = true; // toggle between Sign-In and Sign-Up
  bool _isVerifying = false;
  String? _error;
  String? _successMsg;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _otpCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isLogin = !_isLogin;
      _isVerifying = false;
      _error = null;
      _successMsg = null;
    });
    _animCtrl.forward(from: 0);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; _successMsg = null; });

    if (_isVerifying) {
      await _handleVerifyOTP();
    } else if (_isLogin) {
      await _handleLogin();
    } else {
      await _handleSignUp();
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _handleLogin() async {
    final result = await AuthService.instance.signIn(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() => _error = result.error ?? 'Login failed');
      return;
    }

    // Verify admin role
    final role = await AuthService.instance.getUserRole();
    if (!mounted) return;
    if (role != 'admin') {
      await AuthService.instance.signOut();
      setState(() => _error = 'Access denied. This portal is for admins only.');
    }
    // If admin, _AdminAuthGate StreamBuilder handles navigation
  }

  Future<void> _handleVerifyOTP() async {
    final result = await AuthService.instance.verifyOTP(
      email: _emailCtrl.text.trim(),
      token: _otpCtrl.text.trim(),
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() => _error = result.error ?? 'Verification failed');
      return;
    }

    // Role is set to admin during handleSignUp, verifyOTP completes the auth flow
  }

  Future<void> _handleSignUp() async {
    final result = await AuthService.instance.signUp(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      fullName: _nameCtrl.text.trim(),
      role: 'admin', // Explicitly pass admin role
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() => _error = result.error ?? 'Sign up failed');
      return;
    }

    // Show success or auto-navigate if email confirmation is disabled
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      // Already signed in — _AdminAuthGate will navigate automatically
    } else {
      if (mounted) {
        setState(() {
          _isVerifying = true;
          _successMsg = '✅ Account created! Please enter the 6-digit code sent to your email.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isMobile = w < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 24 : 0,
            vertical: 40,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4FC3F7).withValues(alpha: 0.25),
                            blurRadius: 40,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_rounded,
                        color: Color(0xFF4FC3F7),
                        size: 56,
                      ),
                    ),
                    const SizedBox(height: 28),

                    const Text(
                      'Fleet Admin Portal',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isVerifying
                          ? 'Enter the 6-digit code sent to your email'
                          : (_isLogin
                              ? 'Sign in to manage your fleet'
                              : 'Create your admin account'),
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    ),
                    const SizedBox(height: 32),

                    // Error / Success banner
                    if (_error != null) _banner(_error!, isError: true),
                    if (_successMsg != null) _banner(_successMsg!, isError: false),

                    // ── Sign Up only: Name field ──
                    // ── Sign Up/Verify UI flow ──
                    if (_isVerifying) ...[
                      _field(
                        controller: _otpCtrl,
                        label: 'Verification Code',
                        icon: Icons.pin_outlined,
                        type: TextInputType.number,
                        validator: (v) => v!.length < 6 ? 'Enter 6-digit code' : null,
                      ),
                    ] else ...[
                      if (!_isLogin) ...[
                        _field(
                          controller: _nameCtrl,
                          label: 'Full Name',
                          icon: Icons.person_outline,
                          validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Email
                      _field(
                        controller: _emailCtrl,
                        label: 'Admin Email',
                        icon: Icons.email_outlined,
                        type: TextInputType.emailAddress,
                        validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),

                      // Password
                      _field(
                        controller: _passwordCtrl,
                        label: 'Password',
                        icon: Icons.lock_outline,
                        obscure: _obscure,
                        validator: (v) {
                          if (v!.isEmpty) return 'Required';
                          if (!_isLogin && v.length < 6) return 'Min 6 characters';
                          return null;
                        },
                        suffix: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                            size: 20,
                            color: Colors.grey,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4FC3F7),
                          foregroundColor: const Color(0xFF0F0F1A),
                          disabledBackgroundColor: const Color(0xFF4FC3F7).withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Color(0xFF0F0F1A),
                                ),
                              )
                             : Text(
                                _isVerifying
                                    ? 'VERIFY CODE'
                                    : (_isLogin ? 'SIGN IN AS ADMIN' : 'CREATE ADMIN ACCOUNT'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  letterSpacing: 1,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Toggle Sign-In / Sign-Up
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isLogin
                              ? "Don't have an admin account? "
                              : 'Already have an account? ',
                          style: TextStyle(color: Colors.grey[400], fontSize: 13),
                        ),
                         GestureDetector(
                           onTap: () {
                             if (_loading) return;
                             if (_isVerifying) {
                               setState(() {
                                 _isVerifying = false;
                                 _error = null;
                                 _successMsg = null;
                               });
                             } else {
                               _toggle();
                             }
                           },
                           child: Text(
                             _isVerifying
                                 ? 'Back to Sign Up'
                                 : (_isLogin ? 'Sign Up' : 'Sign In'),
                             style: const TextStyle(
                               color: Color(0xFF4FC3F7),
                               fontSize: 13,
                               fontWeight: FontWeight.bold,
                             ),
                           ),
                         ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _banner(String message, {required bool isError}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError
            ? Colors.red.withValues(alpha: 0.15)
            : Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isError
              ? Colors.red.withValues(alpha: 0.4)
              : Colors.green.withValues(alpha: 0.4),
        ),
      ),
      child: Row(children: [
        Icon(
          isError ? Icons.error_outline : Icons.check_circle_outline,
          color: isError ? Colors.red : Colors.green,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: isError ? Colors.red[300] : Colors.green[300],
              fontSize: 13,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? type,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: type,
      obscureText: obscure,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.grey[500], size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF1A1A2E),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2D2D45)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2D2D45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4FC3F7), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F0F1A),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF4FC3F7)),
      ),
    );
  }
}

class _NotAdminScreen extends StatelessWidget {
  final String? errorHint;
  const _NotAdminScreen({this.errorHint});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_outline, color: Colors.red, size: 56),
          ),
          const SizedBox(height: 20),
          const Text(
            'Access Denied',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'This portal is for administrators only.',
            style: TextStyle(color: Colors.grey[400]),
          ),
          if (errorHint != null) ...[
            const SizedBox(height: 6),
            Text(errorHint!, style: TextStyle(color: Colors.orange[300], fontSize: 12)),
          ],
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () => AuthService.instance.signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4FC3F7),
              foregroundColor: const Color(0xFF0F0F1A),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      ),
    );
  }
}
