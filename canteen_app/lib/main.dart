import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/app_config.dart';
import 'providers/auth_provider.dart';
import 'providers/menu_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/order_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/wallet_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/staff/staff_dashboard_screen.dart';
import 'screens/student/student_home_screen.dart';
import 'services/local_notifier.dart';
import 'utils/constants.dart';

/// Lets [AuthGate] clear stale auth routes (signup / forgot-password) when
/// the password-recovery deep link takes over as the home screen.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var backendConfigured = false;
  try {
    await AppConfig.init();
    backendConfigured = true;
    await LocalNotifier.init();
  } catch (e) {
    debugPrint('Setup error: $e');
  }

  runApp(CanteenApp(backendConfigured: backendConfigured));
}

class CanteenApp extends StatelessWidget {
  final bool backendConfigured;
  const CanteenApp({super.key, this.backendConfigured = true});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => MenuProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => WalletProvider()),
      ],
      child: MaterialApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        navigatorKey: rootNavigatorKey,
        scaffoldMessengerKey: LocalNotifier.scaffoldMessengerKey,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: AppColors.primary,
          scaffoldBackgroundColor: AppColors.background,
          fontFamily: 'Roboto',
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 1,
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        home: backendConfigured
            ? const AuthGate()
            : const SetupGuideScreen(),
      ),
    );
  }
}

/// Decides the start destination from the auth state.
///
/// A session can appear without going through the login form — the email
/// confirmation link signs the user in through a deep link, including when the
/// link is what launched the app. Watching the provider covers both cases.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.passwordResetRequired) {
          // The recovery link can arrive while signup or forgot-password is
          // pushed on top; drop those so the reset screen (the new home) is
          // what the user actually sees.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
          });
          return const ResetPasswordScreen();
        }
        if (!auth.isLoggedIn) return const LoginScreen();
        return auth.isCanteenStaff
            ? const StaffDashboardScreen()
            : const StudentHomeScreen();
      },
    );
  }
}

class SetupGuideScreen extends StatelessWidget {
  const SetupGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text('🍽️', style: TextStyle(fontSize: 48)),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  AppStrings.appName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.settings, color: AppColors.error, size: 22),
                      SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Supabase backend is not configured',
                          style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'To connect the backend:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 12),
                const _SetupStep(
                  number: '1',
                  text: 'Create a project at supabase.com and copy the Project '
                      'URL and anon public key from Settings → API.',
                ),
                const _SetupStep(
                  number: '2',
                  text: 'Open supabase/schema.sql in this project, then run the '
                      'whole file in the Supabase SQL editor.',
                ),
                const _SetupStep(
                  number: '3',
                  text: 'Copy .env.example to .env and fill in SUPABASE_URL and '
                      'SUPABASE_ANON_KEY.',
                ),
                const _SetupStep(
                  number: '4',
                  text: 'In Authentication → URL Configuration → Redirect URLs, '
                      'add canteen://auth-callback so the email confirmation '
                      'link can open the app.',
                ),
                const _SetupStep(
                  number: '5',
                  text: 'Restart the app, then sign up Student or Teacher '
                      'accounts to test ordering. For the management '
                      'dashboard, add a profile in Supabase with '
                      'role = "canteen_staff".',
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  final String number;
  final String text;
  const _SetupStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.primary,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}