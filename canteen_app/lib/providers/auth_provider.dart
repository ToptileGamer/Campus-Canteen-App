import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  AppUser? _user;
  bool _isLoading = false;
  String? _error;
  bool _awaitingEmailVerification = false;
  bool _passwordResetRequired = false;
  StreamSubscription<AuthState>? _authSubscription;

  AuthProvider() {
    if (AppConfig.isSupabaseConfigured) {
      // The email confirmation link comes back as a deep link, which supabase
      // turns into a session. Watch for it so the app can move on by itself.
      _authSubscription = AppConfig.supabase.auth.onAuthStateChange.listen(
        (state) {
          if (state.event == AuthChangeEvent.passwordRecovery) {
            _passwordResetRequired = true;
            _awaitingEmailVerification = false;
            _user = null;
            _error = null;
            notifyListeners();
            return;
          }
          if (state.event != AuthChangeEvent.signedIn) return;
          if (!_awaitingEmailVerification) return;
          unawaited(_completeEmailVerification());
        },
        onError: handleAuthStreamError,
      );
    }
  }

  /// Handles failures forwarded from the auth stream, e.g. the deep-link code
  /// exchange rejecting an expired or already-used email link.
  @visibleForTesting
  void handleAuthStreamError(Object error) {
    if (error is AuthException && error.message.contains('Email link')) {
      _error = 'This link has expired or is no longer valid. '
          'Please request a new one.';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    _authSubscription = null;
    super.dispose();
  }

  AppUser? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;
  /// Only canteen staff reach the management dashboard; students and
  /// teachers both use the ordering app.
  bool get isCanteenStaff => _user?.role == UserRole.canteenStaff;
  bool get canManageMenu => _user?.canManageMenu ?? false;
  String? get error => _error;

  /// True after a sign-up that requires the user to click the emailed
  /// confirmation link before a session exists.
  bool get awaitingEmailVerification => _awaitingEmailVerification;

  /// True when the recovery deep link has established a session and the user
  /// still has to pick a new password ([ResetPasswordScreen] is shown).
  bool get passwordResetRequired => _passwordResetRequired;

  /// Asks Supabase to email a reset link. Returns true when the request went
  /// through; Supabase answers the same way for unknown addresses, so the
  /// caller should show the "check your email" view either way.
  Future<bool> sendPasswordReset(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _authService.sendPasswordReset(email);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Sets the new password on the recovery session, then loads the profile so
  /// AuthGate drops the reset screen and lands on the normal home screen.
  Future<bool> resetPassword(String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _authService.updatePassword(password);
      _user = await _authService.loadProfileFromSession();
      _passwordResetRequired = false;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Leaves the reset flow (back button) by ending the recovery session, so
  /// the login screen starts from a clean state.
  Future<void> dismissPasswordReset() async {
    _passwordResetRequired = false;
    _error = null;
    await logout();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await _authService.login(email, password);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Restores a previously logged-in user from the stored session.
  Future<AppUser?> restoreSession() async {
    try {
      _user = await _authService.restoreSession();
      if (_user != null) notifyListeners();
    } catch (_) {
      _user = null;
    }
    return _user;
  }

  Future<SignupResult> signup({
    required String name,
    required String email,
    required String rollNumber,
    required UserRole role,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    _awaitingEmailVerification = false;
    notifyListeners();

    try {
      final result = await _authService.signup(
        name: name,
        email: email,
        rollNumber: rollNumber,
        role: role,
        password: password,
      );
      _user = result == SignupResult.signedIn ? _authService.currentUser : null;
      _awaitingEmailVerification = result == SignupResult.needsEmailVerification;
      _isLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Pulls the profile row for the session created by the confirmation deep
  /// link and flips [isLoggedIn] so the UI can navigate.
  Future<void> _completeEmailVerification() async {
    if (!AppConfig.isSupabaseConfigured) return;
    try {
      _user = await _authService.loadProfileFromSession();
      _awaitingEmailVerification = false;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _user = null;
    _awaitingEmailVerification = false;
    _passwordResetRequired = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
