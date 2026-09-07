import 'package:local_auth/local_auth.dart';

abstract interface class AppAuthenticator {
  Future<bool> authenticate();
}

class LocalAppAuthenticator implements AppAuthenticator {
  LocalAppAuthenticator({LocalAuthentication? localAuthentication})
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuthentication;

  @override
  Future<bool> authenticate() => _localAuthentication.authenticate(
    localizedReason: 'Unlock Hmmm',
    persistAcrossBackgrounding: true,
  );
}
