import 'package:supabase_flutter/supabase_flutter.dart';

/// Singleton authentication service wrapping Supabase Auth.
/// Reverted to Email/Password authentication for all users.
class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  final _supabase = Supabase.instance.client;

  // ─────────────────────────────────────────
  //  Core auth getters
  // ─────────────────────────────────────────

  Stream<AuthState> get onAuthStateChange => _supabase.auth.onAuthStateChange;
  User? get currentUser => _supabase.auth.currentUser;
  String? get currentUserId => _supabase.auth.currentUser?.id;
  bool get isSignedIn => _supabase.auth.currentUser != null;

  Future<({bool success, String? error})> verifyOTP({
    required String email,
    required String token,
  }) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.signup,
      );

      if (response.session == null) {
        return (success: false, error: 'Invalid or expired OTP');
      }

      return (success: true, error: null);
    } on AuthException catch (e) {
      return (success: false, error: _mapError(e.message));
    } catch (e) {
      return (success: false, error: 'An unexpected error occurred');
    }
  }

  // ─────────────────────────────────────────
  //  Email + password sign-up/sign-in
  // ─────────────────────────────────────────

  /// Register a new user (Driver or Admin) with email + password.
  Future<({bool success, String? error})> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phoneNumber,
    String? vehicleNumber,
    String? redirectTo,
    String role = 'driver', // New role parameter
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName ?? '',
          'phone_number': phoneNumber ?? '',
          'vehicle_number': vehicleNumber ?? '',
          'role': role,
          'password': password, // PASS PASSWORD TO TRIGGER
        },
        emailRedirectTo: redirectTo,
      );

      if (response.user == null) {
        return (success: false, error: 'Failed to create account');
      }

      // REMOVED: Manual client-side upsert. 
      // The database trigger 'handle_new_user' now handles this automatically 
      // with system-level permissions, avoiding RLS check errors (403).

      return (success: true, error: null);
    } on AuthException catch (e) {
      return (success: false, error: _mapError(e.message));
    } catch (e) {
      return (success: false, error: 'An unexpected error occurred');
    }
  }

  /// Sign in with email + password.
  Future<({bool success, String? error})> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return (success: true, error: null);
    } on AuthException catch (e) {
      return (success: false, error: _mapError(e.message));
    } catch (e) {
      return (success: false, error: 'An unexpected error occurred');
    }
  }

  Future<({bool success, String? error})> signOut() async {
    try {
      await _supabase.auth.signOut();
      return (success: true, error: null);
    } on AuthException catch (e) {
      return (success: false, error: _mapError(e.message));
    } catch (e) {
      return (success: false, error: 'An unexpected error occurred');
    }
  }

  // ─────────────────────────────────────────
  //  Phone helpers (Legacy/Optional)
  // ─────────────────────────────────────────

  String _toE164(String phone) {
    phone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (phone.startsWith('+')) return phone;
    if (phone.startsWith('0')) phone = phone.substring(1);
    return '+91$phone';
  }

  // Maintaining these for backward compatibility if needed temporarily
  Future<({bool success, String? error})> signInWithPhone({
    required String phone,
    required String password,
  }) async {
    final e164 = _toE164(phone);
    try {
      await _supabase.auth.signInWithPassword(phone: e164, password: password);
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: e.toString());
    }
  }

  // ─────────────────────────────────────────
  //  Profile helpers
  // ─────────────────────────────────────────

  Future<String> getUserRole() async {
    final userId = currentUserId;
    if (userId == null) return 'driver';
    try {
      final response = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      return response?['role'] ?? 'driver';
    } catch (_) {
      return 'driver';
    }
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      return await _supabase
          .from('profiles')
          .select('*')
          .eq('id', userId)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCurrentUserProfile() => getUserProfile();

  Future<({bool success, String? error})> updateProfile({
    String? fullName,
    String? phoneNumber,
    String? vehicleNumber,
  }) async {
    final userId = currentUserId;
    if (userId == null) return (success: false, error: 'Not authenticated');
    try {
      final updates = <String, dynamic>{};
      if (fullName != null) updates['full_name'] = fullName;
      if (phoneNumber != null) updates['phone_number'] = phoneNumber;
      if (vehicleNumber != null) updates['vehicle_number'] = vehicleNumber;
      updates['updated_at'] = DateTime.now().toIso8601String();
      await _supabase.from('profiles').update(updates).eq('id', userId);
      return (success: true, error: null);
    } catch (_) {
      return (success: false, error: 'Failed to update profile');
    }
  }

  // ─────────────────────────────────────────
  //  Error mapping
  // ─────────────────────────────────────────

  String _mapError(String message) {
    if (message.contains('Invalid login credentials')) {
      return 'Incorrect email or password';
    }
    if (message.contains('Email not confirmed')) {
      return 'Please verify your email address to continue';
    }
    if (message.contains('User already registered') ||
        message.contains('already been registered')) {
      return 'An account with this email already exists';
    }
    if (message.contains('Password should be at least')) {
      return 'Password must be at least 6 characters';
    }
    if (message.contains('rate limit') ||
        message.contains('too many requests')) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    return message;
  }
}

