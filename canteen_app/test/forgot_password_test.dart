import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:canteen_app/providers/auth_provider.dart';
import 'package:canteen_app/screens/auth/forgot_password_screen.dart';
import 'package:canteen_app/screens/auth/reset_password_screen.dart';
import 'package:canteen_app/services/local_notifier.dart';

class _FakeAuthProvider extends AuthProvider {
  bool sendCalled = false;
  bool resetCalled = false;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<bool> sendPasswordReset(String email) async {
    sendCalled = true;
    lastEmail = email;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> resetPassword(String password) async {
    resetCalled = true;
    lastPassword = password;
    notifyListeners();
    return true;
  }

  @override
  Future<void> dismissPasswordReset() async {
    notifyListeners();
  }
}

Widget _wrap(Widget child, AuthProvider auth) {
  return ChangeNotifierProvider<AuthProvider>(
    create: (_) => auth,
    child: MaterialApp(
      scaffoldMessengerKey: LocalNotifier.scaffoldMessengerKey,
      home: child,
    ),
  );
}

void main() {
  test('expired email link stream error shows a friendly message', () {
    final auth = AuthProvider();

    auth.handleAuthStreamError(
      AuthException('Email link is invalid or has expired'),
    );
    expect(auth.error, contains('expired or is no longer valid'));

    auth.handleAuthStreamError(AuthException('some unrelated failure'));
    expect(auth.error, contains('expired or is no longer valid'));
  });

  testWidgets('forgot password screen sends reset link and shows confirmation',
      (tester) async {
    final auth = _FakeAuthProvider();
    await tester.pumpWidget(_wrap(const ForgotPasswordScreen(), auth));
    await tester.pumpAndSettle();

    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Send Reset Link'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'a@b.com');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();

    expect(auth.sendCalled, isTrue);
    expect(auth.lastEmail, 'a@b.com');
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('a@b.com'), findsOneWidget);
  });

  testWidgets('forgot password screen validates empty email', (tester) async {
    final auth = _FakeAuthProvider();
    await tester.pumpWidget(_wrap(const ForgotPasswordScreen(), auth));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();

    expect(auth.sendCalled, isFalse);
    expect(find.text('Enter your email'), findsOneWidget);
  });

  testWidgets('reset password screen requires valid matching passwords',
      (tester) async {
    final auth = _FakeAuthProvider();
    await tester.pumpWidget(_wrap(const ResetPasswordScreen(), auth));
    await tester.pumpAndSettle();

    expect(find.text('Choose a new password'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'short');
    await tester.enterText(find.byType(TextFormField).at(1), 'different');
    await tester.tap(find.text('Update Password'));
    await tester.pumpAndSettle();

    expect(auth.resetCalled, isFalse);
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('reset password screen updates password and shows snackbar',
      (tester) async {
    final auth = _FakeAuthProvider();
    await tester.pumpWidget(_wrap(const ResetPasswordScreen(), auth));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'newsecret');
    await tester.enterText(find.byType(TextFormField).at(1), 'newsecret');
    await tester.tap(find.text('Update Password'));
    await tester.pumpAndSettle();

    expect(auth.resetCalled, isTrue);
    expect(auth.lastPassword, 'newsecret');
    expect(
      find.textContaining('Password updated'),
      findsOneWidget,
    );
  });
}
