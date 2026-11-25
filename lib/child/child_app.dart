import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/backend.dart';
import '../shared/commands.dart';
import '../shared/glass_ui.dart';

class ChildApp extends StatefulWidget {
  const ChildApp({super.key});

  @override
  State<ChildApp> createState() => _ChildAppState();
}

class _ChildAppState extends State<ChildApp> {
  List<Map<String, dynamic>> _pending = [];
  bool _connected = false;
  int? _bedtimeMinutes;
  bool _savingBedtime = false;
  Map<String, bool> _permissions = {};
  Map<String, bool>? _reportedPermissions;
  Timer? _pairTimer;
  StreamSubscription<RemoteMessage>? _foregroundPush;
  StreamSubscription<RemoteMessage>? _openedPush;
  late final AppLifecycleListener _lifecycle;
  bool _checking = false;
  static const _native = MethodChannel('safeguard/child');
  StreamSubscription<String>? _tokenUpdates;
  bool _busy = false;
  bool _handlingRequest = false;
  String? _error;
  String? _code;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => _refresh());
    _foregroundPush = FirebaseMessaging.onMessage.listen((_) => _refresh());
    _openedPush = FirebaseMessaging.onMessageOpenedApp.listen((_) => _refresh());
    _issueCode();
    unawaited(_loadBedtime());
  }

  @override
  void dispose() {
    _pairTimer?.cancel();
    _foregroundPush?.cancel();
    _openedPush?.cancel();
    _lifecycle.dispose();
    _tokenUpdates?.cancel();
    super.dispose();
  }

  Future<void> _syncPermissions() async {
    final snapshot = await _native.invokeMapMethod<String, bool>('permissionStatus');
    if (!mounted || snapshot == null) return;
    setState(() => _permissions = snapshot);
    if (!_connected || snapshot.entries.every((entry) => _reportedPermissions?[entry.key] == entry.value)) {
      return;
    }
    await callBackend('updatePermissions', snapshot);
    if (mounted && _connected) _reportedPermissions = snapshot;
  }

  Future<void> _registerPush() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission();
      if (permission.authorizationStatus != AuthorizationStatus.authorized) {
        await _openSettings('notificationSettings');
        return;
      }
      final token = await messaging.getToken();
      if (token != null) await callBackend('registerPushToken', {'token': token});
      if (!mounted) return;
      _tokenUpdates ??= messaging.onTokenRefresh.listen((token) async {
        try {
          await callBackend('registerPushToken', {'token': token});
        } catch (error) {
          if (mounted) setState(() => _error = backendError(error));
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = backendError(error));
    }
  }

  Future<void> _review(Map<String, dynamic> data) async {
    final command = data['command'] as String;
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(commandLabels[command] ?? 'Parent request'),
        content: Text(data['message'] as String? ?? 'Allow this request on this device?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Decline')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Allow')),
        ],
      ),
    );
    if (!mounted || choice == null || _handlingRequest) return;
    setState(() {
      _handlingRequest = true;
      _error = null;
    });
    Future<void> report(String status, [String? result]) async {
      await callBackend('updateCommand', {
        'commandId': data['id'],
        'status': status,
        'result': result,
      });
    }
    try {
      if (!choice) {
        await report('declined');
        return;
      }
      await report('running');
      String? result;
      try {
        result = await _native.invokeMethod<String>('execute', {
          'command': command,
          'message': data['message'],
        });
      } on PlatformException catch (error) {
        await report('failed', error.message);
        if (mounted) setState(() => _error = error.message ?? 'Action failed.');
        return;
      }
      await report('completed', result);
    } catch (error) {
      if (mounted) setState(() => _error = backendError(error));
    } finally {
      if (mounted) {
        setState(() => _handlingRequest = false);
        await _refresh();
      }
    }
  }

  Widget _requests() {
    if (_pending.isEmpty) return const Text('No pending requests');
    return Column(
      children: [
        for (final request in _pending)
          ListTile(
            title: Text(commandLabels[request['command']] ?? 'Parent request'),
            trailing: TextButton(
              onPressed: _handlingRequest ? null : () => _review(request),
              child: const Text('Review'),
            ),
          ),
      ],
    );
  }

  Future<void> _refresh({bool showError = false}) async {
    if (!mounted || _checking || FirebaseAuth.instance.currentUser == null) return;
    _checking = true;
    try {
      final result = await callBackend('deviceInbox');
      if (!mounted) return;
      setState(() {
        _connected = result['connected'] == true;
        if (!_connected) _reportedPermissions = null;
        if (_connected) {
          _code = null;
          _pairTimer?.cancel();
        }
        _pending = (result['commands'] as List)
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .toList();
      });
      await _syncPermissions();
    } catch (error) {
      if (mounted && showError) setState(() => _error = backendError(error));
    } finally {
      _checking = false;
    }
  }

  void _watchPairing() {
    _pairTimer?.cancel();
    var remaining = 12;
    _pairTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || --remaining == 0 ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        timer.cancel();
        return;
      }
      unawaited(_refresh());
    });
  }

  Future<void> _unlink() async {
    if (_busy || _handlingRequest) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Parent?'),
        content: const Text('Confirm to stop new requests from this Parent. A fresh code will be required to pair again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (!mounted || confirmed != true || _busy || _handlingRequest) return;
    setState(() {
      _busy = true;
      _error = null;
      _code = null;
    });
    try {
      await callBackend('unlinkDevice');
      await _refresh(showError: true);
    } catch (error) {
      if (mounted) setState(() => _error = backendError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadBedtime() async {
    try {
      final minutes = await _native.invokeMethod<int>('bedtimeStatus');
      if (mounted) setState(() => _bedtimeMinutes = minutes);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Could not load bedtime.');
    }
  }

  Future<void> _setBedtime() async {
    final minutes = _bedtimeMinutes;
    final selected = await showTimePicker(
      context: context,
      initialTime: minutes == null
          ? const TimeOfDay(hour: 22, minute: 0)
          : TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      helpText: 'Choose a daily bedtime',
    );
    if (!mounted || selected == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable bedtime lock?'),
        content: Text(
          'This device will lock the screen once daily around ${selected.format(context)}. '
          'You can unlock it normally or turn off the schedule here.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enable')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _saveBedtime(selected.hour * 60 + selected.minute);
  }

  Future<void> _saveBedtime(int? minutes) async {
    if (_savingBedtime) return;
    setState(() {
      _savingBedtime = true;
      _error = null;
    });
    try {
      if (minutes == null) {
        await _native.invokeMethod<void>('disableBedtime');
      } else {
        await _native.invokeMethod<void>('setBedtime', {'minutes': minutes});
      }
      await _loadBedtime();
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Could not save bedtime.');
    } finally {
      if (mounted) setState(() => _savingBedtime = false);
    }
  }

  Future<void> _openSettings(String method) async {
    try {
      await _native.invokeMethod<void>(method);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? 'Android settings could not open.');
      }
    }
  }

  Future<void> _issueCode() async {
    setState(() {
      _busy = true;
      _error = null;
      _code = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) await auth.signInAnonymously();
      await _refresh(showError: true);
      if (!mounted || _connected) return;
      final response = await callBackend('issuePairCode');
      if (!mounted) return;
      setState(() => _code = response['code'] as String?);
      if (_code != null) _watchPairing();
    } catch (error) {
      if (mounted) setState(() => _error = backendError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _bedtimeMinutes;
    final bedtime = minutes == null
        ? null
        : TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);
    return GlassScaffold(
      title: 'RDX SafeGuard Child',
      body: SafeArea(
        child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: GlassPanel(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(24),
                    children: [
                      Icon(
                        !_connected ? Icons.phonelink_lock_outlined : Icons.verified_user_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 42,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        !_connected ? 'Pair this device' : 'Device connected',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 16),
                      if (_connected) ...[
                        const ListTile(
                          leading: Icon(Icons.verified_user_outlined),
                          title: Text('Connected to Parent ✅'),
                        ),
                        const Text('Your paired parent can send requests. Every request must be reviewed and approved on this device.'),
                        OutlinedButton(
                          onPressed: _registerPush,
                          child: Text(_permissions['notifications'] == true
                            ? 'Register request notifications'
                            : 'Allow request notifications'),
                        ),
                        OutlinedButton(
                          onPressed: _permissions['deviceAdmin'] == true ? null : () => _openSettings('activateAdmin'),
                          child: Text(_permissions['deviceAdmin'] == true
                            ? 'Device lock ready'
                            : 'Enable Device Admin for locking'),
                        ),
                        OutlinedButton(
                          onPressed: _permissions['notificationPolicy'] == true ? null : () => _openSettings('notificationPolicySettings'),
                          child: Text(_permissions['notificationPolicy'] == true
                            ? 'Silent and Do Not Disturb ready'
                            : 'Allow silent mode and Do Not Disturb'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _refresh(showError: true),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh requests'),
                        ),
                        _requests(),
                        TextButton(
                          onPressed: _busy || _handlingRequest ? null : _unlink,
                          child: const Text('Disconnect Parent'),
                        ),
                      ] else ...[
                        if (_code case final code?) ...[
                          Text(code,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const Text('यह कोड Parent को दें', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          const Text(
                            'Share the code only with the parent you want to pair with. '
                            'SafeGuard stores pairing and request history on its server. '
                            'Device actions require your approval on this screen.',
                          ),
                        ],
                        if (_busy) const LinearProgressIndicator(),
                        if (!_busy)
                          FilledButton(
                            onPressed: _issueCode,
                            child: const Text('Refresh Code'),
                          ),
                        if (_code != null)
                          TextButton(
                            onPressed: () => _refresh(showError: true),
                            child: const Text('Check pairing status'),
                          ),
                      ],
                      ExpansionTile(
                        leading: const Icon(Icons.bedtime_outlined),
                        title: const Text('Daily bedtime lock'),
                        subtitle: Text(bedtime == null ? 'Off' : 'Around $bedtime each day'),
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Text('Choose a time on this device. The screen locks once with a notification. Device Admin and notifications must be enabled.'),
                          ),
                          if (!_connected) ...[
                            TextButton(
                              onPressed: () => _openSettings('activateAdmin'),
                              child: const Text('Enable Device Admin'),
                            ),
                            TextButton(
                              onPressed: () => _openSettings('notificationSettings'),
                              child: const Text('Notification settings'),
                            ),
                          ],
                          TextButton(
                            onPressed: _savingBedtime ? null : _setBedtime,
                            child: Text(bedtime == null ? 'Set bedtime' : 'Change bedtime'),
                          ),
                          if (bedtime != null)
                            TextButton(
                              onPressed: _savingBedtime ? null : () => _saveBedtime(null),
                              child: const Text('Turn off bedtime lock'),
                            ),
                        ],
                      ),
                      if (_error case final error?) Text(error),
                    ],
                  ),
                ),
              ),
        ),
      ),
    );
  }
}
