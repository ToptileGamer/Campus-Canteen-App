import '../config/app_config.dart';
import '../models/order.dart';
import '../models/time_slot.dart';

class OrderService {
  static const int maxOrdersPerSlot = AppConfig.maxOrdersPerSlot;
  static const int openingHour = 8; // 8 AM
  static const int closingHour = 20; // 8 PM

  Future<List<Order>> getOrdersByUser(String userId) async {
    final supabase = AppConfig.supabase;
    final rows = await supabase
        .from('order_details')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows.map(_fromRow).toList();
  }

  Future<Order?> getOrderById(String orderId) async {
    final supabase = AppConfig.supabase;
    final row = await supabase
        .from('order_details')
        .select()
        .eq('id', orderId)
        .maybeSingle();
    return row == null ? null : _fromRow(row);
  }

  Future<List<Order>> getActiveOrders() async {
    final supabase = AppConfig.supabase;
    final rows = await supabase
        .from('order_details')
        .select()
        .inFilter('status', const [
          'paidPendingApproval',
          'preparing',
          'readyForPickup',
        ])
        .order('pickup_start_time');
    return rows.map(_fromRow).toList();
  }

  Future<List<Order>> getCompletedOrders() async {
    final supabase = AppConfig.supabase;
    final rows = await supabase
        .from('order_details')
        .select()
        .inFilter('status', const ['completed', 'cancelled'])
        .order('created_at', ascending: false);
    return rows.map(_fromRow).toList();
  }

  Future<double> getTodayRevenue() async {
    final supabase = AppConfig.supabase;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final rows = await supabase
        .from('orders')
        .select('total_amount')
        .eq('status', 'completed')
        .gte('created_at', startOfDay.toIso8601String());

    var total = 0.0;
    for (final row in rows) {
      total += (row['total_amount'] as num).toDouble();
    }
    return total;
  }

  Future<int> getTodayOrderCount() async {
    final supabase = AppConfig.supabase;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final rows = await supabase
        .from('orders')
        .select('id')
        .eq('status', 'completed')
        .gte('created_at', startOfDay.toIso8601String());
    return rows.length;
  }

  /// Generates 30-minute pickup slots for a given day (defaults to today).
  /// Supports advance booking: pass a future date to book ahead.
  Future<List<TimeSlot>> getAvailableTimeSlots({DateTime? date}) async {
    final supabase = AppConfig.supabase;
    final now = DateTime.now();
    final target = date != null
        ? DateTime(date.year, date.month, date.day)
        : DateTime(now.year, now.month, now.day);
    final isToday = target.year == now.year &&
        target.month == now.month &&
        target.day == now.day;

    // Fetch all orders on the selected day to compute per-slot counts.
    final dayStart = target;
    final dayEnd = target.add(const Duration(days: 1));
    final orderRows = await supabase
        .from('orders')
        .select('pickup_start, pickup_end, status')
        .gte('pickup_start', dayStart.toIso8601String())
        .lt('pickup_start', dayEnd.toIso8601String());

    final counts = <String, int>{};
    for (final row in orderRows) {
      if (row['status'] == 'cancelled') continue;
      final start = DateTime.parse(row['pickup_start']);
      final end = DateTime.parse(row['pickup_end']);
      counts[_slotKey(start, end)] = (counts[_slotKey(start, end)] ?? 0) + 1;
    }

    final slots = <TimeSlot>[];
    var minuteOfDay = openingHour * 60;
    final lastSlotStart = closingHour * 60 - 30;

    while (minuteOfDay <= lastSlotStart) {
      final slotStart = target.add(Duration(minutes: minuteOfDay));
      final slotEnd = slotStart.add(const Duration(minutes: 30));

      // For today: skip slots that are less than 15 minutes away or past.
      if (isToday &&
          (slotStart.isBefore(now) ||
              slotStart.difference(now).inMinutes < 15)) {
        minuteOfDay += 30;
        continue;
      }

      final key = _slotKey(slotStart, slotEnd);
      final currentOrders = counts[key] ?? 0;

      slots.add(TimeSlot(
        startTime: slotStart,
        endTime: slotEnd,
        maxOrders: maxOrdersPerSlot,
        currentOrders: currentOrders,
        isAvailable: currentOrders < maxOrdersPerSlot,
      ));

      minuteOfDay += 30;
    }

    return slots;
  }

  static String _slotKey(DateTime start, DateTime end) =>
      '${start.millisecondsSinceEpoch}-${end.millisecondsSinceEpoch}';

  /// Places an order paid from the user's wallet. The server debits the
  /// wallet and creates the order in one transaction — if the balance is
  /// short, nothing is created and the RPC raises a friendly error.
  Future<Order> placeOrder({
    required List<OrderItem> items,
    required DateTime pickupStartTime,
    required DateTime pickupEndTime,
  }) async {
    final supabase = AppConfig.supabase;
    final result = await supabase.rpc('place_order_from_wallet', params: {
      'p_items': items.map((i) => i.toJson()).toList(),
      'p_pickup_start': pickupStartTime.toIso8601String(),
      'p_pickup_end': pickupEndTime.toIso8601String(),
    });
    return _fromRow(result as Map<String, dynamic>);
  }

  Future<Order> updateOrderStatus(String orderId, OrderStatus newStatus) async {
    final supabase = AppConfig.supabase;
    final result = await supabase.rpc('update_order_status', params: {
      'p_order_id': orderId,
      'p_new_status': newStatus.name,
    });
    return _fromRow(result as Map<String, dynamic>);
  }

  Order _fromRow(Map<String, dynamic> row) {
    final items = ((row['items'] as List?) ?? const [])
        .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return Order(
      id: row['id'],
      orderNumber: row['order_number'] ?? row['id'],
      userId: row['user_id'],
      items: items,
      totalAmount: (row['total_amount'] as num).toDouble(),
      status: OrderStatus.values.byName(row['status']),
      createdAt: DateTime.parse(row['created_at']),
      pickupStartTime: DateTime.parse(row['pickup_start_time']),
      pickupEndTime: DateTime.parse(row['pickup_end_time']),
      transactionId: row['transaction_id'] ?? '',
    );
  }
}