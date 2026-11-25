import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'child/child_app.dart';
import 'parent/parent_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final app = switch (appFlavor) {
    'parent' => const ParentApp(),
    'child' => const ChildApp(),
    _ => throw StateError('Select the parent or child Android flavor.'),
  };
  runApp(MaterialApp(
    title: appFlavor == 'parent' ? 'SafeGuard Parent' : 'SafeGuard Child',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: app,
  ));
}
