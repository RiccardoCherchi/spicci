import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../state.dart';
import '../theme/theme.dart';
import 'solar.dart';

final _auth = LocalAuthentication();

/// Whether the app asks for Face ID (or the device passcode) when opened.
class LockEnabled extends Notifier<bool> {
  static const _key = 'lock_enabled';

  @override
  bool build() => ref.read(prefsProvider).getBool(_key) ?? false;

  void set(bool on) {
    state = on;
    ref.read(prefsProvider).setBool(_key, on);
  }
}

final lockEnabledProvider = NotifierProvider<LockEnabled, bool>(LockEnabled.new);

/// Asks for Face ID, falling back to the device passcode. Returns true when the
/// user passed, and also when the device has no way to authenticate at all, so
/// the app can never end up locked forever.
Future<bool> authenticate(String reason) async {
  try {
    if (!await _auth.isDeviceSupported()) return true;
    return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
  } on LocalAuthException catch (e) {
    return e.code == LocalAuthExceptionCode.noCredentialsSet;
  }
}

/// Covers the app while it is in the background (so the app switcher shows no
/// amounts) and asks to unlock after more than [grace] away.
class AppLock extends ConsumerStatefulWidget {
  const AppLock({super.key, required this.child, this.grace = const Duration(seconds: 30)});
  final Widget child;
  final Duration grace;

  @override
  ConsumerState<AppLock> createState() => _AppLockState();
}

class _AppLockState extends ConsumerState<AppLock> {
  late bool _locked = ref.read(lockEnabledProvider);
  var _covered = false;
  var _busy = false;
  DateTime? _leftAt;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onInactive: () {
        if (ref.read(lockEnabledProvider)) setState(() => _covered = true);
      },
      onHide: () => _leftAt ??= DateTime.now(),
      onResume: () {
        final away = _leftAt == null ? Duration.zero : DateTime.now().difference(_leftAt!);
        _leftAt = null;
        setState(() {
          _covered = false;
          if (ref.read(lockEnabledProvider) && away > widget.grace) _locked = true;
        });
        if (_locked) _unlock();
      },
    );
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy) return;
    _busy = true;
    final ok = await authenticate('lock.reason'.tr());
    _busy = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hide = _locked || _covered;
    return Stack(
      children: [
        // Kept alive underneath so state and scroll positions survive the lock.
        ExcludeSemantics(excluding: hide, child: widget.child),
        if (hide)
          Positioned.fill(
            child: ColoredBox(
              color: t.bg,
              child: SafeArea(
                child: Column(
                  children: [
                    const Spacer(),
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(26)),
                      alignment: Alignment.center,
                      child: SolarIcon.category('wallet', color: t.onAccent, size: 48),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Spicci',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: t.ink),
                    ),
                    const Spacer(),
                    if (_locked)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(gap, 0, gap, gap),
                        // Always visible: a failed or cancelled check can be retried, never a dead end.
                        child: FilledButton(onPressed: _unlock, child: Text('lock.unlock'.tr())),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
