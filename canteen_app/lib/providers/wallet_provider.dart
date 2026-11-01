import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/canteen_payout.dart';
import '../models/wallet_transaction.dart';
import '../services/wallet_service.dart';

class WalletProvider extends ChangeNotifier {
  final WalletService _service = WalletService();

  double _balance = 0;
  List<WalletTransaction> _transactions = [];
  double _canteenBalance = 0;
  List<CanteenPayout> _canteenPayouts = [];
  bool _isLoading = false;
  bool _isBusy = false;
  bool _hasLoaded = false;
  bool _canteenLoaded = false;
  String? _error;
  RealtimeChannel? _channel;
  Timer? _debounce;

  double get balance => _balance;
  List<WalletTransaction> get transactions => _transactions;
  double get canteenBalance => _canteenBalance;
  List<CanteenPayout> get canteenPayouts => _canteenPayouts;
  bool get isLoading => _isLoading;
  bool get isBusy => _isBusy;

  /// True once balance and ledger have been fetched at least once — lets UI
  /// distinguish "wallet is empty" from "balance not loaded yet".
  bool get hasLoaded => _hasLoaded;

  /// Same distinction for the canteen balance / payout history.
  bool get canteenLoaded => _canteenLoaded;
  String? get error => _error;

  /// Loads the signed-in user's balance and ledger.
  Future<void> load(String userId, {bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      _balance = await _service.getBalance();
      _transactions = await _service.getTransactions();
      _error = null;
      _hasLoaded = true;
    } catch (e) {
      _error = _messageOf(e);
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Credits the wallet after a short "gateway" delay so the top-up feels
  /// like a real payment round-trip. Returns true on success.
  Future<bool> addFunds(double amount) async {
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      await Future.delayed(const Duration(milliseconds: 1200));
      _balance = await _service.addFunds(amount);
      _transactions = await _service.getTransactions();
      _error = null;
      _hasLoaded = true;
      _isBusy = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _messageOf(e);
      _isBusy = false;
      notifyListeners();
      return false;
    }
  }

  /// Loads the canteen's pooled balance and payout history (staff only).
  Future<void> loadCanteen({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      _canteenBalance = await _service.getCanteenBalance();
      _canteenPayouts = await _service.getCanteenPayouts();
      _error = null;
      _canteenLoaded = true;
    } catch (e) {
      _error = _messageOf(e);
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Records moving [amount] out of the canteen balance to the owner's bank.
  Future<bool> createPayout(double amount, String note) async {
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      _canteenBalance = await _service.createPayout(amount, note);
      _canteenPayouts = await _service.getCanteenPayouts();
      _isBusy = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _messageOf(e);
      _isBusy = false;
      notifyListeners();
      return false;
    }
  }

  /// Live balance: every top-up, payment and refund writes a ledger row, so
  /// watching this one table catches all of them (RLS scopes it to the user).
  void subscribe(String userId) {
    unsubscribe();
    try {
      _channel = AppConfig.supabase
          .channel('wallet_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'wallet_transactions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 150), () {
                load(userId, silent: true);
              });
            },
          )
          .subscribe();
    } catch (_) {
      // realtime unavailable (e.g. not initialized in tests)
    }
  }

  void unsubscribe() {
    _debounce?.cancel();
    _debounce = null;
    try {
      _channel?.unsubscribe();
    } catch (_) {}
    _channel = null;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _messageOf(Object e) {
    if (e is PostgrestException) return e.message;
    return e.toString().replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }
}
