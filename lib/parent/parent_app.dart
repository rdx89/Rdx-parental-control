import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/backend.dart';
import '../shared/commands.dart';
import '../shared/glass_ui.dart';

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
  bool _busy = false;
  String? _error;
  String _selectedCommand = 'lock';
  final _message = TextEditingController();
  String? _familyId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _familyUpdates;
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
    _familyUpdates?.cancel();
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
    final familyId = profile['familyId'] as String;
    await _familyUpdates?.cancel();
    if (!mounted) return;
    setState(() {
      _familyId = familyId;
      _childDeviceId = profile['childDeviceId'] as String?;
    });
    _familyUpdates = FirebaseFirestore.instance.collection('families').doc(familyId)
        .snapshots().listen((snapshot) {
      if (!mounted || _familyId != familyId || snapshot.metadata.isFromCache) return;
      final child = snapshot.data()?['childDeviceId'] as String?;
      if (_childDeviceId != child) setState(() => _childDeviceId = child);
    }, onError: (Object error) {
      if (mounted && _familyId == familyId) {
        setState(() => _error = 'Could not monitor the device connection.');
      }
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
        'mobile': _mobile.text.trim(),
        'password': _password.text,
      });
      await FirebaseAuth.instance.signInWithCustomToken(result['token'] as String);
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
      setState(() => _childDeviceId = result['childDeviceId'] as String);
    });
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final pairing = _familyId != null && _childDeviceId == null;
    final connected = _childDeviceId != null;
    final title = connected
        ? 'RDX SafeGuard Parent'
        : pairing
            ? 'Enter Pair Code'
            : _signUp
                ? 'Sign up'
                : 'Log in';
    return GlassScaffold(
      title: title,
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
                    Text(
                      connected ? 'Device controls' : pairing ? 'Connect a device' : 'RDX SafeGuard Parent',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 20),
                    if (connected) ...[
                      const ListTile(
                        leading: Icon(Icons.verified_user_outlined),
                        title: Text('Child device connected'),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final entry in commandLabels.entries)
                            ChoiceChip(
                              label: Text(entry.value),
                              selected: _selectedCommand == entry.key,
                              onSelected: _busy ? null : (_) {
                                setState(() => _selectedCommand = entry.key);
                              },
                            ),
                        ],
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
                        }),
                        child: const Text('Send request'),
                      ),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('families').doc(_familyId).collection('commands')
                            .orderBy('timestamp', descending: true).limit(10).snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) return const Text('Could not load request history.');
                          return Column(
                            children: [
                              for (final command in snapshot.data?.docs ?? const [])
                                ListTile(
                                  title: Text(commandLabels[command.get('command')] ?? 'Request'),
                                  subtitle: Text(
                                    [command.get('status'), command.get('result')].whereType<String>().join(' · '),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      TextButton(
                        onPressed: _busy ? null : _unlink,
                        child: const Text('Disconnect Child device'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _run(() async {
                          await _familyUpdates?.cancel();
                          _familyUpdates = null;
                          await FirebaseAuth.instance.signOut();
                          if (!mounted) return;
                          setState(() {
                            _familyId = null;
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
                          hintText: '+91…',
                        ),
                        keyboardType: TextInputType.phone,
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                        obscureText: true,
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      if (_signUp)
                        TextFormField(
                          controller: _confirmation,
                          decoration: const InputDecoration(labelText: 'Confirm Password'),
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
