import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/backend.dart';
import '../shared/commands.dart';

class ChildApp extends StatefulWidget {
  const ChildApp({super.key});

  @override
  State<ChildApp> createState() => _ChildAppState();
}

class _ChildAppState extends State<ChildApp> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _device;
  static const _native = MethodChannel('safeguard/child');
  StreamSubscription<String>? _tokenUpdates;
  bool _busy = false;
  bool _handlingRequest = false;
  String? _error;
  String? _code;

  @override
  void initState() {
    super.initState();
    _issueCode();
  }

  @override
  void dispose() {
    _tokenUpdates?.cancel();
    super.dispose();
  }

  Future<void> _registerPush() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission();
      if (permission.authorizationStatus != AuthorizationStatus.authorized) return;
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

  Future<void> _review(
    String familyId,
    QueryDocumentSnapshot<Map<String, dynamic>> request,
  ) async {
    final data = request.data();
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
        'familyId': familyId,
        'commandId': request.id,
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
      try {
        await _native.invokeMethod<void>('execute', {
          'command': command,
          'message': data['message'],
        });
      } on PlatformException catch (error) {
        await report('failed', error.message);
        if (mounted) setState(() => _error = error.message ?? 'Action failed.');
        return;
      }
      await report('completed');
    } catch (error) {
      if (mounted) setState(() => _error = backendError(error));
    } finally {
      if (mounted) setState(() => _handlingRequest = false);
    }
  }

  Widget _requests(String familyId, String deviceId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('families').doc(familyId)
          .collection('commands').where('childDeviceId', isEqualTo: deviceId)
          .orderBy('timestamp', descending: true).limit(20).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Could not load requests.');
        return Column(
          children: [
            for (final request in snapshot.data?.docs ?? const [])
              if (request.get('status') == 'pending' &&
                  (request.get('expiresAt') as Timestamp).toDate().isAfter(DateTime.now()))
                ListTile(
                  title: Text(commandLabels[request.get('command')] ?? 'Parent request'),
                  trailing: TextButton(
                    onPressed: _handlingRequest ? null : () => _review(familyId, request),
                    child: const Text('Review'),
                  ),
                ),
          ],
        );
      },
    );
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
      final identity = auth.currentUser ?? (await auth.signInAnonymously()).user!;
      final response = await callBackend('issuePairCode');
      if (!mounted) return;
      setState(() {
        _device ??= FirebaseFirestore.instance.collection('devices').doc(identity.uid).snapshots();
        _code = response['code'] as String?;
      });
    } catch (error) {
      if (mounted) setState(() => _error = backendError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SafeGuard Child')),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _device,
          builder: (context, snapshot) {
            final familyId = snapshot.data?.data()?['familyId'] as String?;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(24),
                  children: [
                    if (familyId != null) ...[
                      const ListTile(
                        leading: Icon(Icons.verified_user_outlined),
                        title: Text('Connected to Parent ✅'),
                      ),
                      const Text('Your paired parent can send requests. Every request must be reviewed and approved on this device.'),
                      OutlinedButton(
                        onPressed: _registerPush,
                        child: const Text('Enable request notifications'),
                      ),
                      OutlinedButton(
                        onPressed: () => _openSettings('activateAdmin'),
                        child: const Text('Enable Device Admin for locking'),
                      ),
                      OutlinedButton(
                        onPressed: () => _openSettings('notificationPolicySettings'),
                        child: const Text('Allow silent mode and Do Not Disturb'),
                      ),
                      _requests(familyId, snapshot.data!.id),
                    ] else ...[
                      if (_code case final code?) ...[
                        Text(code,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displayMedium,
                        ),
                        const Text('यह कोड Parent को दें', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        const Text(
                          'Share the code only with the parent you want to pair with. '
                          'SafeGuard stores the pairing and request history in Firebase. '
                          'Device actions require your approval on this screen.',
                        ),
                      ],
                      if (_busy) const LinearProgressIndicator(),
                      if (!_busy)
                        FilledButton(
                          onPressed: _issueCode,
                          child: const Text('Refresh Code'),
                        ),
                    ],
                    if (_error case final error?) Text(error),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
