import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/backend.dart';
import '../shared/commands.dart';
import '../shared/glass_ui.dart';
import '../shared/mobile_number.dart';

const _controlIcons = <String, IconData>{
  'lock': Icons.lock_outline,
  'vibrate': Icons.vibration_rounded,
  'sound': Icons.volume_up_outlined,
  'flashlight': Icons.flashlight_on_outlined,
  'message': Icons.chat_bubble_outline,
  'alarm': Icons.alarm_rounded,
  'silent': Icons.volume_off_outlined,
  'ringer_normal': Icons.notifications_active_outlined,
  'dnd_on': Icons.do_not_disturb_on_outlined,
  'dnd_off': Icons.do_not_disturb_off_outlined,
  'battery_status': Icons.battery_charging_full_outlined,
};

class ParentApp extends StatefulWidget {
  const ParentApp({super.key});

  @override
  State<ParentApp> createState() => _ParentAppState();
}

class _ParentAppState extends State<ParentApp> {
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _code = TextEditingController();
  final _form = GlobalKey<FormState>();

  bool _signUp = true;
  bool _showPassword = false;
  bool _busy = false;
  String? _error;
  String _selectedCommand = 'lock';
  final _message = TextEditingController();
  bool _signedIn = false;
  List<Map<String, dynamic>> _history = [];
  Map<String, bool>? _devicePermissions;
  Timer? _refreshTimer;
  String? _childDeviceId;

  @override
  void initState() {
    super.initState();
    if (FirebaseAuth.instance.currentUser != null) {
      _run(_loadProfile);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mobile.dispose();
    _password.dispose();
    _confirmation.dispose();
    _code.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = backendError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadProfile() async {
    final profile = await callBackend('parentProfile');
    if (!mounted) return;
    setState(() {
      _signedIn = true;
      _childDeviceId = profile['childDeviceId'] as String?;
      final permissions = profile['permissions'] as Map?;
      _devicePermissions = permissions == null ? null : Map<String, bool>.from(permissions);
      _history = (profile['commands'] as List).map(
        (entry) => Map<String, dynamic>.from(entry as Map),
      ).toList();
    });
  }

  void _watchResult() {
    _refreshTimer?.cancel();
    var remaining = 6;
    _refreshTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (!mounted || --remaining == 0 || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        timer.cancel();
        return;
      }
      if (!_busy) unawaited(_loadProfile().catchError((Object error) {}));
    });
  }

  Future<void> _unlink() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Child device?'),
        content: const Text('A fresh code will be required to connect again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (!mounted || confirmed != true || _busy) return;
    await _run(() async {
      await callBackend('unlinkDevice');
      if (!mounted) return;
      setState(() {
        _childDeviceId = null;
        _code.clear();
      });
    });
  }

