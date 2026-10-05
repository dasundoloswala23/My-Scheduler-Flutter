import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/theme.dart';
import 'core/notifications.dart';
import 'core/providers.dart';
import 'features/auth/auth_gate.dart';
import 'features/home/notification_router.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Keep a local cache so the board, calendar and edits all work with no
  // connection. Queued writes replay automatically when the network returns,
  // which is what makes a drag survive a dropout.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  await Notifications.init();
  runApp(const ProviderScope(child: MyScheduleApp()));
}

class MyScheduleApp extends ConsumerWidget {
  const MyScheduleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'My scheduler',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(brightness: Brightness.light),
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      home: const NotificationRouter(child: AuthGate()),
    );
  }
}
