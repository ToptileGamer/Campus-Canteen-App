import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/order.dart';
import '../models/time_slot.dart';
import '../services/order_service.dart';

class OrderProvider extends ChangeNotifier {
  final OrderService _orderService = OrderService();

  List<Order> _userOrders = [];
  List<Order> _activeOrders = [];
  List<Order> _pendingOrders = [];
  List<Order> _preparingOrders = [];
  List<Order> _readyOrders = [];
  List<Order> _completedOrders = [];
  List<TimeSlot> _availableSlots = [];
  bool _isLoading = false;
  String? _error;
  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _pollTimer;

  // Staff analytics
  double _todayRevenue = 0;
  int _todayOrderCount = 0;

  List<Order> get userOrders => _userOrders;
  List<Order> get activeOrders => _activeOrders;
  List<Order> get pendingOrders => _pendingOrders;
  List<Order> get preparingOrders => _preparingOrders;
  List<Order> get readyOrders => _readyOrders;
  List<Order> get completedOrders => _completedOrders;
  List<TimeSlot> get availableSlots => _availableSlots;
  bool get isLoading => _isLoading;
  String? get error => _error;
  double get todayRevenue => _todayRevenue;
  int get todayOrderCount => _todayOrderCount;

  /// Subscribes to the orders table. Students receive only their own orders,
  /// staff receive all orders — both update live without any manual reload.
  void subscribe(String userId, {required bool isStaff}) {
    _setupChannel(userId, isStaff: isStaff);
  }

  void _setupChannel(String userId, {required bool isStaff}) {
    unsubscribe();
    try {
      final supabase = AppConfig.supabase;
      _channel = supabase
          .channel('orders_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            filter: isStaff
                ? null
                : PostgresChangeFilter(
                    type: PostgresChangeFilterType.eq,
                    column: 'user_id',
                    value: userId,
                  ),
            callback: (_) => _onOrdersChanged(userId, isStaff),
          )
          .subscribe();
    } catch (_) {
      // realtime unavailable (e.g. not initialized in tests)
    }
  }

  void _onOrdersChanged(String userId, bool isStaff) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      _refreshFromRealtime(userId, isStaff);
    });
  }

  /// Fallback safety net: even if the realtime WebSocket drops, orders still
  /// reflect on the other side within ~5 seconds. The refresh is silent
  /// (no spinner) so it never flickers the UI.
  void startPolling(String userId, {required bool isStaff}) {
    stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (isStaff) {
        loadActiveOrders(silent: true);
        loadAnalytics();
      } else {
        loadUserOrders(userId, silent: true);
      }
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _refreshFromRealtime(String userId, bool isStaff) async {
    if (isStaff) {
      await Future.wait([
        loadActiveOrders(),
        loadAnalytics(),
      ]);
    } else {
      await loadUserOrders(userId);
    }
  }

  void unsubscribe() {
    _debounce?.cancel();
    try {
      _channel?.unsubscribe();
    } catch (_) {}
    _channel = null;
  }

  Future<void> loadUserOrders(String userId, {bool silent = false}) async {
    try {
      _userOrders = await _orderService.getOrdersByUser(userId);
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  /// Loads a single order and merges it into the user order list so tracking
  /// works even when opened directly from a notification.
  Future<void> loadOrderById(String orderId) async {
    try {
      final order = await _orderService.getOrderById(orderId);
      if (order == null) return;
      final exists = _userOrders.any((o) => o.id == order.id);
      _userOrders = exists
          ? _userOrders.map((o) => o.id == order.id ? order : o).toList()
          : [order, ..._userOrders];
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadActiveOrders({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final orders = await _orderService.getActiveOrders();
      _activeOrders = orders;
      _pendingOrders =
          orders.where((o) => o.status == OrderStatus.paidPendingApproval).toList();
      _preparingOrders =
          orders.where((o) => o.status == OrderStatus.preparing).toList();
      _readyOrders =
          orders.where((o) => o.status == OrderStatus.readyForPickup).toList();
    } catch (e) {
      _error = e.toString();
    }

    if (!silent) {
      _isLoading = false;
    }
    notifyListeners();
  }

  Future<void> loadCompletedOrders() async {
    _isLoading = true;
    notifyListeners();

    try {
      _completedOrders = await _orderService.getCompletedOrders();
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadTimeSlots({DateTime? date}) async {
    try {
      _availableSlots = await _orderService.getAvailableTimeSlots(date: date);
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<void> loadAnalytics() async {
    try {
      _todayRevenue = await _orderService.getTodayRevenue();
      _todayOrderCount = await _orderService.getTodayOrderCount();
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  bool canPlaceOrderInSlot(DateTime start, DateTime end) {
    final slot = _availableSlots
        .where((s) => s.startTime == start && s.endTime == end)
        .firstOrNull;
    return slot == null ? true : slot.remainingSpots > 0;
  }

  int getSlotOrderCount(DateTime start, DateTime end) {
    final slot = _availableSlots
        .where((s) => s.startTime == start && s.endTime == end)
        .firstOrNull;
    return slot?.currentOrders ?? 0;
  }

  Future<bool> updateOrderStatus(String orderId, OrderStatus newStatus) async {
    try {
      final updated = await _orderService.updateOrderStatus(orderId, newStatus);
      await loadActiveOrders();
      _userOrders = _userOrders
          .map((o) => o.id == updated.id ? updated : o)
          .toList();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Pays from the wallet and places the order. The server does both in one
  /// transaction, so a short balance means no order is created.
  Future<Order?> checkout({
    required List<OrderItem> items,
    required DateTime pickupStartTime,
    required DateTime pickupEndTime,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (!canPlaceOrderInSlot(pickupStartTime, pickupEndTime)) {
        _error = 'This time slot is full. Please choose another.';
        _isLoading = false;
        notifyListeners();
        return null;
      }

      final order = await _orderService.placeOrder(
        items: items,
        pickupStartTime: pickupStartTime,
        pickupEndTime: pickupEndTime,
      );

      _userOrders = [order, ..._userOrders.where((o) => o.id != order.id)];
      _isLoading = false;
      notifyListeners();
      return order;
    } catch (e) {
      _error = _friendlyError(e);
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  String _friendlyError(Object e) {
    final raw = e is PostgrestException
        ? e.message
        : e.toString().replaceFirst('Exception: ', '');
    if (raw.contains('full')) return 'This time slot is full. Please choose another.';
    if (raw.contains('PostgrestException')) {
      final start = raw.indexOf('message: ');
      if (start != -1) {
        return raw.substring(start + 9, raw.indexOf(',', start));
      }
    }
    return raw;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}