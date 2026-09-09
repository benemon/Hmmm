import 'package:flutter/material.dart';

import '../app_authenticator.dart';
import '../data/settings_repository.dart';
import 'theme.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.settingsRepository,
    required this.authenticator,
    required this.child,
  });

  final SettingsRepository settingsRepository;
  final AppAuthenticator authenticator;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  late bool _locked = widget.settingsRepository.requireUnlock;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.settingsRepository.requireUnlock) return;
    if (state == AppLifecycleState.paused) {
      if (mounted) setState(() => _locked = true);
    } else if (state == AppLifecycleState.resumed && _locked) {
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (_authenticating || !widget.settingsRepository.requireUnlock) return;
    _authenticating = true;
    var authenticated = false;
    try {
      authenticated = await widget.authenticator.authenticate();
    } on Exception {
      authenticated = false;
    }
    _authenticating = false;
    if (mounted) setState(() => _locked = !authenticated);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settingsRepository,
      builder: (context, child) {
        if (!widget.settingsRepository.requireUnlock || !_locked) {
          return widget.child;
        }
        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 32,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: Dim.s3),
                Text(
                  'Hmmm is locked',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: Dim.s1),
                Text(
                  'device authentication required',
                  style: HmmmType.of(context).figureSmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Dim.s5),
                SizedBox(
                  height: Dim.minTarget,
                  child: FilledButton(
                    key: const ValueKey('unlock-app'),
                    onPressed: _authenticating ? null : _authenticate,
                    child: const Text('Unlock'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
