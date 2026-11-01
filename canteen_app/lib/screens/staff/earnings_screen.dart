import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/canteen_payout.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../utils/constants.dart';

/// Staff view of the money the canteen has collected from wallet payments,
/// plus a payout log for "I transferred the balance to my bank".
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final wallet = context.read<WalletProvider>();
      if (!wallet.canteenLoaded) wallet.loadCanteen();
    });
  }

  Future<void> _refresh() async {
    await context.read<WalletProvider>().loadCanteen(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final auth = context.watch<AuthProvider>();
    final canPayout = auth.user?.canManageMenu ?? false;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _BalanceCard(
            balance: wallet.canteenBalance,
            hasLoaded: wallet.canteenLoaded,
            canPayout: canPayout,
            onPayout: () => showDialog(
              context: context,
              builder: (_) => const _PayoutDialog(),
            ),
          ),
          if (!canPayout) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.lock_outline, size: 15, color: AppColors.textSecondary),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Only canteen staff can record a payout.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          if (wallet.error != null) ...[
            const SizedBox(height: 8),
            Text(wallet.error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          const Text('Payout History',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          if (wallet.isLoading && !wallet.canteenLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (wallet.canteenPayouts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.account_balance, size: 44, color: Colors.grey),
                  SizedBox(height: 10),
                  Text('No payouts yet',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14)),
                  SizedBox(height: 4),
                  Text(
                    'Record a payout after you transfer the balance to your bank.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            ...wallet.canteenPayouts.map(_PayoutTile.new),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final double balance;
  final bool hasLoaded;
  final bool canPayout;
  final VoidCallback onPayout;

  const _BalanceCard({
    required this.balance,
    required this.hasLoaded,
    required this.canPayout,
    required this.onPayout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [AppColors.secondary, Color(0xFF1B5E20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.3),
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
              Icon(Icons.storefront, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text('Canteen Balance',
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
          const SizedBox(height: 4),
          const Text(
            'Collected from wallet payments',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (canPayout) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                onPressed: hasLoaded ? onPayout : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                icon: const Icon(Icons.payments_outlined, size: 20),
                label: const Text('Record Payout',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PayoutTile extends StatelessWidget {
  final CanteenPayout payout;
  const _PayoutTile(this.payout);

  @override
  Widget build(BuildContext context) {
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
          backgroundColor: AppColors.secondary.withValues(alpha: 0.1),
          child: const Icon(Icons.account_balance,
              color: AppColors.secondary, size: 20),
        ),
        title: Text(
          payout.note.isNotEmpty ? payout.note : 'Payout to bank',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _formatDate(payout.createdAt),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: Text(
          '-₹${payout.amount.toStringAsFixed(2)}',
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppColors.textPrimary),
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

class _PayoutDialog extends StatefulWidget {
  const _PayoutDialog();

  @override
  State<_PayoutDialog> createState() => _PayoutDialogState();
}

class _PayoutDialogState extends State<_PayoutDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid payout amount'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final wallet = context.read<WalletProvider>();
    final ok = await wallet.createPayout(amount, _noteController.text.trim());

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '₹${amount.toStringAsFixed(2)} payout recorded'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final available = wallet.canteenBalance;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Record Payout'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available balance: ₹${available.toStringAsFixed(2)}',
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
                labelText: 'Note (optional)', hintText: 'e.g. HDFC transfer'),
          ),
          if (wallet.error != null) ...[
            const SizedBox(height: 10),
            Text(wallet.error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: wallet.isBusy ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
          ),
          child: wallet.isBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Text('Record'),
        ),
      ],
    );
  }
}
