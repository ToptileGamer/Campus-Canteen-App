import '../config/app_config.dart';
import '../models/canteen_payout.dart';
import '../models/wallet_transaction.dart';

/// Data access for the wallet. Every write goes through a SECURITY DEFINER
/// RPC (add_wallet_funds / place_order_from_wallet / canteen_payout) — the
/// client only ever reads.
class WalletService {
  String get _uid {
    final user = AppConfig.supabase.auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    return user.id;
  }

  Future<double> getBalance() async {
    final row = await AppConfig.supabase
        .from('wallets')
        .select('balance')
        .eq('user_id', _uid)
        .maybeSingle();
    if (row == null) return 0;
    return (row['balance'] as num).toDouble();
  }

  Future<List<WalletTransaction>> getTransactions({int limit = 50}) async {
    final rows = await AppConfig.supabase
        .from('wallet_transactions')
        .select()
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(WalletTransaction.fromJson).toList();
  }

  /// Simulated top-up: credits instantly (no gateway wired up yet).
  /// Returns the new balance.
  Future<double> addFunds(double amount) async {
    final result = await AppConfig.supabase.rpc('add_wallet_funds', params: {
      'p_amount': amount,
      'p_method': 'simulated',
    });
    return ((result as Map<String, dynamic>)['balance'] as num).toDouble();
  }

  Future<double> getCanteenBalance() async {
    final row = await AppConfig.supabase
        .from('canteen_wallet')
        .select('balance')
        .eq('id', 1)
        .maybeSingle();
    if (row == null) return 0;
    return (row['balance'] as num).toDouble();
  }

  Future<List<CanteenPayout>> getCanteenPayouts({int limit = 30}) async {
    final rows = await AppConfig.supabase
        .from('canteen_payouts')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(CanteenPayout.fromJson).toList();
  }

  /// Records moving [amount] of the canteen balance to the owner's bank.
  /// Returns the new canteen balance.
  Future<double> createPayout(double amount, String note) async {
    final result = await AppConfig.supabase.rpc('canteen_payout', params: {
      'p_amount': amount,
      'p_note': note,
    });
    return ((result as Map<String, dynamic>)['balance'] as num).toDouble();
  }
}