  Future<void> _authenticate() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      final result = await callBackend(_signUp ? 'signup' : 'login', {
        'mobile': normalizeMobileNumber(_mobile.text),
        'password': _password.text,
      });
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: result['loginAlias'] as String,
        password: _password.text,
      );
      await _loadProfile();
      if (!mounted) return;
      _password.clear();
      _confirmation.clear();
    });
  }

  Future<void> _connect() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      final result = await callBackend('pairChild', {'code': _code.text});
      if (!mounted) return;
      setState(() {
        _childDeviceId = result['childDeviceId'] as String;
        _devicePermissions = null;
      });
      await _loadProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pairing = _signedIn && _childDeviceId == null;
    final connected = _childDeviceId != null;
    final colors = Theme.of(context).colorScheme;
    final animate = !MediaQuery.disableAnimationsOf(context);
    final title = connected
        ? 'RDX SafeGuard Parent'
        : pairing
            ? 'Enter Pair Code'
            : _signUp
                ? 'Sign up'
                : 'Log in';
    return GlassScaffold(
      title: title,
      animateColors: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: GlassPanel(
              child: Form(
                key: _form,
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(24),
                  children: [
                    if (!connected && !pairing) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xff7656ff), Color(0xffbc438e)],
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(13),
                            child: Icon(Icons.shield_rounded, color: Colors.white, size: 27),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      connected
                          ? 'Device controls'
                          : pairing
                              ? 'Connect a device'
                              : _signUp ? 'Create your account' : 'Welcome back',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (connected) ...[
                      ListTile(
                        leading: Icon(Icons.verified_user_outlined, color: colors.primary),
                        title: const Text('Child device paired'),
                        subtitle: const Text('Requests require approval on the Child device.'),
                        tileColor: colors.primary.withValues(alpha: .1),
                      ),
                      ExpansionTile(
                        title: const Text('Child permissions'),
                        children: [
                          for (final setting in const {
                            'notifications': 'Visible notifications',
                            'deviceAdmin': 'Lock device',
                            'notificationPolicy': 'Silent and Do Not Disturb',
                          }.entries)
                            ListTile(
                              dense: true,
                              title: Text(setting.value),
                              trailing: Text(switch (_devicePermissions?[setting.key]) {
                                true => 'Ready',
                                false => 'Setup needed',
                                null => 'Pending sync',
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final largeText = MediaQuery.textScalerOf(context).scale(16) > 21;
                          final width = largeText || constraints.maxWidth < 255
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 10) / 2;
                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final entry in commandLabels.entries)
                                SizedBox(
                                  width: width,
                                  child: Semantics(
                                    selected: _selectedCommand == entry.key,
                                    child: AnimatedContainer(
                                      duration: animate ? const Duration(milliseconds: 220) : Duration.zero,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        color: _selectedCommand == entry.key
                                            ? colors.primary.withValues(alpha: .2)
                                            : colors.onSurface.withValues(alpha: .07),
                                        border: Border.all(
                                          color: _selectedCommand == entry.key
                                              ? colors.primary
                                              : colors.onSurface.withValues(alpha: .13),
                                        ),
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: _busy ? null : () {
                                          setState(() => _selectedCommand = entry.key);
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                _controlIcons[entry.key] ?? Icons.tune,
                                                color: _selectedCommand == entry.key
                                                    ? colors.primary
                                                    : colors.onSurfaceVariant,
                                                size: 21,
                                              ),
                                              const SizedBox(height: 7),
                                              Text(entry.value),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_selectedCommand == 'message')
                        TextField(
                          controller: _message,
                          maxLength: 160,
                          decoration: const InputDecoration(labelText: 'Message'),
                        ),
                      FilledButton(
                        onPressed: _busy ? null : () => _run(() async {
                          await callBackend('queueCommand', {
                            'command': _selectedCommand,
                            'message': _message.text,
                          });
                          await _loadProfile();
                          if (mounted) _watchResult();
                        }),
                        child: Text('Send: ${commandLabels[_selectedCommand]}'),
                      ),
                      const SizedBox(height: 14),
                      TextButton.icon(
                        onPressed: _busy ? null : () => _run(_loadProfile),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh request history'),
                      ),
                      for (final command in _history)
                        ListTile(
                          title: Text(commandLabels[command['command']] ?? 'Request'),
                          subtitle: Text([command['status'], command['result']]
                              .whereType<String>().join(' · ')),
                        ),
                      TextButton(
                        onPressed: _busy ? null : _unlink,
                        child: const Text('Disconnect Child device'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _run(() async {
                          _refreshTimer?.cancel();
                          await FirebaseAuth.instance.signOut();
                          if (!mounted) return;
                          setState(() {
                            _signedIn = false;
                            _history = [];
                            _childDeviceId = null;
                            _signUp = false;
                            _code.clear();
                          });
                        }),
                        child: const Text('Log out'),
                      ),
                    ] else if (pairing) ...[
                      TextFormField(
                        controller: _code,
                        decoration: const InputDecoration(labelText: 'Pair code'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        maxLength: 6,
                        validator: (value) =>
                            value?.length == 6 ? null : 'Enter all six digits',
                      ),
                      FilledButton(
                        onPressed: _busy ? null : _connect,
                        child: const Text('Connect'),
                      ),
                    ] else ...[
                      TextFormField(
                        controller: _mobile,
                        decoration: const InputDecoration(
                          labelText: 'Mobile Number',
                          prefixIcon: Icon(Icons.phone_android_outlined),
                          hintText: '10-digit mobile number',
                          helperText: 'India (+91) is added automatically.',
                        ),
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        validator: (value) => normalizeMobileNumber(value ?? '') == null
                            ? 'Enter 10 digits or add your country code'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _showPassword ? 'Hide password' : 'Show password',
                            icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        obscureText: !_showPassword,
                        enableSuggestions: false,
                        autocorrect: false,
                        textInputAction: _signUp ? TextInputAction.next : TextInputAction.done,
                        validator: (value) => value == null || value.length < 8 || value.length > 128
                            ? 'Password must be 8–128 characters'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      if (_signUp)
                        TextFormField(
                          controller: _confirmation,
                          decoration: const InputDecoration(
                            labelText: 'Confirm Password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          obscureText: true,
                          validator: (value) =>
                              value == _password.text ? null : 'Passwords do not match',
                        ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _authenticate,
                        child: Text(title),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => setState(() {
                          _signUp = !_signUp;
                          _confirmation.clear();
                          _showPassword = false;
                          _error = null;
                        }),
                        child: Text(_signUp ? 'Log in' : 'Create an account'),
                      ),
                    ],
                    if (_busy) const LinearProgressIndicator(),
                    if (_error case final error?) Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
