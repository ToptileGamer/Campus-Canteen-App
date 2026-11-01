import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/menu_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../utils/constants.dart';
import 'menu_browsing_screen.dart';
import 'cart_screen.dart';
import 'order_history_screen.dart';
import 'wallet_screen.dart';
import '../shared/notifications_screen.dart';
import '../auth/login_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    MenuBrowsingScreen(),
    CartScreen(),
    OrderHistoryScreen(),
    WalletScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (!auth.isLoggedIn) return;

      context.read<MenuProvider>().loadMenu();
      context.read<OrderProvider>().loadUserOrders(auth.user!.id);
      context.read<NotificationProvider>().load(auth.user!.id);
      context.read<WalletProvider>().load(auth.user!.id);

      // Real-time sync: orders, menu and notifications without reloads.
      context.read<OrderProvider>().subscribe(auth.user!.id, isStaff: false);
      context.read<MenuProvider>().subscribeRealtime();
      context.read<NotificationProvider>().subscribe(auth.user!.id);
      context.read<WalletProvider>().subscribe(auth.user!.id);

      // 5s fallback poll so order changes always reflect even if realtime drops.
      context.read<OrderProvider>().startPolling(auth.user!.id, isStaff: false);
    });
  }

  @override
  void dispose() {
    context.read<OrderProvider>().unsubscribe();
    context.read<OrderProvider>().stopPolling();
    context.read<MenuProvider>().unsubscribeRealtime();
    context.read<NotificationProvider>().unsubscribe();
    context.read<WalletProvider>().unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cart = context.watch<CartProvider>();
    final notifProvider = context.watch<NotificationProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hello, ${auth.user?.name ?? 'Student'}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(auth.user?.rollNumber ?? '',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: notifProvider.unreadCount > 0,
              label: Text('${notifProvider.unreadCount}'),
              child: const Icon(Icons.notifications_outlined,
                  color: AppColors.textSecondary),
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.textSecondary),
            onPressed: () async {
              await auth.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 2) {
            final auth = context.read<AuthProvider>();
            if (auth.isLoggedIn) {
              context.read<OrderProvider>().loadUserOrders(auth.user!.id);
            }
          }
          if (index == 3) {
            final auth = context.read<AuthProvider>();
            if (auth.isLoggedIn) {
              context.read<WalletProvider>().load(auth.user!.id, silent: true);
            }
          }
        },
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Menu'),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: cart.itemCount > 0,
              label: Text('${cart.itemCount}'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
            label: 'Cart',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Orders'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined), label: 'Wallet'),
        ],
      ),
    );
  }
}