// Widget tests for the Account Security screen: passkey list/manage + the
// delete-account danger zone (App Store compliance requires in-app deletion).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/screens/account/security_screen.dart';
import 'package:orbguard/services/orbnet/models/passkey_info.dart';

class _FakeAccount extends AccountProvider {
  _FakeAccount({required this.passkeys})
      : super(enableProactiveRefresh: false);

  List<PasskeyInfo> passkeys;
  final List<int> deleted = [];
  int deleteAccountCalls = 0;

  @override
  Future<bool> isPasskeyAvailable() async => true;

  @override
  Future<List<PasskeyInfo>> listPasskeys() async => List.of(passkeys);

  @override
  Future<void> deletePasskey(int passkeyId) async {
    deleted.add(passkeyId);
    passkeys = passkeys.where((p) => p.id != passkeyId).toList();
  }

  @override
  Future<bool> deleteAccount() async {
    deleteAccountCalls++;
    return true;
  }
}

Future<void> _pump(WidgetTester tester, _FakeAccount account) async {
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<AccountProvider>.value(
      value: account,
      child: const MaterialApp(home: SecurityScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final keys = [
    PasskeyInfo(id: 1, name: 'iPhone Face ID', createdAt: DateTime(2026, 7, 1)),
    PasskeyInfo(id: 2, name: 'Samsung fingerprint'),
  ];

  testWidgets('lists registered passkeys with manage menus', (tester) async {
    final account = _FakeAccount(passkeys: keys);
    await _pump(tester, account);

    expect(find.text('iPhone Face ID'), findsOneWidget);
    expect(find.text('Samsung fingerprint'), findsOneWidget);
    expect(find.text('Add a passkey'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);

    account.dispose();
  });

  testWidgets('empty state invites setup, never shows a fake passkey',
      (tester) async {
    final account = _FakeAccount(passkeys: []);
    await _pump(tester, account);

    expect(find.textContaining('No passkeys yet'), findsOneWidget);

    account.dispose();
  });

  testWidgets('delete flows through a confirm sheet to deletePasskey',
      (tester) async {
    final account = _FakeAccount(passkeys: List.of(keys));
    await _pump(tester, account);

    // Open the first passkey's menu → Delete → confirm sheet → confirm.
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete passkey'), findsWidgets); // sheet title + button
    await tester.tap(find.text('Delete passkey').last);
    await tester.pumpAndSettle();

    expect(account.deleted, [1]);
    expect(find.text('iPhone Face ID'), findsNothing);

    account.dispose();
  });

  testWidgets(
      'delete account requires typing DELETE — wrong text does NOT delete',
      (tester) async {
    final account = _FakeAccount(passkeys: []);
    await _pump(tester, account);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();

    expect(account.deleteAccountCalls, 0,
        reason: 'mistyped confirmation must never delete the account');

    account.dispose();
  });

  testWidgets('delete account with typed DELETE calls deleteAccount',
      (tester) async {
    final account = _FakeAccount(passkeys: []);
    await _pump(tester, account);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();

    expect(account.deleteAccountCalls, 1);

    account.dispose();
  });
}
