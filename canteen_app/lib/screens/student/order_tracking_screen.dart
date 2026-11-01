import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart';
import '../../providers/order_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Ensure the order is loaded even when opened from a notification.
    context.read<OrderProvider>().loadOrderById(widget.orderId);
    // Keep polling as a fallback so updates arrive even without realtime.
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final a = context.read<AuthProvider>();
      if (a.isLoggedIn) {
        context.read<OrderProvider>().loadUserOrders(a.user!.id);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Order? _findOrder(BuildContext context) {
    final orders = context.watch<OrderProvider>().userOrders;
    return orders.where((o) => o.id == widget.orderId).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final order = _findOrder(context);

    if (order == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Order Tracking'),
          backgroundColor: Colors.white,
          elevation: 0.5,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16),
              Text('Loading order details...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Order Tracking', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final auth = context.read<AuthProvider>();
              context.read<OrderProvider>().loadUserOrders(auth.user!.id);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Order header
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Status icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _statusColor(order.status).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_statusIcon(order.status),
                          size: 40, color: _statusColor(order.status)),
                    ),
                    const SizedBox(height: 16),
                    Text(order.status.displayName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _statusColor(order.status),
                        )),
                    const SizedBox(height: 8),
                    Text('Order #${order.displayNumber}',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                    if (order.transactionId.startsWith('WALLET-')) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.account_balance_wallet,
                                size: 16, color: AppColors.primary),
                            SizedBox(width: 6),
                            Text('Paid from Wallet',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Status timeline
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Order Progress',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 16),
                    _StatusStep(
                      icon: Icons.payment,
                      label: 'Payment Confirmed',
                      isComplete: order.status.index >= OrderStatus.paidPendingApproval.index,
                      isCurrent: order.status == OrderStatus.paidPendingApproval,
                    ),
                    _StatusStep(
                      icon: Icons.restaurant,
                      label: 'Preparing',
                      isComplete: order.status.index >= OrderStatus.preparing.index,
                      isCurrent: order.status == OrderStatus.preparing,
                    ),
                    _StatusStep(
                      icon: Icons.check_circle_outline,
                      label: 'Ready for Pickup',
                      isComplete: order.status.index >= OrderStatus.readyForPickup.index,
                      isCurrent: order.status == OrderStatus.readyForPickup,
                    ),
                    _StatusStep(
                      icon: Icons.done_all,
                      label: 'Completed',
                      isComplete: order.status.index >= OrderStatus.completed.index,
                      isCurrent: order.status == OrderStatus.completed,
                      isLast: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Pickup info
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.access_time, color: AppColors.warning, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Pickup Time',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          Text(order.pickupSlotLabel,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Order items
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Divider(),
                    ...order.items.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Text('${item.quantity}x'),
                              const SizedBox(width: 8),
                              Expanded(child: Text(item.menuItemName)),
                              Text('₹${item.totalPrice.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('₹${order.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.paidPendingApproval:
        return AppColors.pending;
      case OrderStatus.preparing:
        return AppColors.preparing;
      case OrderStatus.readyForPickup:
        return AppColors.ready;
      case OrderStatus.completed:
        return AppColors.completed;
      case OrderStatus.cancelled:
        return AppColors.error;
    }
  }

  IconData _statusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.paidPendingApproval:
        return Icons.payment;
      case OrderStatus.preparing:
        return Icons.restaurant;
      case OrderStatus.readyForPickup:
        return Icons.check_circle_outline;
      case OrderStatus.completed:
        return Icons.done_all;
      case OrderStatus.cancelled:
        return Icons.cancel;
    }
  }
}

class _StatusStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isComplete;
  final bool isCurrent;
  final bool isLast;

  const _StatusStep({
    required this.icon,
    required this.label,
    this.isComplete = false,
    this.isCurrent = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isComplete ? AppColors.success : (isCurrent ? AppColors.warning : Colors.grey.shade300);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isComplete || isCurrent ? color : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isComplete ? Icons.check : icon,
                    size: 16,
                    color: (isComplete || isCurrent) ? Colors.white : Colors.grey,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isComplete ? AppColors.success : Colors.grey.shade200,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isComplete || isCurrent ? AppColors.textPrimary : Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
