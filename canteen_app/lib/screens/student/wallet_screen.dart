import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../utils/constants.dart';
import '../../models/wallet_transaction.dart';

/// Student wallet: balance, top-up and ledger. Used two ways — as a tab in
/// [StudentHomeScreen] (plain body) and pushed from checkout via [WalletPage].
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final wallet = context.read<WalletProvider>();
      if (!wallet.hasLoaded && auth.isLoggedIn) {
        wallet.load(auth.user!.id);
      }
    });
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthProvider>();
    if (auth.isLoggedIn) {
      await context.read<WalletProvider>().load(auth.user!.id, silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _BalanceCard(
            balance: wallet.balance,
            hasLoaded: wallet.hasLoaded,
            onAddMoney: () => _showAddMoneySheet(context),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Pay for orders straight from your wallet — no card or UPI needed.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          if (wallet.error != null) ...[
            const SizedBox(height: 8),
            Text(wallet.error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          const Text('Recent Activity',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          if (wallet.isLoading && !wallet.hasLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (wallet.transactions.isEmpty)
            const _EmptyLedger()
          else
            ...wallet.transactions.map(_LedgerTile.new),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showAddMoneySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _AddMoneySheet(),
    );
  }
}

/// Scaffold wrapper for pushing the wallet as its own route (e.g. from
/// checkout when the balance is short).
class WalletPage extends StatelessWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Wallet', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const WalletScreen(),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final double balance;
  final bool hasLoaded;
  final VoidCallback onAddMoney;

  const _BalanceCard({
    required this.balance,
    required this.hasLoaded,
    required this.onAddMoney,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text('Wallet Balance',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            hasLoaded ? '₹${balance.toStringAsFixed(2)}' : '—',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: onAddMoney,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add Money',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  final WalletTransaction txn;
  const _LedgerTile(this.txn);

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (txn.type) {
      'topup' => (Icons.add_circle_outline, AppColors.success),
      'refund' => (Icons.replay, AppColors.success),
      'order_payment' => (Icons.restaurant, AppColors.primary),
      _ => (Icons.swap_horiz, AppColors.textSecondary),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          txn.description.isNotEmpty ? txn.description : txn.typeLabel,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${txn.typeLabel} • ${_formatDate(txn.createdAt)}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: Text(
          '${txn.isCredit ? '+' : '-'}₹${txn.amount.abs().toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: txn.isCredit ? AppColors.success : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final period = t.hour < 12 ? 'AM' : 'PM';
    final minute = t.minute.toString().padLeft(2, '0');
    return '${t.day} ${months[t.month - 1]}, $hour:$minute $period';
  }
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.receipt_long, size: 44, color: Colors.grey),
          SizedBox(height: 10),
          Text('No transactions yet',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          SizedBox(height: 4),
          Text(
            'Add money and pay for orders from here.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AddMoneySheet extends StatefulWidget {
  const _AddMoneySheet();

  @override
  State<_AddMoneySheet> createState() => _AddMoneySheetState();
}

class _AddMoneySheetState extends State<_AddMoneySheet> {
  static const _presets = [100, 200, 500, 1000];
  final _amountController = TextEditingController();
  int? _selected;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _amount {
    if (_selected != null) return _selected!.toDouble();
    return double.tryParse(_amountController.text.trim()) ?? 0;
  }

  Future<void> _add() async {
    final amount = _amount;
    if (amount < 1 || amount > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter an amount between ₹1 and ₹5000'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final wallet = context.read<WalletProvider>();
    final ok = await wallet.addFunds(amount);

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('₹${amount.toStringAsFixed(2)} added to your wallet'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.add_circle, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Add Money',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'This is a demo wallet — no real payment is processed.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((p) {
              final selected = _selected == p;
              return ChoiceChip(
                label: Text('₹$p'),
                selected: selected,
                selectedColor: AppColors.primary.withValues(alpha: 0.12),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                ),
                side: BorderSide(
                    color: selected ? AppColors.primary : Colors.grey.shade300),
                onSelected: (_) {
                  setState(() {
                    _selected = p;
                    _amountController.clear();
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Or enter a custom amount',
              prefixText: '₹ ',
            ),
            onChanged: (_) => setState(() => _selected = null),
          ),
          if (wallet.error != null) ...[
            const SizedBox(height: 10),
            Text(wallet.error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: wallet.isBusy ? null : _add,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: wallet.isBusy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Add to Wallet',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
