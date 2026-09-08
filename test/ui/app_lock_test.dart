import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/app_authenticator.dart';
import 'package:hmmm/data/database.dart';
import 'package:hmmm/data/settings_repository.dart';
import 'package:hmmm/ui/app_lock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('lock gate authenticates on start and after background resume', (
    tester,
  ) async {
    final database = await openHmmmDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    final settings = SettingsRepository(database);
    await settings.load();
    await settings.setRequireUnlock(true);
    final authenticator = _FakeAuthenticator();

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          settingsRepository: settings,
          authenticator: authenticator,
          child: const Text('clinical data'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Hmmm is locked'), findsOneWidget);
    expect(find.text('device authentication required'), findsOneWidget);
    expect(find.text('clinical data'), findsNothing);
    expect(authenticator.calls, 1);

    authenticator.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('clinical data'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.text('clinical data'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(authenticator.calls, 2);
    expect(find.text('Hmmm is locked'), findsOneWidget);

    authenticator.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('clinical data'), findsOneWidget);

    settings.dispose();
    await database.close();
  });
}

class _FakeAuthenticator implements AppAuthenticator {
  final _pending = <Completer<bool>>[];
  var calls = 0;

  @override
  Future<bool> authenticate() {
    calls++;
    final completer = Completer<bool>();
    _pending.add(completer);
    return completer.future;
  }

  void complete(bool result) => _pending.removeAt(0).complete(result);
}
