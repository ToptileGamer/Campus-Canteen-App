import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/menu_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../utils/constants.dart';
import 'order_management_screen.dart';
import 'menu_management_screen.dart';
import 'analytics_screen.dart';
import 'earnings_screen.dart';
import '../shared/notifications_screen.dart';
import '../auth/login_screen.dart';

class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (!auth.isLoggedIn) return;

      context.read<OrderProvider>().loadActiveOrders();
      context.read<OrderProvider>().loadAnalytics();
      context.read<MenuProvider>().loadMenu();
      context.read<NotificationProvider>().load(auth.user!.id);

      // Real-time sync: orders, menu and notifications without reloads.
      context.read<OrderProvider>().subscribe(auth.user!.id, isStaff: true);
      context.read<MenuProvider>().subscribeRealtime();
      context.read<NotificationProvider>().subscribe(auth.user!.id);

      // 5s fallback poll so staff (college or canteen) always see new orders
      // and status changes within ~5 seconds, even if realtime drops.
      context.read<OrderProvider>().startPolling(auth.user!.id, isStaff: true);
    });
  }

  @override
  void dispose() {
    context.read<OrderProvider>().unsubscribe();
    context.read<OrderProvider>().stopPolling();
    context.read<MenuProvider>().unsubscribeRealtime();
    context.read<NotificationProvider>().unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final orderProvider = context.watch<OrderProvider>();
    final notifProvider = context.watch<NotificationProvider>();
    final canManageMenu = auth.user?.canManageMenu ?? false;

    final screens = [
      const OrderManagementScreen(),
      if (canManageMenu) const MenuManagementScreen(),
      const AnalyticsScreen(),
      const EarningsScreen(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Staff Dashboard',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('${orderProvider.todayOrderCount} orders today',
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
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: () {
              orderProvider.loadActiveOrders();
              orderProvider.loadAnalytics();
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
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          // Refresh data when switching tabs
          final screen = screens[index];
          if (screen is OrderManagementScreen) orderProvider.loadActiveOrders();
          if (screen is MenuManagementScreen) context.read<MenuProvider>().loadMenu();
          if (screen is AnalyticsScreen) orderProvider.loadAnalytics();
          if (screen is EarningsScreen) context.read<WalletProvider>().loadCanteen();
        },
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primary.withValues(alpha: 0.1),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: orderProvider.pendingOrders.isNotEmpty,
              label: Text('${orderProvider.pendingOrders.length}'),
              child: const Icon(Icons.dashboard),
            ),
            label: 'Orders',
          ),
          if (canManageMenu)
            const NavigationDestination(
              icon: Icon(Icons.restaurant_menu),
              label: 'Menu',
            ),
          const NavigationDestination(
            icon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Earnings',
          ),
        ],
      ),
    );
  }
}
