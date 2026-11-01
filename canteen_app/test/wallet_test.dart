import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:canteen_app/models/canteen_payout.dart';
import 'package:canteen_app/models/user.dart';
import 'package:canteen_app/models/wallet_transaction.dart';
import 'package:canteen_app/providers/auth_provider.dart';
import 'package:canteen_app/providers/wallet_provider.dart';
import 'package:canteen_app/screens/staff/earnings_screen.dart';
import 'package:canteen_app/screens/student/wallet_screen.dart';

class _FakeWalletProvider extends WalletProvider {
  bool addCalled = false;
  double addedAmount = 0;
  bool payoutCalled = false;
  double payoutAmount = 0;

  @override
  bool get hasLoaded => true;

  @override
  bool get canteenLoaded => true;

  @override
  bool get isLoading => false;

  @override
  bool get isBusy => false;

  @override
  double get balance => 250;

  @override
  double get canteenBalance => 1200;

  @override
  List<WalletTransaction> get transactions => [
        WalletTransaction(
          id: 't1',
          userId: 'u1',
          amount: 500,
          type: 'topup',
          balanceAfter: 500,
          description: 'Added via simulated',
          createdAt: DateTime(2026, 11, 1, 10, 30),
        ),
        WalletTransaction(
          id: 't2',
          userId: 'u1',
          amount: -120,
          type: 'order_payment',
          orderId: 'o1',
          balanceAfter: 380,
          description: 'Paid for order ORD-ABC123',
          createdAt: DateTime(2026, 11, 1, 12, 0),
        ),
      ];

  @override
  List<CanteenPayout> get canteenPayouts => [
        CanteenPayout(
          id: 'p1',
          amount: 400,
          note: 'HDFC transfer',
          createdBy: 's1',
          createdAt: DateTime(2026, 10, 30, 17, 0),
        ),
      ];

  @override
  Future<void> load(String userId, {bool silent = false}) async {}

  @override
  Future<void> loadCanteen({bool silent = false}) async {}

  @override
  Future<bool> addFunds(double amount) async {
    addCalled = true;
    addedAmount = amount;
    return true;
  }

  @override
  Future<bool> createPayout(double amount, String note) async {
    payoutCalled = true;
    payoutAmount = amount;
    return true;
  }
}

class _FakeAuthProvider extends AuthProvider {
  @override
  AppUser? get user => AppUser(
        id: 'u1',
        name: 'Canteen Owner',
        email: 'owner@example.com',
        rollNumber: 'C1',
        role: UserRole.canteenStaff,
      );

  @override
  bool get isLoggedIn => true;
}

Widget _wrap(Widget child, {WalletProvider? wallet}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuthProvider()),
      ChangeNotifierProvider<WalletProvider>(
          create: (_) => wallet ?? _FakeWalletProvider()),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('wallet screen shows balance and ledger entries', (tester) async {
    await tester.pumpWidget(_wrap(const WalletScreen()));
    await tester.pumpAndSettle();

    expect(find.text('₹250.00'), findsOneWidget);
    expect(find.text('Added via simulated'), findsOneWidget);
    expect(find.text('Paid for order ORD-ABC123'), findsOneWidget);
    expect(find.text('+₹500.00'), findsOneWidget);
    expect(find.text('-₹120.00'), findsOneWidget);
  });

  testWidgets('add money sheet credits the chosen amount', (tester) async {
    final wallet = _FakeWalletProvider();
    await tester.pumpWidget(_wrap(const WalletScreen(), wallet: wallet));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Money'));
    await tester.pumpAndSettle();
    expect(find.text('Add to Wallet'), findsOneWidget);

    await tester.tap(find.text('₹200'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Wallet'));
    await tester.pumpAndSettle();

    expect(wallet.addCalled, isTrue);
    expect(wallet.addedAmount, 200);
    expect(find.textContaining('added to your wallet'), findsOneWidget);
  });

  testWidgets('earnings screen shows canteen balance and payout history',
      (tester) async {
    await tester.pumpWidget(_wrap(const EarningsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('₹1200.00'), findsOneWidget);
    expect(find.text('Record Payout'), findsOneWidget);
    expect(find.text('HDFC transfer'), findsOneWidget);
    expect(find.text('-₹400.00'), findsOneWidget);
    expect(find.text('Only canteen staff can record a payout.'), findsNothing);
  });

  testWidgets('recording a payout calls the provider', (tester) async {
    final wallet = _FakeWalletProvider();
    await tester.pumpWidget(_wrap(const EarningsScreen(), wallet: wallet));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Record Payout'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '500');
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();

    expect(wallet.payoutCalled, isTrue);
    expect(wallet.payoutAmount, 500);
    expect(find.textContaining('payout recorded'), findsOneWidget);
  });
}
