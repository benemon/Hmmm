import 'package:local_auth/local_auth.dart';

abstract interface class AppAuthenticator {
  Future<bool> authenticate();
}

class LocalAppAuthenticator implements AppAuthenticator {
  final LocalAuthentication _localAuthentication = LocalAuthentication();

  @override
  Future<bool> authenticate() => _localAuthentication.authenticate(
    localizedReason: 'Unlock Hmmm',
    persistAcrossBackgrounding: true,
  );
}
